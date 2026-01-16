#ifndef _TCC_COMPAT_SYS_UTSNAME_H
#define _TCC_COMPAT_SYS_UTSNAME_H

struct utsname {
  char sysname[256];
  char nodename[256];
  char release[256];
  char version[256];
  char machine[256];
};

int uname(struct utsname *name);

#endif /* _TCC_COMPAT_SYS_UTSNAME_H */
