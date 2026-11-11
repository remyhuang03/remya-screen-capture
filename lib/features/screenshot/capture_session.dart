import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color, Offset, Rect, Size;

import 'capture_geometry.dart';

enum CaptureMode { region, window }

class FrozenOutput {
  FrozenOutput(this.monitor, this.png, this.image, this.pixels);

  final CaptureMonitor monitor;
  final Uint8List png;
  final ui.Image image;
  final ByteData pixels;

  Size get size => Size(image.width.toDouble(), image.height.toDouble());
  String get name => monitor.name;

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
  CaptureSession(this.outputs, this.windows, this.active);

  final List<FrozenOutput> outputs;
  final List<CaptureWindow> windows;
  FrozenOutput active;
  CaptureMode mode = .region;
  Rect? selection;
  Offset? pointer;
  CaptureWindow? hoveredWindow;
  bool edit = false;
  bool busy = false;
  String? message;
  ScrollPreview? scroll;

  Offset? _origin;
  Rect? draft;

  void hover(FrozenOutput output, Offset position, Size viewport) {
    if (busy || selection != null || _origin != null || scroll != null) return;
    active = output;
    pointer = position;
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
    if (busy || selection != null || _origin != null || mode == value) return;
    mode = value;
    hoveredWindow = null;
    message = null;
    final currentPointer = pointer;
    if (currentPointer != null) {
      hover(active, currentPointer, viewport);
    } else {
      notifyListeners();
    }
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
    selection = pixelRect(scaleRect(rect, viewport, output.size), output.size);
    notifyListeners();
    return null;
  }

  void cancelDrag() {
    _origin = null;
    draft = null;
    notifyListeners();
  }

  void setSelection(Rect value) {
    selection = pixelRect(value, active.size);
    message = null;
    notifyListeners();
  }

  void clearSelection() {
    selection = null;
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
