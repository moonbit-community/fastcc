#include "moonbit.h"

#include <stdint.h>
#include <stdlib.h>
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
