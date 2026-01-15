#ifndef _TCC_COMPAT_DISPATCH_DISPATCH_H
#define _TCC_COMPAT_DISPATCH_DISPATCH_H

#include <stdint.h>

typedef void *dispatch_object_t;
typedef void *dispatch_queue_t;
typedef void *dispatch_group_t;
typedef void *dispatch_queue_attr_t;
typedef void *dispatch_source_t;
typedef struct dispatch_semaphore_s *dispatch_semaphore_t;

typedef uint64_t dispatch_time_t;
typedef int64_t dispatch_once_t;

#define DISPATCH_TIME_FOREVER (~(dispatch_time_t)0)
#define DISPATCH_TIME_NOW ((dispatch_time_t)0)

dispatch_semaphore_t dispatch_semaphore_create(long value);
long dispatch_semaphore_wait(dispatch_semaphore_t dsema, dispatch_time_t timeout);
long dispatch_semaphore_signal(dispatch_semaphore_t dsema);
void dispatch_release(dispatch_object_t object);

#endif /* _TCC_COMPAT_DISPATCH_DISPATCH_H */
