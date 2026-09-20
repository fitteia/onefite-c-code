#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
gcc -std=c11 -O2 -I"$here/../../.." -c "$here/../../../core/onefit-3.1/fitutil.c" -o "$work/fitutil.o"
gcc -std=c11 -O2 -I"$here/../../.." -c "$here/../../../core/onefit-3.1/gamma.c" -o "$work/gamma.o"
gcc -std=c11 -O2 -I"$here/../../.." -c "$here/../../../core/onefit-3.1/ludcmp.c" -o "$work/ludcmp.o"
gcc -std=c11 -O2 -I"$here/../../.." -c "$here/../../../core/onefit-3.1/lubksb.c" -o "$work/lubksb.o"
gcc -std=c11 -O2 -I"$here/../../.." -c "$here/../../../core/onefit-3.1/fft-utils.c" -o "$work/fft-utils.o"
gcc -std=c11 -O2 -I"$here/../../.." -c "$here/../../../core/onefit-3.1/integra.c" -o "$work/integra.o"
gcc -std=c11 -O2 -I"$here/../../../core/onefit-3.1" "$here/benchmark.c" "$work/gamma.o" "$work/ludcmp.o" "$work/lubksb.o" "$work/fft-utils.o" "$work/integra.o" "$work/fitutil.o" -lm -o "$work/benchmark"
"$work/benchmark"
