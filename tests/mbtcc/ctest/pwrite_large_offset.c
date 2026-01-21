#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {
  const char *path = "pwrite_large_offset.tmp";
  int fd = open(path, O_CREAT | O_TRUNC | O_RDWR, 0600);
  if (fd < 0) {
    puts("skip");
    return 0;
  }
  off_t off = ((off_t)1 << 33) + 5;
  char value = 'A';
  if (pwrite(fd, &value, 1, off) != 1) {
    puts("skip");
    close(fd);
    unlink(path);
    return 0;
  }
  off_t end = lseek(fd, 0, SEEK_END);
  if (end == off + 1) {
    puts("ok");
  } else {
    printf("bad:%lld\n", (long long)end);
  }
  close(fd);
  unlink(path);
  return 0;
}
