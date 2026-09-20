#include <math.h>
#include <stdio.h>
#include "struct.h"
double sqromo(Function *X, double (*choose)(Function *, int, int), int p);
double sqgaus(Function *X, int p);
void clear_struct(Function *X, int npar);
static double square(Function *X) { double x = X->par[0].val; return x * x; }
void gauleg(double x1, double x2, double x[], double w[], int n);
int main(void)
{
    double x[9], w[9], sum = 0.0;
    int i, p;
    gauleg(-1.0, 1.0, x, w, 8);
    for (i = 1; i <= 8; ++i) {
        if (!(x[i] > -1.0 && x[i] < 1.0) || w[i] <= 0.0) return 1;
        sum += w[i] * (x[i]*x[i]*x[i]*x[i]*x[i]*x[i] + 2.0*x[i]*x[i] + 1.0);
    }
    if (fabs(sum - (2.0/7.0 + 4.0/3.0 + 2.0)) > 1e-12) return 1;
    {
        Function function;
        clear_struct(&function, 1);
        function.par[0].low_v = -2.0;
        function.par[0].high_v = 3.0;
        function.f_ptr = square;
        if (fabs(sqromo(&function, NULL, 0) - (27.0 - (-8.0)) / 3.0) > 1e-10)
            return 1;
        if (fabs(sqgaus(&function, 0) - (27.0 - (-8.0)) / 3.0) > 1e-12)
            return 1;
    }
    puts("PASS: Gauss-Legendre and adaptive integration reproduce analytic integrals");
    return 0;
}
