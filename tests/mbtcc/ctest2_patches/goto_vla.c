#include "test.h"

// Exercise goto that leaves a scope containing a VLA. Without restoring SP on
// the jump, the stack grows each iteration and the program will crash long
// before reaching the final print.

int main() {
    int len = 1024;
    int i = 0;
    int sum = 0;

loop:
    {
        int arr[len];
        arr[0] = i;
        arr[len - 1] = i + 1;
        sum += arr[0] + arr[len - 1];
        i++;
        if (i < 4000) goto loop;
        printf("%d %d\n", i, sum);
    }

    return 0;
}

