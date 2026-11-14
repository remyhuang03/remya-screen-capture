#include "my_application.h"

#include <fcntl.h>
#include <gmodule.h>
#include <unistd.h>

// The Dart lock uses fcntl too; locks are shared by threads in this process.
static void prefetch_capture(int argc, char** argv) {
  for (int i = 1; i < argc; ++i) {
    if (g_str_equal(argv[i], "--settings")) return;
    if (g_str_equal(argv[i], "--record")) {
      bool color = false;
      for (int j = 1; j < argc; ++j) {
        color |= g_str_equal(argv[j], "--color-picker") ||
                 (g_str_equal(argv[j], "--mode") && j + 1 < argc &&
                  g_str_equal(argv[j + 1], "color"));
      }
      if (!color) return;
    }
  }
  const char* runtime = g_getenv("XDG_RUNTIME_DIR");
  if (runtime == nullptr || !g_path_is_absolute(runtime)) return;
  g_autofree char* path = g_build_filename(runtime, APPLICATION_ID ".lock", nullptr);
  const int lock = open(path, O_WRONLY | O_CREAT | O_CLOEXEC, 0600);
  if (lock < 0) return;
  struct flock region = {};
  region.l_type = F_WRLCK;
  region.l_whence = SEEK_SET;
  if (fcntl(lock, F_SETLK, &region) < 0) {
    close(lock);
    return;
  }
  // Keep the descriptor open until process exit or Dart releases its lock.
  g_autofree char* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable == nullptr) return;
  g_autofree char* directory = g_path_get_dirname(executable);
  g_autofree char* library = g_build_filename(directory, "lib", "libremya_capture.so", nullptr);
  auto* module = g_module_open(library, G_MODULE_BIND_LAZY);
  void (*prefetch)() = nullptr;
  if (module != nullptr && g_module_symbol(module, "remya_prefetch_capture",
                                         reinterpret_cast<gpointer*>(&prefetch))) {
    g_module_make_resident(module);
    prefetch();
  }
}

int main(int argc, char** argv) {
  prefetch_capture(argc, argv);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
