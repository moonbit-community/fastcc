#ifndef _TCC_COMPAT_LIBKERN_OSCACHECONTROL_H
#define _TCC_COMPAT_LIBKERN_OSCACHECONTROL_H

#include <stddef.h>

static inline void sys_icache_invalidate(void *start, size_t len) {
  (void)start;
  (void)len;
}

#endif /* _TCC_COMPAT_LIBKERN_OSCACHECONTROL_H */
