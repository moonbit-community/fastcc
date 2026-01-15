#ifndef _TCC_COMPAT_SYS_TYPES_H
#define _TCC_COMPAT_SYS_TYPES_H

#include <stddef.h>
#include <stdint.h>

typedef unsigned long size_t;
typedef long ssize_t;
typedef long off_t;
typedef long time_t;
typedef long suseconds_t;
typedef long useconds_t;
typedef unsigned int mode_t;
typedef int pid_t;
typedef unsigned int uid_t;
typedef unsigned int gid_t;
typedef unsigned int uint;
typedef unsigned long ulong;
typedef unsigned short ushort;
typedef unsigned char uchar;

typedef long blksize_t;
typedef long blkcnt_t;
typedef long dev_t;
typedef unsigned long ino_t;
typedef unsigned long nlink_t;

#endif /* _TCC_COMPAT_SYS_TYPES_H */
