#ifndef _TCC_COMPAT_MALLOC_MALLOC_H
#define _TCC_COMPAT_MALLOC_MALLOC_H

#include <stddef.h>

size_t malloc_size(const void *ptr);
size_t malloc_usable_size(void *ptr);

#endif /* _TCC_COMPAT_MALLOC_MALLOC_H */
