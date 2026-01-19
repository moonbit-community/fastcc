#ifndef _TCC_COMPAT_SYS_WAIT_H
#define _TCC_COMPAT_SYS_WAIT_H

#include <sys/types.h>

#define WEXITSTATUS(status) (((status) >> 8) & 0xff)
#define WIFEXITED(status) (((status) & 0x7f) == 0)
#define WIFSIGNALED(status) (((status) & 0x7f) != 0 && ((status) & 0x7f) != 0x7f)
#define WTERMSIG(status) ((status) & 0x7f)
#define WNOHANG 0x00000001

pid_t wait(int *status);
pid_t waitpid(pid_t pid, int *status, int options);

#endif /* _TCC_COMPAT_SYS_WAIT_H */
