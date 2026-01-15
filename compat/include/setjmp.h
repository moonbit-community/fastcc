#ifndef _TCC_COMPAT_SETJMP_H
#define _TCC_COMPAT_SETJMP_H

typedef long jmp_buf[32];

int setjmp(jmp_buf env);
void longjmp(jmp_buf env, int val);

#endif /* _TCC_COMPAT_SETJMP_H */
