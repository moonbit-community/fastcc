#ifndef _TCC_COMPAT_SYS_UCONTEXT_H
#define _TCC_COMPAT_SYS_UCONTEXT_H

#include <signal.h>
#include <stdint.h>

typedef struct __tcc_arm_thread_state64 {
  uint64_t __x[29];
  uint64_t __fp;
  uint64_t __lr;
  uint64_t __sp;
  uint64_t __pc;
  uint32_t __cpsr;
  uint32_t __pad;
} __tcc_arm_thread_state64;

typedef struct __tcc_mcontext64 {
  __tcc_arm_thread_state64 __ss;
} mcontext_t;

typedef struct ucontext {
  unsigned long uc_onstack;
  sigset_t uc_sigmask;
  stack_t uc_stack;
  mcontext_t *uc_mcontext;
  struct ucontext *uc_link;
} ucontext_t;

#endif /* _TCC_COMPAT_SYS_UCONTEXT_H */
