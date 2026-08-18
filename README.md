# onefite-c-code

The C and Fortran fitting-engine core used by [OneFit-Engine](https://github.com/fitteia/OneFit-Engine)
(the Raku CLI, `onefite`) and [onefite-native](https://github.com/fitteia/OneFit-Engine-go) (the
Go/Rust native port). This is the code that actually gets compiled per fit and linked with
[MINUIT](https://github.com/fitteia/minuit) into `onefit-user`, the binary that runs the real
non-linear least-squares fit.

Extracted from `OneFit-Engine`'s own `C/` subtree via `git subtree split`, so this repo's history
predates the split and traces the real history of these files, not a fresh import.

## Layout

- **`core/onefit-3.1/`** - the main engine: MINUIT driver (`gfitn.c`), data/parameter I/O, the
  results/plotting pipeline (`gfit_out.c`, `xmgr.c`), and the per-fit build recipe's own source
  templates (`tabfunc.c`). Builds `libonefit-4.0.4.a` and `libonefit-util-4.0.4.a`.
  - **`core/onefit-3.1/modelos/`** - a library of built-in model functions. Builds
    `libonefit-modelos-4.0.4.a`. Depends on `core/onefit-3.1`'s own headers via a relative
    `-I..` - it must stay a structural sibling of `core/onefit-3.1`, wherever this repo itself
    ends up living.
  - **`core/onefit-3.1/perl/`** - small installed helper scripts: `pcop`, `pdf2mp4` (PDF-to-MP4,
    used by `--mp4`), and a vendored `epstopdf` (see [Vendored files](#vendored-files) below).
- **`local/`** - additional, user-contributed model functions (`libuserlib.a`), documented in
  `META-C.json` (function signatures, parameter ranges, and literature references - this is what
  `onefite`'s own alias/function catalog reads). Its own build genuinely depends on
  `core/onefit-3.1` having already run its install step first (it compiles against the
  *installed* headers, not this repo's own source tree directly) - see
  [Build order](#build-order).
- **`makefile`** - top-level orchestration: builds and installs everything above, in the
  correct order.

## Building

```bash
make ARCH=<x86_64|aarch64> ROOT=<install-prefix> PERLCORE=<perl-CORE-dir> BINDIR=<bin-dir> install
```

`PERLCORE` is only needed for `core/onefit-3.1/perl`'s own `AuxCode.so` SWIG module build (the
Raku-Perl interop bridge onefite's own CLI uses) - find it with
`perl -MConfig -e 'print "$Config{archlib}/CORE"'`. It is **not** needed to build any of the
static libraries themselves.

**Dependencies to build**: `gcc`, `gfortran`, `make`, `ar` (binutils). Nothing else - no Perl,
no Raku, no SWIG - are required to produce the four static libraries
(`libonefit-4.0.4.a`, `libonefit-modelos-4.0.4.a`, `libonefit-util-4.0.4.a`, `libuserlib.a`) and
their headers. `PERLCORE`/`swig` only matter for the separate `AuxCode.so` module build, which
`onefite-native` never uses at all, and which real `onefite` itself only builds as a (currently
unused - nothing in `OneFit-Engine` loads it) side effect of the `gfitn` per-fit compile.

### Build order

`core/onefit-3.1` must install (headers to `$ROOT/include`, libraries to `$ROOT/lib`) *before*
`local` builds, since `local`'s own compile step reads those installed headers rather than
reaching into `core/onefit-3.1`'s source tree directly. The top-level `makefile` already
sequences this correctly - `make install` handles it, no manual ordering needed unless you're
invoking the subdirectory makefiles directly.

## Vendored files

`core/onefit-3.1/perl/epstopdf` is [epstopdf.pl](https://ctan.org/pkg/epstopdf) from CTAN,
vendored here rather than depended on via `texlive-font-utils` (which pulls in `texlive-base` -
tens of MB - for one script with no CPAN dependencies of its own). It carries its own permissive
3-clause BSD-style license, included in the file's own header; see that file for the exact terms.
Only `perl-base` + `ghostscript` are needed to run it, not any part of TeX Live.

## Used by

`OneFit-Engine`'s own `INSTALL` script clones this repo as a sibling directory during
`compile()`, the same way it already clones [`minuit`](https://github.com/fitteia/minuit) - see
that script for the exact invocation. `onefite-native`'s own packaging story builds against the
same artifacts this repo produces (`lib/*.a` + `include/*.h`), without needing Raku, Perl, or
`zef` at any point in that chain.
