#include <stdio.h>
#include <float.h>
#include <math.h>
#include <stdlib.h>
#include "struct.h"
#include <string.h>
#include "integra.h"
#include "fitutil.h"

#define EPS1	3.0e-11
#define EPS	8.0e-5
#define	JMAX	20
#define	JMAXP	JMAX+1
#define	K	5
#define SIGN(a) ((a) > 0.0 ? 1 : -1)


double	r_pval(Function	*x, int n) { return( (*x).par[n].val); }

double	r_pmin(Function	*x, int n) { return( (*x).par[n].min_v); }

double	r_pstep(Function	*x, int n) { return( (*x).par[n].step_v); }

double	r_plow(Function *x, int n) { return( (*x).par[n].low_v); }

double	r_phigh(Function *x, int n) { return( (*x).par[n].high_v); }

int	r_n_par(Function *x) { return( (*x).n_par ); }

int	r_status(Function *x) { return( (*x).status ); }

int	r_pstatus(Function *x, int n) { return( (*x).par[n].status ); }

char *r_name(Function *x) { return( (*x).name ); }

char *r_pname(Function *x, int n) { return( (*x).par[n].name ); }

void	wsval(Function *x)
{
	int	i;

	for(i=0; i<r_n_par(x); i++) printf("p[%d]=%g\n",i,r_pval(x,i));
}

void	w_f_ptr(Function *x, double (*f)(Function *x)) { (*x).f_ptr = f; }

void	w_name(Function *x, char name[]) { strcpy( (*x).name, name ); }

void	w_status(Function *x, int status) { (*x).status = status; }

void	w_pname(Function *x, int n, char name[]) { strcpy( (*x).par[n].name, name ); }

void	w_plow(Function	*x, int n, double lv) { (*x).par[n].low_v = lv; }

void	w_phigh(Function *x, int n, double hv) { (*x).par[n].high_v = hv; }

void	w_pmin(Function *x, int n, double mv) { (*x).par[n].min_v = mv; }

void	w_pstatus(Function *x, int n, int status) { (*x).par[n].status = status; }

void	w_pstep(Function *x, int n, double sv) { (*x).par[n].step_v = sv; }

void	w_pval(Function *x, int n, double v) { (*x).par[n].val = v; }

