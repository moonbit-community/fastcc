#ifndef _TCC_COMPAT_SYS_MMAN_H
#define _TCC_COMPAT_SYS_MMAN_H

#include <sys/types.h>

#define PROT_NONE  0x00
#define PROT_READ  0x01
#define PROT_WRITE 0x02
#define PROT_EXEC  0x04

#define MAP_SHARED    0x0001
#define MAP_PRIVATE   0x0002
#define MAP_FIXED     0x0010
#define MAP_ANON      0x1000
#define MAP_ANONYMOUS MAP_ANON

#define MAP_FAILED ((void *)-1)

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
int munmap(void *addr, size_t length);
int mprotect(void *addr, size_t len, int prot);
int msync(void *addr, size_t len, int flags);

#endif /* _TCC_COMPAT_SYS_MMAN_H */
