#ifndef _TCC_COMPAT_MATH_H
#define _TCC_COMPAT_MATH_H

#include <stddef.h>

#define HUGE_VAL (__builtin_huge_val())
#define HUGE_VALF (__builtin_huge_valf())
#define HUGE_VALL (__builtin_huge_vall())
#define NAN (__builtin_nanf(""))

double sin(double x);
double cos(double x);
double tan(double x);
double asin(double x);
double acos(double x);
double atan(double x);
double atan2(double y, double x);
double sinh(double x);
double cosh(double x);
double tanh(double x);
double exp(double x);
double log(double x);
double log10(double x);
double pow(double x, double y);
double sqrt(double x);
double ceil(double x);
double floor(double x);
double fabs(double x);
double fmod(double x, double y);
double frexp(double x, int *exp);
double ldexp(double x, int exp);

float sinf(float x);
float cosf(float x);
float tanf(float x);
float asinf(float x);
float acosf(float x);
float atanf(float x);
float atan2f(float y, float x);
float sinhf(float x);
float coshf(float x);
float tanhf(float x);
float expf(float x);
float logf(float x);
float log10f(float x);
float powf(float x, float y);
float sqrtf(float x);
float ceilf(float x);
float floorf(float x);
float fabsf(float x);
float fmodf(float x, float y);
float frexpf(float x, int *exp);
float ldexpf(float x, int exp);

int isnan(double x);
int isinf(double x);
int finite(double x);

#endif /* _TCC_COMPAT_MATH_H */
