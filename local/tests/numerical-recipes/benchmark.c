#define _POSIX_C_SOURCE 200809L
#include <math.h>
#include <stdio.h>
#include <time.h>
#include "struct.h"

double gammq(double a, double x);
void ludcmp(double **a, int n, int *indx, double *d);
void lubksb(double **a, int n, int *indx, double b[]);
void dfour1(double data[], int nn, int isign);
void gauleg(double x1, double x2, double x[], double w[], int n);
double sqromo(Function *X, double (*choose)(Function *, int, int), int p);
double smidpnt(Function *X, int p, int n);
double sqgaus(Function *X, int p);
void clear_struct(Function *X, int npar);
static double benchmark_square(Function *X)
{
    double x = X->par[0].val;
    return x * x;
}

static double seconds(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + 1e-9 * (double)t.tv_nsec;
}

int main(void)
{
    volatile double sink = 0.0;
    double start, elapsed;
    int i, j, indx[4];
    double storage[4][4] = {{0}}, *a[4], rhs[4], determinant;
    for (i = 1; i <= 3; ++i) a[i] = storage[i];

    start = seconds();
    for (i = 0; i < 200000; ++i) sink += gammq(0.5 + (i % 17) * 0.1, 0.25 + (i % 31) * 0.2);
    elapsed = seconds() - start;
    printf("gamma: 200000 evaluations in %.6f s (%.0f/s)\n",
           elapsed, 200000.0 / elapsed);

    start = seconds();
    for (i = 0; i < 100000; ++i) {
        const double values[4][4] = {
            {0, 0, 0, 0}, {0, 3, 2, -1}, {0, 2, -2, 4}, {0, -1, .5, 2}
        };
        for (j = 1; j <= 3; ++j) {
            int k;
            for (k = 1; k <= 3; ++k) a[j][k] = values[j][k];
        }
        rhs[1] = 1.0; rhs[2] = -2.0; rhs[3] = 3.0;
        ludcmp(a, 3, indx, &determinant);
        lubksb(a, 3, indx, rhs);
        sink += rhs[1] + rhs[2] + rhs[3];
    }
    elapsed = seconds() - start;
    printf("LU: 100000 factor-and-solve operations in %.6f s (%.0f/s)\n",
           elapsed, 100000.0 / elapsed);
    {
        double fft[513] = {0};
        for (i = 1; i <= 512; i += 2) fft[i] = sin((double)i);
        start = seconds();
        for (i = 0; i < 10000; ++i) {
            int k;
            for (k = 1; k <= 512; ++k) fft[k] = (k & 1) ? sin((double)(k + i)) : 0.0;
            dfour1(fft, 256, 1);
            sink += fft[1];
        }
        elapsed = seconds() - start;
        printf("FFT: 10000 256-point transforms in %.6f s (%.0f/s)\n",
               elapsed, 10000.0 / elapsed);
    }
    {
        double nodes[33], weights[33];
        start = seconds();
        for (i = 0; i < 10000; ++i) {
            gauleg(-1.0, 1.0, nodes, weights, 32);
            sink += nodes[1] + weights[1];
        }
        elapsed = seconds() - start;
        printf("quadrature: 10000 32-point rules in %.6f s (%.0f/s)\n",
               elapsed, 10000.0 / elapsed);
    }
    {
        Function function;
        clear_struct(&function, 1);
        function.par[0].low_v = -2.0;
        function.par[0].high_v = 3.0;
        function.f_ptr = benchmark_square;
        start = seconds();
        for (i = 0; i < 5000; ++i) sink += sqromo(&function, smidpnt, 0);
        elapsed = seconds() - start;
        printf("integration: 5000 adaptive integral calls in %.6f s (%.0f/s)\n",
               elapsed, 5000.0 / elapsed);
        start = seconds();
        for (i = 0; i < 5000; ++i) sink += sqgaus(&function, 0);
        elapsed = seconds() - start;
        printf("fixed quadrature: 5000 calls in %.6f s (%.0f/s)\n",
               elapsed, 5000.0 / elapsed);
    }
    if (!isfinite(sink)) return 1;
    return 0;
}
