#ifndef RUNNER_FROZEN_BACKGROUND_H_
#define RUNNER_FROZEN_BACKGROUND_H_

#include <gtk/gtk.h>

#include <cstddef>
#include <cstdint>
#include <memory>

struct wl_buffer;
struct wl_compositor;
struct wl_shm;
struct wl_subcompositor;
struct wl_subsurface;
struct wl_surface;
struct wp_viewport;
struct wp_viewporter;

class FrozenBackground;

class FrozenBackgroundProtocol {
 public:
  explicit FrozenBackgroundProtocol(GdkDisplay* display);
  ~FrozenBackgroundProtocol();

  std::unique_ptr<FrozenBackground> decode(const uint8_t* png, size_t size);

 private:
  friend class FrozenBackground;
  wl_compositor* compositor_ = nullptr;  // Owned by GDK.
  wl_subcompositor* subcompositor_ = nullptr;
  wl_shm* shm_ = nullptr;
  wp_viewporter* viewporter_ = nullptr;
};

class FrozenBackground {
 public:
  FrozenBackground(const FrozenBackgroundProtocol& protocol, wl_buffer* buffer);
  ~FrozenBackground();

  void update(GtkWidget* window, bool visible);
  void unmap();

 private:
  const FrozenBackgroundProtocol& protocol_;
  wl_buffer* const buffer_;
  wl_surface* surface_ = nullptr;
  wl_subsurface* subsurface_ = nullptr;
  wp_viewport* viewport_ = nullptr;
  int width_ = 0;
  int height_ = 0;
  bool visible_ = false;
};

#endif  // RUNNER_FROZEN_BACKGROUND_H_
