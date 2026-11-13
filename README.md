<p align="center">
  <img src="assets/icons/screen_capture.svg" width="128" alt="Remy'a Screen Capture icon">
</p>

<h1 align="center">Remy'a Screen Capture</h1>

<h3 align="center">Screenshot, screen recording, and color picker tool for Arch Linux Hyprland</h3>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20Hyprland-1793D1?logo=archlinux" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.47.9-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Rust-2024-dea584?logo=rust" alt="Rust">
  <img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue" alt="License">
</p>

<p align="center">
  <strong>English</strong> ·
  <a href="docs/README.zh-CN.md">简体中文</a> ·
  <a href="docs/README.zh-TW.md">繁體中文</a> ·
  <a href="docs/README.ru.md">Русский</a> ·
  <a href="docs/README.de.md">Deutsch</a> ·
  <a href="docs/README.es.md">Español</a> ·
  <a href="docs/README.ja.md">日本語</a>
</p>

A modern, refined interface built with **Material Design 3 Expressive**, combining **keyboard-centric** efficiency with **rich built-in editing**—from capture to post-processing in one seamless flow.

- **Keyboard-centric experience**: Comprehensive keyboard shortcuts for a fast, streamlined workflow.
- **Refined MD3E design**: Follows Material Design 3 Expressive guidelines with smooth animations and clean visual hierarchy, fitting naturally into the Hyprland desktop aesthetic.
- **Rich built-in editing**: Full-featured screenshot annotation, video trimming, and color picker panels.

> [!WARNING]
> This software is currently in **Beta** and may contain bugs or instability. Features and behavior are still being refined.

## 🚀 Installation

### Install via AUR

Install `remya-screen-capture` using your preferred AUR helper:

```bash
paru -S remya-screen-capture || yay -S remya-screen-capture
```

### Hyprland Keybindings

Add these keybindings to your Hyprland configuration (use the executable's absolute path if `~/.local/bin` is outside your session's `PATH`):

```lua
-- Screenshot
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("remya_screen_capture"))

-- Screen recording
hl.bind("SUPER + R", hl.dsp.exec_cmd("remya_screen_capture --record"))

-- Color picker
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("remya_screen_capture --color-picker"))
```

## ✨ Features

### Screenshots

| Screenshot | Annotation Editor |
|:---:|:---:|
| ![Screenshot overlay and selection](docs/images/demo-screenshot.png) | ![Screenshot and annotation editor](docs/images/demo-screenshot-editor.png) |

<p align="center">
  <img src="docs/images/demo-screenshot-tools.png" alt="Annotation editor toolbar" width="100%">
</p>

- **Full-scenario capture**: Supports window capture, custom region selection, and automatic vertical scrolling capture (powered by `zwlr_virtual_pointer_v1` auto-scrolling and stitching).
- **Precision selection**: Mouse drag and keyboard pixel-level adjustments.
- **Built-in editor**: Rich drawing and annotation tools.

### Screen Recording

<p align="center">
  <img src="docs/images/demo-video-editor.png" alt="Screen recording and video editor" width="100%">
</p>

- **Live annotations while recording**: Supports marker and laser pointer tools during recording.
- **Built-in video trimming and multi-format export**: Frame-by-frame preview and exact trim range selection; export to MP4, WebM, GIF, or MKV with mixed system audio and microphone tracks.

### Color Picker

<p align="center">
  <img src="docs/images/demo-color-picker.png" alt="Color picker and result panel" width="540">
</p>

- **Professional color analysis and editing**: Displays multiple color formats, contrast, and shades in real time, with HSL adjustments and sampling history.

## ⌨️ Development

### Tech Stack & Architecture

- **Flutter**: `3.47.9` pinned via FVM, with Material Design 3 Expressive (`material_ui: ^1.5.0`).
- **Rust**: `2024` edition, managed as a Cargo workspace with the root `rust-toolchain.toml`.
- **FFI**: `flutter_rust_bridge` `2.13.0`. The Linux build bundles the Rust screenshot library.
- **Recording and video**: System GPU Screen Recorder for capture, libmpv for preview, and FFmpeg for export.
- **Settings integration**: Public `remya_settings_client` package, reserved for future integration.
- **Structure**:
  - `lib/main.dart` and `lib/app.dart`: Startup and theme.
  - `lib/features/`: Screenshot UI, image editor, and reusable capture controls.
  - `lib/src/rust/capture/`: Wayland capture commands, PNG processing, and auto-scroll capture (using `wayland-client` and `wayland-protocols-wlr`). See its third-party notices for Rust dependency licenses.
  - `linux/`: Linux GTK runner and desktop packaging.
  - `assets/icons/`: Application icon.
  - `tool/install.py`: XDG installation helper.

### Prerequisites & Setup

- FVM with Flutter SDK `3.47.9`
- Rust toolchain managed by `rustup`
- Flutter Linux build dependencies
- Install runtime and native build dependencies on Arch Linux:

```bash
sudo pacman -S grim wl-clipboard gtk-layer-shell wayland wayland-protocols inter-font fontconfig
# Recording and video editing dependencies
sudo pacman -S gpu-screen-recorder ffmpeg mpv libepoxy
```

- A sibling `../remya-settings` checkout providing `packages/remya_settings_client`

```bash
fvm install
fvm flutter pub get
```

After changing the Rust bridge API, regenerate it with `flutter_rust_bridge_codegen` 2.13.0 and run `fvm dart format lib/src/rust_bridge`.

### Validation & Local Installation

```bash
# Dart formatting, analysis, and tests
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# Rust formatting, lints, and tests
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Linux debug build
fvm flutter build linux --debug

# Release build and install to local XDG directories
fvm flutter build linux --release
python3 tool/install.py
```

## 📜 License

This project is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).
