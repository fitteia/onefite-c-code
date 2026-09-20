#include <math.h>
#include <stdio.h>
#include <stdlib.h>

void dspline(double x[], double y[], int n, double yp1, double ypn, double y2[]);
void dsplint(double xa[], double ya[], double y2a[], int n, double x, double *y);

static double f(double x) { return x*x*x - 2.0*x*x + x + 3.0; }
static double df(double x) { return 3.0*x*x - 4.0*x + 1.0; }

int main(void)
{
    const int n = 9;
    double x[10], y[10], y2[10], value;
    int i;
    for (i = 1; i <= n; ++i) {
        x[i] = -2.0 + 0.5 * (double)(i - 1);
        y[i] = f(x[i]);
    }
    dspline(x, y, n, df(x[1]), df(x[n]), y2);
    for (i = 0; i < 41; ++i) {
        double at = -2.0 + 4.0 * (double)i / 40.0;
        dsplint(x, y, y2, n, at, &value);
        if (fabs(value - f(at)) > 2e-11) {
            fprintf(stderr, "FAIL clamped spline x=%.17g got=%.17g want=%.17g\n",
                    at, value, f(at));
            return 1;
        }
    }
    dspline(x, y, n, 1e30, 1e30, y2);
    dsplint(x, y, y2, n, -1.25, &value);
    if (!isfinite(value)) return 1;
    puts("PASS: cubic spline replacement reproduces clamped polynomial and natural spline is finite");
    return 0;
}
