#include <inttypes.h>
#include <stdio.h>

int main(void) {
  int64_t vals[] = {
    -8388609LL, -8388608LL, -32769LL, -32768LL, -129LL, -128LL,
    -3LL, -2LL, -1LL, 0LL, 1LL, 2LL, 3LL, 4LL, 127LL, 128LL,
    255LL, 256LL, 16383LL, 16384LL
  };
  int n = (int)(sizeof(vals) / sizeof(vals[0]));
  for (int i = 0; i < n; i++) {
    if (vals[i] < 16384) {
      printf("%lld ", (long long)vals[i]);
    }
  }
  printf("\n");
  return 0;
}
