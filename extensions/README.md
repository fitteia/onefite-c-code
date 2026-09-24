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
python3 tools/extensions.py validate extensions/mymodel
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
| `metadata` | yes | JSON file with a `functions` object (see template) |
| `license` | yes | `spdx`, `files` (at least one), `redistributable` (true/false) |
| `conflicts` | no | extensions that cannot be installed together with this one |
| `requires_base` | no | e.g. `">=4.0.4"` |
| `extra_libs` | no | link flags such as `"-llapack"` |
| `tests` | no | a shell script, run with `TEST=1`; gets `C_ROOT`, `ROOT`, `EXT_NAME` |

## Rules the build enforces

- **No name clashes.** Two installed extensions may not provide the same
  function, and an extension may not redefine a function of the base catalog.
  Two implementations of the same functions (for example a public and a
  licensed variant of one model) also share linker symbols, so they cannot be
  linked together: declare them in each other's `conflicts` and install one.
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
