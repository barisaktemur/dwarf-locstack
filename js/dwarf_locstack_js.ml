open Dwarf_locstack_sexp
open Js_of_ocaml
open Dom_html
open Sexplib

(* Shorthand for coerced getElementById with assertion *)
let get id coerce_to = Option.get (getElementById_coerce id coerce_to)

let _ =
  let context = get "context" CoerceTo.element in
  let input = get "input" CoerceTo.textarea in
  let eval = get "eval" CoerceTo.button in
  let output = get "output" CoerceTo.element in
  context##.innerHTML := (Js.string (Sexp.to_string_hum (sexp_of_context_t Dwarf_locstack.context)));
  let render _ =
    let output_html =
      try
        let locexpr_sexp_string = "(" ^ (Js.to_string input##.value) ^ ")" in
        let locexpr = (locexpr_t_of_sexp (Parsexp.Single.parse_string_exn locexpr_sexp_string)) in
        let result_loc = Dwarf_locstack.eval_to_loc locexpr Dwarf_locstack.context  in
        let result_loc_sexp = sexp_of_location result_loc in
        Sexp.to_string_hum result_loc_sexp
      with e -> Printexc.to_string e in
    output##.innerHTML := Js.string output_html;
    Js._true in
  ignore (addEventListener eval Event.click (handler render) Js._false)
