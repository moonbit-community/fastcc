#ifndef _TCC_COMPAT_STDLIB_H
#define _TCC_COMPAT_STDLIB_H

#include <stddef.h>

typedef struct { int quot, rem; } div_t;
typedef struct { long quot, rem; } ldiv_t;
typedef struct { long long quot, rem; } lldiv_t;

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1

void abort(void);
void exit(int status);
int atexit(void (*fn)(void));

int atoi(const char *s);
long atol(const char *s);
long long atoll(const char *s);

long strtol(const char *s, char **endp, int base);
long long strtoll(const char *s, char **endp, int base);
unsigned long strtoul(const char *s, char **endp, int base);
unsigned long long strtoull(const char *s, char **endp, int base);
double strtod(const char *s, char **endp);
float strtof(const char *s, char **endp);
long double strtold(const char *s, char **endp);

void *malloc(size_t size);
void *calloc(size_t nmemb, size_t size);
void *realloc(void *ptr, size_t size);
void *aligned_alloc(size_t alignment, size_t size);
void free(void *ptr);
void *alloca(size_t size);
#ifndef alloca
#define alloca(size) __builtin_alloca(size)
#endif

void *bsearch(const void *key, const void *base, size_t nmemb, size_t size, int (*cmp)(const void *, const void *));
void qsort(void *base, size_t nmemb, size_t size, int (*cmp)(const void *, const void *));

int rand(void);
void srand(unsigned int seed);

char *getenv(const char *name);
int system(const char *cmd);

int mkstemp(char *template);
char *mktemp(char *template);
char *realpath(const char *path, char *resolved);

long labs(long n);
long long llabs(long long n);
div_t div(int x, int y);
ldiv_t ldiv(long x, long y);
lldiv_t lldiv(long long x, long long y);

#endif /* _TCC_COMPAT_STDLIB_H */
