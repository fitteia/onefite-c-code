# Extensions

An extension adds model functions to onefite without touching the base
repository: a directory with an `extension.json`, some C and/or Fortran
sources, a metadata file describing the functions, and a licence. The same
extension works with `onefite-go`/`ofego` and with `oferaku`.

Installed extensions live in `extensions/<name>/` (git-ignored - each one is
its own repository). This folder tracks only the contract: this README,
`registry.json`, `extension.mk` (shared build rules) and `template/`.

## Write your own in five steps

1. Copy the template: `cp -r extensions/template extensions/mymodel`
2. Edit `extension.json`: set `name` (must equal the directory name), `provides`,
   `sources`, `headers`, `license`.
3. Write your functions. A model is a plain function of doubles returning a
   double, called once per data point:
   `double MyModel(double x, double a, double b);`
4. Describe each function in `META-C-model.json` (`function`, `call`,
   `parameters`, `description`, `devision`). `provides` must list exactly the
   names in its `functions` object - the build checks this.
5. Replace `LICENSE` and `NOTICE` with your own and build:

```
perl tools/extensions.pl validate extensions/mymodel
make extensions ROOT=/path/to/ofe-root TEST=1
```

`extensions/example` from the template is built and tested the same way; run
`make extensions-selftest` to exercise the whole mechanism.

## `extension.json`

| field | required | meaning |
|---|---|---|
| `schema` | yes | always `1` |
| `name` | yes | `[a-z][a-z0-9_-]*`, equal to the directory name |
| `version` | yes | your version string |
| `provides` | yes | exact list of function names you define |
| `sources` | yes | `.c` (C) and `.f` (fixed-form Fortran) files |
| `headers` | no | installed to `include/ext/<name>/` |
| `declarations` | no | the headers (a subset of `headers`) that declare your model functions for fit code; default: all `headers`. Fit code only sees `userlib.h`, so functions must be declared here. Keep internal prototypes (e.g. Fortran entry points) out of this list |
| `metadata` | yes | JSON file with a `functions` object (see template) |
| `license` | yes | `spdx`, `files` (at least one), `redistributable` (true/false) |
| `conflicts` | no | extensions that cannot be installed together with this one |
| `requires_base` | no | e.g. `">=4.0.4"` |
| `extra_libs` | no | link flags such as `"-llapack"` |
| `fflags` | no | extra Fortran compiler options, e.g. `["-std=legacy"]` for Fortran 77 code that gfortran now calls a "deleted feature" (real `DO` bounds, shared `DO` labels). Plain options only. The shared default stays strict, so new code is still checked |
| `tests` | no | a script, run with `TEST=1` (through its shebang if executable); gets `C_ROOT`, `ROOT`, `EXT_NAME` |
| `makefile` | no | your own Makefile to build with instead of the shared rules; must provide an `install` target that honours `C_ROOT` and `ROOT`. A Makefile not named here is ignored |

## Rules the build enforces

- **No name clashes.** Two installed extensions may not provide the same
  function, and an extension may not redefine a function of the base catalog.
  Two implementations of the same functions (for example a public and a
  licensed variant of one model) also share linker symbols, so they cannot be
  linked together: declare them in each other's `conflicts` and install one.
  When a named extension (`--extension NAME=URL`) declares a conflict with a
  default one, `fetch` skips that default, so no extra flag is needed. A
  conflicting folder left by an earlier install is refused with the fix (remove
  it) - it is never deleted for you.
- **Licensing is explicit.** Every extension names its licence files.
  `redistributable: false` means it must never be published, packaged or
  included in a default install - use it for anything you may not share.
- **The base is never edited.** `META-C.json` is untouched; the build writes
  `META-CATALOG.json` (base plus extensions) and `<root>/etc/extensions.mk`
  (link and include flags). Removing an extension and re-running
  `make extensions` removes it from both.

## Sharing

Publish the extension as its own repository (convention: `onefite-ext-<name>`)
with `extension.json` at its root, so users can clone it into
`extensions/<name>/`. Public, redistributable extensions can be listed in
`registry.json` so they can be installed by short name.

## A bundle from before this layout

A directory with a `Makefile` but no `extension.json` is an older-style bundle.
`make extensions` skips it (and says so); it is still installed by `doctor`'s
older path until it adopts this layout.
