#include <stdio.h>

int main(void) {
  unsigned char data[2] = {0, 0};
  int i;
  for (i = 0; i < 256; i++) {
    if (++data[1] == 0) {
      data[0]++;
    }
  }
  printf("%u %u\n", data[0], data[1]);
  return 0;
}
