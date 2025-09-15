(lang dune 3.20)
(name dwarf_locstack)

(source (github barisaktemur/dwarf-locstack))
(license GPL-3.0-only)
(authors "Tankut Baris Aktemur <tankut.baris.aktemur@intel.com>")
(maintainers "Tankut Baris Aktemur <tankut.baris.aktemur@intel.com>")
(generate_opam_files true)

(package
  (name dwarf_locstack)
  (synopsis "DWARF: locations on stack")
  (depends
    (ocaml (>= 4.13))
    (sexplib (>= 0.17))
    (ppx_sexp_conv (>= 0.17.1))
    (ppx_import (>= 1.11.0))
    (js_of_ocaml (>= 6.2.0))
    (js_of_ocaml-ppx (>= 6.2.0))))
