open Sexplib.Std

(* Re-open relevant types in Dwarf_locstack to derive sexp functions *)
type data = [%import: Dwarf_locstack.data]
and context_item = [%import: Dwarf_locstack.context_item]
and storage = [%import: Dwarf_locstack.storage]
and location = [%import: Dwarf_locstack.location]
and stack_element = [%import: Dwarf_locstack.stack_element]
and dwarf_op = [%import: Dwarf_locstack.dwarf_op]
[@@deriving sexp]

(* Add some types not present in Dwarf_locstack but useful with sexp *)
type context_t = (context_item list) [@@deriving sexp]
type locexpr_t = (dwarf_op list) [@@deriving sexp]
type stack_t = (stack_element list) [@@deriving sexp]
