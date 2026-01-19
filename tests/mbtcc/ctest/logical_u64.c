#include <inttypes.h>
#include <stdio.h>

int main(void) {
  uint64_t x = 1ULL;
  uint64_t mask = (uint64_t)1 << 63;
  int n = 0;
  while (mask && (x & mask) == 0) {
    n++;
    mask >>= 1;
  }
  printf("%d\n", n);
  return 0;
}
