<p align="center">
  <img src="../assets/icons/app_icon-full.svg" width="128" alt="Remy'a Screen Capture icon">
</p>

<h1 align="center">Remy'a Screen Capture</h1>

<h3 align="center">Инструмент для снимков экрана, записи видео и подбора цвета в Arch Linux Hyprland</h3>

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
  <strong>Русский</strong> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.ja.md">日本語</a>
</p>

Современный и элегантный интерфейс на базе **Material Design 3 Expressive**, сочетающий **ориентацию на клавиатуру** и **богатые встроенные инструменты редактирования** — от захвата до постобработки в одном потоке.

- **Ориентация на клавиатуру**: продуманная система горячих клавиш для быстрого рабочего процесса.
- **Эстетика MD3E**: интерфейс соответствует Material Design 3 Expressive, отличается плавной анимацией, чёткой визуальной иерархией и органично вписывается в окружение Hyprland.
- **Богатое встроенное редактирование**: полноценные редакторы аннотаций и видео, а также функциональная панель пипетки.

> [!WARNING]
> Программа находится на стадии **Beta** и может содержать ошибки или работать нестабильно. Функциональность продолжает дорабатываться.

## 🚀 Установка

### Установка через AUR

Установите `remya-screen-capture` с помощью вашего AUR-помощника:

```bash
paru -S remya-screen-capture || yay -S remya-screen-capture
```

### Горячие клавиши Hyprland

Добавьте привязки клавиш в конфигурацию Hyprland (укажите абсолютный путь к исполняемому файлу, если `~/.local/bin` отсутствует в `PATH` сессии):

```lua
-- Снимок экрана
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("remya_screen_capture"))

-- Запись экрана
hl.bind("SUPER + R", hl.dsp.exec_cmd("remya_screen_capture --record"))

-- Пипетка цвета
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("remya_screen_capture --color-picker"))
```

## ✨ Возможности

### Снимки экрана

| Снимок экрана | Редактор аннотаций |
|:---:|:---:|
| ![Оверлей и выделение области](images/demo-screenshot.png) | ![Снимок экрана и редактор аннотаций](images/demo-screenshot-editor.png) |

<p align="center">
  <img src="images/demo-screenshot-tools.png" alt="Панель инструментов редактора" width="100%">
</p>

- **Захват любых сценариев**: поддержка снимков окон, произвольных областей и автоматической вертикальной прокрутки (на базе протокола `zwlr_virtual_pointer_v1`).
- **Точное выделение**: выделение мышью и попиксельная доводка с клавиатуры.
- **Встроенный редактор**: богатый набор инструментов для рисования и аннотаций.

### Запись экрана

<p align="center">
  <img src="images/demo-video-editor.png" alt="Запись экрана и видеоредактор" width="100%">
</p>

- **Аннотации в реальном времени**: инструменты маркера и лазерной указки прямо во время записи.
- **Встроенный видеоредактор и экспорт**: покадровый предпросмотр и точная обрезка; экспорт в MP4, WebM, GIF или MKV со сведением дорожек системного звука и микрофона.

### Пипетка цвета

<p align="center">
  <img src="images/demo-color-picker.png" alt="Пипетка цвета и панель результатов" width="540">
</p>

- **Профессиональный анализ и правка цвета**: отображение множества цветовых форматов, контрастности и оттенков в реальном времени, настройка HSL и история выборок.

## ⌨️ Разработка

### Стек технологий и архитектура

- **Flutter**: версия `3.47.9` (зафиксирована через FVM) с Material Design 3 Expressive (`material_ui: ^1.5.0`).
- **Rust**: редакция `2024`, управляется как Cargo workspace с корневым `rust-toolchain.toml`.
- **FFI**: `flutter_rust_bridge` `2.13.0`. В сборку для Linux включена библиотека захвата на Rust.
- **Запись и видео**: системный GPU Screen Recorder для захвата, libmpv для предпросмотра и FFmpeg для экспорта.
- **Интеграция настроек**: публичный пакет `remya_settings_client`, зарезервированный для будущей интеграции.
- **Структура**:
  - `lib/main.dart` и `lib/app.dart`: запуск приложения и тема оформления.
  - `lib/features/`: интерфейс снимков экрана, редактор изображений и переиспользуемые элементы управления захватом.
  - `lib/src/rust/capture/`: команды захвата Wayland, обработка PNG и захват с автопрокруткой (с зависимостями `wayland-client` и `wayland-protocols-wlr`). Лицензии зависимостей Rust см. в уведомлениях о стороннем ПО.
  - `linux/`: Linux GTK-раннер и упаковка для рабочего стола.
  - `assets/icons/`: значок приложения.
  - `tool/install.py`: вспомогательный скрипт установки по стандарту XDG.

### Подготовка среды сборки

- FVM с Flutter SDK `3.47.9`
- Инструментарий Rust под управлением `rustup`
- Зависимости сборки Flutter для Linux
- Установка системных и сборочных зависимостей в Arch Linux:

```bash
sudo pacman -S grim wl-clipboard gtk-layer-shell wayland wayland-protocols inter-font fontconfig
# Зависимости для записи и редактирования видео
sudo pacman -S gpu-screen-recorder ffmpeg mpv libepoxy
```

- Соседняя копия репозитория `../remya-settings`, предоставляющая `packages/remya_settings_client`

```bash
fvm install
fvm flutter pub get
```

После изменения API Rust-моста перегенерируйте привязки с помощью `flutter_rust_bridge_codegen` 2.13.0 и выполните `fvm dart format lib/src/rust_bridge`.

### Проверка и локальная установка

```bash
# Форматирование, статический анализ и тесты Dart
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# Форматирование, линтер и тесты Rust
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Отладочная сборка для Linux
fvm flutter build linux --debug

# Релизная сборка и установка в локальные каталоги XDG
fvm flutter build linux --release
python3 tool/install.py
```

## 📜 Лицензия

Проект распространяется под лицензией [PolyForm Noncommercial License 1.0.0](../LICENSE).
