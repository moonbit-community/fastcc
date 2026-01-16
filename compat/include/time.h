#ifndef _TCC_COMPAT_TIME_H
#define _TCC_COMPAT_TIME_H

#include <stddef.h>
#include <sys/types.h>

typedef long clock_t;

struct tm {
  int tm_sec;
  int tm_min;
  int tm_hour;
  int tm_mday;
  int tm_mon;
  int tm_year;
  int tm_wday;
  int tm_yday;
  int tm_isdst;
  long tm_gmtoff;
};

struct timespec {
  time_t tv_sec;
  long tv_nsec;
};

#define CLOCKS_PER_SEC 1000000
#define CLOCK_REALTIME 0

time_t time(time_t *tloc);
double difftime(time_t end, time_t beginning);
clock_t clock(void);
char *ctime(const time_t *timep);
struct tm *localtime(const time_t *timep);
struct tm *gmtime(const time_t *timep);
size_t strftime(char *s, size_t max, const char *fmt, const struct tm *tm);

int nanosleep(const struct timespec *req, struct timespec *rem);

#endif /* _TCC_COMPAT_TIME_H */
