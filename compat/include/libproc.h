#ifndef _TCC_COMPAT_LIBPROC_H
#define _TCC_COMPAT_LIBPROC_H

#include <stdint.h>

int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

#endif /* _TCC_COMPAT_LIBPROC_H */
