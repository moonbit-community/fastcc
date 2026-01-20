#ifndef _SYS_MOUNT_H
#define _SYS_MOUNT_H

#include <sys/types.h>

#define MNT_RDONLY 0x00000001

struct statfs {
  unsigned long f_flags;
  char f_fstypename[16];
};

int statfs(const char *path, struct statfs *buf);
int fstatfs(int fd, struct statfs *buf);

#endif
