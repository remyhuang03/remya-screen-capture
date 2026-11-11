#include "capture_windows.h"

#include <flutter_linux/flutter_linux.h>
#include <gdk/gdkwayland.h>
#include <gtk-layer-shell.h>
#include <wayland-client.h>

#include <map>
#include <memory>
#include <string>
#include <utility>

#include "flutter/generated_plugin_registrant.h"
#include "xdg-output-client-protocol.h"

namespace {

constexpr char kHostKey[] = "remya-capture-windows";

using OutputNames = std::map<std::string, GdkMonitor*>;
using InputRegion =
    std::unique_ptr<cairo_region_t, decltype(&cairo_region_destroy)>;

OutputNames get_named_outputs(GdkDisplay* display) {
  if (!GDK_IS_WAYLAND_DISPLAY(display) || !gtk_layer_is_supported()) return {};

  // Query names for GDK's own wl_outputs on a private queue, so the roundtrips
  // do not dispatch unrelated GDK callbacks in the middle of a method call.
  auto* wayland = gdk_wayland_display_get_wl_display(display);
  auto* queue = wl_display_create_queue(wayland);
  if (queue == nullptr) return {};
  auto* wrapper = wl_proxy_create_wrapper(wayland);
  if (wrapper == nullptr) {
    wl_event_queue_destroy(queue);
    return {};
  }
  wl_proxy_set_queue(static_cast<wl_proxy*>(wrapper), queue);
  auto* registry = wl_display_get_registry(static_cast<wl_display*>(wrapper));
  wl_proxy_wrapper_destroy(wrapper);

  zxdg_output_manager_v1* manager = nullptr;
  const wl_registry_listener registry_listener = {
      [](void* data, wl_registry* registry, uint32_t name,
         const char* interface, uint32_t version) {
        auto** manager = static_cast<zxdg_output_manager_v1**>(data);
        if (*manager == nullptr && version >= 2 &&
            g_str_equal(interface, zxdg_output_manager_v1_interface.name)) {
          *manager = static_cast<zxdg_output_manager_v1*>(wl_registry_bind(
              registry, name, &zxdg_output_manager_v1_interface, 2));
        }
      },
      [](void*, wl_registry*, uint32_t) {},
  };
  wl_registry_add_listener(registry, &registry_listener, &manager);

  OutputNames names;
  if (wl_display_roundtrip_queue(wayland, queue) >= 0 && manager != nullptr) {
    struct Output {
      GdkMonitor* monitor;
      std::string name;
    };
    const zxdg_output_v1_listener output_listener = {
        [](void*, zxdg_output_v1*, int32_t, int32_t) {},
        [](void*, zxdg_output_v1*, int32_t, int32_t) {},
        [](void*, zxdg_output_v1*) {},
        [](void* data, zxdg_output_v1*, const char* name) {
          static_cast<Output*>(data)->name = name;
        },
        [](void*, zxdg_output_v1*, const char*) {},
    };
    std::map<zxdg_output_v1*, Output> outputs;
    for (int i = 0; i < gdk_display_get_n_monitors(display); ++i) {
      auto* monitor = gdk_display_get_monitor(display, i);
      auto* output = gdk_wayland_monitor_get_wl_output(monitor);
      if (output == nullptr) continue;
      auto* xdg_output = zxdg_output_manager_v1_get_xdg_output(manager, output);
      auto entry = outputs.emplace(xdg_output, Output{monitor, {}});
      zxdg_output_v1_add_listener(xdg_output, &output_listener,
                                  &entry.first->second);
    }
    const bool queried = wl_display_roundtrip_queue(wayland, queue) >= 0;
    for (const auto& entry : outputs) {
      if (queried && !entry.second.name.empty()) {
        names.emplace(entry.second.name, entry.second.monitor);
      }
      zxdg_output_v1_destroy(entry.first);
    }
  }
  if (manager != nullptr) zxdg_output_manager_v1_destroy(manager);
  wl_registry_destroy(registry);
  wl_event_queue_destroy(queue);
  return names;
}

FlValue* lookup(FlValue* map, const char* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  return fl_value_lookup_string(map, key);
}

const char* string_at(FlValue* map, const char* key) {
  FlValue* value = lookup(map, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value)
             : "";
}

bool int_at(FlValue* map, const char* key, int64_t* result) {
  FlValue* value = lookup(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return false;
  }
  *result = fl_value_get_int(value);
  return true;
}

bool read_rectangle(FlValue* value, cairo_rectangle_int_t* rect) {
  int64_t x, y, width, height;
  constexpr int kMaxCoordinate = G_MAXINT / 2;
  if (!int_at(value, "x", &x) || !int_at(value, "y", &y) ||
      !int_at(value, "width", &width) || !int_at(value, "height", &height) ||
      x < -kMaxCoordinate || x > kMaxCoordinate || y < -kMaxCoordinate ||
      y > kMaxCoordinate || width < 0 || width > kMaxCoordinate || height < 0 ||
      height > kMaxCoordinate) {
    return false;
  }
  *rect = {static_cast<int>(x), static_cast<int>(y), static_cast<int>(width),
           static_cast<int>(height)};
  return true;
}

void success(FlMethodCall* call) {
  fl_method_call_respond_success(call, nullptr, nullptr);
}

void error(FlMethodCall* call, const char* code, const char* message) {
  fl_method_call_respond_error(call, code, message, nullptr, nullptr);
}

class CaptureWindows {
 public:
  CaptureWindows(GtkApplication* application, char** arguments)
      : application_(application), display_(gdk_display_get_default()) {
    g_application_hold(G_APPLICATION(application_));

    g_autoptr(FlDartProject) project = fl_dart_project_new();
    fl_dart_project_set_dart_entrypoint_arguments(project, arguments);
    bootstrap_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    g_object_ref_sink(bootstrap_);
    gtk_window_set_default_size(GTK_WINDOW(bootstrap_), 1, 1);
    auto* view = fl_view_new(project);
    engine_ = fl_view_get_engine(view);
    gtk_container_add(GTK_CONTAINER(bootstrap_), GTK_WIDGET(view));

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    channel_ = fl_method_channel_new(fl_engine_get_binary_messenger(engine_),
                                     APPLICATION_ID "/windows",
                                     FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(channel_, method_call, this,
                                              nullptr);
    g_signal_connect(display_, "monitor-added", G_CALLBACK(monitor_added),
                     this);
    g_signal_connect(display_, "monitor-removed", G_CALLBACK(monitor_removed),
                     this);
    for (int i = 0; i < gdk_display_get_n_monitors(display_); ++i) {
      watch_monitor(gdk_display_get_monitor(display_, i));
    }

    // Realize the implicit view to start the engine and keep its GL context
    // alive for the mapped views without adding it to the desktop.
    gtk_widget_realize(bootstrap_);
    gtk_widget_realize(GTK_WIDGET(view));
  }

  ~CaptureWindows() {
    g_signal_handlers_disconnect_by_data(display_, this);
    for (int i = 0; i < gdk_display_get_n_monitors(display_); ++i) {
      g_signal_handlers_disconnect_by_data(gdk_display_get_monitor(display_, i),
                                           this);
    }
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                              nullptr);
    g_clear_object(&channel_);
    while (!windows_.empty()) {
      gtk_widget_destroy(windows_.begin()->second->window);
    }
    gtk_widget_destroy(bootstrap_);
    g_clear_object(&bootstrap_);
    g_application_release(G_APPLICATION(application_));
  }

