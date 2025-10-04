open Dwarf_locstack_sexp
open Js_of_ocaml
open Dom_html
open Sexplib

(* Shorthand for coerced getElementById with assertion *)
let get id coerce_to = Option.get (getElementById_coerce id coerce_to)

(* Get the non-empty, non-comment part of line, or None if it doesn't exist *)
let noncomment_part line =
  List.nth_opt (String.split_on_char ';' line) 0
  |> Option.map String.trim
  |> function | Some "" -> None | s -> s

(*
  Heuristically "Sexp-ify" the input.

  Goal: reduce noise for the common case by allowing the user to elide parens
  around non-0-ary constructors, and around the top-level list of op
  constructors.

  Approach:

    First, remove comments.

    Then, if the remaining input contains no parenthesis, surround any lines containing spaces with parens.

    Finally, surround everything in a top-level set of parens.

  Note: To avoid ambiguity in the case of all 0-ary constructors this means we
  need to require each constructor and its arguments appear on one line, and
  that each constructors be on a different line.
 *)
let preprocess input =
  let uncommented_lines = input
    |> String.split_on_char '\n'
    |> List.filter_map noncomment_part in
  let has_parens = uncommented_lines
    |> List.exists (fun line -> let c = String.contains line in c '(' || c ')') in
  if has_parens then
    uncommented_lines
    |> String.concat "\n"
  else
    uncommented_lines
    |> List.map (fun s -> if String.contains s ' ' then "(" ^ s ^ ")" else s)
    |> String.concat "\n"
    |> (fun s -> "(" ^ s ^ ")")

let _ =
  let context = get "context" CoerceTo.element in
  let input = get "input" CoerceTo.textarea in
  let eval = get "eval" CoerceTo.button in
  let preprocessed = get "preprocessed" CoerceTo.element in
  let output = get "output" CoerceTo.element in
  context##.innerHTML := (Js.string (Sexp.to_string_hum (sexp_of_context_t Dwarf_locstack.context)));
  let render _ =
    let locexpr_sexp_string = preprocess (Js.to_string input##.value) in
    let output_html =
      try
        let locexpr = (locexpr_t_of_sexp (Parsexp.Single.parse_string_exn locexpr_sexp_string)) in
        let result_loc = Dwarf_locstack.eval_to_loc locexpr Dwarf_locstack.context  in
        let result_loc_sexp = sexp_of_location result_loc in
        Sexp.to_string_hum result_loc_sexp
      with e -> Printexc.to_string e in
    preprocessed##.innerHTML := Js.string locexpr_sexp_string;
    output##.innerHTML := Js.string output_html;
    Js._true in
  ignore (addEventListener eval Event.click (handler render) Js._false)
