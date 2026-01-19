#ifndef _TCC_COMPAT_MATH_H
#define _TCC_COMPAT_MATH_H

#include <stddef.h>
#include <stdint.h>

#ifndef __builtin_huge_val
#define __builtin_huge_val() 1e500
#endif
#ifndef __builtin_huge_valf
#define __builtin_huge_valf() 1e50f
#endif
#ifndef __builtin_huge_vall
#define __builtin_huge_vall() 1e5000L
#endif
#ifndef __builtin_nanf
#define __builtin_nanf(ignored_string) (0.0F/0.0F)
#endif

#define HUGE_VAL (__builtin_huge_val())
#define HUGE_VALF (__builtin_huge_valf())
#define HUGE_VALL (__builtin_huge_vall())
#define NAN (__builtin_nanf(""))
#define INFINITY (1.0F/0.0F)

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
double asinh(double x);
double acosh(double x);
double atanh(double x);
double exp(double x);
double expm1(double x);
double log(double x);
double log1p(double x);
double log2(double x);
double log10(double x);
double pow(double x, double y);
double cbrt(double x);
double sqrt(double x);
double ceil(double x);
double floor(double x);
double fabs(double x);
double fmod(double x, double y);
double trunc(double x);
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
float asinhf(float x);
float acoshf(float x);
float atanhf(float x);
float expf(float x);
float expm1f(float x);
float logf(float x);
float log1pf(float x);
float log2f(float x);
float log10f(float x);
float powf(float x, float y);
float cbrtf(float x);
float sqrtf(float x);
float ceilf(float x);
float floorf(float x);
float fabsf(float x);
float fmodf(float x, float y);
float truncf(float x);
float frexpf(float x, int *exp);
float ldexpf(float x, int exp);

int isnan(double x);
int isinf(double x);
static inline int finite(double x) { return !isnan(x) && !isinf(x); }
#define isfinite(x) finite(x)
static inline int tcc_signbit_double(double x) {
  union { double d; uint64_t u; } v;
  v.d = x;
  return (int)(v.u >> 63);
}
#define signbit(x) tcc_signbit_double((double)(x))

#endif /* _TCC_COMPAT_MATH_H */
