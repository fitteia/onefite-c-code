#include <stdio.h>
#include "lubksb.h"
#include "fitutil.h"

/* Solve the vector equation using the row-pivoted LU factors from ludcmp. */
void lubksb(double **a, int n, int *indx, double b[])
{
    int i, j;
    int first_nonzero = 0;

    if (n < 1) nrerror("Empty matrix in LU back-substitution");
    for (i = 1; i <= n; ++i) {
        int pivot_row = indx[i];
        double sum = b[pivot_row];
        b[pivot_row] = b[i];
        if (first_nonzero) {
            for (j = first_nonzero; j < i; ++j) sum -= a[i][j] * b[j];
        } else if (sum != 0.0) {
            first_nonzero = i;
        }
        b[i] = sum;
    }
    for (i = n; i >= 1; --i) {
        double sum = b[i];
        for (j = i + 1; j <= n; ++j) sum -= a[i][j] * b[j];
        if (a[i][i] == 0.0) nrerror("Singular matrix in LU back-substitution");
        b[i] = sum / a[i][i];
    }
}
