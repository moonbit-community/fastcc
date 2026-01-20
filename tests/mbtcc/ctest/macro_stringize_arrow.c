#include <stdio.h>

#define STR(x) #x
#define STR2(x) STR(x)

int main(void) {
  printf("%s\n", STR2(->));
  printf("%s\n", STR2(->>));
  return 0;
}
