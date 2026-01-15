#include "test.h"

// Multi-dimensional VLA: verify allocation and sizeof use the values at the
// declaration point (not after variables change), and that runtime size math
// works for nested VLAs.
int main() {
    int n = 3;
    int m = 4;
    int sum = 0;

    int a[n][m];
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < m; j++) {
            a[i][j] = i * 10 + j;
            sum += a[i][j];
        }
    }

    // Change m after declaration; sizeof should keep original extent.
    m = 5;
    printf("%lu %d\n", (unsigned long)sizeof(a), sum);
    return 0;
}

