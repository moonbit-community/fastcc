#include <stdio.h>

int main(void) {
  static const void *const table[2] = {&&label0, &&label1};
  goto *table[0];

label0:
  printf("0\n");
  goto *table[1];

label1:
  printf("1\n");
  return 0;
}
