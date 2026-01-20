#ifndef _TCC_COMPAT_FCNTL_H
#define _TCC_COMPAT_FCNTL_H

#include <sys/types.h>

#define O_RDONLY 0x0000
#define O_WRONLY 0x0001
#define O_RDWR   0x0002
#define O_ACCMODE 0x0003
#define O_CREAT  0x0200
#define O_EXCL   0x0800
#define O_TRUNC  0x0400
#define O_APPEND 0x0008
#define O_NONBLOCK 0x0004
#define O_CLOEXEC 0x1000000

#define F_RDLCK 1
#define F_WRLCK 3
#define F_UNLCK 2
#define F_GETLK 7
#define F_SETLK 8
#define F_SETLKW 9

#if defined(__APPLE__)
struct flock {
  off_t l_start;
  off_t l_len;
  pid_t l_pid;
  short l_type;
  short l_whence;
};
#else
struct flock {
  short l_type;
  short l_whence;
  off_t l_start;
  off_t l_len;
  pid_t l_pid;
};
#endif

int open(const char *path, int flags, ...);
int creat(const char *path, mode_t mode);
int fcntl(int fd, int cmd, ...);

#endif /* _TCC_COMPAT_FCNTL_H */
