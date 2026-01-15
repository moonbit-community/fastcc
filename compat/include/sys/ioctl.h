#ifndef _TCC_COMPAT_SYS_IOCTL_H
#define _TCC_COMPAT_SYS_IOCTL_H

#include <sys/types.h>

struct winsize {
  unsigned short ws_row;
  unsigned short ws_col;
  unsigned short ws_xpixel;
  unsigned short ws_ypixel;
};

#define TIOCGWINSZ 0x5413

int ioctl(int fd, unsigned long request, ...);

#endif /* _TCC_COMPAT_SYS_IOCTL_H */
