#include <stdint.h>
#include <stdio.h>

struct Shape {
  int a;
  int b;
  uint32_t prop_hash_mask;
  int prop_count;
};

static inline uint32_t *prop_hash_end(struct Shape *sh) {
  return (uint32_t *)sh;
}

int main(void) {
  uint32_t buf[8];
  for (int i = 0; i < 8; i++) {
    buf[i] = 0;
  }
  struct Shape *sh = (struct Shape *)(buf + 4);
  sh->prop_hash_mask = 3;
  sh->prop_count = 7;
  uintptr_t atom = 2;
  intptr_t h = (uintptr_t)atom & sh->prop_hash_mask;
  prop_hash_end(sh)[-h - 1] = sh->prop_count;
  printf("%u %u %u %u\n", buf[0], buf[1], buf[2], buf[3]);
  return 0;
}
