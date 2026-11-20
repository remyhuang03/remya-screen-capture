#include "my_application.h"

#include <fcntl.h>
#include <gmodule.h>
#include <unistd.h>

#include "capture_windows.h"

// The Dart lock uses fcntl too; locks are shared by threads in this process.
static void prefetch_cold_capture() {
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
  prefetch_capture_snapshot();
}

void prefetch_capture_snapshot() {
  using Prefetch = void (*)();
  static const auto prefetch = []() -> Prefetch {
    g_autofree char* executable = g_file_read_link("/proc/self/exe", nullptr);
    if (executable == nullptr) return nullptr;
    g_autofree char* directory = g_path_get_dirname(executable);
    g_autofree char* library =
        g_build_filename(directory, "lib", "libremya_capture.so", nullptr);
    auto* module = g_module_open(library, G_MODULE_BIND_LAZY);
    gpointer symbol = nullptr;
    if (module == nullptr) return nullptr;
    if (!g_module_symbol(module, "remya_prefetch_capture", &symbol)) {
      g_module_close(module);
      return nullptr;
    }
    g_module_make_resident(module);
    g_module_close(module);
    return reinterpret_cast<Prefetch>(symbol);
  }();
  if (prefetch != nullptr) prefetch();
}

int main(int argc, char** argv) {
  bool settings = false;
  bool background = false;
  bool recording = false;
  bool color = false;
  bool has_mode = false;
  for (int i = 1; i < argc; ++i) {
    settings |= g_str_equal(argv[i], "--settings");
    background |= g_str_equal(argv[i], "--background");
    recording |= g_str_equal(argv[i], "--record");
    color |= g_str_equal(argv[i], "--color-picker");
    if (!has_mode && g_str_equal(argv[i], "--mode")) {
      color |= i + 1 < argc && g_str_equal(argv[i + 1], "color");
      has_mode = true;
    }
  }
  if (settings) background = false;
  if (!settings && !background) {
    const char* mode = color ? "colorPicker" : recording ? "recording" : "screenshot";
    if (forward_resident_capture(mode)) return 0;
    if (color || !recording) prefetch_cold_capture();
  }
  g_autoptr(MyApplication) app = my_application_new(background);
  return g_application_run(G_APPLICATION(app), argc, argv);
}
