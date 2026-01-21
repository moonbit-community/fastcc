#include <inttypes.h>
#include <stdio.h>

int main(void) {
  int cond = 1;
  int32_t neg = -1;
  int64_t big = 0x100000000LL;

  int64_t res1 = cond ? neg : big;
  int64_t res2 = cond ? big : neg;
  printf("%lld %lld\n", (long long)res1, (long long)res2);

  uint32_t u32 = 0xffffffffu;
  uint64_t u64 = 0x100000000ULL;
  uint64_t res3 = cond ? u32 : u64;
  printf("%llu\n", (unsigned long long)res3);
  return 0;
}
