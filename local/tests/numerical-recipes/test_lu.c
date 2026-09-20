#include <math.h>
#include <stdio.h>
#include <stdlib.h>

void ludcmp(double **a, int n, int *indx, double *d);
void lubksb(double **a, int n, int *indx, double b[]);

int main(void)
{
    double storage[4][4] = {{0}};
    double *a[4];
    int indx[4], i, j;
    double d, b[4] = {0.0, 1.0, -2.0, 3.0};
    const double expected[4] = {0.0, -0.6363636363636364, 1.8181818181818183, 0.7272727272727273};
    const double original[4][4] = {
        {0.0, 0.0, 0.0, 0.0},
        {0.0, 3.0, 2.0, -1.0},
        {0.0, 2.0, -2.0, 4.0},
        {0.0, -1.0, 0.5, 2.0}
    };
    for (i = 1; i <= 3; ++i) {
        a[i] = storage[i];
        for (j = 1; j <= 3; ++j) storage[i][j] = original[i][j];
    }
    ludcmp(a, 3, indx, &d);
    lubksb(a, 3, indx, b);
    for (i = 1; i <= 3; ++i) {
        if (fabs(b[i] - expected[i]) > 1e-12) {
            fprintf(stderr, "FAIL LU x[%d]=%.17g want %.17g\n", i, b[i], expected[i]);
            return 1;
        }
    }
    for (i = 1; i <= 3; ++i) {
        double residual = 0.0;
        for (j = 1; j <= 3; ++j) residual += original[i][j] * b[j];
        if (fabs(residual - (double[]){0.0, 1.0, -2.0, 3.0}[i]) > 1e-12) return 1;
    }
    puts("PASS: LU factorisation and back-substitution solve a pivoted system");
    return 0;
}
