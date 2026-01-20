#ifndef _TCC_COMPAT_PTHREAD_H
#define _TCC_COMPAT_PTHREAD_H

#include <sys/types.h>
#include <time.h>

typedef void *pthread_t;

typedef struct { int __opaque; } pthread_attr_t;
typedef struct { int __opaque; } pthread_mutex_t;
typedef struct { int __opaque; } pthread_mutexattr_t;
typedef struct { int __opaque; } pthread_cond_t;
typedef struct { int __opaque; } pthread_condattr_t;
typedef struct { int __opaque; } pthread_rwlock_t;
typedef struct { int __opaque; } pthread_rwlockattr_t;
typedef struct { int __opaque; } pthread_once_t;

#define PTHREAD_MUTEX_INITIALIZER {0}
#define PTHREAD_COND_INITIALIZER {0}
#define PTHREAD_RWLOCK_INITIALIZER {0}
#define PTHREAD_ONCE_INIT {0}
#define PTHREAD_CREATE_DETACHED 2
#define PTHREAD_MUTEX_NORMAL 0
#define PTHREAD_MUTEX_ERRORCHECK 1
#define PTHREAD_MUTEX_RECURSIVE 2
#define PTHREAD_MUTEX_DEFAULT PTHREAD_MUTEX_NORMAL

int pthread_create(
  pthread_t *thread,
  const pthread_attr_t *attr,
  void *(*start_routine)(void *),
  void *arg
);
int pthread_join(pthread_t thread, void **retval);
int pthread_detach(pthread_t thread);

int pthread_mutex_init(pthread_mutex_t *mutex, const pthread_mutexattr_t *attr);
int pthread_mutex_destroy(pthread_mutex_t *mutex);
int pthread_mutex_lock(pthread_mutex_t *mutex);
int pthread_mutex_unlock(pthread_mutex_t *mutex);
int pthread_mutexattr_init(pthread_mutexattr_t *attr);
int pthread_mutexattr_destroy(pthread_mutexattr_t *attr);
int pthread_mutexattr_settype(pthread_mutexattr_t *attr, int type);

int pthread_cond_init(pthread_cond_t *cond, const pthread_condattr_t *attr);
int pthread_cond_destroy(pthread_cond_t *cond);
int pthread_cond_wait(pthread_cond_t *cond, pthread_mutex_t *mutex);
int pthread_cond_timedwait(
  pthread_cond_t *cond,
  pthread_mutex_t *mutex,
  const struct timespec *abstime
);
int pthread_cond_signal(pthread_cond_t *cond);
int pthread_cond_broadcast(pthread_cond_t *cond);

int pthread_rwlock_init(pthread_rwlock_t *lock, const pthread_rwlockattr_t *attr);
int pthread_rwlock_destroy(pthread_rwlock_t *lock);
int pthread_rwlock_rdlock(pthread_rwlock_t *lock);
int pthread_rwlock_wrlock(pthread_rwlock_t *lock);
int pthread_rwlock_unlock(pthread_rwlock_t *lock);
int pthread_rwlockattr_setkind_np(pthread_rwlockattr_t *attr, int pref);

#endif /* _TCC_COMPAT_PTHREAD_H */
