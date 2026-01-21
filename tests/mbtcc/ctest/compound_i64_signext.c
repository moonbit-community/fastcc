#include <stdint.h>
#include <stdio.h>

int main(void) {
  int64_t x = 0;
  int32_t y = -1;
  x -= y;
  printf("%lld\n", (long long)x);
  return 0;
}
