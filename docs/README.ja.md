<p align="center">
  <img src="../assets/icons/screen_capture.svg" width="128" alt="Remy'a Screen Capture icon">
</p>

<h1 align="center">Remy'a Screen Capture</h1>

<h3 align="center">Arch Linux Hyprland 向けのスクリーンショット・録画・カラーピッカーツール</h3>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20Hyprland-1793D1?logo=archlinux" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.47.9-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Rust-2024-dea584?logo=rust" alt="Rust">
  <img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue" alt="License">
</p>

<p align="center">
  <a href="../README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <strong>日本語</strong>
</p>

**Material Design 3 Expressive** で構築されたモダンで洗練された UI に、**キーボード中心（Keyboard-centric）**の高速な操作性と**豊富な内蔵編集機能**を融合し、キャプチャから仕上げまでをシームレスにつなぎます。

- **キーボード中心の操作性**：充実したショートカットにより、効率的なワークフローを実現します。
- **洗練された MD3E デザイン**：Material Design 3 Expressive に準拠した滑らかなアニメーションと明快な視覚階層が、Hyprland デスクトップに自然に溶け込みます。
- **豊富な内蔵編集機能**：スクリーンショットの注釈、動画のトリミング、高機能なカラーピッカーパネルを備えています。

> [!WARNING]
> 本ソフトウェアは現在 **Beta** 段階にあり、不具合や不安定な挙動が含まれる可能性があります。機能や仕様は継続的に改善中です。

## 🚀 インストール

### AUR からインストール

お好みの AUR ヘルパーで `remya-screen-capture` をインストールします：

```bash
paru -S remya-screen-capture || yay -S remya-screen-capture
```

### Hyprland ショートカット設定

以下のキーバインドを Hyprland 設定に追加してください（`~/.local/bin` がセッションの `PATH` に含まれない場合は、実行ファイルの絶対パスを指定してください）：

```lua
-- スクリーンショット
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("remya_screen_capture"))

-- 画面録画
hl.bind("SUPER + R", hl.dsp.exec_cmd("remya_screen_capture --record"))

-- カラーピッカー
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("remya_screen_capture --color-picker"))
```

## ✨ 機能一覧

### スクリーンショット

| スクリーンショット | 注釈エディタ |
|:---:|:---:|
| ![スクリーンショットのオーバーレイと選択](images/demo-screenshot.png) | ![スクリーンショットと注釈エディタ](images/demo-screenshot-editor.png) |

<p align="center">
  <img src="images/demo-screenshot-tools.png" alt="注釈編集ツールバー" width="100%">
</p>

- **あらゆる撮影シーンに対応**：ウィンドウ撮影、カスタム領域選択、および `zwlr_virtual_pointer_v1` プロトコルによる自動縦スクロール撮影に対応。
- **精密な範囲選択**：マウスドラッグとキーボードによるピクセル単位の微調整が可能。
- **内蔵エディタ**：豊富な描画・注釈ツールを搭載。

### 画面録画

<p align="center">
  <img src="images/demo-video-editor.png" alt="画面録画と動画エディタ" width="100%">
</p>

- **録画中のリアルタイム注釈**：録画しながらマーカーやレーザーポインターで描画可能。
- **内蔵動画トリミング＆マルチフォーマット書き出し**：コマ送りプレビューと正確な区間トリミングに対応し、システム音声とマイク音声をミックスして MP4 / WebM / GIF / MKV へ書き出せます。

### カラーピッカー

<p align="center">
  <img src="images/demo-color-picker.png" alt="カラーピッカーと結果パネル" width="540">
</p>

- **高度なカラー解析と編集**：複数のカラー形式・コントラスト・シェードをリアルタイム表示し、HSL 微調整や取得履歴の参照に対応。

## ⌨️ 開発ガイド

### 技術スタックとアーキテクチャ

- **Flutter**：FVM により `3.47.9` に固定、Material Design 3 Expressive（`material_ui: ^1.5.0`）を採用。
- **Rust**：`2024` エディション、ルートの `rust-toolchain.toml` とともに Cargo workspace として管理。
- **FFI**：`flutter_rust_bridge` `2.13.0`。Linux ビルドには Rust 製スクリーンショットライブラリを同梱。
- **録画と動画**：キャプチャにシステムの GPU Screen Recorder、プレビューに libmpv、書き出しに FFmpeg を使用。
- **設定連携**：公開パッケージ `remya_settings_client`（将来の連携向けに予約）。
- **構成**：
  - `lib/main.dart` / `lib/app.dart`: 起動処理とテーマ。
  - `lib/features/`: スクリーンショット UI、画像エディタ、再利用可能なキャプチャコントロール。
  - `lib/src/rust/capture/`: Wayland キャプチャコマンド、PNG 処理、自動スクロールキャプチャ（`wayland-client` および `wayland-protocols-wlr` を使用）。Rust 依存ライブラリのライセンスはサードパーティ表記を参照してください。
  - `linux/`: Linux GTK ランナーおよびデスクトップパッケージング。
  - `assets/icons/`: アプリアイコン。
  - `tool/install.py`: XDG インストール補助スクリプト。

### ビルド環境の準備

- Flutter SDK `3.47.9` が入った FVM
- `rustup` で管理された Rust ツールチェイン
- Flutter Linux ビルド依存パッケージ
- Arch Linux で実行およびネイティブビルド依存パッケージをインストール：

```bash
sudo pacman -S grim wl-clipboard gtk-layer-shell wayland wayland-protocols inter-font fontconfig
# 録画・動画編集用の依存パッケージ
sudo pacman -S gpu-screen-recorder ffmpeg mpv libepoxy
```

- `packages/remya_settings_client` を提供する隣接チェックアウト `../remya-settings`

```bash
fvm install
fvm flutter pub get
```

Rust ブリッジ API を変更した後は、`flutter_rust_bridge_codegen` 2.13.0 でバインディングを再生成し、`fvm dart format lib/src/rust_bridge` を実行してください。

### 検証とローカルインストール

```bash
# Dart フォーマット、解析、テスト
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# Rust フォーマット、リント、テスト
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Linux デバッグビルド
fvm flutter build linux --debug

# リリースビルドとローカル XDG ディレクトリへのインストール
fvm flutter build linux --release
python3 tool/install.py
```

## 📜 ライセンス

本プロジェクトは [PolyForm Noncommercial License 1.0.0](../LICENSE) の下でライセンスされています。
