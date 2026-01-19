#include <stdio.h>
#include <string.h>
#include <stddef.h>

struct BitfieldCross {
  int ref_count;
  unsigned int len : 31;
  unsigned char is_wide_char : 1;
  unsigned int hash : 30;
  unsigned char atom_type : 2;
  unsigned int hash_next;
};

int main(void) {
  struct BitfieldCross s;
  memset(&s, 0, sizeof(s));
  s.len = 0;
  s.is_wide_char = 1;
  s.hash = 0x21b5ab31;
  s.atom_type = 1;
  printf("%08x\n", *(unsigned int *)((unsigned char *)&s + 8));
  printf("%zu %zu\n", sizeof(struct BitfieldCross), offsetof(struct BitfieldCross, hash_next));
  return 0;
}
