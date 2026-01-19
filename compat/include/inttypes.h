#ifndef _TCC_COMPAT_INTTYPES_H
#define _TCC_COMPAT_INTTYPES_H

#include <stdint.h>

typedef struct {
  intmax_t quot;
  intmax_t rem;
} imaxdiv_t;

#define PRId8  "d"
#define PRId16 "d"
#define PRId32 "d"
#define PRId64 "lld"

#define PRIu8  "u"
#define PRIu16 "u"
#define PRIu32 "u"
#define PRIu64 "llu"

#define PRIx8  "x"
#define PRIx16 "x"
#define PRIx32 "x"
#define PRIx64 "llx"

static inline intmax_t imaxabs(intmax_t n) { return n < 0 ? -n : n; }

static inline imaxdiv_t imaxdiv(intmax_t numer, intmax_t denom) {
  imaxdiv_t r;
  r.quot = numer / denom;
  r.rem = numer % denom;
  return r;
}

#ifndef _TCC_COMPAT_BUILTIN_BITS
#define _TCC_COMPAT_BUILTIN_BITS
static inline int tcc_builtin_clz32(unsigned int x) {
  int n = 0;
  unsigned int mask = 1u << ((sizeof(unsigned int) * 8) - 1);
  while (mask && (x & mask) == 0) {
    n++;
    mask >>= 1;
  }
  return n;
}

static inline int tcc_builtin_clz64(uint64_t x) {
  int n = 0;
  uint64_t mask = (uint64_t)1 << 63;
  while (mask && (x & mask) == 0) {
    n++;
    mask >>= 1;
  }
  return n;
}

static inline int tcc_builtin_ctz32(unsigned int x) {
  int n = 0;
  unsigned int mask = 1u;
  while (mask && (x & mask) == 0) {
    n++;
    mask <<= 1;
  }
  return n;
}

static inline int tcc_builtin_ctz64(uint64_t x) {
  int n = 0;
  uint64_t mask = (uint64_t)1;
  while (mask && (x & mask) == 0) {
    n++;
    mask <<= 1;
  }
  return n;
}

#define __builtin_clz(x) tcc_builtin_clz32((unsigned int)(x))
#define __builtin_clzll(x) tcc_builtin_clz64((uint64_t)(x))
#define __builtin_ctz(x) tcc_builtin_ctz32((unsigned int)(x))
#define __builtin_ctzll(x) tcc_builtin_ctz64((uint64_t)(x))
#endif

#define strtoimax strtoll
#define strtoumax strtoull
#define wcstoimax wcstoll
#define wcstoumax wcstoull

#endif /* _TCC_COMPAT_INTTYPES_H */