 private:
  enum class Role { overlay, result, editor };

  struct Window {
    CaptureWindows* host;
    GtkWidget* window;
    FlView* view;
    int64_t id;
    Role role;
    bool active = true;
    guint32 drag_time = GDK_CURRENT_TIME;
    int drag_x = 0;
    int drag_y = 0;
    InputRegion input_region{nullptr, cairo_region_destroy};

    bool is_layer() const { return role != Role::editor; }

    void apply_input_region() const {
      gtk_widget_input_shape_combine_region(window, input_region.get());
      gtk_widget_queue_draw(window);
    }
  };

  static void method_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
    static_cast<CaptureWindows*>(data)->handle(call);
  }

  void handle(FlMethodCall* call) {
    const char* method = fl_method_call_get_name(call);
    FlValue* args = fl_method_call_get_args(call);
    if (g_str_equal(method, "outputs")) {
      const auto names = get_named_outputs(display_);
      if (names.empty()) {
        error(call, "outputs-unavailable",
              "No named Wayland outputs with layer-shell support.");
        return;
      }
      g_autoptr(FlValue) value = fl_value_new_list();
      for (const auto& output : names) {
        fl_value_append_take(value, fl_value_new_string(output.first.c_str()));
      }
      fl_method_call_respond_success(call, value, nullptr);
      return;
    }
    if (g_str_equal(method, "open")) {
      open(call, args);
      return;
    }
    if (g_str_equal(method, "picturesDirectory")) {
      const char* path = g_getenv("XDG_PICTURES_DIR");
      if (path == nullptr || !g_path_is_absolute(path)) {
        path = g_get_user_special_dir(G_USER_DIRECTORY_PICTURES);
      }
      g_autoptr(FlValue) value =
          path == nullptr ? fl_value_new_null() : fl_value_new_string(path);
      fl_method_call_respond_success(call, value, nullptr);
      return;
    }
    if (g_str_equal(method, "quit")) {
      success(call);
      g_application_quit(G_APPLICATION(application_));
      return;
    }

    int64_t id;
    if (!int_at(args, "id", &id)) {
      error(call, "bad-arguments", "Expected a Flutter view ID.");
      return;
    }
    auto found = windows_.find(id);
    if (found == windows_.end() || !found->second->active) {
      error(call, "window-closed", "This capture window is already closed.");
      return;
    }
    auto& window = *found->second;
    if (g_str_equal(method, "show")) {
      gtk_widget_show_all(window.window);
      // GTK's first map resets the Wayland region during realization.
      if (window.is_layer()) window.apply_input_region();
      gtk_widget_grab_focus(GTK_WIDGET(window.view));
      success(call);
    } else if (g_str_equal(method, "hide")) {
      gtk_widget_hide(window.window);
      gdk_display_sync(display_);
      success(call);
    } else if (g_str_equal(method, "close")) {
      // shortcut: retain hidden views until shutdown, destroy them sooner
      // when Flutter's GTK view disposal can safely overlap raster work.
      const bool was_mapped = gtk_widget_get_mapped(window.window);
      gtk_widget_hide(window.window);
      window.active = false;
      window.drag_time = GDK_CURRENT_TIME;
      window.input_region.reset();
      if (window.is_layer()) {
        gtk_layer_set_keyboard_mode(GTK_WINDOW(window.window),
                                    GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
        gtk_layer_set_monitor(GTK_WINDOW(window.window), nullptr);
      }
      if (was_mapped) gdk_display_sync(display_);
      emit("closed", window.id);
      success(call);
    } else if (g_str_equal(method, "input")) {
      set_input(call, args, window);
    } else if (g_str_equal(method, "beginMove")) {
      if (!window.is_layer() && window.drag_time != GDK_CURRENT_TIME) {
        gtk_window_begin_move_drag(GTK_WINDOW(window.window), 1, window.drag_x,
                                   window.drag_y, window.drag_time);
        window.drag_time = GDK_CURRENT_TIME;
      }
      success(call);
    } else {
      fl_method_call_respond_not_implemented(call, nullptr);
    }
  }

  void open(FlMethodCall* call, FlValue* args) {
    const char* role_name = string_at(args, "role");
    const bool editor = g_str_equal(role_name, "editor");
    const bool overlay = g_str_equal(role_name, "overlay");
    const bool result = g_str_equal(role_name, "result");
    if (!editor && !overlay && !result) {
      error(call, "bad-arguments", "Unknown capture window role.");
      return;
    }

    GdkMonitor* monitor = nullptr;
    if (!editor) {
      const auto names = get_named_outputs(display_);
      const auto found = names.find(string_at(args, "output"));
      if (found == names.end()) {
        error(call, "output-unavailable",
              "The requested Wayland output is unavailable.");
        return;
      }
      monitor = found->second;
    }
    const auto role = editor    ? Role::editor
                      : overlay ? Role::overlay
                                : Role::result;
    for (auto& entry : windows_) {
      auto& state = *entry.second;
      if (state.active || state.role != role) continue;
      state.active = true;
      if (monitor != nullptr) {
        gtk_layer_set_monitor(GTK_WINDOW(state.window), monitor);
      }
      respond_view(call, state.id);
      return;
    }

    auto* widget = gtk_application_window_new(application_);
    auto* window = GTK_WINDOW(widget);
    gtk_window_set_title(window, "Remy'a Screen Capture");
    gtk_window_set_decorated(window, FALSE);
    auto* view = fl_view_new_for_engine(engine_);
    const int64_t id = fl_view_get_id(view);
    auto state = std::make_unique<Window>(Window{this, widget, view, id, role});

    if (editor) {
      gtk_window_set_default_size(window, 1280, 800);
      gtk_widget_set_size_request(GTK_WIDGET(view), 480, 340);
      fl_register_plugins(FL_PLUGIN_REGISTRY(view));
      auto* gesture = gtk_gesture_multi_press_new(widget);
      g_object_set_data_full(G_OBJECT(widget), "move-gesture", gesture,
                             g_object_unref);
      gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(gesture),
                                                 GTK_PHASE_CAPTURE);
      gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(gesture), 1);
      g_signal_connect(gesture, "pressed", G_CALLBACK(remember_pointer),
                       state.get());
      g_signal_connect(widget, "delete-event", G_CALLBACK(close_requested),
                       state.get());
    } else {
      gtk_layer_init_for_window(window);
      gtk_layer_set_namespace(window, overlay ? APPLICATION_ID "/overlay"
                                              : APPLICATION_ID "/result");
      gtk_layer_set_monitor(window, monitor);
      gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
      gtk_layer_set_exclusive_zone(window, -1);
      gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
      for (auto edge :
           {GTK_LAYER_SHELL_EDGE_LEFT, GTK_LAYER_SHELL_EDGE_RIGHT,
            GTK_LAYER_SHELL_EDGE_TOP, GTK_LAYER_SHELL_EDGE_BOTTOM}) {
        gtk_layer_set_anchor(window, edge, TRUE);
      }
      gtk_widget_set_app_paintable(widget, TRUE);
      auto* visual = gdk_screen_get_rgba_visual(gtk_widget_get_screen(widget));
      if (visual != nullptr) gtk_widget_set_visual(widget, visual);
      const GdkRGBA transparent = {0, 0, 0, 0};
      fl_view_set_background_color(view, &transparent);
    }

