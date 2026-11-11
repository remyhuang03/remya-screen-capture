<p align="center">
  <img src="assets/icons/screen_capture.svg" width="128" alt="Remy'a Screen Capture icon">
</p>

<h1 align="center">Remy'a Screen Capture</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20Hyprland-1793D1?logo=archlinux" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.47.9-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Rust-2024-dea584?logo=rust" alt="Rust">
  <img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue" alt="License">
</p>

**Hyprland screen capture and annotation tool for Linux.** Capture a display, an individual window, a region, or a vertically scrolling area. Copy and save a PNG, or open the capture in the editor to annotate and crop it.

## Screenshots

- Run `remya_screen_capture` or open **Remy'a Screen Capture** from the application menu. Use **Tab** to switch between Region and Window. Click in Region mode to capture that display, or drag to select an area on the starting display. Use the selection handles and arrow keys to refine the crop.
- Use the left mouse button to copy and save to `Screenshots` in your XDG Pictures directory. Use the right mouse button to open the editor. The copied notification also offers **Edit**.
- For a scrolling screenshot, draw a region, choose **Scrolling**, and scroll the underlying app downward in small steps. Select **Done** when the preview shows the content you want.
- In the editor, **Ctrl+C** copies the edited PNG, **Ctrl+S** saves it, and **Ctrl+Shift+S** chooses a destination. Open **Shortcuts** for drawing and navigation keys.

To use Super+Shift+S, add this binding to your Hyprland configuration. Use the installed executable's absolute path if `~/.local/bin` is outside the session's `PATH`.

```lua
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("remya_screen_capture"))
```

## Tech Stack & Architecture

- **Flutter**: `3.47.9` pinned via FVM, with Material Design 3 Expressive (`material_ui: ^1.5.0`).
- **Rust**: `2024` edition, managed as a Cargo workspace with the root `rust-toolchain.toml`.
- **FFI**: `flutter_rust_bridge` `2.13.0`. The Linux build bundles the Rust screenshot library.
- **Settings integration**: Public `remya_settings_client` package, reserved for future integration.
- **Structure**:
  - `lib/main.dart` and `lib/app.dart`: Startup and theme.
  - `lib/features/`: Screenshot UI, image editor, and reusable capture controls.
  - `lib/src/rust/capture/`: Wayland capture commands, PNG processing, and scroll stitching. See its third-party notices for the Shotori code and Rust dependency licenses.
  - `linux/`: Linux GTK runner and desktop packaging.
  - `assets/icons/`: Application icon.
  - `tool/install.py`: XDG installation helper.

## Development

### Prerequisites

- FVM with Flutter SDK `3.47.9`
- Rust toolchain managed by `rustup`
- Flutter Linux build dependencies
- Hyprland Wayland session with `grim` 1.5.0 or newer and support for foreign-toplevel image capture. The target is Hyprland 0.57.2.
- On Arch, install the capture and native build dependencies with `sudo pacman -S grim wl-clipboard gtk-layer-shell wayland wayland-protocols`.
- Inter system font and fontconfig for installation (Arch: `sudo pacman -S inter-font fontconfig`)
- A sibling `../remya-settings` checkout providing `packages/remya_settings_client`

### Setup

```bash
fvm install
fvm flutter pub get
```

After changing the Rust bridge API, regenerate it with `flutter_rust_bridge_codegen` 2.13.0 and run `fvm dart format lib/src/rust_bridge`.

### Validation

```bash
# Dart formatting, analysis, and tests
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# Rust formatting, lints, and tests
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Linux application build
fvm flutter build linux --debug
```

### Installation

```bash
fvm flutter build linux --release
python3 tool/install.py
```

---

## License

This project is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).
