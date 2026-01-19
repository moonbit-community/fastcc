#ifndef _TCC_COMPAT_SYS_TYPES_H
#define _TCC_COMPAT_SYS_TYPES_H

#include <stddef.h>
#include <stdint.h>

typedef unsigned long size_t;
typedef long ssize_t;
typedef long time_t;
#if defined(__APPLE__)
typedef int64_t off_t;
typedef int32_t suseconds_t;
typedef uint32_t useconds_t;
typedef uint16_t mode_t;
typedef int32_t pid_t;
typedef uint32_t uid_t;
typedef uint32_t gid_t;
#else
typedef long off_t;
typedef long suseconds_t;
typedef long useconds_t;
typedef unsigned int mode_t;
typedef int pid_t;
typedef unsigned int uid_t;
typedef unsigned int gid_t;
#endif
typedef unsigned int uint;
typedef unsigned long ulong;
typedef unsigned short ushort;
typedef unsigned char uchar;

#if defined(__APPLE__)
typedef int32_t blksize_t;
typedef int64_t blkcnt_t;
typedef int32_t dev_t;
typedef uint64_t ino_t;
typedef uint16_t nlink_t;
#else
typedef long blksize_t;
typedef long blkcnt_t;
typedef long dev_t;
typedef unsigned long ino_t;
typedef unsigned long nlink_t;
#endif

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

#endif /* _TCC_COMPAT_SYS_TYPES_H */
