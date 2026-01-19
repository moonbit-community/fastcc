#include <stdint.h>
#include <stdio.h>

struct bf {
    uint64_t target:36;
    uint64_t high8:8;
    uint64_t reserved:7;
    uint64_t next:12;
    uint64_t bind:1;
};

int main(void) {
    union {
        struct bf v;
        uint64_t raw;
    } u;
    u.raw = 0;
    uint64_t base = 0x3000000000000000ULL | 0x0000000100125eb8ULL;
    u.v.target = base & ((1ULL << 36) - 1);
    u.v.high8 = (base >> 56) & 0xff;
    u.v.reserved = 0;
    u.v.next = 0x123;
    u.v.bind = 1;
    printf("%016llx\n", (unsigned long long)u.raw);
    return 0;
}
