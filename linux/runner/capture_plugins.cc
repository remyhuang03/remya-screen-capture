#include "capture_plugins.h"

#include <gmodule.h>

namespace {

void register_plugin(FlPluginRegistry* registry, const char* library,
                     const char* symbol, const char* name) {
  g_autoptr(GError) error = nullptr;
  g_autofree char* executable = g_file_read_link("/proc/self/exe", &error);
  if (executable == nullptr) {
    g_warning("Could not locate %s: %s", name, error->message);
    return;
  }
  g_autofree char* bundle = g_path_get_dirname(executable);
  g_autofree char* path = g_build_filename(bundle, "lib", library, nullptr);
  auto* module = g_module_open(path, G_MODULE_BIND_LAZY);
  if (module == nullptr) {
    g_warning("Could not load %s: %s", name, g_module_error());
    return;
  }
  void (*register_with_registrar)(FlPluginRegistrar*) = nullptr;
  if (g_module_symbol(module, symbol,
                      reinterpret_cast<gpointer*>(&register_with_registrar))) {
    // Registered GTypes and callbacks remain in use until process exit.
    g_module_make_resident(module);
    g_autoptr(FlPluginRegistrar) registrar =
        fl_plugin_registry_get_registrar_for_plugin(registry, name);
    register_with_registrar(registrar);
  } else {
    g_warning("Could not register %s: %s", name, g_module_error());
  }
  g_module_close(module);
}

}  // namespace

void register_capture_plugins(FlPluginRegistry* registry) {
  register_plugin(registry, "libfile_selector_linux_plugin.so",
                  "file_selector_plugin_register_with_registrar",
                  "FileSelectorPlugin");
  register_plugin(registry, "libmedia_kit_video_plugin.so",
                  "media_kit_video_plugin_register_with_registrar",
                  "MediaKitVideoPlugin");
}
