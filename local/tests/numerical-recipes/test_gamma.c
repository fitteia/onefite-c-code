#include <math.h>
#include <stdio.h>

double gammln(double x);
double gammq(double a, double x);

static int close(double got, double want)
{
    return fabs(got - want) <= 5e-13 * fmax(1.0, fabs(want));
}

int main(void)
{
    const double pi = acos(-1.0);
    if (!close(gammln(1.0), 0.0) ||
        !close(gammln(0.5), log(sqrt(pi))) ||
        !close(gammln(5.0), log(24.0))) return 1;
    if (!close(gammq(1.0, 2.0), exp(-2.0)) ||
        !close(gammq(2.0, 3.0), 4.0 * exp(-3.0)) ||
        !close(gammq(3.0, 4.0), (1.0 + 4.0 + 8.0) * exp(-4.0)) ||
        !close(gammq(0.5, 1.0), erfc(1.0))) return 1;
    puts("PASS: log-gamma and regularised upper incomplete gamma agree with analytic values");
    return 0;
}
