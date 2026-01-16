#ifndef _TCC_COMPAT_STDARG_H
#define _TCC_COMPAT_STDARG_H

typedef __builtin_va_list va_list;
#define va_start __builtin_va_start
#define va_arg __builtin_va_arg
#define va_copy __builtin_va_copy
#define va_end __builtin_va_end

typedef va_list __gnuc_va_list;
#define _VA_LIST_DEFINED

#endif /* _TCC_COMPAT_STDARG_H */
