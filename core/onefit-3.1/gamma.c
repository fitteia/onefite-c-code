#include <float.h>
#include <math.h>
#include <stdio.h>
#include "gamma.h"
#include "fitutil.h"

#define GAMMA_MAX_ITER 10000
#define GAMMA_EPS 1.0e-12

/* Regularised incomplete gamma functions.  The public API is retained, but
   the old Numerical Recipes coefficient approximation is replaced by libm's
   log-gamma and independently written series/continued-fraction evaluators. */
double gammln(double xx)
{
    if (!(xx > 0.0) || !isfinite(xx)) return NAN;
    return lgamma(xx);
}

void gser(double *gamser, double a, double x, double *gln)
{
    double term, sum, ap, scale;
    int n;

    if (!(a > 0.0) || x < 0.0 || !isfinite(a) || !isfinite(x))
        nrerror("Invalid arguments in lower incomplete gamma");
    *gln = gammln(a);
    if (x == 0.0) {
        *gamser = 0.0;
        return;
    }
    ap = a;
    term = sum = 1.0 / a;
    for (n = 1; n <= GAMMA_MAX_ITER; ++n) {
        ap += 1.0;
        term *= x / ap;
        sum += term;
        if (fabs(term) <= fabs(sum) * GAMMA_EPS) {
            scale = exp(-x + a * log(x) - *gln);
            *gamser = sum * scale;
            return;
        }
    }
    nrerror("Lower incomplete gamma series did not converge");
}

void gcf(double *gammcf, double a, double x, double *gln)
{
    double b, c, d, h, an, delta, scale;
    int n;

    if (!(a > 0.0) || x < 0.0 || !isfinite(a) || !isfinite(x))
        nrerror("Invalid arguments in upper incomplete gamma");
    *gln = gammln(a);
    if (x == 0.0) {
        *gammcf = 1.0;
        return;
    }
    b = x + 1.0 - a;
    c = 1.0 / DBL_MIN;
    d = fabs(b) < DBL_MIN ? 1.0 / DBL_MIN : 1.0 / b;
    h = d;
    for (n = 1; n <= GAMMA_MAX_ITER; ++n) {
        an = -(double)n * ((double)n - a);
        b += 2.0;
        d = an * d + b;
        if (fabs(d) < DBL_MIN) d = copysign(DBL_MIN, d);
        c = b + an / c;
        if (fabs(c) < DBL_MIN) c = copysign(DBL_MIN, c);
        d = 1.0 / d;
        delta = d * c;
        h *= delta;
        if (fabs(delta - 1.0) <= GAMMA_EPS) {
            scale = exp(-x + a * log(x) - *gln);
            *gammcf = scale * h;
            return;
        }
    }
    nrerror("Upper incomplete gamma continued fraction did not converge");
}

double gammq(double a, double x)
{
    double lower, upper, gln;

    if (x < 0.0 || a <= 0.0 || !isfinite(a) || !isfinite(x)) return -1.0;
    /* For small integral shapes the regularised upper function is a finite
       Poisson sum.  This avoids an iterative series/continued fraction in a
       common fitting case while retaining the same mathematical result. */
    if (a == floor(a) && a <= 64.0 && x < 700.0) {
        double term = 1.0, sum = 1.0;
        int k;
        for (k = 1; k < (int)a; ++k) {
            term *= x / (double)k;
            sum += term;
        }
        return exp(-x) * sum;
    }
    if (x < a + 1.0) {
        gser(&lower, a, x, &gln);
        return 1.0 - lower;
    }
    gcf(&upper, a, x, &gln);
    return upper;
}
