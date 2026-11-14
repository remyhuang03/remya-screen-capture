<p align="center">
  <img src="../assets/icons/app_icon-full.svg" width="128" alt="Remy'a Screen Capture icon">
</p>

<h1 align="center">Remy'a Screen Capture</h1>

<h3 align="center">Herramienta de captura, grabación de pantalla y selector de color para Arch Linux Hyprland</h3>

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
  <strong>Español</strong> ·
  <a href="README.ja.md">日本語</a>
</p>

Una interfaz moderna y elegante creada con **Material Design 3 Expressive**, que combina eficiencia **orientada al teclado** con **amplias funciones de edición integradas**: desde la captura hasta la posproducción sin fricciones.

- **Experiencia orientada al teclado**: Atajos de teclado completos para un flujo de trabajo ágil.
- **Diseño elegante MD3E**: Basado en Material Design 3 Expressive, con animaciones fluidas y una jerarquía visual limpia que encaja de forma natural en Hyprland.
- **Edición integrada completa**: Anotación de capturas, recorte de vídeo y panel avanzado de selección de color.

> [!WARNING]
> Este software se encuentra actualmente en fase **Beta** y puede presentar errores o inestabilidad. Sus funciones y comportamiento siguen en desarrollo activo.

## 🚀 Instalación

### Instalar desde AUR

Instala [Remya Core](https://github.com/remyhuang03/remya-core) `0.1.0` para usar los temas y las preferencias compartidas. AUR ofrece el paquete fuente `remya-screen-capture` y el binario `remya-screen-capture-bin`. Ambos dependen de `remya-core`.

```bash
paru -S remya-screen-capture || yay -S remya-screen-capture
```

### Instalar desde un archivo de la versión

Para instalar manualmente, instala primero Core. Descarga el archivo x86_64 y `SHA256SUMS` desde [GitHub Releases](https://github.com/remyhuang03/remya-screen-capture/releases).

```bash
sha256sum -c SHA256SUMS
tar --zstd -xf remya_screen_capture-0.2.0-linux-x86_64.tar.zst
cd remya_screen_capture-0.2.0-linux-x86_64
python tool/install.py
```

### Atajos de Hyprland

Añade estos atajos a tu configuración de Hyprland (usa la ruta absoluta del ejecutable si `~/.local/bin` está fuera del `PATH` de la sesión):

```lua
-- Captura de pantalla
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("remya_screen_capture"))

-- Grabación de pantalla
hl.bind("SUPER + R", hl.dsp.exec_cmd("remya_screen_capture --record"))

-- Selector de color
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("remya_screen_capture --color-picker"))
```

## ✨ Funciones

### Capturas de pantalla

| Captura de pantalla | Editor de anotaciones |
|:---:|:---:|
| ![Superposición y selección de captura](images/demo-screenshot.png) | ![Captura y editor de anotaciones](images/demo-screenshot-editor.png) |

<p align="center">
  <img src="images/demo-screenshot-tools.png" alt="Barra de herramientas de anotación" width="100%">
</p>

- **Captura para cualquier escenario**: Admite captura de ventanas, regiones personalizadas y desplazamiento vertical automático (mediante el protocolo `zwlr_virtual_pointer_v1`).
- **Selección de precisión**: Arrastrar con el ratón y ajuste píxel a píxel con el teclado.
- **Editor integrado**: Amplia variedad de herramientas de dibujo y anotación.

### Grabación de pantalla

<p align="center">
  <img src="images/demo-video-editor.png" alt="Grabación de pantalla y editor de vídeo" width="100%">
</p>

- **Anotaciones en vivo durante la grabación**: Herramientas de marcador y puntero láser en tiempo real mientras grabas.
- **Edición de vídeo y exportación multiformato**: Vista previa fotograma a fotograma y recorte preciso; exporta a MP4, WebM, GIF o MKV mezclando el audio del sistema y el micrófono.

### Selector de color

<p align="center">
  <img src="images/demo-color-picker.png" alt="Selector de color y panel de resultados" width="540">
</p>

- **Análisis y edición de color profesional**: Muestra múltiples formatos, contraste y matices en tiempo real, con ajuste HSL e historial de muestras.

## ⌨️ Desarrollo

### Stack tecnológico y arquitectura

- **Flutter**: `3.47.9` fijado mediante FVM, con Material Design 3 Expressive (`material_ui: ^1.5.0`).
- **Rust**: edición `2024`, gestionado como espacio de trabajo Cargo con el archivo `rust-toolchain.toml` en la raíz.
- **FFI**: `flutter_rust_bridge` `2.13.0`. La compilación de Linux incluye la biblioteca de captura en Rust.
- **Grabación y vídeo**: GPU Screen Recorder del sistema para captura, libmpv para vista previa y FFmpeg para exportación.
- Los temas compartidos y las preferencias de grabación y selección de color usan `remya_client` y `remya_ui` de Remya Core. Abre la ventana de ajustes con `remya_screen_capture --settings`.
- **Estructura**:
  - `lib/main.dart` y `lib/app.dart`: inicio y tema.
  - `lib/features/`: interfaz de captura, editor de imágenes y controles reutilizables.
  - `lib/src/rust/capture/`: comandos de captura Wayland, procesamiento PNG y captura con desplazamiento automático (con `wayland-client` y `wayland-protocols-wlr`). Consulta sus avisos de terceros para las licencias de dependencias Rust.
  - `linux/`: ejecutor GTK para Linux y empaquetado de escritorio.
  - `assets/icons/`: icono de la aplicación.
  - `tool/install.py`: asistente de instalación XDG.

### Preparación del entorno

- FVM con Flutter SDK `3.47.9`
- Cadena de herramientas Rust gestionada por `rustup`
- Dependencias de compilación de Flutter para Linux
- Instala las dependencias de ejecución y compilación nativa en Arch Linux:

```bash
sudo pacman -S grim wl-clipboard gtk-layer-shell wayland wayland-protocols inter-font fontconfig
# Dependencias de grabación y edición de vídeo
sudo pacman -S gpu-screen-recorder ffmpeg mpv libepoxy
```

- Una copia de `../remya-core` en `v0.1.0` junto al repositorio, con `packages/remya_client` y `packages/remya_ui`.

```bash
fvm install
fvm flutter pub get
```

Tras modificar la API del puente Rust, regenérala con `flutter_rust_bridge_codegen` 2.13.0 y ejecuta `fvm dart format lib/src/rust_bridge`.

### Validación e instalación local

```bash
# Formato, análisis y pruebas de Dart
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# Formato, lints y pruebas de Rust
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Compilación de depuración para Linux
fvm flutter build linux --debug

# Compilación de lanzamiento e instalación en directorios XDG locales
fvm flutter build linux --release
python3 tool/install.py
```

## 📜 Licencia

Este proyecto se distribuye bajo la licencia [PolyForm Noncommercial License 1.0.0](../LICENSE).
