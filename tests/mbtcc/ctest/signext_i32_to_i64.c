#include <inttypes.h>
#include <stdio.h>

int main(void) {
  int32_t y = -2;
  int64_t x = y;
  printf("%lld\n", (long long)x);
  return 0;
}
