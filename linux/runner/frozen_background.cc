#include "frozen_background.h"

#include <gdk/gdkwayland.h>
#include <gtk-layer-shell.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

#include <cstring>

#include "viewporter-client-protocol.h"

FrozenBackgroundProtocol::FrozenBackgroundProtocol(GdkDisplay* display) {
  if (!GDK_IS_WAYLAND_DISPLAY(display)) return;
  compositor_ = gdk_wayland_display_get_wl_compositor(display);
  auto* wayland = gdk_wayland_display_get_wl_display(display);
  auto* queue = wl_display_create_queue(wayland);
  if (queue == nullptr) return;
  auto* wrapper = wl_proxy_create_wrapper(wayland);
  if (wrapper == nullptr) {
    wl_event_queue_destroy(queue);
    return;
  }
  // Bind on a private queue so the synchronous query cannot reenter GTK.
  wl_proxy_set_queue(static_cast<wl_proxy*>(wrapper), queue);
  auto* registry = wl_display_get_registry(static_cast<wl_display*>(wrapper));
  wl_proxy_wrapper_destroy(wrapper);
  const wl_registry_listener listener = {
      [](void* data, wl_registry* registry, uint32_t name,
         const char* interface, uint32_t) {
        auto& protocol = *static_cast<FrozenBackgroundProtocol*>(data);
        if (g_str_equal(interface, wl_subcompositor_interface.name)) {
          protocol.subcompositor_ = static_cast<wl_subcompositor*>(
              wl_registry_bind(registry, name, &wl_subcompositor_interface, 1));
        } else if (g_str_equal(interface, wl_shm_interface.name)) {
          protocol.shm_ = static_cast<wl_shm*>(
              wl_registry_bind(registry, name, &wl_shm_interface, 1));
        } else if (g_str_equal(interface, wp_viewporter_interface.name)) {
          protocol.viewporter_ = static_cast<wp_viewporter*>(
              wl_registry_bind(registry, name, &wp_viewporter_interface, 1));
        }
      },
      [](void*, wl_registry*, uint32_t) {},
  };
  wl_registry_add_listener(registry, &listener, this);
  wl_display_roundtrip_queue(wayland, queue);
  wl_registry_destroy(registry);
  if (subcompositor_)
    wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(subcompositor_), nullptr);
  if (shm_) wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(shm_), nullptr);
  if (viewporter_)
    wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(viewporter_), nullptr);
  wl_event_queue_destroy(queue);
}

FrozenBackgroundProtocol::~FrozenBackgroundProtocol() {
  if (viewporter_) wp_viewporter_destroy(viewporter_);
  if (shm_) wl_shm_destroy(shm_);
  if (subcompositor_) wl_subcompositor_destroy(subcompositor_);
}

std::unique_ptr<FrozenBackground> FrozenBackgroundProtocol::decode(
    const uint8_t* png, size_t size) {
  if (!compositor_ || !subcompositor_ || !shm_ || !viewporter_) return nullptr;
  struct Png {
    const uint8_t* bytes;
    size_t remaining;
  } reader{png, size};
  const auto read = [](void* data, unsigned char* target, unsigned int length) {
    auto& reader = *static_cast<Png*>(data);
    if (length > reader.remaining) return CAIRO_STATUS_READ_ERROR;
    std::memcpy(target, reader.bytes, length);
    reader.bytes += length;
    reader.remaining -= length;
    return CAIRO_STATUS_SUCCESS;
  };
  std::unique_ptr<cairo_surface_t, decltype(&cairo_surface_destroy)> image(
      cairo_image_surface_create_from_png_stream(read, &reader),
      cairo_surface_destroy);
  if (cairo_surface_status(image.get()) != CAIRO_STATUS_SUCCESS) return nullptr;
  const auto format = cairo_image_surface_get_format(image.get());
  if (format != CAIRO_FORMAT_RGB24 && format != CAIRO_FORMAT_ARGB32)
    return nullptr;
  const int width = cairo_image_surface_get_width(image.get());
  const int height = cairo_image_surface_get_height(image.get());
  const int stride = cairo_image_surface_get_stride(image.get());
  if (width <= 0 || height <= 0 || stride <= 0 || height > INT32_MAX / stride) {
    return nullptr;
  }

  const int length = stride * height;
  const int fd = memfd_create("remya-frozen-preview", MFD_CLOEXEC);
  if (fd < 0) return nullptr;
  void* pixels = ftruncate(fd, length) == 0
                     ? mmap(nullptr, length, PROT_WRITE, MAP_SHARED, fd, 0)
                     : MAP_FAILED;
  if (pixels == MAP_FAILED) {
    close(fd);
    return nullptr;
  }
  std::memcpy(pixels, cairo_image_surface_get_data(image.get()), length);
  munmap(pixels, length);
  auto* pool = wl_shm_create_pool(shm_, fd, length);
  close(fd);
  if (pool == nullptr) return nullptr;
  auto* buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride,
                                           format == CAIRO_FORMAT_ARGB32
                                               ? WL_SHM_FORMAT_ARGB8888
                                               : WL_SHM_FORMAT_XRGB8888);
  wl_shm_pool_destroy(pool);
  return buffer ? std::make_unique<FrozenBackground>(*this, buffer) : nullptr;
}

FrozenBackground::FrozenBackground(const FrozenBackgroundProtocol& protocol,
                                   wl_buffer* buffer)
    : protocol_(protocol), buffer_(buffer) {}

FrozenBackground::~FrozenBackground() {
  unmap();
  wl_buffer_destroy(buffer_);
}

void FrozenBackground::update(GtkWidget* window, bool visible) {
  if (!gtk_widget_get_mapped(window)) return;
  if (visible == visible_) return;
  if (surface_ == nullptr) {
    auto* parent =
        gdk_wayland_window_get_wl_surface(gtk_widget_get_window(window));
    auto* monitor = gtk_layer_get_monitor(GTK_WINDOW(window));
    if (parent == nullptr || monitor == nullptr) return;
    GdkRectangle bounds{};
    gdk_monitor_get_geometry(monitor, &bounds);
    if (bounds.width <= 0 || bounds.height <= 0) return;
    surface_ = wl_compositor_create_surface(protocol_.compositor_);
    subsurface_ = wl_subcompositor_get_subsurface(protocol_.subcompositor_,
                                                  surface_, parent);
    // GTK/EGL draws the Flutter controls on the transparent parent surface.
    wl_subsurface_place_below(subsurface_, parent);
    auto* region = wl_compositor_create_region(protocol_.compositor_);
    wl_surface_set_input_region(surface_, region);
    wl_region_destroy(region);
    viewport_ = wp_viewporter_get_viewport(protocol_.viewporter_, surface_);
    // Use the output's logical bounds from the first commit, before GTK
    // resizes.
    wp_viewport_set_destination(viewport_, bounds.width, bounds.height);
    width_ = bounds.width;
    height_ = bounds.height;
  }
  wl_surface_attach(surface_, visible ? buffer_ : nullptr, 0, 0);
  if (visible) wl_surface_damage(surface_, 0, 0, width_, height_);
  visible_ = visible;
  wl_surface_commit(surface_);
  gtk_widget_queue_draw(window);
}

void FrozenBackground::unmap() {
  if (surface_ == nullptr) return;
  wp_viewport_destroy(viewport_);
  wl_subsurface_destroy(subsurface_);
  wl_surface_destroy(surface_);
  surface_ = nullptr;
  subsurface_ = nullptr;
  viewport_ = nullptr;
  visible_ = false;
}
