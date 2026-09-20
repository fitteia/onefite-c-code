#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "struct.h"
#include "fitutil.h"
#include "integra.h"
#include "dif_phase.h"

#define CA 0.0003
#define PIO2 1.57079632679490
#define SIGN(a) ((a) > 0.0 ? 1 : -1)
/******************************************************************************/
/*				DIF_PHASE.C				      */
/******************************************************************************/
double dif_phase(double H, double par[])
// double	H,par[];
{
	Function X;
	double	a1,a2,af;
	double	x,phiM,niu,H0;

	H0   = par[1];
	x    = par[2]-1.0;
	niu  = par[3];

	clear_struct(&X,5);

	X.par[0].low_v  = 0.0;
	X.par[0].high_v = 89.0*PIO2/90.0; 
	X.par[1].val    = H0;
	X.par[2].val    = x;
	X.par[3].val    = niu;
	X.par[4].val    = H;
	w_f_ptr(&X,calc_phiM);

	phiM = szero(&X,0,1e-6);

	clear_struct(&X,4);
	X.par[0].low_v  = 0.0;
	X.par[0].high_v = PIO2; 
	X.par[1].val    = phiM;
	X.par[2].val    = x;
	X.par[3].val    = niu;
	w_f_ptr(&X,integranda);

	a2 = sqromo(&X,smidpnt,0);
	af = (1-1.0/PIO2*H0/H*a2);

	return af;
}
/******************************************************************************/
/*									      */
/******************************************************************************/
double	integranda(Function *X)
// Function *X;
{
	double	x,phiM,qzi,niu,af,s1,s2;

	qzi  = r_pval(X,0);
	phiM = r_pval(X,1);
	x    = r_pval(X,2);
	niu  = r_pval(X,3);
	
	s1   = sin(phiM)*sin(phiM);
	s2   = sin(qzi)*sin(qzi);
	af   = sqrt( (1+x*s1*s2)/((1-s1*s2)*(1+niu*s1*s2)) );

	return af;
}
/******************************************************************************/
/*									      */
/******************************************************************************/
double	calc_phiM(Function *X)
// Function *X;
{
	double	x,phiM,niu,alfa2,k,H0,H;
	double  af,s1,a1;

	phiM = r_pval(X,0);
	H0   = r_pval(X,1);
	x    = r_pval(X,2);
	niu  = r_pval(X,3);
	H    = r_pval(X,4);

	s1   = sin(phiM)*sin(phiM);
	alfa2= x*s1/(1+x*s1);
	k    = sqrt( (1+x)*s1/(1+x*s1) );

	a1   = dcel( sqrt(1-k*k),1-alfa2,1.0,1.0);
	af   = H0-PIO2*sqrt(1+x*s1)/a1*H;
	return af;
}
/******************************************************************************/
/*									      */
/******************************************************************************/
double dcel(double qqc, double pp, double aa, double bb)
// double qqc,pp,aa,bb;
{
	double a,b,e,f,g,em,p,q,qc;

	if (qqc == 0.0) nrerror("Bad qqc in routine CEL");
	qc=fabs(qqc);
	a=aa;
	b=bb;
	p=pp;
	e=qc;
	em=1.0;
	if (p > 0.0) {
		p=sqrt(p);
		b /= p;
	} else {
		f=qc*qc;
		q=1.0-f;
		g=1.0-p;
		f -= p;
		q *= (b-a*p);
		p=sqrt(f/g);
		a=(a-b)/g;
		b = -q/(g*g*p)+a*p;
	}
	for (;;) {
		f=a;
		a += (b/p);
		g=e/p;
		b += (f*g);
		b += b;
		p=g+p;
		g=em;
		em += qc;
		if (fabs(g-qc) <= g*CA) break;
		qc=sqrt(e);
		qc += qc;
		e=qc*em;
	}
	return PIO2*(b+a*em)/(em*(em+p));
}
/******************************************************************************/
/*									      */
/******************************************************************************/
/* The root-finder implementation is provided by integra.c. */
/******************************************************************************/
/*									      */
/******************************************************************************/

#undef CA
#undef PIO2
#undef SIGN
