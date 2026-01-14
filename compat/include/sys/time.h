#ifndef _TCC_COMPAT_SYS_TIME_H
#define _TCC_COMPAT_SYS_TIME_H

#include <sys/types.h>
#include <time.h>

struct timeval {
  time_t tv_sec;
  suseconds_t tv_usec;
};

struct timezone {
  int tz_minuteswest;
  int tz_dsttime;
};

int gettimeofday(struct timeval *tv, struct timezone *tz);

#endif /* _TCC_COMPAT_SYS_TIME_H */
