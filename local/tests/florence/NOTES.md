# Florence model rewrite: review notes

Records the review of the `local/Florence_c.c` + `local/Florence_f.f` rewrite
(see the commit that added this directory). Both changes are
behavior-preserving for the physics - they fix caching correctness/
performance, not the underlying model.

## `Florence_c.c`

Old: each of `FlorenceN`, `FlorenceN4LS`, `Florence4` kept its own
`static` result array plus a `count`/`countLS` heuristic that only
re-invoked the Fortran backend once every *N* calls, assuming the caller
always queries indices 0->4 in that exact order for one evaluation point
before moving to the next. `Florence` (no-index variant) never cached at
all - recomputed every call.

New: one shared 8-slot cache keyed on an **exact match** of
`(frequency, parameters[28])` via `memcmp`, used by all four public
functions. Any parameter change forces a real recomputation; a cache
miss never returns a wrong answer, only a slower one. A failed
(non-finite) backend result is never cached either.

Verified:
- All 28 parameter-array positions match the old `PINP[]` assignments
  1-for-1 in every function, including the hardcoded `2.0` at index 8
  (`TAUDELTA`).
- `FLAG` routing to `modflor_` vs `florencef77_` is equivalent
  (`(int)FLAG==2` vs `FLAG>=2.0 && FLAG<3.0`) for every value that
  matters (1, 2, non-integer values near 2).
- No other file in the repo family (checked `OneFit-Engine/t/`)
  references the removed internals (`count`, `countLS`).
- Compiles with `gcc -Wall -Wextra` with zero warnings (the old version
  had two pre-existing dead-code warnings this incidentally removed).

## `Florence_f.f`

One subroutine changed - confirmed via `diff` against the pre-rewrite
version that only 3 contiguous hunks in the whole 14,709-line file
differ.

Old: inside `DO 10 K=1,NMX / DO 10 L=1,NMX`, nine complex angular-factor
expressions (`FF1..FF9`) were recomputed from scratch on **every**
`(K,L)` pair, then the same nine expressions recomputed **again** as
`GG1..GG9` - despite none of them depending on `K` or `L` (they only
depend on per-orientation constants set before the loop). `O(NMX^2)`
redundant complex arithmetic for something loop-invariant.

New: hoists the nine expressions into `DFAC(1..9)` (computed once before
the loop); the loop body reduces to `FF_i = DFAC(i)*C(K,L,i)`,
`GG_i = GFAC(i)*C(L,K,i)`.

Verified: extracted the exact pre-rewrite inline formulas for
`FF1..FF9`/`GG1..GG9` and diffed them character-for-character against
`DFAC(1..9)`/`GFAC(1..9)` - all 18 matched exactly, every coefficient
and `SQRT(...)` term. `gfortran -Wall` produces the identical warning
count (2403) before and after.

## What this test directory actually checks

`run_tests.sh`:

1. **Golden-value regression** - builds `local/Florence_c.c` +
   `local/Florence_f.f`, calls `Florence`/`Florence4`/`FlorenceN`/
   `FlorenceN4LS` across 20 `(FREQ, FLAG)` combinations (one full 0-4
   index sequence per combination - the pattern these functions are
   meant to support), and diffs the output against `golden_output.txt`,
   captured from the verified rewrite. Any future change to either file
   that alters real fit results will fail this.

2. **Stale-cache regression** - reproduces the specific bug the rewrite
   fixed: prime `FlorenceN`'s cache with one frequency's full 0-4
   sequence, then ask for index 0 of a *different* frequency. The old
   count-based cache's invalidation condition (`count<1 || count>n-1`)
   didn't catch this pattern and silently returned the previous
   frequency's stale result (`19.848...` instead of the correct
   `6.339...`, confirmed against `Florence()` as independent
   cache-free ground truth). This isn't a contrived edge case - it's an
   entirely ordinary call pattern for a fitting loop that doesn't
   always need every index at every point.

Run with `./run_tests.sh` from anywhere; requires `gcc` and `gfortran`.
Builds into a temp dir, cleaned up on exit.
