#include <stdio.h>
#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "struct.h"
#include "fitk_util.h"
#include "fitutil.h"

#define EPS1	3.0e-11
#define EPS	8.0e-5

/*****************************************************************************/
/*                             FITK_UTIL.C                                   */
/*****************************************************************************/
int	r_n_par(Function *x)
// Function	*x;
{
	return( (*x).n_par );
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void	wsval(Function *X)
// Function *X;
{
	long int	i;

	for(i=0; i<r_n_par(X); i++) printf("p[%ld]=%lg\n",i,r_pval(X,i));
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void	w_f_ptr(Function *x,double		(*f)(Function *a))
// double		(*f)();
// Function	*x;
{
	(*x).f_ptr = f;
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double	r_plow(Function *x, int n)
// int		n;
// Function	*x;
{
	return( (*x).par[n].low_v);
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void	w_plow(Function *x, int n, double lv)
// int		n;
// double		lv;
// Function	*x;
{
	(*x).par[n].low_v = lv;
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double	r_phigh(Function *x, int n)
// int		n;
// Function	*x;
{
	return( (*x).par[n].high_v);
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void	w_phigh(Function *x, int n, double hv)
// int		n;
// double		hv;
// Function	*x;
{
	(*x).par[n].high_v = hv;
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double	r_pstep(Function *x, int n)
// int		n;
// Function	*x;
{
	return( (*x).par[n].step_v);
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void	w_pstep(Function *x, int n, double sv)
// int		n;
// double		sv;
// Function	*x;
{
	(*x).par[n].step_v = sv;
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double	r_pval(Function *x, int n)
// int		n;
// Function	*x;
{
	return( (*x).par[n].val);
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void	w_pval(Function *x, int n, double v)
// int		n;
// double		v;
// Function	*x;
{
	(*x).par[n].val = v;
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void	clear_struct(Function *f_struct, int n_par)
// Function	*f_struct;
// int	n_par;
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
