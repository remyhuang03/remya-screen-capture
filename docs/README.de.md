<p align="center">
  <img src="../assets/icons/app_icon-full.svg" width="128" alt="Remy'a Screen Capture icon">
</p>

<h1 align="center">Remy'a Screen Capture</h1>

<h3 align="center">Screenshot-, Bildschirmaufnahme- und Farbwähler-Werkzeug für Arch Linux Hyprland</h3>

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
  <strong>Deutsch</strong> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.ja.md">日本語</a>
</p>

Eine moderne, elegante Oberfläche auf Basis von **Material Design 3 Expressive**, die **tastaturzentrierte** Effizienz mit **umfangreichen integrierten Bearbeitungsfunktionen** verbindet – von der Aufnahme bis zur Nachbearbeitung aus einem Guss.

- **Tastaturzentriertes Arbeiten**: Durchdachte Tastenkürzel für einen schnellen, flüssigen Arbeitsablauf.
- **Elegantes MD3E-Design**: Gestaltet nach Material Design 3 Expressive mit geschmeidigen Animationen und klarer visueller Hierarchie, passend zur Hyprland-Ästhetik.
- **Umfangreiche integrierte Bearbeitung**: Vollständige Funktionen für Screenshot-Anmerkungen, Videoschnitt und das Farbwähler-Panel.

> [!WARNING]
> Diese Software befindet sich derzeit in der **Beta-Phase** und kann Fehler oder Instabilitäten aufweisen. Funktionen und Verhalten werden laufend weiterentwickelt.

## 🚀 Installation

### Installation über das AUR

Installieren Sie `remya-screen-capture` mit Ihrem bevorzugten AUR-Helfer:

```bash
paru -S remya-screen-capture || yay -S remya-screen-capture
```

### Hyprland-Tastenkürzel

Fügen Sie diese Tastenkombinationen Ihrer Hyprland-Konfiguration hinzu (verwenden Sie den absoluten Pfad zur ausführbaren Datei, falls `~/.local/bin` nicht im `PATH` der Sitzung liegt):

```lua
-- Bildschirmfoto
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("remya_screen_capture"))

-- Bildschirmaufnahme
hl.bind("SUPER + R", hl.dsp.exec_cmd("remya_screen_capture --record"))

-- Farbwähler
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("remya_screen_capture --color-picker"))
```

## ✨ Funktionen

### Bildschirmfotos

| Bildschirmfoto | Anmerkungseditor |
|:---:|:---:|
| ![Screenshot-Overlay und Auswahl](images/demo-screenshot.png) | ![Screenshot und Anmerkungseditor](images/demo-screenshot-editor.png) |

<p align="center">
  <img src="images/demo-screenshot-tools.png" alt="Werkzeugleiste des Editors" width="100%">
</p>

- **Aufnahme für jedes Szenario**: Unterstützt Fensteraufnahmen, benutzerdefinierte Bereiche sowie automatische vertikale Scroll-Screenshots (per `zwlr_virtual_pointer_v1`-Protokoll).
- **Präzise Auswahl**: Bereichsauswahl per Maus und pixelgenaue Feinjustierung per Tastatur.
- **Integrierter Editor**: Umfangreiche Zeichen- und Anmerkungswerkzeuge.

### Bildschirmaufnahme

<p align="center">
  <img src="images/demo-video-editor.png" alt="Bildschirmaufnahme und Videoeditor" width="100%">
</p>

- **Live-Anmerkungen während der Aufnahme**: Unterstützt Markierstift und Laserpointer direkt während der Aufzeichnung.
- **Integrierter Videoschnitt & Multi-Format-Export**: Bildgenaue Vorschau und exaktes Zuschneiden; Export nach MP4, WebM, GIF oder MKV inklusive Abmischung getrennter System- und Mikrofonspuren.

### Farbwähler

<p align="center">
  <img src="images/demo-color-picker.png" alt="Farbwähler und Ergebnispanel" width="540">
</p>

- **Professionelle Farbanalyse & -bearbeitung**: Echtzeitanzeige verschiedener Farbformate, Kontrastwerte und Abstufungen mit HSL-Anpassung und Verlauf.

## ⌨️ Entwicklung

### Technologie-Stack & Architektur

- **Flutter**: `3.47.9` via FVM fixiert, mit Material Design 3 Expressive (`material_ui: ^1.5.0`).
- **Rust**: Edition `2024`, verwaltet als Cargo-Workspace über `rust-toolchain.toml`.
- **FFI**: `flutter_rust_bridge` `2.13.0`. Der Linux-Build bündelt die Rust-Screenshot-Bibliothek.
- **Aufnahme & Video**: Systemweiter GPU Screen Recorder für die Aufnahme, libmpv für die Vorschau und FFmpeg für den Export.
- **Einstellungsintegration**: Öffentliches Paket `remya_settings_client`, reserviert für künftige Integration.
- **Struktur**:
  - `lib/main.dart` und `lib/app.dart`: Startvorgang und Design.
  - `lib/features/`: Screenshot-Oberfläche, Bildeditor und wiederverwendbare Aufnahmesteuerungen.
  - `lib/src/rust/capture/`: Wayland-Aufnahmebefehle, PNG-Verarbeitung und Auto-Scroll-Aufnahme (mit `wayland-client` und `wayland-protocols-wlr`). Lizenzen der Rust-Abhängigkeiten finden sich in den Drittanbieterhinweisen.
  - `linux/`: Linux-GTK-Runner und Desktop-Paketierung.
  - `assets/icons/`: Anwendungssymbol.
  - `tool/install.py`: XDG-Installationshelfer.

### Build-Umgebung vorbereiten

- FVM mit Flutter SDK `3.47.9`
- Über `rustup` verwaltete Rust-Toolchain
- Flutter-Linux-Build-Abhängigkeiten
- Laufzeit- und Build-Abhängigkeiten unter Arch Linux installieren:

```bash
sudo pacman -S grim wl-clipboard gtk-layer-shell wayland wayland-protocols inter-font fontconfig
# Abhängigkeiten für Aufnahme und Videoschnitt
sudo pacman -S gpu-screen-recorder ffmpeg mpv libepoxy
```

- Ein benachbarter Checkout `../remya-settings` mit `packages/remya_settings_client`

```bash
fvm install
fvm flutter pub get
```

Nach Änderungen an der Rust-Bridge-API generieren Sie die Bindings mit `flutter_rust_bridge_codegen` 2.13.0 neu und führen `fvm dart format lib/src/rust_bridge` aus.

### Validierung & lokale Installation

```bash
# Dart-Formatierung, Analyse und Tests
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# Rust-Formatierung, Lints und Tests
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Linux-Debug-Build
fvm flutter build linux --debug

# Release-Build und Installation in lokale XDG-Verzeichnisse
fvm flutter build linux --release
python3 tool/install.py
```

## 📜 Lizenz

Dieses Projekt steht unter der [PolyForm Noncommercial License 1.0.0](../LICENSE).