    g_signal_connect(widget, "destroy", G_CALLBACK(window_destroyed),
                     state.get());
    windows_.emplace(id, std::move(state));
    gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
    respond_view(call, id);
  }

  static void respond_view(FlMethodCall* call, int64_t id) {
    g_autoptr(FlValue) value = fl_value_new_int(id);
    fl_method_call_respond_success(call, value, nullptr);
  }

  void set_input(FlMethodCall* call, FlValue* args, Window& window) {
    const char* mode = string_at(args, "keyboard");
    GtkLayerShellKeyboardMode keyboard;
    if (g_str_equal(mode, "none")) {
      keyboard = GTK_LAYER_SHELL_KEYBOARD_MODE_NONE;
    } else if (g_str_equal(mode, "exclusive")) {
      keyboard = GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE;
    } else if (g_str_equal(mode, "onDemand")) {
      keyboard = GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND;
    } else {
      error(call, "bad-arguments", "Unknown capture keyboard mode.");
      return;
    }
    if (!window.is_layer()) {
      error(call, "bad-arguments", "Input regions apply to capture overlays.");
      return;
    }

    FlValue* rects = lookup(args, "rects");
    InputRegion region(nullptr, cairo_region_destroy);
    if (rects != nullptr && fl_value_get_type(rects) != FL_VALUE_TYPE_NULL) {
      if (fl_value_get_type(rects) != FL_VALUE_TYPE_LIST) {
        error(call, "bad-arguments", "Expected a list of input rectangles.");
        return;
      }
      region.reset(cairo_region_create());
      for (size_t i = 0; i < fl_value_get_length(rects); ++i) {
        cairo_rectangle_int_t rect;
        if (!read_rectangle(fl_value_get_list_value(rects, i), &rect)) {
          error(call, "bad-arguments", "Invalid input rectangle.");
          return;
        }
        cairo_region_union_rectangle(region.get(), &rect);
      }
    }
    window.input_region = std::move(region);
    if (gtk_widget_get_mapped(window.window)) window.apply_input_region();
    gtk_layer_set_keyboard_mode(GTK_WINDOW(window.window), keyboard);
    if (keyboard != GTK_LAYER_SHELL_KEYBOARD_MODE_NONE) {
      gtk_window_set_focus(GTK_WINDOW(window.window), GTK_WIDGET(window.view));
    }
    success(call);
  }

  void watch_monitor(GdkMonitor* monitor) {
    g_signal_connect(monitor, "notify::geometry", G_CALLBACK(monitor_changed),
                     this);
    g_signal_connect(monitor, "notify::scale-factor",
                     G_CALLBACK(monitor_changed), this);
    g_signal_connect(monitor, "notify::refresh-rate",
                     G_CALLBACK(monitor_changed), this);
  }

  static void monitor_added(GdkDisplay*, GdkMonitor* monitor, gpointer data) {
    auto* self = static_cast<CaptureWindows*>(data);
    self->watch_monitor(monitor);
    self->emit("outputsChanged");
  }

  static void monitor_removed(GdkDisplay*, GdkMonitor* monitor, gpointer data) {
    auto* self = static_cast<CaptureWindows*>(data);
    g_signal_handlers_disconnect_by_data(monitor, self);
    self->emit("outputsChanged");
  }

  static void monitor_changed(GdkMonitor*, GParamSpec*, gpointer data) {
    static_cast<CaptureWindows*>(data)->emit("outputsChanged");
  }

  static void remember_pointer(GtkGestureMultiPress*, int, double, double,
                               gpointer data) {
    auto& window = *static_cast<Window*>(data);
    g_autoptr(GdkEvent) event = gtk_get_current_event();
    double x, y;
    if (event == nullptr || !gdk_event_get_root_coords(event, &x, &y)) return;
    window.drag_time = gdk_event_get_time(event);
    window.drag_x = static_cast<int>(x);
    window.drag_y = static_cast<int>(y);
  }

  static gboolean close_requested(GtkWidget*, GdkEvent*, gpointer data) {
    const auto& window = *static_cast<Window*>(data);
    window.host->emit("closeRequested", window.id);
    return TRUE;
  }

  static void window_destroyed(GtkWidget*, gpointer data) {
    const auto& window = *static_cast<Window*>(data);
    auto* self = window.host;
    const auto id = window.id;
    const bool active = window.active;
    self->windows_.erase(id);
    if (active) self->emit("closed", id);
  }

  void emit(const char* method, int64_t id = -1) {
    if (channel_ == nullptr) return;
    g_autoptr(FlValue) args = nullptr;
    if (id >= 0) {
      args = fl_value_new_map();
      fl_value_set_string_take(args, "id", fl_value_new_int(id));
    }
    fl_method_channel_invoke_method(channel_, method, args, nullptr, nullptr,
                                    nullptr);
  }

  GtkApplication* application_;
  GdkDisplay* display_;
  GtkWidget* bootstrap_ = nullptr;
  FlEngine* engine_ = nullptr;
  FlMethodChannel* channel_ = nullptr;
  std::map<int64_t, std::unique_ptr<Window>> windows_;
};

}  // namespace

void start_capture_windows(GtkApplication* application, char** arguments) {
  if (g_object_get_data(G_OBJECT(application), kHostKey) != nullptr) return;
  g_object_set_data_full(
      G_OBJECT(application), kHostKey,
      new CaptureWindows(application, arguments),
      [](gpointer data) { delete static_cast<CaptureWindows*>(data); });
}

void stop_capture_windows(GtkApplication* application) {
  g_object_set_data(G_OBJECT(application), kHostKey, nullptr);
}
