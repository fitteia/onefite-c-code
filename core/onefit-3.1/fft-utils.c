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
/* Real FFT using the full complex kernel, retaining the historical packed
   one-based layout: data[1]=DC, data[2]=Nyquist, then positive frequencies.
   The inverse remains unnormalised in the historical sense (divide by n). */
{
    double *spectrum;
    int k, length;

    if (n < 1 || (n & (n - 1)) != 0 || (isign != 1 && isign != -1))
        nrerror("Invalid size or direction in real FFT");
    length = 2 * n;
    spectrum = (double *)calloc((size_t)2 * length + 1, sizeof(*spectrum));
    if (spectrum == NULL) nrerror("Allocation failure in real FFT");

    if (isign == 1) {
        for (k = 0; k < length; ++k) {
            spectrum[2 * k + 1] = data[k + 1];
            spectrum[2 * k + 2] = 0.0;
        }
        dfour1(spectrum, length, 1);
        data[1] = spectrum[1];
        data[2] = spectrum[2 * n + 1];
        for (k = 1; k < n; ++k) {
            data[2 * k + 1] = spectrum[2 * k + 1];
            data[2 * k + 2] = spectrum[2 * k + 2];
        }
    } else {
        spectrum[1] = data[1];
        spectrum[2] = 0.0;
        spectrum[2 * n + 1] = data[2];
        spectrum[2 * n + 2] = 0.0;
        for (k = 1; k < n; ++k) {
            double real = data[2 * k + 1];
            double imag = data[2 * k + 2];
            spectrum[2 * k + 1] = real;
            spectrum[2 * k + 2] = imag;
            spectrum[2 * (length - k) + 1] = real;
            spectrum[2 * (length - k) + 2] = -imag;
        }
        dfour1(spectrum, length, -1);
        for (k = 0; k < length; ++k) data[k + 1] = 0.5 * spectrum[2 * k + 1];
    }
    free(spectrum);
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
