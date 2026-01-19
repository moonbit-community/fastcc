#ifndef _TCC_COMPAT_UNISTD_H
#define _TCC_COMPAT_UNISTD_H

#include <sys/types.h>
#include <sys/wait.h>

#define F_OK 0
#define X_OK 1
#define W_OK 2
#define R_OK 4

#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2

#define _SC_PAGESIZE 29
#define _SC_NPROCESSORS_ONLN 83
#define _SC_OPEN_MAX 5

int access(const char *path, int mode);
int unlink(const char *path);
int rmdir(const char *path);
int close(int fd);
ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
off_t lseek(int fd, off_t offset, int whence);
int pipe(int fds[2]);
unsigned sleep(unsigned seconds);
int usleep(useconds_t usec);
int getpagesize(void);
long sysconf(int name);
char *getcwd(char *buf, size_t size);
int chdir(const char *path);
int isatty(int fd);
int dup(int oldfd);
int dup2(int oldfd, int newfd);
pid_t fork(void);
int execv(const char *path, char *const argv[]);
int execlp(const char *file, const char *arg, ...);
pid_t getpid(void);

extern int optind;

#endif /* _TCC_COMPAT_UNISTD_H */
