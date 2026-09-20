/*****************************************************************************/
/*             FITUTIL.C                                    */
/*****************************************************************************/
#ifndef MacOSX
     #include "malloc.h"
#endif
#include "stdio.h"
#include "math.h"
#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "fitutil.h" 

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void nrerror(char error_text[])
{
   fprintf(stderr,"OneFit run-time error...\n");
   fprintf(stderr,"%s\n",error_text);
   fprintf(stderr,"...now exiting to system...\n");
   exit(1);
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void gfitn_error(char error_text[],char option_msg[])
{
   fprintf(stderr,"OneFit run-time error...\n");
   fprintf(stderr,"%s %s\n",error_text,option_msg);
   fprintf(stderr,"...now exiting to system...\n");
   exit(1);
}

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
/* The public one-based allocation API is retained for source compatibility.
   Allocation is centralized here so bounds and byte-size overflow are checked
   before the historical indexed pointer view is returned. */
static void *indexed_alloc(int low, int high, size_t width, const char *name)
{
   size_t count;
   unsigned char *base;
   if (high < low || width == 0 ||
       (size_t)(high - low) > SIZE_MAX / width - 1)
      nrerror("invalid indexed allocation range");
   count = (size_t)(high - low) + 1;
   base = (unsigned char *)calloc(count, width);
   if (!base) {
      char message[96];
      snprintf(message, sizeof(message), "allocation failure in %s()", name);
      nrerror(message);
   }
   return base - (ptrdiff_t)low * (ptrdiff_t)width;
}

int *ivector(int nl, int nh)
{
   return (int *)indexed_alloc(nl, nh, sizeof(int), "ivector");
}

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double *dvector(int nl, int nh)
{
   return (double *)indexed_alloc(nl, nh, sizeof(double), "dvector");
}

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
char *cvector(int nl, int nh)
{
   return (char *)indexed_alloc(nl, nh, sizeof(char), "cvector");
}

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double **dmatrix(int nrl, int nrh, int ncl, int nch)
{
   int i;
   double **m;

   m=(double **) indexed_alloc(nrl, nrh, sizeof(double *), "dmatrix");
   if (!m) nrerror("allocation failure 1 in dmatrix()");

   for(i=nrl;i<=nrh;i++) {
      m[i]=(double *) indexed_alloc(ncl, nch, sizeof(double), "dmatrix");
      if (!m[i]) nrerror("allocation failure 2 in dmatrix()");
   }
   return m;
}

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
char **cmatrix(int nrl, int nrh, int ncl, int nch)
{
   int i;
   char **m;

   m=(char **) indexed_alloc(nrl, nrh, sizeof(char *), "cmatrix");
   if (!m) nrerror("allocation failure 1 in cmatrix()");

   for(i=nrl;i<=nrh;i++) {
      m[i]=(char *) indexed_alloc(ncl, nch, sizeof(char), "cmatrix");
      if (!m[i]) nrerror("allocation failure 2 in cmatrix()");
   }
   return m;
}

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
float *vector(int nl, int nh)
{
   return (float *)indexed_alloc(nl, nh, sizeof(float), "vector");
}

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
float **matrix(int nrl, int nrh, int ncl, int nch)
{
   int i;
   float **m;

   m=(float **) indexed_alloc(nrl, nrh, sizeof(float *), "matrix");
   if (!m) nrerror("allocation failure 1 in matrix()");

   for(i=nrl;i<=nrh;i++) {
      m[i]=(float *) indexed_alloc(ncl, nch, sizeof(float), "matrix");
      if (!m[i]) nrerror("allocation failure 2 in matrix()");
   }
   return m;
}

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void free_matrix(float **m, int nrl, int nrh, int ncl, int nch)
{
   int i;

   for(i=nrh;i>=nrl;i--) free((char*) (m[i]+ncl));
   free((char*) (m+nrl));
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void free_cmatrix(char **m, int nrl, int nrh, int ncl, int nch)
{
   int i;

   for(i=nrh;i>=nrl;i--) free((char*) (m[i]+ncl));
   free((char*) (m+nrl));
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void free_vector(float *v, int nl, int nh)
{
   free((char*) (v+nl));
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void free_dvector(double *v, int nl, int nh)
{
   free((char*) (v+nl));
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void free_cvector(char *v, int nl, int nh)
{
   free((char*) (v+nl));
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void free_dmatrix(double **m, int nrl, int nrh, int ncl, int nch)
{
   int i;

   for(i=nrh;i>=nrl;i--) free((char*) (m[i]+ncl));
   free((char*) (m+nrl));
}

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void free_ivector(int *v, int nl, int nh)
{
   free((char*) (v+nl));
}

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
FILE   *openf(char fname[],char mode[])
{
   FILE   *f;

   if( (f = fopen(fname,mode)) == NULL) {
      printf("Cannot open file %s for %c%s%c.\n",fname,'"',mode,'"');
      printf("...exiting...\n");
      nrerror("Check your code");
      return 0;
   }
   else return(f);
}

/****************************************************************************/
/*                                                                          */
/****************************************************************************/
int RRemove(char *fname)
// char *fname;
{
  int f;

  if( (f = remove(fname)) == -1  ) {
    printf("Unable to remove file %s\n",fname);
    printf("...exiting...\n");
    exit(1);
  }
  else return f;
}

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
int Rename(char *oldfname, char *newfname)
// char *oldfname;
// char *newfname;
{
  int f;

  if( (f = rename(oldfname,newfname)) != 0 ) {
    printf("Unable to rename file %s to %s.\n",oldfname,newfname);
    printf("...exiting...\n");
    exit(1);
  }
  else return f;
}

/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double atanh(double x)
// double   x;
{
   if( x <= -1.0 || x >= 1.0 ) nrerror("Error in function atanh() -1<x<1");
   return -0.5*log( (1-x)/(1+x) );
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double   Iden(double x)
// double   x;
{
   return x;
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double Inv(double x)
// double   x;
{
   if(x == 0.0) {
       nrerror("arg = 0.0 in Inv.");
       return 1.0;
   }
   else return 1.0/x;
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
double logT1(double x)
// double   x;
{
   if(x == 0.0) {
       nrerror("arg = 0.0 in Inv.");
       return 1.0;
   }
   else return log10(1.0/x);
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
static int ofe_barycentric_eval(const double xa[], const double ya[], int n,
                                 int skip, double x, double *value)
{
   int i, j;
   double *weights;
   double numerator, denominator, term;

   if (skip < 0 || skip > n) skip = 0;
   weights = (double *)calloc((size_t)n + 1, sizeof(*weights));
   if (weights == NULL) return 0;
   for (i = 1; i <= n; ++i) {
      if (i == skip) continue;
      weights[i] = 1.0;
      for (j = 1; j <= n; ++j) {
         if (j == skip) continue;
         if (i == j) continue;
         if (xa[i] == xa[j]) {
            free(weights);
            return 0;
         }
         weights[i] /= xa[i] - xa[j];
      }
   }
   for (i = 1; i <= n; ++i) {
      if (i == skip) continue;
      if (x == xa[i]) {
         *value = ya[i];
         free(weights);
         return 1;
      }
   }
   numerator = 0.0;
   denominator = 0.0;
   for (i = 1; i <= n; ++i) {
      if (i == skip) continue;
      term = weights[i] / (x - xa[i]);
      numerator += term * ya[i];
      denominator += term;
   }
   free(weights);
   if (denominator == 0.0) return 0;
   *value = numerator / denominator;
   return isfinite(*value);
}

void dpolint(double xa[],double ya[],int n, double x, double *y, double *dy)
/* Independent barycentric polynomial interpolation, preserving OneFit's
   historical one-based array convention. */
{
   double reduced, distance, candidate;
   int i, skip;

   if (n < 1 || !ofe_barycentric_eval(xa, ya, n, 0, x, y))
      nrerror("Invalid input in polynomial interpolation");
   if (n == 1) {
      *dy = 0.0;
      return;
   }
   /* Estimate the error by removing the node nearest to x.  For n=2 this
      exactly reproduces the correction from linear interpolation, while for
      larger n it remains a degree-(n-2) comparison without the old tableau.
   */
   skip = 1;
   distance = fabs(x - xa[1]);
   for (i = 2; i <= n; ++i) {
      candidate = fabs(x - xa[i]);
      if (candidate < distance) { distance = candidate; skip = i; }
   }
   if (!ofe_barycentric_eval(xa, ya, n, skip, x, &reduced))
      nrerror("Invalid input in polynomial interpolation");
   *dy = *y - reduced;
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void dsplint(double xa[], double ya[], double y2a[], int n, double x, double *y)
/* Evaluate a cubic spline from its tabulated values and second derivatives.
   This keeps the historical one-based API and extrapolates with the first or
   last interval, as the original OneFit callers expect. */
{
   int lo, hi;
   double h, left_weight, right_weight;

   if (n < 2) nrerror("Too few points in spline interpolation");
   lo = 1;
   hi = n;
   while (hi - lo > 1) {
      int mid = lo + (hi - lo) / 2;
      if (xa[mid] > x) hi = mid;
      else lo = mid;
   }
   h = xa[hi] - xa[lo];
   if (h == 0.0) nrerror("Repeated XA value in spline interpolation");
   left_weight = (xa[hi] - x) / h;
   right_weight = (x - xa[lo]) / h;
   *y = left_weight * ya[lo] + right_weight * ya[hi]
      + ((left_weight * left_weight * left_weight - left_weight) * y2a[lo]
       + (right_weight * right_weight * right_weight - right_weight) * y2a[hi])
        * (h * h) / 6.0;
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void dspline(double x[], double y[], int n, double yp1, double ypn,
              double y2[])
/* Cubic-spline second derivatives solved with an explicit tridiagonal system.
   The one-based public API and the original natural/clamped boundary rules
   are retained. */
{
   int i;
   double *lower, *diag, *upper, *rhs;

   if (n < 2) nrerror("Too few points in spline");
   lower = (double *)calloc((size_t)n + 1, sizeof(*lower));
   diag = (double *)calloc((size_t)n + 1, sizeof(*diag));
   upper = (double *)calloc((size_t)n + 1, sizeof(*upper));
   rhs = (double *)calloc((size_t)n + 1, sizeof(*rhs));
   if (!lower || !diag || !upper || !rhs)
      nrerror("Allocation failure in spline");

   if (yp1 > 0.99e30) {
      diag[1] = 1.0;
      rhs[1] = 0.0;
   } else {
      diag[1] = 2.0;
      upper[1] = 1.0;
      rhs[1] = 6.0 * ((y[2] - y[1]) / (x[2] - x[1]) - yp1)
             / (x[2] - x[1]);
   }
   for (i = 2; i < n; ++i) {
      double hleft = x[i] - x[i - 1];
      double hright = x[i + 1] - x[i];
      double span = x[i + 1] - x[i - 1];
      if (hleft == 0.0 || hright == 0.0 || span == 0.0)
         nrerror("Repeated X value in spline");
      lower[i] = hright / span;
      diag[i] = 2.0;
      upper[i] = hleft / span;
      rhs[i] = 6.0 * ((y[i + 1] - y[i]) / hright
                    - (y[i] - y[i - 1]) / hleft) / span;
   }
   if (ypn > 0.99e30) {
      lower[n] = 0.0;
      diag[n] = 1.0;
      rhs[n] = 0.0;
   } else {
      lower[n] = 1.0;
      diag[n] = 2.0;
      rhs[n] = 6.0 * (ypn - (y[n] - y[n - 1]) / (x[n] - x[n - 1]))
             / (x[n] - x[n - 1]);
   }
   for (i = 2; i <= n; ++i) {
      double factor = lower[i] / diag[i - 1];
      diag[i] -= factor * upper[i - 1];
      rhs[i] -= factor * rhs[i - 1];
   }
   y2[n] = rhs[n] / diag[n];
   for (i = n - 1; i >= 1; --i)
      y2[i] = (rhs[i] - upper[i] * y2[i + 1]) / diag[i];
   free(lower);
   free(diag);
   free(upper);
   free(rhs);
}
/*****************************************************************************/
/*                                                                           */
/*****************************************************************************/
void new_line(FILE *f, int n)
// FILE *f;
// int n;
{
  int i;
  char c;

  for(i=1;i<=n;i++) while( (c=fgetc(f)) != '\n');
}
/****************************************************************************/
/*                                                                          */
/****************************************************************************/
#define IN  1
#define OUT 0

int swc(char *s)
// char *s;
{
  int nw,i,state;
  char c;

  nw = i = 0;
  state = OUT;

  if(s == NULL) return 0;

  while((c=s[i++]) != 0){
    if(c == ' ' || c == '\n' || c == '\t' || c == EOF) state = OUT;
    else if(state == OUT){
      state = IN;
      ++nw;
    }
  }
  return nw;
}
/****************************************************************************/
/*                                                                          */
/****************************************************************************/
int flc(FILE *file)
// FILE *file;
{
  char str[1024]="";
  int lc=0;
  char *cerr=str;
  
  while(1){
    cerr = fgets(str,1024,file);
    if(swc(str)) lc++;
    if(str[0] == '#') lc--;
    if(!feof(file)) break;
  }
  rewind(file);
  if (cerr==NULL) printf("fgets read error in fitutil.c, flc().\n");
  return lc;
}
/****************************************************************************/
/*                                                                          */
/****************************************************************************/
void *Malloc(unsigned int size)
// unsigned int size;
{
  void *ptr;

  if((ptr = malloc(size)) != NULL) return ptr;
  else {
    puts("malloc alocation failure...exiting");
    exit(1);
  }
}
/****************************************************************************/
/*                                                                          */
/****************************************************************************/
void *Realloc(void *ptr,unsigned int size)
// void *ptr;
// unsigned int size;
{
  if((ptr = realloc(ptr,size)) != NULL) return ptr;
  else {
    puts("realloc alocation failure...exiting");
    exit(1);
  }
}
/****************************************************************************/
/*                                                                          */
/****************************************************************************/
int *Flc(FILE *file, int *nlines)
// FILE *file;
// int *nlines;
{
  int c;
  char *str;
  int lc=0,*char_count,nchar=0;

  char_count = (int *) Malloc((unsigned) sizeof(int));
  while(1){
    str = (char *) Malloc((unsigned) sizeof(char));
    nchar=0;
	str[0]=0;
    while(1){
      c = fgetc(file);
	  if (c == EOF ){ 
		  break;
	  }
	  str[nchar++] = (char)c;
      str = (char *) Realloc(str,(unsigned) (nchar+1)*sizeof(char));
      str[nchar]=0;
      if(c=='\n'){
	    break;
      }
    }
    if(swc(str) && str[0] != '#') {
      lc++;
      char_count = (int *) Realloc(char_count,(unsigned) lc*sizeof(int));
      char_count[lc-1]=nchar;
    }
    free((char *) str);
    if(feof(file)) break;
  }
  rewind(file);

  *nlines = lc;
  return char_count;
}
/****************************************************************************/
/*                                                                          */
/****************************************************************************/
char **nlnc( int nlinhas, int *nchar_linha)
// int nlinhas,*nchar_linha;
{
  int i;
  char **opt;
  
  opt =(char **) Malloc((unsigned) (nlinhas+1)*sizeof(char*));
  for(i=0;i<nlinhas;i++) {
    opt[i]=(char *) Malloc((unsigned) (nchar_linha[i]+1)*sizeof(char));
  }
  opt[nlinhas]=NULL;
  return opt;
}
/****************************************************************************/
/*                                                                          */
/****************************************************************************/
void free_nlnc(char **m, int nlinhas)
// char **m;
// int nlinhas;
{
   int i;

   for(i=0;i<=nlinhas+1;i++) free((char*) m[i]);
   free((char*) m);
}
/****************************************************************************/
/*                                                                          */
/****************************************************************************/
char **lines(FILE *file, int nlines, int *nchar_line)
// FILE *file;
// int nlines,*nchar_line;
{
  char c,*str;
  int lc=0,nchar=0;
  char **opt;

  
  opt = nlnc(nlines,nchar_line);
  
  while(1){
    str = (char *) Malloc((unsigned) sizeof(char));
    nchar=0;
    while(1){
      c = fgetc(file);
      if(c == '\n' || feof(file)) {
	str[nchar]=0;
	break;
      }
      else {
	str[nchar++]=c;
	str = (char *) Realloc(str,(unsigned) (nchar+1)*sizeof(char));
	str[nchar]=0;
      }
    }
    if(swc(str) && str[0] != '#') {
      lc++;
      strcpy(opt[lc-1],str);
    }
    free((char *) str);
    if(feof(file)) break;
  }
  rewind(file);

  return opt;
}
/****************************************************************************/
/*                                                                          */
/****************************************************************************/
char **getsstring(char *str, int *n)
// char *str;
// int *n;
{
  int i,state,nw,nc;
  char c,**ptr;

  if((*n=swc(str))==0 || str == NULL) {
    return NULL;
  }

  ptr = (char **) Malloc((unsigned) (*n+1)*sizeof(char *));

  for(i=0;i<*n;i++) ptr[i] = (char *) Malloc((unsigned) sizeof(char));
  ptr[*n]=NULL;

  nw = nc = i = 0;
  state = OUT;

  while((c=str[i++]) != 0){
    if(c == ' ' || c == '\n' || c == '\t' || c == EOF) {
      state = OUT;
      nc = 0;
    }
    else if(state == OUT){
      state = IN;
      ++nw;
    }
    if(state == IN){
      ptr[nw-1][nc++] = c;
      ptr[nw-1] = (char *) Realloc(ptr[nw-1], (unsigned) (nc+1)*sizeof(char));
      ptr[nw-1][nc]=0;
    }
  }

  *n = nw;
  return ptr;

}
/****************************************************************************/
/*                                                                          */
/****************************************************************************/
char *purges(char *str)
{
  int n,m,state=OUT;

  n = m = strlen(str);

  while(--n >= 0) {
    if(str[n] == ' ' || str[n] == '\n' || str[n]=='\t') {
      str[n]=0;
      state = OUT;
    }
    else if(state == OUT) break;
  }
  for(n=0;n<m;n++) {
    if(str[n]!=' ' && str[n]!='\t') break;
  }
  return str+n;
}
/****************************************************************************/
/*                                                                          */
/****************************************************************************/
void puti(int i)
{
  printf("%d\n",i);
}
/****************************************************************************/
/*                                                                          */
/****************************************************************************/
void putd(double x)
{
  printf("%g\n",x);
}
/****************************************************************************/
/*                                                                          */
/****************************************************************************/
double ler_num(FILE *f)
// FILE   *f;
{
   double   x;
   char   c;

   while( (c=fgetc(f)) != '=');
   if (!fscanf(f,"%lf",&x)) printf("fscanf() call error in fitutil.c, lernum()\n");
   return x;
}
/****************************************************************************/
/*                                                                           */
/*****************************************************************************/
int strplen(char **str)
{
  int i=0;
  
  while(str[0]!=NULL) i++;
  return i;
}

/****************************************************************************/
/*                                                                           */
/*****************************************************************************/
int *buffer_Flc(FILE *file, int *nlines)
// FILE *file;
// int *nlines;
{
  char c,*str;
  int lc=0,*char_count,nchar=0;

  char_count = (int *) Malloc((unsigned) sizeof(int));
  while(1){
    str = (char *) Malloc((unsigned) sizeof(char));
    nchar=0;
    while(1){
      c = fgetc(file);
      str[nchar++]=c;
      str = (char *) Realloc(str,(unsigned) (nchar+1)*sizeof(char));
      str[nchar]=0;
      if(c=='\n' || feof(file)){
	break;
      }
    }
    lc++;
    char_count = (int *) Realloc(char_count,(unsigned) lc*sizeof(int));
    char_count[lc-1]=nchar;
    free((char *) str);
    if(feof(file)) break;
  }
  rewind(file);

  *nlines = lc-1;
  return char_count;
}
/****************************************************************************/
/*                                                                           */
/*****************************************************************************/
char **buffer_lines(FILE *file, int nlines, int *nchar_line)
// FILE *file;
// int nlines,*nchar_line;
{
  char c,*str;
  int lc=0,nchar=0;
  char **opt;

  
  opt = nlnc(nlines,nchar_line);
  
  while(1){
    str = (char *) Malloc((unsigned) sizeof(char));
    nchar=0;
    while(1){
      c = fgetc(file);
      if(c == '\n' || feof(file)) {
	str[nchar]=0;
	break;
      }
      else {
	str[nchar++]=c;
	str = (char *) Realloc(str,(unsigned) (nchar+1)*sizeof(char));
	str[nchar]=0;
      }
    }

    lc++;
    strcpy(opt[lc-1],str);

    free((char *) str);
    if(feof(file)) break;
  }
  rewind(file);

  return opt;
}
/****************************************************************************/
/*                                                                           */
/*****************************************************************************/


















