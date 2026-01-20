#include <stdio.h>

static int *get_counter(void) {
  static int value = 41;
  return &value;
}

static void clobber_stack(void) {
  volatile char buf[2048];
  for (int i = 0; i < (int)sizeof(buf); i++) {
    buf[i] = (char)i;
  }
}

int main(void) {
  int *first = get_counter();
  *first = 7;
  clobber_stack();
  int *second = get_counter();
  printf("%d %d\n", first == second, *second);
  return 0;
}