void	clear_struct(Function *f_struct, int n_par)
{
	int	i;
	
	strcpy((*f_struct).name," ");
	(*f_struct).status 	=0;
	(*f_struct).n_par	=n_par;
	(*f_struct).f_ptr	=0;

	for (i=0; i<n_par; i++) {
			strcpy((*f_struct).par[i].name," ");
			(*f_struct).par[i].status	=0.0;
			(*f_struct).par[i].low_v	=0.0;
			(*f_struct).par[i].high_v	=0.0;
			(*f_struct).par[i].step_v	=0.0;
			(*f_struct).par[i].val  	=0.0;
			(*f_struct).par[i].min_v	=0.0;
	}
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double smidpnt(Function *X, int p, int n)
/* Stateful midpoint refinement retained for legacy callers. */
{
    double a = r_plow(X, p), b = r_phigh(X, p);
    double *value = &X->par[p].val;
    double *estimate = &X->par[p].min_v;
    double *panels = &X->par[p].step_v;
    int j;
    if (n < 1) nrerror("Invalid refinement level in midpoint integration");
    if (a == b) return 0.0;
    if (n == 1) {
        *panels = 1.0;
        *value = 0.5 * (a + b);
        *estimate = (b - a) * FUNC(X);
        return *estimate;
    }
    {
        double previous_panels = *panels;
        double spacing = (b - a) / (3.0 * previous_panels);
        double total = 0.0;
        *value = a + 0.5 * spacing;
        for (j = 0; j < (int)previous_panels; ++j) {
            total += FUNC(X);
            *value += 2.0 * spacing;
            total += FUNC(X);
            *value += spacing;
        }
        *panels = 3.0 * previous_panels;
        *estimate = (*estimate + (b - a) * total / previous_panels) / 3.0;
    }
    return *estimate;
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
static double ofe_simpson_value(Function *X, int p, double x)
{
    w_pval(X, p, x);
    return FUNC(X);
}

static double ofe_simpson_refine(Function *X, int p, double left, double right,
                                 double fleft, double fmid, double fright,
                                 double whole, double tolerance, int depth)
{
    double mid = 0.5 * (left + right);
    double lmid = 0.5 * (left + mid);
    double rmid = 0.5 * (mid + right);
    double flmid = ofe_simpson_value(X, p, lmid);
    double frmid = ofe_simpson_value(X, p, rmid);
    double left_area = (mid - left) * (fleft + 4.0 * flmid + fmid) / 6.0;
    double right_area = (right - mid) * (fmid + 4.0 * frmid + fright) / 6.0;
    double refined = left_area + right_area;

    if (depth <= 0 || fabs(refined - whole) <= 15.0 * tolerance)
        return refined + (refined - whole) / 15.0;
    return ofe_simpson_refine(X, p, left, mid, fleft, flmid, fmid,
                              left_area, tolerance * 0.5, depth - 1)
         + ofe_simpson_refine(X, p, mid, right, fmid, frmid, fright,
                              right_area, tolerance * 0.5, depth - 1);
}

double sqromo(Function *X, double (*choose)(Function *a, int b, int c), int p)
/* Adaptive Simpson integration replacing the old Romberg/midpoint tableau.
   `choose` remains accepted for source compatibility; the adaptive evaluator
   controls refinement directly and evaluates the supplied function at finite
   points including the interval endpoints. */
{
    double left = r_plow(X, p), right = r_phigh(X, p);
    double mid, fleft, fmid, fright, whole, tolerance;
    (void)choose;
    if (left == right) return 0.0;
    mid = 0.5 * (left + right);
    fleft = ofe_simpson_value(X, p, left);
    fmid = ofe_simpson_value(X, p, mid);
    fright = ofe_simpson_value(X, p, right);
    whole = (right - left) * (fleft + 4.0 * fmid + fright) / 6.0;
    tolerance = 1.0e-10 + EPS * fabs(whole);
    return ofe_simpson_refine(X, p, left, right, fleft, fmid, fright,
                              whole, tolerance, 20);
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double sqgaus(Function *X, int p)
{
	static double nodes[11], weights[11];
	static int initialized = 0;
	double a = r_plow(X, p), b = r_phigh(X, p);
	double midpoint = 0.5 * (a + b), half_width = 0.5 * (b - a), sum = 0.0;
	if (!initialized) {
		gauleg(-1.0, 1.0, nodes, weights, 10);
		initialized = 1;
	}
	X->par[p].val = midpoint - half_width * nodes[1]; sum += weights[1] * X->f_ptr(X);
	X->par[p].val = midpoint + half_width * nodes[1]; sum += weights[1] * X->f_ptr(X);
	X->par[p].val = midpoint - half_width * nodes[2]; sum += weights[2] * X->f_ptr(X);
	X->par[p].val = midpoint + half_width * nodes[2]; sum += weights[2] * X->f_ptr(X);
	X->par[p].val = midpoint - half_width * nodes[3]; sum += weights[3] * X->f_ptr(X);
	X->par[p].val = midpoint + half_width * nodes[3]; sum += weights[3] * X->f_ptr(X);
	X->par[p].val = midpoint - half_width * nodes[4]; sum += weights[4] * X->f_ptr(X);
	X->par[p].val = midpoint + half_width * nodes[4]; sum += weights[4] * X->f_ptr(X);
	X->par[p].val = midpoint - half_width * nodes[5]; sum += weights[5] * X->f_ptr(X);
	X->par[p].val = midpoint + half_width * nodes[5]; sum += weights[5] * X->f_ptr(X);
	return half_width * sum;
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void gauleg(double x1, double x2, double x[], double w[], int n)
{
	int half, degree, i;
	double midpoint, half_width;
	if (n < 1 || !isfinite(x1) || !isfinite(x2))
		nrerror("Invalid interval or order in Gauss-Legendre quadrature");
	half = (n + 1) / 2;
	midpoint = 0.5 * (x1 + x2);
	half_width = 0.5 * (x2 - x1);
	for (i = 1; i <= half; ++i) {
		double z = cos(3.141592653589793 * (i - 0.25) / (n + 0.5));
		double derivative = 0.0;
		int iteration;
		for (iteration = 0; iteration < 100; ++iteration) {
			double p_prev = 1.0, p = z, p_next;
			for (degree = 2; degree <= n; ++degree) {
				p_next = (((2.0 * degree - 1.0) * z * p)
				          - (degree - 1.0) * p_prev) / degree;
				p_prev = p;
				p = p_next;
			}
			if (n == 1) { p = z; p_prev = 1.0; }
			derivative = n * (z * p - p_prev) / (z * z - 1.0);
			p_next = z - p / derivative;
			if (fabs(p_next - z) <= EPS1) { z = p_next; break; }
			z = p_next;
		}
		if (iteration == 100) nrerror("Gauss-Legendre root did not converge");
		/* Small fixed-order rules are often used as accuracy-critical model
		   kernels; refresh the derivative at the converged root for them. */
		if (n <= 16) {
			double p_prev = 1.0, p = z, p_next;
			for (degree = 2; degree <= n; ++degree) {
				p_next = (((2.0 * degree - 1.0) * z * p)
				          - (degree - 1.0) * p_prev) / degree;
				p_prev = p; p = p_next;
			}
			if (n == 1) { p = z; p_prev = 1.0; }
			derivative = n * (z * p - p_prev) / (z * z - 1.0);
		}
		x[i] = midpoint - half_width * z;
		x[n + 1 - i] = midpoint + half_width * z;
		w[i] = 2.0 * half_width / ((1.0 - z * z) * derivative * derivative);
		w[n + 1 - i] = w[i];
	}

}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double sqgausn(Function *X, int p, int n)
{
	int j;
	double a,b,s,*x,*w;

	a = r_plow(X,p);
	b = r_phigh(X,p);

	x = dvector(0,n);
	w = dvector(0,n);

	gauleg(a,b,x,w,n);

	s=0;
	for (j=1;j<=n;j++) {
		w_pval(X,p,x[j]);
		s += w[j]*FUNC(X);
	}
	free_dvector(x,0,n);
	free_dvector(w,0,n);

	return s;
}

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double szero(Function *X, int n, double eps)
/* Bounded Brent root finder retaining the historical Function callback ABI. */
{
    double a = X->par[n].low_v, b = X->par[n].high_v;
    double c = a, d = b - a, e = d, fa, fb, fc;
    int iteration;
    if (!(eps > 0.0) || !isfinite(eps)) nrerror("Invalid tolerance in root finder");
    X->par[n].val = a; fa = FUNC(X);
    X->par[n].val = b; fb = FUNC(X);
    if (fa == 0.0) return a;
    if (fb == 0.0) return b;
    if (!isfinite(fa) || !isfinite(fb) || fa * fb > 0.0)
        nrerror("Root is not bracketed");
    fc = fa;
    for (iteration = 0; iteration < 100; ++iteration) {
        if ((fb > 0.0 && fc > 0.0) || (fb < 0.0 && fc < 0.0)) {
            c = a; fc = fa; d = b - a; e = d;
        }
        if (fabs(fc) < fabs(fb)) {
            double old_a = a, old_fa = fa;
            a = b; fa = fb; b = c; fb = fc; c = old_a; fc = old_fa;
        }
        {
            double tolerance = 2.0 * DBL_EPSILON * fabs(b) + 0.5 * eps;
            double midpoint = 0.5 * (c - b);
            double p, q, r, s;
            if (fabs(midpoint) <= tolerance || fb == 0.0) {
                X->par[n].val = b;
                return b;
            }
            if (fabs(e) >= tolerance && fabs(fa) > fabs(fb)) {
                s = fb / fa;
                if (a == c) { p = 2.0 * midpoint * s; q = 1.0 - s; }
                else {
                    q = fa / fc; r = fb / fc;
                    p = s * (2.0 * midpoint * q * (q - r) - (b - a) * (r - 1.0));
                    q = (q - 1.0) * (r - 1.0) * (s - 1.0);
                }
                if (p > 0.0) q = -q; else p = -p;
                if (2.0 * p < fmin(3.0 * midpoint * q - fabs(tolerance * q), fabs(e * q))) {
                    e = d; d = p / q;
                } else d = midpoint, e = midpoint;
            } else d = midpoint, e = midpoint;
            a = b; fa = fb;
            b += (fabs(d) > tolerance) ? d : copysign(tolerance, midpoint);
            X->par[n].val = b; fb = FUNC(X);
        }
    }
    nrerror("Root finder did not converge");
    return b;
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
#undef 	EPS1   
#undef  SIGN
#undef  EPS
#undef 	JMAX
#undef	JMAXP
#undef	K
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
