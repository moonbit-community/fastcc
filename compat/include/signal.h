#ifndef _TCC_COMPAT_SIGNAL_H
#define _TCC_COMPAT_SIGNAL_H

#include <sys/types.h>

typedef unsigned long sigset_t;
typedef void (*sighandler_t)(int);

typedef struct siginfo {
  int si_signo;
  int si_code;
  void *si_addr;
} siginfo_t;

typedef struct stack {
  void *ss_sp;
  size_t ss_size;
  int ss_flags;
} stack_t;

struct sigaction {
  int sa_flags;
  sigset_t sa_mask;
  union {
    sighandler_t sa_handler;
    void (*sa_sigaction)(int, siginfo_t *, void *);
  };
};

#define SIG_DFL ((sighandler_t)0)
#define SIG_IGN ((sighandler_t)1)
#define SIG_ERR ((sighandler_t)-1)

#define SIGABRT 6
#define SIGFPE  8
#define SIGKILL 9
#define SIGBUS  10
#define SIGSEGV 11
#define SIGPIPE 13
#define SIGALRM 14
#define SIGTERM 15
#define SIGINT  2
#define SIGHUP  1
#define SIGTRAP 5
#define SIGILL  4

#define SIG_BLOCK   0
#define SIG_UNBLOCK 1
#define SIG_SETMASK 2

#define SA_ONSTACK   0x0001
#define SA_RESTART   0x0002
#define SA_NOCLDSTOP 0x0004
#define SA_SIGINFO   0x0008
#define SA_RESETHAND 0x0010

#define FPE_INTDIV 1
#define FPE_FLTDIV 2

int sigaction(int signum, const struct sigaction *act, struct sigaction *oldact);
int sigprocmask(int how, const sigset_t *set, sigset_t *oldset);
int sigemptyset(sigset_t *set);
int sigfillset(sigset_t *set);
int sigaddset(sigset_t *set, int signo);
sighandler_t signal(int signum, sighandler_t handler);
int raise(int signum);
int sigaltstack(const stack_t *ss, stack_t *oss);

#endif /* _TCC_COMPAT_SIGNAL_H */
