#include <math.h>
#include <stdio.h>
#include "struct.h"
double szero(Function *X, int n, double eps);
void clear_struct(Function *X, int npar);
static double root_function(Function *X) { double x = X->par[0].val; return x*x - 2.0; }
int main(void) { Function f; clear_struct(&f,1); f.par[0].low_v=0; f.par[0].high_v=2; f.f_ptr=root_function; if (fabs(szero(&f,0,1e-12)-sqrt(2.0))>1e-11) return 1; puts("PASS: Brent root finder locates a bracketed analytic root"); return 0; }
