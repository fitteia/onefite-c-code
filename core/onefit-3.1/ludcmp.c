#include <math.h>
#include <stdio.h>
#include "fitutil.h"

/* In-place LU factorisation with scaled partial pivoting.  The one-based
   matrix ABI is retained because the covariance code allocates that way. */
void ludcmp(double **a, int n, int *indx, double *d)
{
    double local_scale[32];
    double *scale;
    int i, j, k, pivot_row;

    if (n < 1) nrerror("Empty matrix in LU decomposition");
    scale = (n <= 32) ? local_scale : dvector(1, n);
    *d = 1.0;
    for (i = 1; i <= n; ++i) {
        double largest = 0.0;
        for (j = 1; j <= n; ++j) {
            double magnitude = fabs(a[i][j]);
            if (magnitude > largest) largest = magnitude;
        }
        if (largest == 0.0 || !isfinite(largest))
            nrerror("Singular matrix in LU decomposition");
        scale[i] = 1.0 / largest;
    }

    for (j = 1; j <= n; ++j) {
        for (i = 1; i < j; ++i) {
            double sum = a[i][j];
            for (k = 1; k < i; ++k) sum -= a[i][k] * a[k][j];
            a[i][j] = sum;
        }
        pivot_row = j;
        {
            double best = 0.0;
            for (i = j; i <= n; ++i) {
                double sum = a[i][j];
                for (k = 1; k < j; ++k) sum -= a[i][k] * a[k][j];
                a[i][j] = sum;
                if (scale[i] * fabs(sum) >= best) {
                    best = scale[i] * fabs(sum);
                    pivot_row = i;
                }
            }
        }
        if (pivot_row != j) {
            for (k = 1; k <= n; ++k) {
                double tmp = a[pivot_row][k];
                a[pivot_row][k] = a[j][k];
                a[j][k] = tmp;
            }
            {
                double tmp = scale[pivot_row];
                scale[pivot_row] = scale[j];
                scale[j] = tmp;
            }
            *d = -*d;
        }
        indx[j] = pivot_row;
        if (a[j][j] == 0.0 || !isfinite(a[j][j]))
            nrerror("Singular matrix in LU decomposition");
        if (j < n) {
            double reciprocal = 1.0 / a[j][j];
            for (i = j + 1; i <= n; ++i) a[i][j] *= reciprocal;
        }
    }
    if (scale != local_scale) free_dvector(scale, 1, n);
}
