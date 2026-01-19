#ifndef _TCC_COMPAT_DIRENT_H
#define _TCC_COMPAT_DIRENT_H

#include <sys/types.h>
#include <stdint.h>

typedef struct DIR DIR;

#if defined(__APPLE__)
#define TCC_DIRENT_NAME_MAX 1024
#pragma pack(4)
struct dirent {
  uint64_t d_ino;
  uint64_t d_seekoff;
  uint16_t d_reclen;
  uint16_t d_namlen;
  uint8_t d_type;
  char d_name[TCC_DIRENT_NAME_MAX];
};
#pragma pack()
#else
struct dirent {
  char d_name[256];
};
#endif

DIR *opendir(const char *name);
struct dirent *readdir(DIR *dirp);
int closedir(DIR *dirp);

#endif /* _TCC_COMPAT_DIRENT_H */
