#include "moonbit.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

int32_t tinyccmbt_run_command(moonbit_bytes_t cmd) {
  if (cmd == NULL) {
    return -1;
  }
  int status = system((const char *)cmd);
  if (status == -1) {
    return -1;
  }
#ifdef WIFEXITED
  if (WIFEXITED(status)) {
    return (int32_t)WEXITSTATUS(status);
  }
  if (WIFSIGNALED(status)) {
    return (int32_t)(128 + WTERMSIG(status));
  }
#endif
  return (int32_t)status;
}

moonbit_bytes_t tinyccmbt_read_stdin_bytes(void) {
  size_t capacity = 4096;
  size_t len = 0;
  uint8_t *buffer = (uint8_t *)malloc(capacity);
  if (buffer == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  for (;;) {
    size_t remaining = capacity - len;
    if (remaining == 0) {
      size_t next_capacity = capacity * 2;
      uint8_t *next = (uint8_t *)realloc(buffer, next_capacity);
      if (next == NULL) {
        free(buffer);
        return moonbit_make_bytes(0, 0);
      }
      buffer = next;
      capacity = next_capacity;
      remaining = capacity - len;
    }
    size_t n = fread(buffer + len, 1, remaining, stdin);
    len += n;
    if (n == 0) {
      break;
    }
  }
  if (len > INT32_MAX) {
    free(buffer);
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)len, 0);
  if (len > 0) {
    memcpy(bytes, buffer, len);
  }
  free(buffer);
  return bytes;
}
