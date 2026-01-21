#include <stdio.h>

struct Bits {
  unsigned a:1;
  unsigned b:2;
  unsigned c:5;
  unsigned d:8;
  unsigned x;
};

int main(void) {
  struct Bits v = {1, 2, 3, 0x5a, 0x12345678};
  struct Bits z = {0};
  printf("%u %u %u %u %u %u\n", v.a, v.b, v.c, v.d, v.x, z.a);
  return 0;
}
