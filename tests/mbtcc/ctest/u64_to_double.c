#include <stdint.h>
#include <stdio.h>

int main(void) {
  uint64_t u = 0x1ffffffffULL;
  int64_t s = 0x1ffffffffLL;
  double du = (double)u;
  double ds = (double)s;

  printf("%.0f\n", du);
  printf("%.0f\n", ds);
  return 0;
}
