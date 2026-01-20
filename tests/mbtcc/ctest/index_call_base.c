#include <stdio.h>

static int mylen(const char *s) {
  int n = 0;
  while (s[n]) {
    n++;
  }
  return n;
}

int main(void) {
  const char *s = "abcdef";
  const char *p = &s[mylen(s) + 1];
  const char *q = s + 7;

  if (p == q) {
    puts("ok");
  } else {
    puts("bad");
  }
  return 0;
}
