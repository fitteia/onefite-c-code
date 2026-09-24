#!/bin/sh
# Runs after `make extensions TEST=1` has installed the extension. The driver
# exports C_ROOT, ROOT and EXT_NAME.
set -e
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/t.c" <<'C'
#include <stdio.h>
#include <math.h>
#include "example.h"
int main(void) {
	double y = ExampleGain(3.0, 2.0);
	if (fabs(y - 6.0) > 1e-12) { printf("FAIL: got %g\n", y); return 1; }
	printf("ok\n");
	return 0;
}
C
cc -I"$ROOT/include/ext/$EXT_NAME" "$tmp/t.c" -L"$ROOT/lib" -lonefit-ext-"$EXT_NAME" -lm -o "$tmp/t"
"$tmp/t"
