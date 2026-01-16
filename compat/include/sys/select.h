#ifndef _TCC_COMPAT_SYS_SELECT_H
#define _TCC_COMPAT_SYS_SELECT_H

#include <sys/time.h>

typedef struct { unsigned long bits[16]; } fd_set;

int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout);

#endif /* _TCC_COMPAT_SYS_SELECT_H */
