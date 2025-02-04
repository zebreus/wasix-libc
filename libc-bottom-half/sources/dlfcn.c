// TODO: These do not belong here
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <wasi/libc-find-relpath.h>
#include <wasi/libc.h>

int dlclose(void *handle) {
  __wasi_dl_handle_t dlid = (__wasi_dl_handle_t)handle;
  __wasi_errno_t error = __wasi_dl_close(dlid);
  return 0;
}

static char error[256] = {0};
char *dlerror() {
  __wasi_size_t result_len = 0;
  __wasi_errno_t wasi_error =
      __wasi_dl_error((uint8_t *)error, sizeof(error), &result_len);
  // TODO: Process result_len
  return (char *)error;
}

void *dlopen(const char *filename, int flags) {
  __wasi_dl_handle_t dlid;
  __wasi_errno_t error = __wasi_dl_open(filename, &dlid);
  return (void *)dlid;
}

void *dlsym(void *__restrict handle, const char *__restrict symbol) {
  __wasi_dl_handle_t dlid = (__wasi_dl_handle_t)handle;
  __wasi_pointersize_t result = 0;
  __wasi_errno_t error = __wasi_dl_load_symbol(symbol, dlid, &result);
  return (void *)result;
}