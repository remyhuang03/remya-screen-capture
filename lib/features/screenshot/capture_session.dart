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
    this._mode = .region,
    this.uppercaseHex = true,
  });

  final List<FrozenOutput> outputs;
  final List<CaptureWindow> windows;
  bool uppercaseHex;
  FrozenOutput active;
  CaptureMode _mode;
  CaptureMode get mode => _mode;
  Rect? _selection;
  ({FrozenOutput output, Offset position})? _hover;
  Offset? pointer;
  Offset? colorPixel;
  ColorFormat colorFormat = .hex;
  int zoom = 12;
  CaptureWindow? hoveredWindow;
  bool edit = false;
  bool busy = false;
  String? message;
  ScrollPreview? scroll;

  ({FrozenOutput output, Offset start, bool confine})? _drag;
  Rect? draft;

  final _toolbarPositions = <FrozenOutput, Offset>{};
  FrozenOutput? toolbarDragSource;
  Offset? _toolbarGrab;

  Rect? get selection => _selection;
  bool get dragging => _drag != null || toolbarDragSource != null;
  FrozenOutput? get confinedOutput =>
      _drag?.confine == true ? _drag?.output : null;
  Offset? toolbarPosition(FrozenOutput output) => _toolbarPositions[output];

  void setUppercaseHex(bool value) {
    if (uppercaseHex == value) return;
    uppercaseHex = value;
    notifyListeners();
  }

  void hover(FrozenOutput output, Offset position, Size viewport) {
    if (_drag != null) return;
    final local = _outputPoint(output, position, viewport);
    _hover = (output: output, position: local);
    if (busy ||
        scroll != null ||
        selection != null ||
        toolbarDragSource != null) {
      return;
    }
    _updatePointer(output, local);
    notifyListeners();
  }

  void _updatePointer(FrozenOutput output, Offset local) {
    active = output;
    pointer = local;
    if (mode == .color) {
      colorPixel = output.pixelAt(local, output.monitor.bounds.size);
    } else if (mode == .window) {
      hoveredWindow = windowAt(
        output.monitor,
        windows,
        output.monitor.bounds.topLeft + local,
      );
    }
  }

  void changeMode(CaptureMode value) {
    if (busy ||
        scroll != null ||
        dragging ||
        selection != null ||
        mode == value ||
        mode == .color ||
        value == .color) {
      return;
    }
    _mode = value;
    hoveredWindow = null;
    message = null;
    if (pointer case final local?) _updatePointer(active, local);
    notifyListeners();
  }

  void cycleMode() => changeMode(mode == .region ? .window : .region);

  void startToolbarDrag(
    FrozenOutput output,
    Offset position,
    Offset toolbarOrigin,
    Size viewport,
  ) {
    if (busy || active != output || dragging) return;
    toolbarDragSource = output;
    _toolbarGrab = _outputPoint(output, position - toolbarOrigin, viewport);
  }

  void updateToolbarDrag(Offset position, Size viewport) {
    final source = toolbarDragSource;
    if (source == null) return;
    final global = _desktopPoint(source, position, viewport);
    final target = _outputAt(global);
    if (target == null) return;
    final local = global - target.monitor.bounds.topLeft;
    _updatePointer(target, local);
    _toolbarPositions[target] = local - _toolbarGrab!;
    notifyListeners();
  }

  void endToolbarDrag() {
    if (toolbarDragSource == null) return;
    toolbarDragSource = null;
    _toolbarGrab = null;
    notifyListeners();
  }

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

  void nudgeColor(Offset delta) {
    final pixel = active.clampPixel(
      (colorPixel ?? active.size.center(Offset.zero)) + delta,
    );
    colorPixel = pixel;
    pointer = active.logicalAt(
      pixel + const Offset(.5, .5),
      active.monitor.bounds.size,
    );
    notifyListeners();
  }

  Offset get colorPosition {
    final local = pointer ?? active.monitor.bounds.size.center(Offset.zero);
    return Offset(local.dx.floorToDouble(), local.dy.floorToDouble());
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

  bool startDrag(
    FrozenOutput output,
    Offset position,
    Size viewport,
    bool edit, {
    bool confinePointer = false,
  }) {
    if (busy || dragging || selection != null || scroll != null) return false;
    final local = _outputPoint(output, position, viewport);
    _hover = (output: output, position: local);
    _updatePointer(output, local);
    this.edit = edit;
    _drag = (
      output: output,
      start: output.monitor.bounds.topLeft + local,
      confine: mode == .region && confinePointer,
    );
    message = null;
    notifyListeners();
    return true;
  }

  void updateDrag(FrozenOutput output, Offset position, Size viewport) {
    final drag = _drag;
    if (drag == null || mode != .region) return;
    final global = _desktopPoint(output, position, viewport);
    final bounds = drag.output.monitor.bounds;
    final bounded = Offset(
      global.dx.clamp(bounds.left, bounds.right),
      global.dy.clamp(bounds.top, bounds.bottom),
    );
    final local = bounded - bounds.topLeft;
    _hover = (output: drag.output, position: local);
    _updatePointer(drag.output, local);
    if ((global - drag.start).distance >= 4 || draft != null) {
      draft = Rect.fromPoints(
        _selectionEdge(drag.start - bounds.topLeft, bounds.size),
        _selectionEdge(local, bounds.size),
      );
    }
    notifyListeners();
  }

  CaptureRequest? endDrag(FrozenOutput output, Offset position, Size viewport) {
    final drag = _drag;
    if (drag == null) return null;
    final global = _desktopPoint(output, position, viewport);
    updateDrag(output, position, viewport);
    final rect = draft;
    _drag = null;
    draft = null;
    if (rect != null && !rect.isEmpty) {
      final source = drag.output;
      setSelection(scaleRect(rect, source.monitor.bounds.size, source.size));
      return null;
    }
    notifyListeners();
    if (drag.output.monitor.bounds.contains(global) &&
        (global - drag.start).distance < 4 &&
        (mode != .window || hoveredWindow != null)) {
      return request;
    }
    return null;
  }

  void cancelDrag() {
    _drag = null;
    draft = null;
    notifyListeners();
  }

  void setSelection(Rect value) {
    _selection = pixelRect(value, active.size);
    message = null;
    notifyListeners();
  }

  void clearSelection() {
    _selection = null;
    message = null;
    if (_hover case final hover?) _updatePointer(hover.output, hover.position);
    notifyListeners();
  }

  FrozenOutput? _outputAt(Offset global) {
    for (final output in outputs) {
      if (output.monitor.bounds.contains(global)) return output;
    }
    return null;
  }

  Offset _outputPoint(FrozenOutput output, Offset local, Size viewport) {
    final bounds = output.monitor.bounds;
    return Offset(
      local.dx * bounds.width / viewport.width,
      local.dy * bounds.height / viewport.height,
    );
  }

  Offset _desktopPoint(FrozenOutput output, Offset local, Size viewport) =>
      output.monitor.bounds.topLeft + _outputPoint(output, local, viewport);

  // Hyprland stops at the last logical pixel. The crop edge is exclusive.
  Offset _selectionEdge(Offset point, Size size) => Offset(
    point.dx >= size.width - 1 ? size.width : point.dx,
    point.dy >= size.height - 1 ? size.height : point.dy,
  );

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
