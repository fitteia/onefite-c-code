#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
gcc -std=c11 -O2 -I"$here/../../.." -c "$here/../../../core/onefit-3.1/fitutil.c" -o "$work/fitutil.o"
gcc -std=c11 -O2 "$here/test_polint.c" "$work/fitutil.o" -lm -o "$work/test"
"$work/test"

gcc -std=c11 -O2 "$here/test_spline.c" "$work/fitutil.o" -lm -o "$work/test-spline"
"$work/test-spline"

gcc -std=c11 -O2 -I"$here/../../.." -c "$here/../../../core/onefit-3.1/ludcmp.c" -o "$work/ludcmp.o"
gcc -std=c11 -O2 -I"$here/../../.." -c "$here/../../../core/onefit-3.1/lubksb.c" -o "$work/lubksb.o"
gcc -std=c11 -O2 "$here/test_lu.c" "$work/ludcmp.o" "$work/lubksb.o" "$work/fitutil.o" -lm -o "$work/test-lu"
"$work/test-lu"

gcc -std=c11 -O2 -I"$here/../../.." -c "$here/../../../core/onefit-3.1/gamma.c" -o "$work/gamma.o"
gcc -std=c11 -O2 "$here/test_gamma.c" "$work/gamma.o" "$work/fitutil.o" -lm -o "$work/test-gamma"
"$work/test-gamma"

 gcc -std=c11 -O2 -I"$here/../../.." -c "$here/../../../core/onefit-3.1/fft-utils.c" -o "$work/fft-utils.o"
 gcc -std=c11 -O2 -I"$here/../../../core/onefit-3.1" "$here/test_fft.c" "$work/fft-utils.o" "$work/fitutil.o" -lm -o "$work/test-fft"
 "$work/test-fft"

 gcc -std=c11 -O2 -I"$here/../../.." -c "$here/../../../core/onefit-3.1/integra.c" -o "$work/integra.o"
 gcc -std=c11 -O2 -I"$here/../../../core/onefit-3.1" "$here/test_quadrature.c" "$work/integra.o" "$work/fitutil.o" -lm -o "$work/test-quadrature"
 "$work/test-quadrature"

 gcc -std=c11 -O2 -I"$here/../../../core/onefit-3.1" "$here/test_root.c" "$work/integra.o" "$work/fitutil.o" -lm -o "$work/test-root"
 "$work/test-root"
