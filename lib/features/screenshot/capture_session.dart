import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color, Offset, Rect, Size;

import '../color_picker/color_data.dart';
import 'capture_geometry.dart';

enum CaptureMode { region, window, color }

class FrozenOutput {
  FrozenOutput(this.monitor, this.png, this.image, this.pixels);

  final CaptureMonitor monitor;
  final Uint8List png;
  final ui.Image image;
  final ByteData pixels;

  Size get size => Size(image.width.toDouble(), image.height.toDouble());
  String get name => monitor.name;

  Offset clampPixel(Offset position) => Offset(
    position.dx.floor().clamp(0, image.width - 1).toDouble(),
    position.dy.floor().clamp(0, image.height - 1).toDouble(),
  );

  Offset pixelAt(Offset position, Size viewport) => clampPixel(
    Offset(
      position.dx * size.width / viewport.width,
      position.dy * size.height / viewport.height,
    ),
  );

  Offset logicalAt(Offset pixel, Size viewport) => Offset(
    pixel.dx * viewport.width / size.width,
    pixel.dy * viewport.height / size.height,
  );

  Color colorAt(Offset position) {
    final x = position.dx.floor().clamp(0, image.width - 1);
    final y = position.dy.floor().clamp(0, image.height - 1);
    final i = (y * image.width + x) * 4;
    return .fromARGB(
      pixels.getUint8(i + 3),
      pixels.getUint8(i),
      pixels.getUint8(i + 1),
      pixels.getUint8(i + 2),
    );
  }
}

typedef CaptureRequest = ({
  FrozenOutput output,
  Rect rect,
  bool edit,
  CaptureWindow? window,
});

typedef ScrollPreview = ({
  PanelPlacement panel,
  int frames,
  int width,
  int height,
  Uint8List? png,
  String message,
  bool ready,
});

class CaptureSession extends ChangeNotifier {
  CaptureSession(
    this.outputs,
    this.windows,
    this.active, {
    this.mode = .region,
    this.uppercaseHex = true,
  });

  final List<FrozenOutput> outputs;
  final List<CaptureWindow> windows;
  final bool uppercaseHex;
  FrozenOutput active;
  CaptureMode mode;
  CaptureMode _previousMode = .region;
  Rect? _selection;
  FrozenOutput? _selectionOutput;
  ({FrozenOutput output, Offset position, Size viewport})? _hover;
  Offset? pointer;
  Offset? colorPixel;
  Size? _colorViewport;
  ColorFormat colorFormat = .hex;
  int zoom = 12;
  CaptureWindow? hoveredWindow;
  bool edit = false;
  bool busy = false;
  String? message;
  ScrollPreview? scroll;

  Offset? _origin;
  Rect? draft;

  Rect? get selection => mode == .region ? _selection : null;

  void hover(FrozenOutput output, Offset position, Size viewport) {
    if (_origin != null || scroll != null) return;
    _hover = (output: output, position: position, viewport: viewport);
    if (busy || selection != null) return;
    active = output;
    pointer = position;
    if (mode == .color) {
      _colorViewport = viewport;
      colorPixel = output.pixelAt(position, viewport);
    }
    if (mode == .window) {
      final monitor = output.monitor;
      hoveredWindow = windowAt(
        monitor,
        windows,
        monitor.bounds.topLeft +
            Offset(
              position.dx * monitor.bounds.width / viewport.width,
              position.dy * monitor.bounds.height / viewport.height,
            ),
      );
    }
    notifyListeners();
  }

  void changeMode(CaptureMode value, Size viewport) {
    if (busy || scroll != null || _origin != null || mode == value) return;
    final previous = mode;
    if (previous != .color) _previousMode = previous;
    mode = value;
    hoveredWindow = null;
    message = null;
    if (value == .color) {
      if (_hover case final hover?) {
        this.hover(hover.output, hover.position, hover.viewport);
      } else {
        nudgeColor(Offset.zero, viewport);
      }
      return;
    }
    final selectionOutput = _selectionOutput;
    if (value == .region && selectionOutput != null) {
      active = selectionOutput;
      pointer = null;
      notifyListeners();
      return;
    }
    if (_hover case final hover?) {
      this.hover(hover.output, hover.position, hover.viewport);
    } else {
      notifyListeners();
    }
  }

