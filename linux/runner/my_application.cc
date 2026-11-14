#include "my_application.h"

#include <clocale>

#include "capture_plugins.h"

#include "capture_windows.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// The undecorated settings window's last primary press, for moving it.
struct SettingsWindow {
  GtkWindow* window;
  guint32 press_time = GDK_CURRENT_TIME;
  int press_x = 0;
  int press_y = 0;
};

static void settings_pressed(GtkGestureMultiPress*, int, double, double,
                             gpointer data) {
  auto* settings = static_cast<SettingsWindow*>(data);
  g_autoptr(GdkEvent) event = gtk_get_current_event();
  double x, y;
  if (event == nullptr || !gdk_event_get_root_coords(event, &x, &y)) return;
  settings->press_time = gdk_event_get_time(event);
  settings->press_x = static_cast<int>(x);
  settings->press_y = static_cast<int>(y);
}

static gboolean settings_close(gpointer window) {
  gtk_window_close(GTK_WINDOW(window));
  return G_SOURCE_REMOVE;
}

static void settings_method_call(FlMethodChannel*, FlMethodCall* call,
                                 gpointer data) {
  auto* settings = static_cast<SettingsWindow*>(data);
  const char* method = fl_method_call_get_name(call);
  if (g_str_equal(method, "beginMove")) {
    if (settings->press_time != GDK_CURRENT_TIME) {
      gtk_window_begin_move_drag(settings->window, 1, settings->press_x,
                                 settings->press_y, settings->press_time);
      settings->press_time = GDK_CURRENT_TIME;
    }
  } else if (g_str_equal(method, "close")) {
    // Close after replying; closing destroys the engine handling this call.
    g_idle_add_full(G_PRIORITY_DEFAULT, settings_close,
                    g_object_ref(settings->window), g_object_unref);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

// Lets RemyaTitleBar move and close the settings window.
static void attach_settings_channel(GtkWindow* window, FlView* view) {
  auto* settings = new SettingsWindow{window};
  g_object_set_data_full(G_OBJECT(window), "settings-window", settings,
                         [](gpointer data) {
                           delete static_cast<SettingsWindow*>(data);
                         });
  auto* gesture = gtk_gesture_multi_press_new(GTK_WIDGET(window));
  g_object_set_data_full(G_OBJECT(window), "move-gesture", gesture,
                         g_object_unref);
  gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(gesture),
                                             GTK_PHASE_CAPTURE);
  gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(gesture), 1);
  g_signal_connect(gesture, "pressed", G_CALLBACK(settings_pressed), settings);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      APPLICATION_ID "/settings", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, settings_method_call,
                                            settings, nullptr);
  g_object_set_data_full(G_OBJECT(window), "settings-channel", channel,
                         g_object_unref);
}

static void my_application_activate(GApplication* application) {
  auto* self = MY_APPLICATION(application);
  // GTK sets the process locale at startup. libmpv requires C numeric parsing.
  std::setlocale(LC_NUMERIC, "C");
  if (self->dart_entrypoint_arguments != nullptr &&
      g_strv_contains(self->dart_entrypoint_arguments, "--settings")) {
    g_autoptr(FlDartProject) project = fl_dart_project_new();
    fl_dart_project_set_dart_entrypoint_arguments(
        project, self->dart_entrypoint_arguments);
    auto* window = gtk_application_window_new(GTK_APPLICATION(application));
    gtk_window_set_title(GTK_WINDOW(window), "Remya Screen Capture Settings");
    gtk_window_set_default_size(GTK_WINDOW(window), 1280, 720);
    // RemyaTitleBar replaces the GTK decorations.
    gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
    auto* view = fl_view_new(project);
    register_capture_plugins(FL_PLUGIN_REGISTRY(view));
    gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
    attach_settings_channel(GTK_WINDOW(window), view);
    gtk_widget_show_all(window);
    return;
  }
  start_capture_windows(GTK_APPLICATION(application),
                        self->dart_entrypoint_arguments);
}

static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  auto* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;
  return TRUE;
}

static void my_application_shutdown(GApplication* application) {
  stop_capture_windows(GTK_APPLICATION(application));
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  auto* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
