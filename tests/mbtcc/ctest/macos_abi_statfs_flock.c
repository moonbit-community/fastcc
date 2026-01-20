#if defined(__APPLE__)
#include <fcntl.h>
#include <stddef.h>
#include <sys/mount.h>

typedef char assert_statfs_size[(sizeof(struct statfs) == 2168) ? 1 : -1];
typedef char assert_statfs_flags[(offsetof(struct statfs, f_flags) == 64) ? 1 : -1];
typedef char assert_statfs_fstypename[
  (offsetof(struct statfs, f_fstypename) == 72) ? 1 : -1
];
typedef char assert_statfs_mntonname[
  (offsetof(struct statfs, f_mntonname) == 88) ? 1 : -1
];

typedef char assert_flock_size[(sizeof(struct flock) == 24) ? 1 : -1];
typedef char assert_flock_l_start[
  (offsetof(struct flock, l_start) == 0) ? 1 : -1
];
typedef char assert_flock_l_len[(offsetof(struct flock, l_len) == 8) ? 1 : -1];
typedef char assert_flock_l_pid[
  (offsetof(struct flock, l_pid) == 16) ? 1 : -1
];
typedef char assert_flock_l_type[
  (offsetof(struct flock, l_type) == 20) ? 1 : -1
];
typedef char assert_flock_l_whence[
  (offsetof(struct flock, l_whence) == 22) ? 1 : -1
];

int main(void) { return 0; }
#else
int main(void) { return 0; }
#endif
