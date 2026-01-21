#include <inttypes.h>
#include <stdio.h>

int main(void) {
  int64_t x = 1;
  int hit = 0;
  switch (x) {
    case 0x100000001LL:
      hit = 1;
      break;
    case 0x100000000LL:
      hit = 2;
      break;
    default:
      break;
  }
  printf("%d\n", hit);
  return 0;
}
