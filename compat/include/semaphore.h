#ifndef _TCC_COMPAT_SEMAPHORE_H
#define _TCC_COMPAT_SEMAPHORE_H

typedef struct { long __opaque[4]; } sem_t;

int sem_init(sem_t *sem, int pshared, unsigned int value);
int sem_destroy(sem_t *sem);
int sem_wait(sem_t *sem);
int sem_trywait(sem_t *sem);
int sem_post(sem_t *sem);
int sem_getvalue(sem_t *sem, int *sval);

#endif /* _TCC_COMPAT_SEMAPHORE_H */
