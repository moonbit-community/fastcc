#ifndef _TCC_COMPAT_STRINGS_H
#define _TCC_COMPAT_STRINGS_H

static inline int ffs(int x) {
  unsigned int v = (unsigned int)x;
  if (v == 0) {
    return 0;
  }
  int pos = 1;
  while ((v & 1u) == 0u) {
    v >>= 1;
    pos++;
  }
  return pos;
}

static inline int ffsl(long x) {
  unsigned long v = (unsigned long)x;
  if (v == 0) {
    return 0;
  }
  int pos = 1;
  while ((v & 1ul) == 0ul) {
    v >>= 1;
    pos++;
  }
  return pos;
}

#define __builtin_ffs ffs
#define __builtin_ffsl ffsl

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

#endif /* _TCC_COMPAT_STRINGS_H */
