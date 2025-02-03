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

int dlclose(void *handle) { return 0; }

char *dlerror() { return "dlerror is not implememented"; }

void *dlopen(const char *filename, int flags) {
  __wasi_dlopenid_t dlid;
  __wasi_errno_t error = __wasi_dl_open(filename, &dlid);
  return (void *)dlid;
}

void *dlsym(void *__restrict handle, const char *__restrict symbol) {
  __wasi_dlopenid_t dlid = (__wasi_dlopenid_t)handle;
  __wasi_pointersize_t result = 0;
  __wasi_errno_t error = __wasi_dl_load_symbol(symbol, dlid, &result);
  return (void *)result;
}