(* A simplified implementation of DWARF specification for locations on
   stack.

   For simplicity, all sizes are in bytes; data access is at the
   granularity of bytes.  *)

(* Data are a sequence of bytes.  *)
type data = string

(* Size of an address in the default address space.  *)
let size_of_generic_type = 4

(* Evaluation context.
   The consumer provides the evaluation context.  *)
type context_item =
  | TargetMem of int * data   (* Address space, contents.  *)
  | TargetReg of int * data   (* Register num, contents.  *)
  | Lane of int               (* Selected lane.  *)
  | Object of location        (* Current object.  *)

(* Virtual storage.  *)
and storage =
  | Mem of int (* Address space.  *)
  | Reg of int (* Register number.  *)
  | Undefined
  | ImpData of data (* Implicit data.  *)
  | ImpPointer of location (* Location of the pointed-to object.  *)
  | Composite of (int * int * location) list (* Parts of the composite.  *)

(* Location is an offset into a storage.  *)
and location = storage * int

(* Context accessors for convenience.  *)
let rec mem_data context addr_space =
  match context with
  | [] -> failwith "memory not found in context"
  | TargetMem(sp, data)::context' when sp = addr_space -> data
  | _::context' -> mem_data context' addr_space

let rec reg_data context num =
  match context with
  | [] -> failwith "register not found in context"
  | TargetReg(n, data)::context' when n = num -> data
  | _::context' -> reg_data context' num

let rec lane context =
  match context with
  | [] -> failwith "lane not found in context"
  | Lane(n)::context' -> n
  | _::context' -> lane context'

let rec objekt context =
  match context with
  | [] -> failwith "object not found in context"
  | Object(loc)::context' -> loc
  | _::context' -> objekt context'


(* Element kinds for the DWARF expression evaluation stack.
   A stack is simply a list of stack elements.  *)
type stack_element =
  | Val of int
  | Loc of location

type dwarf_op =
  | DW_OP_const of int
  | DW_OP_plus
  | DW_OP_mul
  | DW_OP_swap
  | DW_OP_push_lane

  | DW_OP_addr of int
  | DW_OP_reg of int
  | DW_OP_breg of int * int
  | DW_OP_undefined
  | DW_OP_implicit_value of string
  | DW_OP_stack_value
  | DW_OP_implicit_pointer of (dwarf_op list) * int
  | DW_OP_composite
  | DW_OP_piece of int
  | DW_OP_overlay
  | DW_OP_push_object_location

  | DW_OP_deref
  | DW_OP_offset

(* What is the size of a virtual storage?  *)
let rec data_size storage context =
  match storage with
  | Mem(addr_space) -> String.length (mem_data context addr_space)
  | Reg(n) -> String.length (reg_data context n)
  | Undefined -> Int.max_int
  | ImpData(data) -> String.length data
  | ImpPointer(pointee_storage, offset) -> Int.max_int
  | Composite(parts) -> (* The largest "end" marker in the parts.  *)
     List.fold_left (fun max (s, e, loc) -> if e > max then e else max) 0 parts

(* Error kinds.  *)
exception NotImplementedYet
exception OutOfBounds of location
exception UndefinedData of int
exception ReadOnlyData of storage

(* Utility operations.  *)

(* Find the part in a composite that contains the given offset.
   Return the location and the adjusted offset.  *)
let find_part parts offset : location =
  let part = List.find (fun (s, e, loc) -> s <= offset && offset < e) parts
  in let (s, e, (part_storage, part_offset)) = part
     in (part_storage, (part_offset + offset - s))

