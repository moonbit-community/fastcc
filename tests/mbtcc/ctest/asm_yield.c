#include <stdio.h>

int main(void) {
#if defined(__aarch64__)
  asm volatile("yield" ::: "memory");
#endif
  printf("1\n");
  return 0;
}
