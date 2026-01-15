#ifndef _TCC_COMPAT_UTIME_H
#define _TCC_COMPAT_UTIME_H

#include <time.h>

struct utimbuf {
  time_t actime;
  time_t modtime;
};

int utime(const char *filename, const struct utimbuf *times);

#endif /* _TCC_COMPAT_UTIME_H */
