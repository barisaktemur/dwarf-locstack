Experiments with the DWARF locstack proposal.

## Getting Started

For Ubuntu/Debian you can get started by installing `opam` (the OCaml package
manager) using the `apt` package manager, and then creating a "switch" (virtual
environment) for the project:

```
$ sudo apt install opam # or any other recommended means for your OS
$ opam init # follow the prompts here; accepting defaults changes ~/.profile
            # which means you won't have to remember to `eval $(opam env)` in
            # every new shell to access your switches
$ cd path/to/dwarf-locstack
$ opam switch create . 5.3.0 # creates a hermetic environment used for this dir
                             # with the 5.3.0 OCaml compiler
```

At this point, whenever your shell is in the project directory you can run the
code with `ocaml`:

```
$ ocaml dwarf_locstack.ml
...
```

For an interactive REPL, you can install `utop` and `#use` the source:

```
$ opam install utop
$ utop
...
utop # #use "dwarf-locstack.ml";;
...
```

### Building the playground 

To transpile to JavaScript and generate a "playground" HTML file, install the
dependencies and build via `dune`:

```
$ opam install --deps-only . # this pulls from *.opam files in the current dir
$ opam install dune
$ dune build
```

Then point your browser at `_build/default/js/dwarf_locstack.html`.

This builds with the `dev` profile by default, which leaves the `js` source
external to the HTML file and includes sourcemaps for easier debugging. To
package it all together and minimize it you can instead build with the
`release` profile:

```
$ dune build --profile=release
```

At which point the resulting `dwarf_locstack.html` is entirely self-contained.
