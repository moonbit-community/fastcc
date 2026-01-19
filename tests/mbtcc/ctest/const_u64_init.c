#include <stdint.h>
#include <stdio.h>

uint64_t start = ((uint64_t)1 << 32);

int main(void) {
  printf("%llu\n", (unsigned long long)start);
  return 0;
}
