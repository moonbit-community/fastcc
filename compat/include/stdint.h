#include <stddef.h>
#ifndef _TCC_COMPAT_STDINT_H
#define _TCC_COMPAT_STDINT_H

typedef signed char int8_t;
typedef unsigned char uint8_t;

typedef short int16_t;
typedef unsigned short uint16_t;

typedef int int32_t;
typedef unsigned int uint32_t;

typedef long long int64_t;
typedef unsigned long long uint64_t;

typedef int8_t int_least8_t;
typedef uint8_t uint_least8_t;
typedef int16_t int_least16_t;
typedef uint16_t uint_least16_t;
typedef int32_t int_least32_t;
typedef uint32_t uint_least32_t;
typedef int64_t int_least64_t;
typedef uint64_t uint_least64_t;

typedef int8_t int_fast8_t;
typedef uint8_t uint_fast8_t;
typedef int16_t int_fast16_t;
typedef uint16_t uint_fast16_t;
typedef int32_t int_fast32_t;
typedef uint32_t uint_fast32_t;
typedef int64_t int_fast64_t;
typedef uint64_t uint_fast64_t;

typedef long intptr_t;
typedef unsigned long uintptr_t;

typedef long long intmax_t;
typedef unsigned long long uintmax_t;

#define INT8_C(c)   c
#define INT16_C(c)  c
#define INT32_C(c)  c
#define INT64_C(c)  c##LL
#define UINT8_C(c)  c##U
#define UINT16_C(c) c##U
#define UINT32_C(c) c##U
#define UINT64_C(c) c##ULL

#define INTMAX_C(c)  INT64_C(c)
#define UINTMAX_C(c) UINT64_C(c)

#define INT8_MIN (-128)
#define INT16_MIN (-32768)
#define INT32_MIN (-2147483647 - 1)
#define INT64_MIN (-9223372036854775807LL - 1)

#define INT8_MAX 127
#define INT16_MAX 32767
#define INT32_MAX 2147483647
#define INT64_MAX 9223372036854775807LL

#define UINT8_MAX 255U
#define UINT16_MAX 65535U
#define UINT32_MAX 4294967295U
#define UINT64_MAX 18446744073709551615ULL

#define INT_LEAST8_MIN INT8_MIN
#define INT_LEAST16_MIN INT16_MIN
#define INT_LEAST32_MIN INT32_MIN
#define INT_LEAST64_MIN INT64_MIN

#define INT_LEAST8_MAX INT8_MAX
#define INT_LEAST16_MAX INT16_MAX
#define INT_LEAST32_MAX INT32_MAX
#define INT_LEAST64_MAX INT64_MAX

#define UINT_LEAST8_MAX UINT8_MAX
#define UINT_LEAST16_MAX UINT16_MAX
#define UINT_LEAST32_MAX UINT32_MAX
#define UINT_LEAST64_MAX UINT64_MAX

#define INT_FAST8_MIN INT8_MIN
#define INT_FAST16_MIN INT16_MIN
#define INT_FAST32_MIN INT32_MIN
#define INT_FAST64_MIN INT64_MIN

#define INT_FAST8_MAX INT8_MAX
#define INT_FAST16_MAX INT16_MAX
#define INT_FAST32_MAX INT32_MAX
#define INT_FAST64_MAX INT64_MAX

#define UINT_FAST8_MAX UINT8_MAX
#define UINT_FAST16_MAX UINT16_MAX
#define UINT_FAST32_MAX UINT32_MAX
#define UINT_FAST64_MAX UINT64_MAX

#if defined(__LP64__)
#define INTPTR_MIN INT64_MIN
#define INTPTR_MAX INT64_MAX
#define UINTPTR_MAX UINT64_MAX
#define PTRDIFF_MIN INT64_MIN
#define PTRDIFF_MAX INT64_MAX
#define SIZE_MAX UINT64_MAX
#else
#define INTPTR_MIN INT32_MIN
#define INTPTR_MAX INT32_MAX
#define UINTPTR_MAX UINT32_MAX
#define PTRDIFF_MIN INT32_MIN
#define PTRDIFF_MAX INT32_MAX
#define SIZE_MAX UINT32_MAX
#endif

#define INTMAX_MIN INT64_MIN
#define INTMAX_MAX INT64_MAX
#define UINTMAX_MAX UINT64_MAX

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

static inline int tcc_builtin_clz64(unsigned long long x) {
  int n = 0;
  unsigned long long mask = 1ull << 63;
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

static inline int tcc_builtin_ctz64(unsigned long long x) {
  int n = 0;
  unsigned long long mask = 1ull;
  while (mask && (x & mask) == 0) {
    n++;
    mask <<= 1;
  }
  return n;
}

static inline int tcc_builtin_popcount32(unsigned int x) {
  int n = 0;
  while (x) {
    n += (x & 1u);
    x >>= 1;
  }
  return n;
}

static inline int tcc_builtin_popcount64(unsigned long long x) {
  int n = 0;
  while (x) {
    n += (x & 1ull);
    x >>= 1;
  }
  return n;
}

#define __builtin_clz(x) tcc_builtin_clz32((unsigned int)(x))
#define __builtin_clzll(x) tcc_builtin_clz64((unsigned long long)(x))
#define __builtin_ctz(x) tcc_builtin_ctz32((unsigned int)(x))
#define __builtin_ctzll(x) tcc_builtin_ctz64((unsigned long long)(x))
#define __builtin_popcount(x) tcc_builtin_popcount32((unsigned int)(x))
#define __builtin_popcountll(x) tcc_builtin_popcount64((unsigned long long)(x))
#endif

#endif /* _TCC_COMPAT_STDINT_H */
