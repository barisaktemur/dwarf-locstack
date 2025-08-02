open Dwarf_locstack
open Js_of_ocaml
open Dom_html
open Printf

(* Shorthand for coerced getElementById with assertion *)
let get id coerce_to = Option.get (getElementById_coerce id coerce_to)

let html_of_part (s, e, loc) = sprintf
  {|<div class="box" style="width: %nem;"><span>%s</span></div>|}
  (e - s) (string_of_location loc)

let _ =
  let overlay_offset_in = get "overlay_offset_in" CoerceTo.input in
  let overlay_size_in = get "overlay_size_in" CoerceTo.input in
  let out = get "out" CoerceTo.element in
  let render _ =
    let overlay_offset = (Js.parseInt overlay_offset_in##.value) in
    let overlay_size = (Js.parseInt overlay_size_in##.value) in
    let overlay_locexpr = [DW_OP_reg 1;
                           DW_OP_reg 2;
                           DW_OP_const overlay_offset;
                           DW_OP_const overlay_size;
                           DW_OP_overlay] in
    let (storage, offset) = eval_to_loc overlay_locexpr context in
    (*TODO: string_of_locexpr? *)
    let expr_text = sprintf "\
        DW_OP_reg 1;\n\
        DW_OP_reg 2;\n\
        DW_OP_const %n;\n\
        DW_OP_const %n;\n\
        DW_OP_overlay;\
      " overlay_offset overlay_size in
    let boxes_html =
      match storage with
      | Composite(parts) -> String.concat "" (List.map html_of_part (sort_parts parts))
      | _ -> "" in
    let out_html =
      sprintf "\
          <div>Evaluating:</div>\n\
          <pre>%s</pre>\n\
          <div>Yields:</div>\n\
          <pre>%s</pre>\n\
          <div>%s</div>\
        " expr_text (string_of_storage storage) boxes_html in
    out##.innerHTML := Js.string out_html;
    Js._true in
  ignore (addEventListener overlay_offset_in Event.input (handler render) Js._false);
  ignore (addEventListener overlay_size_in Event.input (handler render) Js._false);
  (* Initial render for when page first loads *)
  render ()
