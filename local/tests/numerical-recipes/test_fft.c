#include <math.h>
#include <stdio.h>
#include <string.h>
#include "fft-utils.h"

static int close(double a, double b) { return fabs(a-b) < 1e-10; }
int main(void)
{
    double z[9] = {0, 1,0, 2,0, 3,0, 4,0};
    double real_data[9] = {0, 1,2,3,4,5,6,7,8}, real_original[9];
    double original[9];
    double a[5] = {0,1,2,3,4}, b[5] = {0,4,3,2,1};
    double fa[9] = {0}, fb[9] = {0}, ca[9] = {0}, cb[9] = {0};
    int i;
    memcpy(original,z,sizeof z);
    memcpy(real_original, real_data, sizeof real_data);
    dfour1(z,4,1);
    dfour1(z,4,-1);
    for (i=1;i<=8;++i) if (!close(z[i],4.0*original[i])) return 1;
    dtwofft(a,b,fa,fb,4);
    for (i=1;i<=4;++i) { ca[2*i-1]=a[i]; cb[2*i-1]=b[i]; }
    dfour1(ca,4,1); dfour1(cb,4,1);
    for (i=1;i<=8;++i) if (!close(fa[i],ca[i]) || !close(fb[i],cb[i])) return 1;
    drealfft(real_data, 4, 1);
    drealfft(real_data, 4, -1);
    for (i=1;i<=8;++i) if (!close(real_data[i] / 4.0, real_original[i])) return 1;
    puts("PASS: complex, real-packed, and two-vector FFT transforms agree");
    return 0;
}