  void toggleColor(Size viewport) =>
      changeMode(mode == .color ? _previousMode : .color, viewport);

  void cycleMode(Size viewport) => changeMode(
    CaptureMode.values[(mode.index + 1) % CaptureMode.values.length],
    viewport,
  );

  void cycleColorFormat() {
    const formats = <ColorFormat>[.hex, .rgb, .hsl, .oklch];
    colorFormat = formats[(formats.indexOf(colorFormat) + 1) % formats.length];
    notifyListeners();
  }

  void zoomColor(bool increase) {
    const levels = [4, 6, 8, 12, 16, 24, 32];
    zoom =
        levels[(levels.indexOf(zoom) + (increase ? 1 : -1)).clamp(
          0,
          levels.length - 1,
        )];
    notifyListeners();
  }

  void nudgeColor(Offset delta, Size viewport) {
    final pixel = active.clampPixel(
      (colorPixel ?? active.size.center(Offset.zero)) + delta,
    );
    colorPixel = pixel;
    _colorViewport = viewport;
    pointer = active.logicalAt(pixel + const Offset(.5, .5), viewport);
    notifyListeners();
  }

  Offset get colorPosition {
    final size = active.monitor.bounds.size;
    final viewport = _colorViewport ?? size;
    final local = pointer ?? viewport.center(Offset.zero);
    return Offset(
      (local.dx * size.width / viewport.width).floorToDouble(),
      (local.dy * size.height / viewport.height).floorToDouble(),
    );
  }

  PickedColor get colorSample {
    final pixel =
        colorPixel ?? active.clampPixel(active.size.center(Offset.zero));
    return PickedColor(
      color: active.colorAt(pixel),
      output: active.name,
      position: colorPosition,
      time: DateTime.now(),
    );
  }

  void startDrag(
    FrozenOutput output,
    Offset position,
    Size viewport,
    bool edit,
  ) {
    if (busy || selection != null || scroll != null) return;
    hover(output, position, viewport);
    this.edit = edit;
    _origin = position;
    message = null;
    notifyListeners();
  }

  void updateDrag(FrozenOutput output, Offset position, Size viewport) {
    final origin = _origin;
    if (origin == null || active != output || mode != .region) return;
    pointer = position;
    if ((position - origin).distance >= 4 || draft != null) {
      draft = Rect.fromPoints(
        origin,
        position,
      ).intersect(Offset.zero & viewport);
    }
    notifyListeners();
  }

  CaptureRequest? endDrag(FrozenOutput output, Offset position, Size viewport) {
    final origin = _origin;
    if (origin == null || output != active) return null;
    updateDrag(output, position, viewport);
    _origin = null;
    final rect = draft;
    draft = null;
    if (mode == .window) {
      final hit = hoveredWindow;
      if (hit != null && (position - origin).distance < 4) {
        return (
          output: output,
          rect: Offset.zero & output.size,
          edit: edit,
          window: hit,
        );
      }
      notifyListeners();
      return null;
    }
    if (rect == null) return request;
    setSelection(scaleRect(rect, viewport, output.size));
    return null;
  }

  void cancelDrag() {
    _origin = null;
    draft = null;
    notifyListeners();
  }

  void setSelection(Rect value) {
    _selection = pixelRect(value, active.size);
    _selectionOutput = active;
    message = null;
    notifyListeners();
  }

  void clearSelection() {
    _selection = null;
    _selectionOutput = null;
    message = null;
    notifyListeners();
  }

  CaptureRequest get request => (
    output: active,
    rect: selection ?? Offset.zero & active.size,
    edit: edit,
    window: mode == .window ? hoveredWindow : null,
  );

  void setBusy(bool value, {String? error}) {
    busy = value;
    message = error;
    notifyListeners();
  }

  void setScroll(ScrollPreview? value) {
    scroll = value;
    notifyListeners();
  }
}
