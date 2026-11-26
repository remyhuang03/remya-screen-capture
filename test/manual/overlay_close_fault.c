#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Report an error after native code closes the last overlay, once per process.
int fl_method_call_respond_success(void *call, void *result, void **error) {
  static int closes;
  const char *(*name)(void *) = dlsym(RTLD_NEXT, "fl_method_call_get_name");
  int (*success)(void *, void *, void **) =
      dlsym(RTLD_NEXT, "fl_method_call_respond_success");
  const char *target = getenv("REMYA_TEST_FAIL_CLOSE");
  if (target && strcmp(name(call), "close") == 0 && ++closes == atoi(target)) {
    int (*failure)(void *, const char *, const char *, void *, void **) =
        dlsym(RTLD_NEXT, "fl_method_call_respond_error");
    fprintf(stderr, "Injected overlay close failure\n");
    return failure(call, "injected", "Overlay close response failed", NULL, error);
  }
  return success(call, result, error);
}
