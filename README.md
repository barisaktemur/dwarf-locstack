To experiment with the DWARF locstack implementation, install OCaml.
Then start the interpreter and load the file.

E.g.:

```
$ utop
...
utop # #use "dwarf_locstack.ml";;
...
```

## HTML+JS

The `dwarf_locstack_js.ml` module and `dwarf_locstack.html.in` document are
linked via [`js_of_ocaml`](https://github.com/ocsigen/js_of_ocaml) to form an
interactive and graphical interface to experiment with the locstack
implementation.

E.g.:

```
$ opam install js_of_ocaml js_of_ocaml-ppx
$ ./build_html.sh debug   # debug mode generates separate .js and .map
$ # or
$ ./build_html.sh release # release mode inlines the js into the .html document
                          # resulting in a single self-contained file that
                          # can be copied around and loaded directly in a browser
$ xdg-open dwarf_locstack.html
```
