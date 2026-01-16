#ifndef _TCC_COMPAT_DLFCN_H
#define _TCC_COMPAT_DLFCN_H

#include <stddef.h>

#define RTLD_LAZY   0x1
#define RTLD_NOW    0x2
#define RTLD_GLOBAL 0x100
#define RTLD_LOCAL  0
#define RTLD_DEFAULT ((void *)-2)
#define RTLD_NEXT ((void *)-1)

void *dlopen(const char *filename, int flag);
void *dlsym(void *handle, const char *symbol);
int dlclose(void *handle);
char *dlerror(void);

#endif /* _TCC_COMPAT_DLFCN_H */
