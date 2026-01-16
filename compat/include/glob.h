#ifndef _TCC_COMPAT_GLOB_H
#define _TCC_COMPAT_GLOB_H

#include <stddef.h>

typedef struct {
  size_t gl_pathc;
  char **gl_pathv;
  size_t gl_offs;
} glob_t;

#define GLOB_ERR 1
#define GLOB_NOSPACE 2
#define GLOB_ABORTED 3
#define GLOB_NOMATCH 4

int glob(const char *pattern, int flags, int (*errfunc)(const char *, int), glob_t *pglob);
void globfree(glob_t *pglob);

#endif /* _TCC_COMPAT_GLOB_H */
