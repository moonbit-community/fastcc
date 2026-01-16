#ifndef _TCC_COMPAT_STDDEF_H
#define _TCC_COMPAT_STDDEF_H

typedef unsigned long size_t;
typedef long ssize_t;
typedef long ptrdiff_t;
typedef long intptr_t;
typedef unsigned long uintptr_t;
typedef int wchar_t;
typedef int wint_t;

#ifndef NULL
#define NULL ((void *)0)
#endif

#ifndef offsetof
#define offsetof(type, field) __builtin_offsetof(type, field)
#endif

#endif /* _TCC_COMPAT_STDDEF_H */
