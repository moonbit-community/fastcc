#ifndef _TCC_COMPAT_SYS_SYSCALL_H
#define _TCC_COMPAT_SYS_SYSCALL_H

#if defined(__x86_64__)
#define SYS_write 1
#define SYS_exit 60
#elif defined(__aarch64__)
#define SYS_write 64
#define SYS_exit 93
#elif defined(__riscv)
#define SYS_write 64
#define SYS_exit 93
#elif defined(__i386__)
#define SYS_write 4
#define SYS_exit 1
#elif defined(__arm__)
#define SYS_write 4
#define SYS_exit 1
#else
#define SYS_write 1
#define SYS_exit 60
#endif

#endif /* _TCC_COMPAT_SYS_SYSCALL_H */
