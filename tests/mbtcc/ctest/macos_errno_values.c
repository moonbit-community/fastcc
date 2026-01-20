#if defined(__APPLE__)
#include <errno.h>

typedef char assert_eagain[(EAGAIN == 35) ? 1 : -1];
typedef char assert_edeadlk[(EDEADLK == 11) ? 1 : -1];
typedef char assert_enosys[(ENOSYS == 78) ? 1 : -1];
typedef char assert_enotempty[(ENOTEMPTY == 66) ? 1 : -1];
typedef char assert_etimedout[(ETIMEDOUT == 60) ? 1 : -1];

typedef char assert_enolck[(ENOLCK == 77) ? 1 : -1];

int main(void) { return 0; }
#else
int main(void) { return 0; }
#endif
