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

**Hyprland screen capture tool for Linux.** The app currently opens an interactive preview of the shared capture controls. Screenshot, recording and editor workflows are pending.

## Tech Stack & Architecture

- **Flutter**: `3.47.9` pinned via FVM, with Material Design 3 Expressive (`material_ui: ^1.5.0`).
- **Rust**: `2024` edition, managed as a Cargo workspace with the root `rust-toolchain.toml`.
- **FFI selection**: `flutter_rust_bridge` `2.13.0`. Add bridge configuration and generated bindings when a concrete backend API is needed.
- **Settings integration**: Public `remya_settings_client` package, reserved for future integration.
- **Structure**:
  - `lib/main.dart` and `lib/app.dart`: Startup, theme and component preview entry point.
  - `lib/features/capture_controls/`: Reusable capture widgets and their interactive preview.
  - `lib/src/rust/core/`: Empty Rust core crate; no native library is built into the app yet.
  - `linux/`: Linux GTK runner and desktop packaging.
  - `assets/icons/`: Application icon.
  - `tool/install.py`: XDG installation helper.

## Development

### Prerequisites

- FVM with Flutter SDK `3.47.9`
- Rust toolchain managed by `rustup`
- Flutter Linux build dependencies
- Inter system font and fontconfig for installation (Arch: `sudo pacman -S inter-font fontconfig`)
- A sibling `../remya-settings` checkout providing `packages/remya_settings_client`

### Setup

```bash
fvm install
fvm flutter pub get
```

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
