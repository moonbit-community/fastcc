#include "test.h"

// Regression: static/global/local symbols must link correctly (relocs extern).
static int g = 41;
static int add1(int x) { return x + 1; }

int main() {
    printf("%d\n", add1(g));
    return 0;
}

