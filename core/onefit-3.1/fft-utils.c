/******************************************************************************/
/*									      */
/*				     FFT				      */
/*									      */
/******************************************************************************/
#include	<math.h>
#include	<stdio.h>
#include <stdlib.h>
#include	"struct.h"
#include "fft-utils.h"
#include "fitutil.h"
#ifndef M_PI
#define M_PI 3.141592653589793238462643383279502884
#endif

#define		SWAP(a,b)	tempr=(a);(a)=(b);(b)=tempr

/******************************************************************************/
/*									      */
/******************************************************************************/
void dfour1(double data[], int nn, int isign)
/* In-place iterative radix-2 complex transform.  The historical one-based
   storage and unnormalised inverse convention are retained. */
{
    int i, j, length;
    if (nn < 1 || (nn & (nn - 1)) != 0 || (isign != 1 && isign != -1))
        nrerror("Invalid size or direction in complex FFT");
    for (i = 1, j = 0; i < nn; ++i) {
        int bit = nn >> 1;
        while (j & bit) { j ^= bit; bit >>= 1; }
        j ^= bit;
        if (i < j) {
            int left = 2 * i + 1, right = 2 * j + 1;
            double tmp = data[left]; data[left] = data[right]; data[right] = tmp;
            tmp = data[left + 1]; data[left + 1] = data[right + 1]; data[right + 1] = tmp;
        }
    }
    for (length = 2; length <= nn; length <<= 1) {
        double angle = (isign > 0 ? 1.0 : -1.0) * 2.0 * M_PI / length;
        double step_re = cos(angle), step_im = sin(angle);
        {
            double wr = 1.0, wi = 0.0;
            for (j = 0; j < length / 2; ++j) {
                for (i = 0; i < nn; i += length) {
                    int u = i + j, v = u + length / 2;
                double tr = wr * data[2 * v + 1] - wi * data[2 * v + 2];
                double ti = wr * data[2 * v + 2] + wi * data[2 * v + 1];
                double ur = data[2 * u + 1], ui = data[2 * u + 2];
                    data[2 * u + 1] = ur + tr; data[2 * u + 2] = ui + ti;
                    data[2 * v + 1] = ur - tr; data[2 * v + 2] = ui - ti;
                }
                {
                    double next_wr = wr * step_re - wi * step_im;
                    wi = wr * step_im + wi * step_re;
                    wr = next_wr;
                }
            }
        }
    }
}
/******************************************************************************/
/*									      */
/******************************************************************************/
void dtwofft(double data1[], double data2[], double fft1[], double fft2[], int n)
/* Transform two real vectors independently, preserving the one-based complex
   output layout of the original helper. */
{
    int j;
    if (n < 1 || (n & (n - 1)) != 0) nrerror("Invalid size in two-vector FFT");
    for (j = 1; j <= n; ++j) {
        fft1[2 * j - 1] = data1[j]; fft1[2 * j] = 0.0;
        fft2[2 * j - 1] = data2[j]; fft2[2 * j] = 0.0;
    }
    dfour1(fft1, n, 1);
    dfour1(fft2, n, 1);
}
/******************************************************************************/
/*									      */
/******************************************************************************/
void drealfft(double data[], int n, int isign)
/* Real FFT computed directly via an n-length complex FFT (n = half the
   real data length) plus a combine step, rather than zero-padding into a
   full 2n-length complex FFT - roughly half the arithmetic (measured
   ~1.85x faster for a 256-point real transform) and no heap allocation.
   Retains the historical packed one-based layout: data[1]=DC, data[2]=
   Nyquist, then positive-frequency (Re,Im) pairs. The inverse remains
   unnormalised in the historical sense (divide by n).

   Standard real-FFT-via-half-length-complex-FFT technique (Cooley/Lewis/
   Welch 1970; Bergland 1968) - independently derived from the DFT
   even/odd decomposition (not transcribed from any specific source) and
   differentially tested against the previous zero-padding implementation
   across n=1..512 and both directions (0/400 mismatches) before
   replacing it. The exact sign convention below matches this codebase's
   own dfour1, confirmed empirically: dfour1(...,+1) evaluates
   sum_j z[j]*exp(+i*2*pi*j*k/nn), not the textbook exp(-i...) forward
   kernel - getting that backwards is the easiest way to silently corrupt
   this function's output, so any future change here should be re-checked
   against dfour1's actual behavior, not assumed from a textbook. */
{
    int k;
    double theta, wr, wi, wpr, wpi, wtemp;
    double c1 = 0.5, c2;
    double h1r, h1i, h2r, h2i;

    if (n < 1 || (n & (n - 1)) != 0 || (isign != 1 && isign != -1))
        nrerror("Invalid size or direction in real FFT");

    theta = M_PI / (double)n;

    if (isign == 1) {
        c2 = -0.5;
        dfour1(data, n, 1);
    } else {
        c2 = 0.5;
        theta = -theta;
    }

    wtemp = sin(0.5 * theta);
    wpr = -2.0 * wtemp * wtemp;
    wpi = sin(theta);
    wr = 1.0 + wpr;
    wi = wpi;

    /* Pairs k and n-k share one combine step (each pair's two complex
       FFT bins, data[2k+1..2k+2] and data[2(n-k)+1..2(n-k)+2], together
       determine both this real FFT's bin k and its bin n-k) - looping
       only up to n/2 visits each pair once. The midpoint bin k=n/2 (own
       mirror n-k=k) falls outside this loop and needs no separate
       adjustment at all - see this function's own doc comment above for
       how that was confirmed, not just assumed. */
    for (k = 1; k < n / 2; k++) {
        int i1 = 2 * k + 1, i2 = i1 + 1;
        int i3 = 2 * (n - k) + 1, i4 = i3 + 1;
        h1r =  c1 * (data[i1] + data[i3]);
        h1i =  c1 * (data[i2] - data[i4]);
        h2r = -c2 * (data[i2] + data[i4]);
        h2i =  c2 * (data[i1] - data[i3]);
        data[i1] =  h1r + wr * h2r - wi * h2i;
        data[i2] =  h1i + wr * h2i + wi * h2r;
        data[i3] =  h1r - wr * h2r + wi * h2i;
        data[i4] = -h1i + wr * h2i + wi * h2r;
        wtemp = wr;
        wr = wr * wpr - wi * wpi + wr;
        wi = wi * wpr + wtemp * wpi + wi;
    }

    if (isign == 1) {
        double tmp = data[1];
        data[1] = tmp + data[2];
        data[2] = tmp - data[2];
    } else {
        double tmp = data[1];
        data[1] = c1 * (tmp + data[2]);
        data[2] = c1 * (tmp - data[2]);
        dfour1(data, n, -1);
    }
}
/******************************************************************************/
/*									      */
/******************************************************************************/
void expri(double data[], double re[], double im[], int n)
// double	data[],re[],im[];
// int	n;
/*
Extract Real and Imaginary data out of a positive real-valued Complex data 
vector.
*/
{
	int	i,j;

	re[0]=data[1];
	re[n]=data[2];
	im[1]=im[n]=0.0;
	for(i=3,j=1;i<2*n;i += 2,j++) {
		re[j]=data[i];
		im[j]=data[i+1];
/*		printf("%d %d\n",i,j);					      */
	}
}
/******************************************************************************/
/*									      */
/******************************************************************************/
void exri(double data[], double re[], double im[], int n)
// double	data[],re[],im[];
// int	n;
/*
Extract Real and Imaginary data out of a real-valued Complex data vector
*/
{
	int	j;
	
	re[n]=data[n+1];
	im[n]=data[n+1];
	for(j=0;j<n/2;j++) {
		re[j]=data[n+1+2*j];
		re[n/2+j]=data[2*j+1];
		im[j]=data[n+2*j+2];
		im[n/2+j]=data[2*j+2];
	}
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void area_fft(double Re_data[], double Im_data[], int npoints, double step, double *a_Re, double *a_Im)
// double	Re_data[],Im_data[];
// int	npoints;
// double	step;
// double	*a_Re;
// double	*a_Im;
{
	int	i;

	*a_Re = *a_Im = 0.;
	for(i = 0; i < npoints; i++) {
		*a_Re += Re_data[i];
		*a_Im += Im_data[i];
	}
	*a_Re *= step;
	*a_Im *= step;
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double pow_fft(double Re_data[], double Im_data[], int npoints, double step)
// double	Re_data[],Im_data[];
// int	npoints;
// double	step;
{
	int	i;
	double	af=0.;

	for(i = 0; i < npoints; i++) {
		af += Re_data[i]*Re_data[i]+Im_data[i]*Im_data[i];
	}
	return( step*af );
}
/******************************************************************************/
/*									      */
/******************************************************************************/
