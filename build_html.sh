#!/bin/bash

-() { exit 1; }
usage() { printf 'usage: %s [debug|release]\n' "$0"; -; }

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" ||-

(($# == 1)) || usage

case "$1" in
debug)
    js_of_ocaml_flags=(--pretty --no-inline --source-map --debug-info)
    awk_script='{ print }'
    ;;
release)
    js_of_ocaml_flags=()
    awk_script='
        /^<script/ {
            print "<script type=\"module\">"
            while (getline line < "dwarf_locstack.js") {
                print line
            }
            print "</script>"
            next
        }
        { print }
    '
    ;;
*) usage;;
esac

ocamlfind ocamlc -package js_of_ocaml -package js_of_ocaml-ppx \
    -linkpkg -g -o dwarf_locstack_js.byte \
    dwarf_locstack.ml dwarf_locstack_js.ml ||-
js_of_ocaml "${js_of_ocaml_flags[@]}" \
    -o dwarf_locstack.js dwarf_locstack_js.byte ||-

awk "$awk_script" dwarf_locstack.html.in >dwarf_locstack.html ||-
