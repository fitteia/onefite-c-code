#include "example.h"

/* A model is a plain function of doubles returning a double: the fit calls it
   once per data point with the current parameter values. */
double ExampleGain(double x, double gain)
{
	return gain * x;
}
