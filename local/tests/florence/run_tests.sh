#!/bin/bash
# Regression test for local/Florence_c.c + local/Florence_f.f.
#
# Background: both files were rewritten (see git log for the commit that
# introduced this test) to replace a legacy count-based result cache with
# one keyed on an exact match of the actual (frequency, parameters) input,
# and to hoist nine loop-invariant complex angular-factor expressions out
# of a DO K / DO L double loop in the Fortran backend. golden_output.txt
# was captured from that verified rewrite and is the values this test
# pins going forward - any future change to either file that alters real
# fit results should fail check 1 below.
#
# Checks:
#   1. Florence/Florence4/FlorenceN/FlorenceN4LS reproduce golden_output.txt
#      exactly across 20 (FREQ, FLAG) combinations.
#   2. FlorenceN never returns a stale cached value for a calling pattern
#      (finish one evaluation point's full index 0-4 sequence, then ask
#      for just index 0 of a new point) that the old count-based cache
#      got wrong - see staleness_demo.c's own comment for why.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== building local/Florence_c.c + local/Florence_f.f =="
gfortran -c -ffixed-form "$LOCAL_DIR/Florence_f.f" -o "$WORK/f.o" 2>/dev/null
gcc -c -I"$LOCAL_DIR" "$LOCAL_DIR/Florence_c.c" -o "$WORK/c.o"
gcc -I"$LOCAL_DIR" "$HERE/test_driver.c" "$WORK/f.o" "$WORK/c.o" -lgfortran -lm -o "$WORK/driver"
gcc -I"$LOCAL_DIR" "$HERE/staleness_demo.c" "$WORK/f.o" "$WORK/c.o" -lgfortran -lm -o "$WORK/staleness_demo"

echo "== 1. reproducing golden_output.txt =="
: > "$WORK/actual.txt"
for freq in 1e3 1e4 1e5 1e6 2.5e6 1e7 5e7 1e8 1e9 5e9; do
  for flag in 1 2; do
    { echo "=== freq=$freq flag=$flag ==="; "$WORK/driver" "$freq" "$flag"; } >> "$WORK/actual.txt"
  done
done
if diff -u "$HERE/golden_output.txt" "$WORK/actual.txt"; then
  echo "PASS: matches golden_output.txt across $(grep -c === "$WORK/actual.txt") (FREQ, FLAG) combinations"
else
  echo "FAIL: numeric output diverged from golden_output.txt - see diff above"
  exit 1
fi

echo
echo "== 2. stale-cache regression =="
"$WORK/staleness_demo"
if "$WORK/staleness_demo" | grep -q "MATCH: yes"; then
  echo "PASS: FlorenceN never returns a stale cached value for this pattern"
else
  echo "FAIL: FlorenceN returned a stale value"
  exit 1
fi
