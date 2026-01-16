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

#define strtoimax strtoll
#define strtoumax strtoull
#define wcstoimax wcstoll
#define wcstoumax wcstoull

#endif /* _TCC_COMPAT_INTTYPES_H */
