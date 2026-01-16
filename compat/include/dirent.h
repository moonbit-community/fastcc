#ifndef _TCC_COMPAT_DIRENT_H
#define _TCC_COMPAT_DIRENT_H

#include <sys/types.h>

typedef struct DIR DIR;

struct dirent {
  char d_name[256];
};

DIR *opendir(const char *name);
struct dirent *readdir(DIR *dirp);
int closedir(DIR *dirp);

#endif /* _TCC_COMPAT_DIRENT_H */
