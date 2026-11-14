<p align="center">
  <img src="../assets/icons/app_icon-full.svg" width="128" alt="Remy'a Screen Capture icon">
</p>

<h1 align="center">Remy'a Screen Capture</h1>

<h3 align="center">適用於 Arch Linux Hyprland 的截圖、錄影與取色工具</h3>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20Hyprland-1793D1?logo=archlinux" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.47.9-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Rust-2024-dea584?logo=rust" alt="Rust">
  <img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue" alt="License">
</p>

<p align="center">
  <a href="../README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <strong>繁體中文</strong> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.ja.md">日本語</a>
</p>

以 **Material Design 3 Expressive** 打造的現代優雅介面，兼顧**鍵盤優先**的高效互動與**豐富的內建編輯能力**——從擷取到後製一氣呵成。

- **鍵盤優先體驗**：完備的快捷鍵支援，打造高效工作流程。
- **MD3E 優雅設計**：遵循 Material Design 3 Expressive 規範，具備細膩流暢的動效與清晰克制的視覺層次，原生融入 Hyprland 桌面美學。
- **豐富內建編輯**：完整涵蓋截圖標註、影片剪輯與取色器面板功能。

> [!WARNING]
> 本軟體目前處於 **Beta** 階段，可能存在錯誤與不穩定性，部分功能與行為仍在持續完善中。

## 🚀 安裝

### 透過 AUR 安裝

安裝 [Remya Core](https://github.com/remyhuang03/remya-core) `0.1.0` 以使用共用主題與偏好設定。AUR 提供原始碼套件 `remya-screen-capture` 和預先編譯的 `remya-screen-capture-bin`，兩者皆依賴 `remya-core`。

```bash
paru -S remya-screen-capture || yay -S remya-screen-capture
```

### 從發行封存檔安裝

手動安裝時，請先安裝 Core，再從 [GitHub Releases](https://github.com/remyhuang03/remya-screen-capture/releases) 下載 x86_64 封存檔與 `SHA256SUMS`。

```bash
sha256sum -c SHA256SUMS
tar --zstd -xf remya_screen_capture-0.2.0-linux-x86_64.tar.zst
cd remya_screen_capture-0.2.0-linux-x86_64
python tool/install.py
```

### Hyprland 快捷鍵設定

將快捷鍵綁定新增至 Hyprland 設定中（若 `~/.local/bin` 不在工作階段的 `PATH` 中，請填寫執行檔的絕對路徑），以下為設定範例：

```lua
-- 螢幕截圖
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("remya_screen_capture"))

-- 螢幕錄製
hl.bind("SUPER + R", hl.dsp.exec_cmd("remya_screen_capture --record"))

-- 取色器
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("remya_screen_capture --color-picker"))
```

## ✨ 功能一覽

### 螢幕截圖

| 螢幕截圖                                          | 標註編輯器                                                 |
|:-------------------------------------------------:|:----------------------------------------------------------:|
| ![螢幕截圖遮罩與選區](images/demo-screenshot.png) | ![螢幕截圖與標註編輯器](images/demo-screenshot-editor.png) |

<p align="center">
  <img src="images/demo-screenshot-tools.png" alt="標註編輯工具列" width="100%">
</p>

- **全場景擷取**：支援視窗截圖、自訂區域截圖以及自動垂直捲動長截圖（基於 `zwlr_virtual_pointer_v1` 協定自動捲動並拼接）。
- **精細化選區**：支援滑鼠拖曳與鍵盤像素級微調。
- **內建編輯器**：提供豐富的繪圖與標註工具。

### 螢幕錄製

<p align="center">
  <img src="images/demo-video-editor.png" alt="螢幕錄製與影片編輯器" width="100%">
</p>

- **錄製中即時標註**：支援錄影過程中使用畫筆與雷射筆工具。
- **內建影片剪輯與多格式匯出**：支援逐格步進預覽與精確區間裁剪；支援匯出為 MP4、WebM、GIF 或 MKV，並可將獨立的系統音訊與麥克風音軌混合輸出。

### 取色器

<p align="center">
  <img src="images/demo-color-picker.png" alt="取色器與結果面板" width="540">
</p>

- **專業色彩分析與編輯**：即時顯示多種色彩格式、對比度與色階，支援 HSL 色彩微調與歷史紀錄回溯。

## ⌨️ 開發指南

### 技術堆疊與架構

- **Flutter**：透過 FVM 鎖定為 `3.47.9`，採用 Material Design 3 Expressive（`material_ui: ^1.5.0`）。
- **Rust**：`2024` edition，透過根目錄 `rust-toolchain.toml` 以 Cargo workspace 管理。
- **FFI**：`flutter_rust_bridge` `2.13.0`，Linux 建置會打包 Rust 截圖函式庫。
- **錄影與影片**：使用系統 GPU Screen Recorder 擷取畫面，libmpv 進行預覽，FFmpeg 負責匯出。
- 共用主題、錄影與取色偏好透過 Remya Core 的 `remya_client` 和 `remya_ui` 提供。執行 `remya_screen_capture --settings` 開啟設定視窗。
- **目錄結構**：
  - `lib/main.dart` 與 `lib/app.dart`：應用程式啟動與主題設定。
  - `lib/features/`：截圖 UI、影像編輯器及可重複使用的擷取控制項。
  - `lib/src/rust/capture/`：Wayland 擷取命令、PNG 處理與自動捲動擷取（新增 `wayland-client` 與 `wayland-protocols-wlr` 相依套件）。Rust 相依套件授權請參閱其中的第三方聲明。
  - `linux/`：Linux GTK 執行器與桌面打包設定。
  - `assets/icons/`：應用程式圖示。
  - `tool/install.py`：XDG 安裝輔助腳本。

### 建置環境準備

- 安裝有 Flutter SDK `3.47.9` 的 FVM
- 透過 `rustup` 管理的 Rust 工具鏈
- Flutter Linux 建置相依套件
- 在 Arch Linux 上安裝執行與原生建置相依套件：

```bash
sudo pacman -S grim wl-clipboard gtk-layer-shell wayland wayland-protocols inter-font fontconfig
# 錄影與影片編輯相依套件
sudo pacman -S gpu-screen-recorder ffmpeg mpv libepoxy
```

- 這個版本需要同層的 `../remya-core` 儲存庫切換至 `v0.1.0`，以提供 `packages/remya_client` 和 `packages/remya_ui`。

```bash
fvm install
fvm flutter pub get
```

修改 Rust 橋接 API 後，請使用 `flutter_rust_bridge_codegen` 2.13.0 重新產生繫結，並執行 `fvm dart format lib/src/rust_bridge`。

### 驗證與本地安裝

```bash
# Dart 格式化、靜態分析與測試
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# Rust 格式化、Lint 與測試
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Linux 應用程式除錯建置
fvm flutter build linux --debug

# 發行建置並安裝至本地 XDG 目錄
fvm flutter build linux --release
python3 tool/install.py
```

## 📜 授權條款

本專案採用 [PolyForm Noncommercial License 1.0.0](../LICENSE) 授權。
