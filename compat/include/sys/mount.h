#ifndef _SYS_MOUNT_H
#define _SYS_MOUNT_H

#include <sys/types.h>

#define MNT_RDONLY 0x00000001

#if defined(__APPLE__)
#ifndef MFSNAMELEN
#define MFSNAMELEN 15
#endif
#ifndef MFSTYPENAMELEN
#define MFSTYPENAMELEN 16
#endif
#ifndef MAXPATHLEN
#define MAXPATHLEN 1024
#endif
#ifndef MNAMELEN
#define MNAMELEN MAXPATHLEN
#endif

struct statfs {
  uint32_t f_bsize;
  int32_t f_iosize;
  uint64_t f_blocks;
  uint64_t f_bfree;
  uint64_t f_bavail;
  uint64_t f_files;
  uint64_t f_ffree;
  fsid_t f_fsid;
  uid_t f_owner;
  uint32_t f_type;
  uint32_t f_flags;
  uint32_t f_fssubtype;
  char f_fstypename[MFSTYPENAMELEN];
  char f_mntonname[MAXPATHLEN];
  char f_mntfromname[MAXPATHLEN];
  uint32_t f_flags_ext;
  uint32_t f_reserved[7];
};
#else
struct statfs {
  unsigned long f_flags;
  char f_fstypename[16];
};
#endif

int statfs(const char *path, struct statfs *buf);
int fstatfs(int fd, struct statfs *buf);

#endif
