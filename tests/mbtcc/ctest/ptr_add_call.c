#include <stdio.h>
#include <string.h>

int main(void) {
  char buf[16] = "abc";
  char *q = buf + strlen(buf);
  printf("%d\n", q == buf + 3);
  return 0;
}
