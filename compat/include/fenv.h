#ifndef _TCC_COMPAT_FENV_H
#define _TCC_COMPAT_FENV_H

typedef int fexcept_t;
typedef struct {
  unsigned int __control;
} fenv_t;

#define FE_TONEAREST 0
#define FE_DOWNWARD 0
#define FE_UPWARD 0
#define FE_TOWARDZERO 0
#define FE_ALL_EXCEPT 0

int fesetround(int);

#endif /* _TCC_COMPAT_FENV_H */
