#include <stdint.h>
#include <time.h>
#include <sys/time.h>

uint64_t tinyccmbt_now_ns(void) {
#if defined(CLOCK_MONOTONIC)
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) == 0) {
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
  }
#endif
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (uint64_t)tv.tv_sec * 1000000000ull + (uint64_t)tv.tv_usec * 1000ull;
}
