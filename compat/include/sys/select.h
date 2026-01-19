#ifndef _TCC_COMPAT_SYS_SELECT_H
#define _TCC_COMPAT_SYS_SELECT_H

#include <sys/time.h>
#include <string.h>

#ifndef _TCC_COMPAT_FD_SET_DEFINED
#define _TCC_COMPAT_FD_SET_DEFINED
typedef struct { unsigned long bits[16]; } fd_set;
#endif

#ifndef _TCC_COMPAT_FD_SET_MACROS
#define _TCC_COMPAT_FD_SET_MACROS
#define _TCC_COMPAT_NFDBITS (8U * (unsigned int)sizeof(unsigned long))
#define _TCC_COMPAT_FD_INDEX(fd) ((unsigned int)(fd) / _TCC_COMPAT_NFDBITS)
#define _TCC_COMPAT_FD_MASK(fd) (1UL << ((unsigned int)(fd) % _TCC_COMPAT_NFDBITS))

#define FD_ZERO(set) do { \
  size_t _i; \
  for (_i = 0; _i < (sizeof((set)->bits) / sizeof((set)->bits[0])); _i++) { \
    (set)->bits[_i] = 0; \
  } \
} while (0)

#define FD_SET(fd, set) ((set)->bits[_TCC_COMPAT_FD_INDEX(fd)] |= _TCC_COMPAT_FD_MASK(fd))
#define FD_CLR(fd, set) ((set)->bits[_TCC_COMPAT_FD_INDEX(fd)] &= ~_TCC_COMPAT_FD_MASK(fd))
#define FD_ISSET(fd, set) (((set)->bits[_TCC_COMPAT_FD_INDEX(fd)] & _TCC_COMPAT_FD_MASK(fd)) != 0)
#endif

int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout);

#endif /* _TCC_COMPAT_SYS_SELECT_H */
