#include <stdarg.h>
#include <stdio.h>

static int pick_var(
  int a1,
  int a2,
  int a3,
  int a4,
  int a5,
  int a6,
  int a7,
  int a8,
  int a9,
  ...
) {
  va_list ap;
  va_start(ap, a9);
  int v = va_arg(ap, int);
  va_end(ap);
  return v;
}

int main(void) {
  int value = pick_var(1, 2, 3, 4, 5, 6, 7, 8, 9, 1234);
  printf("%d\n", value);
  return 0;
}
