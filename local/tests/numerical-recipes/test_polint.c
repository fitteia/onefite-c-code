#include <math.h>
#include <stdio.h>
#include <stdlib.h>

void dpolint(double xa[], double ya[], int n, double x, double *y, double *dy);

/* Private oracle copied only for migration comparison; remove this test when
 * the replacement is accepted so the release tree contains no NR code. */
static void nr_reference_polint(double xa[], double ya[], int n, double x,
                                double *y, double *dy)
{
    int i, m, ns = 1;
    double den, dif, dift, ho, hp, w;
    double c[32], d[32];
    dif = fabs(x - xa[1]);
    for (i = 1; i <= n; ++i) {
        if ((dift = fabs(x - xa[i])) < dif) { ns = i; dif = dift; }
        c[i] = d[i] = ya[i];
    }
    *y = ya[ns--];
    for (m = 1; m < n; ++m) {
        for (i = 1; i <= n - m; ++i) {
            ho = xa[i] - x; hp = xa[i + m] - x; w = c[i + 1] - d[i];
            den = w / (ho - hp); d[i] = hp * den; c[i] = ho * den;
        }
        *y += (*dy = (2 * ns < (n - m) ? c[ns + 1] : d[ns--]));
    }
}

/* Independent barycentric Lagrange implementation.  Arrays retain the
 * historical 1-based convention used by OneFit. */
static int ofe_polint(const double xa[], const double ya[], int n, double x,
                      double *y, double *dy)
{
    int i, j;
    double *w = calloc((size_t)n + 1, sizeof(*w));
    if (!w || n < 1) { free(w); return 0; }
    for (i = 1; i <= n; ++i) {
        w[i] = 1.0;
        for (j = 1; j <= n; ++j) {
            if (i == j) continue;
            if (xa[i] == xa[j]) { free(w); return 0; }
            w[i] /= xa[i] - xa[j];
        }
    }
    for (i = 1; i <= n; ++i) {
        if (x == xa[i]) { *y = ya[i]; *dy = 0.0; free(w); return 1; }
    }
    {
        double numerator = 0.0, denominator = 0.0;
        for (i = 1; i <= n; ++i) {
            double term = w[i] / (x - xa[i]);
            numerator += term * ya[i];
            denominator += term;
        }
        *y = numerator / denominator;
    }
    *dy = 0.0;
    free(w);
    return isfinite(*y);
}

static double midpoint_exp(int level)
{
    int i, count = 1;
    double h, sum = 0.0, x;
    for (i = 1; i < level; ++i) count *= 3;
    h = 1.0 / (double)count;
    for (i = 0; i < count; ++i) {
        x = ((double)i + 0.5) * h;
        sum += exp(-x * x);
    }
    return sum * h;
}

static int test_romberg(void)
{
    int j, i;
    double h[8], value[8], result, error;
    const double expected = 0.7468241328124271;
    h[1] = 1.0;
    for (j = 1; j <= 7; ++j) {
        value[j] = midpoint_exp(j);
        if (j >= 5) {
            double xa[6], ya[6], dy;
            for (i = 1; i <= 5; ++i) {
                xa[i] = h[j - 5 + i];
                ya[i] = value[j - 5 + i];
            }
            dpolint(xa, ya, 5, 0.0, &result, &dy);
            error = fabs(result - expected);
            if (error < 1e-10) return 1;
        }
        h[j + 1] = h[j] / 9.0;
    }
    return 0;
}

int main(void)
{
    unsigned seed = 0x4f4645u;
    int n, trial, i;
    for (n = 1; n <= 12; ++n) {
        for (trial = 0; trial < 200; ++trial) {
            double xa[13], ya[13], x;
            double old_y, old_dy, new_y, new_dy, prod_y, prod_dy;
            for (i = 1; i <= n; ++i) {
                seed = 1664525u * seed + 1013904223u;
                xa[i] = (double)(i * 3) + (double)(seed % 1000) / 10000.0;
                ya[i] = sin(xa[i]) + 0.1 * cos(2.0 * xa[i]);
            }
            seed = 1664525u * seed + 1013904223u;
            x = xa[1] + (xa[n] - xa[1]) * (double)(seed % 1000) / 1000.0;
            nr_reference_polint(xa, ya, n, x, &old_y, &old_dy);
            dpolint(xa, ya, n, x, &prod_y, &prod_dy);
            if (!ofe_polint(xa, ya, n, x, &new_y, &new_dy) ||
                (fabs(new_y - old_y) > 2e-12 * (1.0 + fabs(old_y)) ||
                 fabs(prod_y - old_y) > 2e-12 * (1.0 + fabs(old_y)))) {
                fprintf(stderr, "FAIL n=%d trial=%d old=%.17g new=%.17g\n",
                        n, trial, old_y, new_y);
                return 1;
            }
        }
    }
    if (!test_romberg()) {
        fprintf(stderr, "FAIL: Romberg integration did not converge\n");
        return 1;
    }
    puts("PASS: independent barycentric interpolation matches dpolint and Romberg converges");
    return 0;
}
