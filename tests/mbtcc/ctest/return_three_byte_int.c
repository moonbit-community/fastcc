#include <stdint.h>
#include <stdio.h>

#define THREE_BYTE_INT(x)  (65536*(int8_t)((x)[0])|((x)[1]<<8)|(x)[2])

static int64_t decode(const unsigned char *x) {
  return THREE_BYTE_INT(x);
}

int main(void) {
  unsigned char a[3] = {0x80, 0x00, 0x00};
  unsigned char b[3] = {0xff, 0xff, 0xff};
  printf("%lld %lld\n", (long long)decode(a), (long long)decode(b));
  return 0;
}
