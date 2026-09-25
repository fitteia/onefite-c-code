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
  templates (`tabfunc.c`). Builds `libonefit-5.0.0.a` and `libonefit-util-5.0.0.a`
  (the number is `LIBNUMBER`, see [Version](#version)).
  - **`core/onefit-3.1/modelos/`** - a library of built-in model functions. Builds
    `libonefit-modelos-5.0.0.a`. Depends on `core/onefit-3.1`'s own headers via a relative
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
(`libonefit-5.0.0.a`, `libonefit-modelos-5.0.0.a`, `libonefit-util-5.0.0.a`, `libuserlib.a`) and
their headers. `PERLCORE`/`swig` only matter for the separate `AuxCode.so` module build, which
`onefite-native` never uses at all, and which real `onefite` itself only builds as a (currently
unused - nothing in `OneFit-Engine` loads it) side effect of the `gfitn` per-fit compile.

### Build order

`core/onefit-3.1` must install (headers to `$ROOT/include`, libraries to `$ROOT/lib`) *before*
`local` builds, since `local`'s own compile step reads those installed headers rather than
reaching into `core/onefit-3.1`'s source tree directly. The top-level `makefile` already
sequences this correctly - `make install` handles it, no manual ordering needed unless you're
invoking the subdirectory makefiles directly.

## Installing the engine safely

`tools/engine.pl install` builds and installs the whole engine - minuit, this core and its
extensions - into an install root. onefite-go's `doctor --install` and OneFit-Engine's `INSTALL`
only fetch minuit and this repo and then call it, so both install the same way:

```bash
perl tools/engine.pl install --c-root . --root <install-root> --minuit-dir <minuit-checkout>
```

- **Nothing breaks the installed engine.** The installed engine files (libraries, headers,
  `etc/engine.mk`, `etc/extensions.mk`, the model catalog) are backed up first. The new engine
  must build, and a link test must pass: every object of every extension linked with the per-fit
  makefile's own link line, so whatever an extension calls resolves. If anything fails, the
  backup is put back exactly and the previous engine keeps working. The root's own files
  (OneFit-Engine's `lib/*.rakumod`, `bin/onefite`) are never touched.
- **Upgrades keep your extensions.** With no extension options it updates the extensions already
  installed - recorded in `<root>/etc/engine.json` - not the registry defaults, so a machine with
  `florence-nag` keeps it. One that can't be fetched (offline, a private repository) keeps its
  current checkout. Only a fresh install gets the defaults.
- **`--keep-minuit`** leaves an installed `lib/libminuit.a` alone and rebuilds only the core and
  the extensions - as long as minuit's checkout is still at the commit `etc/engine.json`
  recorded; a moved minuit is rebuilt anyway.
- **`--sources DIR`** installs offline from a package's bundled sources (`DIR/sources.json` and
  git bundles, as onefite-go's `.deb` ships in `/opt/onefite-go/share/engine-sources`): the
  bundled extensions are updated from their bundles, only forward (a checkout that is already
  newer is kept); any other installed extension (`florence-nag`, your own) is not fetched but
  keeps its checkout and is rebuilt against the new core. Nothing comes from the network.
- **`--if-changed`** rebuilds nothing when the core, minuit and every extension are still at the
  commits `etc/engine.json` recorded - what a package upgrade that changed nothing in the
  engine uses.
- The `etc/engine.json` record (core version and commit, minuit's commit and parameter limit,
  every extension with its repository and commit, when and where it was installed) is what
  `onefite upgrade`/`fit --hybrid` read the minuit limit from and what onefite-gui's
  Settings > Engine shows.
- **The old extensions layout is repaired** (an extensions clone occupying `extensions/` itself,
  from before 2026): the clone becomes `extensions/florence`, this repo's own files there come
  back, and its old repository name is repointed to `onefite-ext-florence`.
- **One step back:** `perl tools/engine.pl rollback --c-root . --root <install-root>` restores the
  engine as it was before the last install.
- Two installs into one root never run at the same time (`<root>/.engine.lock`).

## Version

`LIBNUMBER` in [`libnumber.mk`](libnumber.mk) is the core's version, defined only there. The
core, model and utility libraries carry it in their names (`libonefit-$(LIBNUMBER).a`),
`make install` writes it to `$(ROOT)/etc/engine.mk` for the per-fit makefiles of onefite-go
and OneFit-Engine, and extensions check it with `requires_base`.

It changes rarely - fixes and internal changes are tracked by git commits alone:

- **minor** (5.0 to 5.1): something extensions may call was added (a model, a function);
- **major** (5.x to 6.0): something extensions may call was changed or removed. Extensions
  declaring `requires_base` `">=5.0.0"` are then refused until someone checks them and raises it -
  `>=` only reaches within one major.

You don't have to remember when to change it. `make api-check` compares what the installed
headers declare (functions, constants, struct layouts) with the snapshot in
[`api/core-api.txt`](api/core-api.txt), recorded for the current `LIBNUMBER`. Comments, spacing
and the bodies of functions or function-like macros defined in headers don't count. If something
was added it asks for a new minor, if something was removed or changed a new major, and shows
what differs:

```
core API changed since 5.0.0:
  added:   local/NEWMODEL.h: double NEWMODEL(double x);
something was added -> needs LIBNUMBER 5.1.0 (it is 5.0.0).
run: make api-accept   (sets LIBNUMBER=5.1.0 and records the new API)
```

`make api-accept` then sets `LIBNUMBER` and records the snapshot; commit both files, saying in the
message what changed. The check runs in `make test`, and `check-and-push-ofe-repos.sh` runs it on
the commit it is about to push, skipping the push with that message until the API is accepted.

It was `4.0.4` from the early 2000s until 5.0.0, which introduced this scheme; the old number had
tracked the libraries since 1993. `make install` also links the `4.0.4` library names to the
current ones, so onefite-go and OneFit-Engine releases whose per-fit makefile still links
`-lonefit-4.0.4` keep working, and extensions written for 4.x (`requires_base` `">=4.0.4"`)
count as written for 5.x, since nothing they use changed. The state before this change is
tagged `pre-5.0.0`.

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

## License and third-party code

Original OneFit engine code in this extracted repository is covered by the
Artistic License 2.0; see [LICENSE](LICENSE). The repository also contains or
builds with separately licensed material. See [NOTICE](NOTICE) before
redistributing source or binaries.

This base repository does not contain any NAG-derived source. The Florence
model bundle (`Florence_c.c`/`.h`, `Florence_f.f`), which historically carried
NAG copyright notices in several Fortran routines, has been moved out
entirely into a separately-licensed external extensions bundle (see
[NOTICE](NOTICE) item 1) - anyone building against this base repository alone
has none of that licensing exposure. That bundle's NAG-derived eigensolver
has since been replaced with an independent, from-scratch implementation
(Householder tridiagonalization + implicit QL, not derived from NAG's code)
and is published separately under the Artistic License 2.0 at
[onefite-ext-florence](https://github.com/fitteia/onefite-ext-florence);
the original NAG-derived version remains available in a separate, private
repository for anyone who already holds the appropriate NAG Library license.
Minuit is a separate GPLv2 project, and the vendored `epstopdf` script
carries its own 3-clause BSD-style license.

The tree also retains GNU getopt sources under the GNU Library General Public
License (LGPL-2-or-later). Its license text is in
`third_party/licenses/gnu/COPYING.LIB`; those files are not relicensed by the
project license. The `core/onefit-3.1/perl/pcop` helper is original OneFit
code and is covered by Artistic 2.0.