(* Remove parts that don't cover any data.  *)
let simplify parts =
  List.fold_left (fun acc (s, e, loc) -> if s < e then (s, e, loc)::acc else acc) [] parts

let rec read_one_byte context (location: location) =
  let (storage, offset) = location
  in if offset >= (data_size storage context) then
       raise (OutOfBounds location)
     else
       match storage with
       | Mem(addr_space) -> String.get (mem_data context addr_space) offset
       | Reg(n) -> String.get (reg_data context n) offset
       | Undefined -> raise (UndefinedData(offset))
       | ImpData(data) -> String.get data offset
       | ImpPointer(_, _) -> raise (UndefinedData(offset))
       | Composite(parts) -> read_one_byte context (find_part parts offset)

let fetch_data context (loc: location) length =
  let (storage, offset) = loc
  in String.init length (fun n -> read_one_byte context (storage, (offset + n)))

let fetch_int context (loc: location) =
  Int32.to_int (String.get_int32_ne (fetch_data context loc 4) 0)

let int_to_data n =
  let data = Bytes.create 4
  in Bytes.set_int32_ne data 0 (Int32.of_int n);
     String.of_bytes data

let ints_to_data ns =
  let data = Bytes.create (4 * List.length ns)
  in List.iteri (fun i n -> Bytes.set_int32_ne data (i * 4) (Int32.of_int n)) ns;
     String.of_bytes data

exception ConversionError of string * stack_element
exception EvalError of string * dwarf_op * (stack_element list)

let eval_error op stack =
  raise (EvalError("Cannot evaluate", op, stack))

(* Implicit conversion rules.  *)
let as_value element =
  match element with
  | Val(i) -> i
  | Loc(Mem(0), address) -> address
  | _ -> raise (ConversionError("Cannot convert to val", element))

let as_loc element =
  match element with
  | Loc(loc) -> loc
  | Val(i) -> (Mem 0, i)

(* Evaluate a single DWARF operator using the given stack.  *)
let rec eval op stack context =
  match op with
  | DW_OP_const(x) -> Val(x)::stack

  | DW_OP_plus ->
     (match stack with
      | e1::e2::stack' -> Val((as_value e1) + (as_value e2))::stack'
      | _ -> eval_error op stack)

  | DW_OP_mul ->
     (match stack with
      | e1::e2::stack' -> Val((as_value e1) * (as_value e2))::stack'
      | _ -> eval_error op stack)

  | DW_OP_swap ->
     (match stack with
      | e1::e2::stack' -> e2::e1::stack'
      | _ -> eval_error op stack)

  | DW_OP_push_lane -> Val(lane context)::stack

  | DW_OP_addr(a) -> Loc(Mem 0, a)::stack

  | DW_OP_reg(n) -> Loc(Reg n, 0)::stack

  | DW_OP_breg(n, offset) ->
     let reg_contents = fetch_int context ((Reg n), 0)
     in let address = reg_contents + offset
        in Loc(Mem 0, address)::stack

  | DW_OP_undefined -> Loc(Undefined, 0)::stack

  | DW_OP_implicit_value(data) -> Loc(ImpData data, 0)::stack

  | DW_OP_stack_value ->
     (match stack with
      | e::stack' ->
         let data = int_to_data (as_value e)
         in Loc(ImpData data, 0)::stack'
      | _ -> eval_error op stack)

  | DW_OP_implicit_pointer(locexpr, offset) ->
     (match eval_all locexpr [] context with
      | result::_ ->
         let (storage, offset2) = as_loc result
         in Loc(ImpPointer(storage, offset2 + offset), 0)::stack
      | _ -> eval_error op stack)

  | DW_OP_composite -> Loc(Composite [], 0)::stack

  | DW_OP_piece(n) ->
     (match stack with
      | element::Loc(Composite(parts), off)::stack' ->
         let loc = as_loc element
         in let new_part = (match parts with
                            | [] -> (0, n, loc)
                            | (s, e, _)::_ -> (e, e + n, loc))
            in Loc(Composite(new_part::parts), off)::stack'

      | _ -> eval_error op stack)

  | DW_OP_push_object_location -> Loc(objekt context)::stack

  | DW_OP_overlay ->
     (match stack with
      | el1::el2::el3::el4::stack' ->
         let width = as_value el1 in
         let offset = as_value el2 in
         let overlay_loc = as_loc el3 in
         let base_loc = as_loc el4 in
         let (b_storage, b_offset) = base_loc in
         let b_storage_size = data_size b_storage context in
         (* TODO: Sync with the proposal.  *)
         if (width < 0 || offset < 0) then
           eval_error op stack
         else
           (* There are 4 types of parts that may occur in the
              resulting composite.  Although not all 4 types will end
              up existing in the end result, to make the definition
              easier, we define all of them and then do elimination at
              the end.

              1. The part of the base storage up to the overlay.  If
              the overlay is beyond the base storage limits, this
              parts goes up to the end of the base storage.

              2. The expansion with undefined storage up to the overlay.

              3. The overlay itself.

              4. The remaining data from the base storage up to its end.  *)

           let part1_end = Int.min offset (b_storage_size - b_offset) in
           let part1 = (0, part1_end, base_loc) in
           let part2 = (part1_end, offset, (Undefined, 0)) in
           let part3 = (offset, offset + width, overlay_loc) in
           let part4_loc = (b_storage, b_offset + offset + width) in
           let part4 = (offset + width, b_storage_size - b_offset, part4_loc) in
           let parts = simplify [part1; part2; part3; part4] in
           Loc(Composite parts, 0)::stack'

      | _ -> eval_error op stack)

  | DW_OP_deref ->
     (match stack with
      | element::stack' ->
         Val(fetch_int context (as_loc element))::stack'

      | _ -> eval_error op stack)

  | DW_OP_offset ->
     (match stack with
      | displacement::location::stack' ->
         let (storage, offset) = as_loc location
         in let new_offset = offset + (as_value displacement)
            in if (new_offset >= (data_size storage context)) then
                 raise (OutOfBounds (storage, offset))
               else
                 Loc(storage, new_offset)::stack'
      | _ -> eval_error op stack)

(* Evaluate the given list of DWARF operators using the given stack.  *)
and eval_all ops stack context =
  match ops with
  | [] -> stack
  | op::ops' -> eval_all ops' (eval op stack context) context

(* Evaluate the given list of DWARF operators using an initially empty
   stack, return the top element.  *)
let eval0 ops context =
  List.hd (eval_all ops [] context)

let eval_to_loc ops context =
  as_loc (eval0 ops context)

(**************)
(* Examples.  *)
(**************)

(* Consumer utility functions.  *)
(* ... *ptr ... *)
let rec dbg_deref (loc: location) context =
  match loc with
  | (ImpPointer(p_loc), 0) -> fetch_int context p_loc
  (* TODO: Handle the case when the data to fetch expands to multiple parts.  *)
  | (Composite parts, offset) -> dbg_deref (find_part parts offset) context
  | _ -> let address = fetch_int context loc
         in fetch_int context (Mem 0, address)

(* ... &x ... *)
let dbg_addr_of (loc: location) =
  match loc with
  | (Mem _, offset) -> offset
  | _ -> failwith "Cannot get address of that."

(* Sample contexts for testing purposes.  *)
let empty = []

let mem_contents =
  String.concat ""
    [(ints_to_data [100; 104; 108; 112; 116; 120]);
     "01234567XXXXCDEF"; (* Starting at offset 24. *)
    ]

let context = [TargetMem(0, mem_contents);
               TargetReg(0, int_to_data 1000);
               TargetReg(1, int_to_data 1001);
               TargetReg(2, int_to_data 1002);
               TargetReg(3, int_to_data 1003);
               TargetReg(4, ints_to_data [400; 401; 402; 403; 404; 405; 406; 407]);
               TargetReg(5, int_to_data 4); (* Pointer to memory #4.  *)
               TargetReg(6, "89AB");
              ]

let num_pass = ref 0
let num_fail = ref 0
let test value expectation message =
  let result =
    if value = expectation then
      (num_pass := !num_pass + 1; "Pass")
    else
      (num_fail := !num_fail + 1; "FAIL")
  in
    Printf.printf "%s: %s\n" result message

(* Simple arithmethic exp test.  *)
let _ =
  test (eval0 [DW_OP_const 9;
               DW_OP_const 5;
               DW_OP_plus;
               DW_OP_const 3;
               DW_OP_mul] context)
    (Val 42)
    "arithmetic expr"

(* x is an integer in memory.  *)
let _ =
  let x_address = 4 in
  let x_locexpr = [DW_OP_addr x_address] in
  let x_loc = eval_to_loc x_locexpr context in
  let x_val = fetch_int context x_loc in
  let addr_of_x = dbg_addr_of x_loc in
  test x_val 104 "value of x";
  test addr_of_x 4 "address of x"

(* y is an integer in register 1.  *)
let _ =
  let y_locexpr = [DW_OP_reg 1] in
  let y_loc = eval_to_loc y_locexpr context in
  let y_val = fetch_int context y_loc in
  test y_val 1001 "value of y"

(* p is a pointer to x and is located in register 5.  *)
let _ =
  let p_locexpr = [DW_OP_reg 5] in
  let p_loc = eval_to_loc p_locexpr context in
  let p_val = fetch_int context p_loc in
  let p_deref_val = dbg_deref p_loc context in
  test p_val 4 "value of p";
  test p_deref_val 104 "value of *p"

(* ip is an implicit pointer to x.  We can deref, but we cannot
   read/write ip.  *)
let _ =
  let ip_locexpr = [DW_OP_implicit_pointer ([DW_OP_addr 4], 0)] in
  let ip_loc = eval_to_loc ip_locexpr context in
  let ip_deref_val = dbg_deref ip_loc context in
  test ip_deref_val 104 "value of *ip, pointing to memory"

(* ip is an implicit pointer to a variable that has been promoted to
   register 3.  *)
let _ =
  let ip_locexpr = [DW_OP_implicit_pointer ([DW_OP_reg 3], 0)] in
  let ip_loc = eval_to_loc ip_locexpr context in
  let ip_deref_val = dbg_deref ip_loc context in
  test ip_deref_val 1003 "value of *ip, pointing to register"

(* v is a vectorized integer in register 4.  *)
let _ =
  let v_locexpr = [DW_OP_reg 4;
                   DW_OP_push_lane;
                   DW_OP_const 4;
                   DW_OP_mul;
                   DW_OP_offset] in
  let v_loc = eval_to_loc v_locexpr (Lane(3)::context) in
  let v_val = fetch_int (Lane(3)::context) v_loc in
  test v_val 403 "value of v in lane 3";
  let v_loc = eval_to_loc v_locexpr (Lane(5)::context) in
  let v_val = fetch_int (Lane(5)::context) v_loc in
  test v_val 405 "value of v in lane 5"

(* q is a value computed in the DWARF stack.  *)
let _ =
  let q_locexpr = [DW_OP_const 14;
                   DW_OP_const 3;
                   DW_OP_mul;
                   DW_OP_stack_value] in
  let q_loc = eval_to_loc q_locexpr empty in
  let q_val = fetch_int empty q_loc in
  test q_val 42 "stack value"

(* z is located 12 bytes away from p's pointee.  *)
let _ =
  let z_locexpr = [DW_OP_breg(5, 12)] in
  let z_loc = eval_to_loc z_locexpr context in
  let z_addr = dbg_addr_of z_loc in
  let z_val = fetch_int context z_loc in
  test z_addr 16 "address of z";
  test z_val 116 "value of z"

(* Another approach for the same thing.  *)
let _ =
  let z_locexpr = [DW_OP_addr 0;
                   DW_OP_reg 5;
                   DW_OP_deref;
                   DW_OP_offset;
                   DW_OP_const 12;
                   DW_OP_offset] in
  let z_loc = eval_to_loc z_locexpr context in
  let z_addr = dbg_addr_of z_loc in
  let z_val = fetch_int context z_loc in
  test z_addr 16 "address of z, take 2";
  test z_val 116 "value of z, take 2"

(* Suppose we have a struct as follows:

   struct {
     int m; // Located in memory at address 20.
     int *ptr; // Implicit pointer to "x" above.
     int r2; // Located in register 2.
     int r3; // Located in register 3.
     int d; // Implicit data known to be 333;
   } s;
*)

let _ =
  let s_locexpr = [DW_OP_composite;
                   DW_OP_addr 20;
                   DW_OP_piece 4;
                   DW_OP_implicit_pointer ([DW_OP_addr 4], 0);
                   DW_OP_piece 4;
                   DW_OP_reg 2;
                   DW_OP_piece 4;
                   DW_OP_reg 3;
                   DW_OP_piece 4;
                   DW_OP_implicit_value (int_to_data 333);
                   DW_OP_piece 4] in
  let s_loc = eval_to_loc s_locexpr context in
  (* ... s.m ... *)
  let s_m_locexpr = s_locexpr @ [DW_OP_const 0; DW_OP_offset] in
  let s_m_val = fetch_int context (eval_to_loc s_m_locexpr context) in
  test s_m_val 120 "value of s.m";
  (* ... s.r2 ... *)
  let s_r2_locexpr = s_locexpr @ [DW_OP_const 8; DW_OP_offset] in
  let s_r2_val = fetch_int context (eval_to_loc s_r2_locexpr context) in
  test s_r2_val 1002 "value of s.r2";
  (* ... s.r3 ... *)
  let s_r3_locexpr = s_locexpr @ [DW_OP_const 12; DW_OP_offset] in
  let s_r3_val = fetch_int context (eval_to_loc s_r3_locexpr context) in
  test s_r3_val 1003 "value of s.r3";
  (* ... s.d ... *)
  let s_d_locexpr = s_locexpr @ [DW_OP_const 16; DW_OP_offset] in
  let s_d_val = fetch_int context (eval_to_loc s_d_locexpr context) in
  test s_d_val 333 "value of s.d";
  (* ... *s.ptr ... *)
  let s_ptr_locexpr = s_locexpr @ [DW_OP_const 4; DW_OP_offset] in
  let s_ptr_loc = eval_to_loc s_ptr_locexpr context in
  let s_ptr_deref_val = dbg_deref s_ptr_loc context in
  test s_ptr_deref_val 104 "value of *s.ptr";
  (* ... this.r3 ...  *)
  let r3_data_member_locexpr = [DW_OP_push_object_location;
                                DW_OP_const 12;
                                DW_OP_offset] in
  let r3_data_member_loc = eval_to_loc r3_data_member_locexpr (Object(s_loc)::context) in
  let r3_data_member_val = fetch_int context r3_data_member_loc in
  test r3_data_member_val 1003 ".r3 with an object context"

(* An array, whose values are "0123456789ABCDEF".  The elements "89AB"
   are in register 6, the others are in the memory.  This example
   illustrates promotion of array elements to a vector register.  *)
let _ =
  let array_locexpr = [DW_OP_composite;
                       DW_OP_addr 24;
                       DW_OP_piece 8;
                       DW_OP_reg 6;
                       DW_OP_piece 4;
                       DW_OP_addr (24 + 12);
                       DW_OP_piece 4] in
  let (storage, offset) = eval_to_loc array_locexpr context in
  let array_element i =
    fetch_data context (storage, offset + i) 1
  in
  test (array_element 0) "0" "array[0] in composite";
  test (array_element 3) "3" "array[3] in composite";
  test (array_element 7) "7" "array[7] in composite";
  test (array_element 8) "8" "array[8] in composite";
  test (array_element 9) "9" "array[9] in composite";
  test (array_element 10) "A" "array[10] in composite";
  test (array_element 11) "B" "array[11] in composite";
  test (array_element 12) "C" "array[12] in composite";
  test (array_element 15) "F" "array[15] in composite";
  ()

(* The same array example with an overlay.  *)
let _ =
  let overlay_locexpr = [DW_OP_addr 24;
                         DW_OP_reg 6;
                         DW_OP_const 8;
                         DW_OP_const 4;
                         DW_OP_overlay] in
  let (storage, offset) = eval_to_loc overlay_locexpr context in
  let array_element i =
    fetch_data context (storage, offset + i) 1
  in
  test (array_element 0) "0" "array[0] in overlay composite";
  test (array_element 3) "3" "array[3] in overlay composite";
  test (array_element 7) "7" "array[7] in overlay composite";
  test (array_element 8) "8" "array[8] in overlay composite";
  test (array_element 9) "9" "array[9] in overlay composite";
  test (array_element 10) "A" "array[10] in overlay composite";
  test (array_element 11) "B" "array[11] in overlay composite";
  test (array_element 12) "C" "array[12] in overlay composite";
  test (array_element 15) "F" "array[15] in overlay composite";
  ()

let _ =
  let overlay_locexpr = [DW_OP_addr 7;
                         DW_OP_reg 3;
                         DW_OP_const 5;
                         DW_OP_const 6;
                         DW_OP_overlay] in
  let overlay_loc = eval_to_loc overlay_locexpr context in
  let mem_size = data_size (Mem 0) context in
  test overlay_loc
    (Composite [(11, mem_size - 7, (Mem 0, 18));
                (5, 11, (Reg 3, 0));
                (0, 5, (Mem 0, 7))], 0)
    "overlay: register on memory"

let _ =
  let reg_size = data_size (Reg 1) context in
  let overlay_locexpr = [DW_OP_reg 1;
                         DW_OP_reg 2;
                         DW_OP_const (reg_size + 11);
                         DW_OP_const 3;
                         DW_OP_overlay] in
  let overlay_loc = eval_to_loc overlay_locexpr context in
  test overlay_loc
    (Composite [(15, 18, (Reg 2, 0));
                (4, 15, (Undefined, 0));
                (0, 4, (Reg 1, 0))], 0)
    "overlay: register on register with gap"

let _ =
  let reg_size = data_size (Reg 1) context in
  let overlay_locexpr = [DW_OP_reg 1;
                         DW_OP_reg 2;
                         DW_OP_const reg_size;
                         DW_OP_const 4;
                         DW_OP_overlay] in
  let overlay_loc = eval_to_loc overlay_locexpr context in
  test overlay_loc
    (Composite [(4, 8, (Reg 2, 0));
                (0, 4, (Reg 1, 0))], 0)
    "overlay: concat two registers"

let _ =
  let reg_size = data_size (Reg 1) context in
  let overlay_locexpr = [DW_OP_reg 1;
                         DW_OP_const (reg_size - 1);
                         DW_OP_offset;
                         DW_OP_reg 2;
                         DW_OP_const 2;
                         DW_OP_offset;
                         DW_OP_const 1;
                         DW_OP_const 2;
                         DW_OP_overlay] in
  let overlay_loc = eval_to_loc overlay_locexpr context in
  test overlay_loc
    (Composite [(1, 3, (Reg 2, 2));
                (0, 1, (Reg 1, 3))], 0)
    "overlay: concat two registers with offsets"

(****************************)
(* Print the final result.  *)
let _ =
  Printf.printf "*************************\n";
  Printf.printf "# of passes:\t %d\n" !num_pass;
  Printf.printf "# of failures:\t %d\n" !num_fail;
  Printf.printf "*************************\n";
