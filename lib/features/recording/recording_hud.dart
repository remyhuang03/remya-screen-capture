import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../capture_controls/capture_buttons.dart';
import '../capture_controls/capture_color_picker.dart';
import '../capture_controls/capture_icon.dart';
import '../capture_controls/capture_labels.dart';
import '../capture_controls/capture_slider.dart';
import '../capture_controls/capture_swatch.dart';
import '../screenshot/capture_geometry.dart';

enum _Annotation { none, marker, laser }

const _toolbarSize = Size(464, 58);
const _optionsSize = Size(514, 50);
const _panelGap = 8.0;
const _dockDistance = 14.0;
const _edgeTrigger = 4.0;
const _laserLifetime = Duration(milliseconds: 600);
const _recordingOutline = Color(0xfff2b8b5);
const _markerPresets = {
  'Red': Color(0xfff44336),
  'Orange': Color(0xffff9800),
  'Yellow': Color(0xffffdd33),
  'Green': Color(0xff4caf50),
  'Blue': Color(0xff2196f3),
  'Purple': Color(0xff9c27b0),
  'Black': Color(0xff121212),
  'White': Colors.white,
};

class RecordingHudController extends ChangeNotifier {
  RecordingHudController({
    required this.monitors,
    required this.target,
    required this.region,
    required this.systemAudio,
    required this.microphone,
    required this.cursor,
    required this.elapsed,
    required this.paused,
    required this.onPause,
    required this.onStop,
    this._cursorPosition = _readHyprlandCursor,
  }) {
    final selection = region ?? (Offset.zero & target.bounds.size);
    final scale = _scale(target);
    final panelsHeight =
        (_toolbarSize.height + _panelGap + _optionsSize.height) * scale;
    final above = selection.top - panelsHeight - 12;
    final below = selection.bottom + 12;
    final top = above >= 20
        ? above
        : below + panelsHeight <= target.bounds.height - 20
        ? below
        : 20.0;
    _position = _clamp(
      target.bounds.topLeft +
          Offset(selection.center.dx - _toolbarSize.width * scale / 2, top),
      target,
    );
    _clockTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => refresh(),
    );
    refresh();
  }

  final List<CaptureMonitor> monitors;
  final CaptureMonitor target;
  final Rect? region;
  final bool systemAudio;
  final bool microphone;
  final bool cursor;
  final Duration Function() elapsed;
  final bool Function() paused;
  final Future<void> Function() onPause;
  final Future<void> Function() onStop;
  final Future<Offset?> Function() _cursorPosition;

  final _seconds = ValueNotifier(0);
  final _ink = ChangeNotifier();
  final _laserClock = Stopwatch();
  final _strokes = <_MarkerStroke>[];
  final _laser = <({Offset point, Duration time})>[];
  late final Timer _clockTimer;
  late CaptureMonitor _toolbarMonitor = target;
  late Offset _position;
  _Annotation _annotation = .none;
  Color _markerColor = _markerPresets['Yellow']!;
  final _recentColors = <Color>[];
  bool _customColor = false;
  double _markerWidth = 6;
  bool _pickingColor = false;
  bool _busy = false;
  bool _wasPaused = false;
  bool _disposed = false;
  ({String label, String detail})? _error;
  Timer? _errorTimer;
  AxisDirection? _docked;
  bool _hidden = false;
  bool _hideRequested = false;
  Timer? _dockWatch;
  bool _checkingCursor = false;
  Timer? _hideTimer;
  Timer? _laserTimer;
  int? _dragPointer;
  Offset _dragOffset = Offset.zero;
  int? _drawingPointer;

  Rect get _drawingBounds => region ?? (Offset.zero & target.bounds.size);

  void refresh() {
    if (_disposed) return;
    _seconds.value = elapsed().inSeconds;
    final nowPaused = paused();
    if (_wasPaused != nowPaused) {
      _wasPaused = nowPaused;
      notifyListeners();
    }
  }

  Future<void> _invoke(Future<void> Function() action, String failure) async {
    if (_busy || _disposed) return;
    _busy = true;
    _errorTimer?.cancel();
    _error = null;
    _holdOpen();
    notifyListeners();
    try {
      await action();
    } on Object catch (error) {
      if (_disposed) return;
      _error = (label: failure, detail: error.toString());
      _errorTimer = Timer(const Duration(seconds: 5), () {
        _error = null;
        notifyListeners();
      });
    } finally {
      if (!_disposed) {
        _busy = false;
        refresh();
        notifyListeners();
        if (_hideRequested) _leave();
      }
    }
  }

  double _scale(CaptureMonitor monitor) => math.min(
    1,
    math.min(
      monitor.bounds.width / _optionsSize.width,
      monitor.bounds.height /
          (_toolbarSize.height + _panelGap + _optionsSize.height),
    ),
  );

  Size get _scaledToolbar => _toolbarSize * _scale(_toolbarMonitor);
  Rect get _toolbar => _position & _scaledToolbar;

  Offset _clamp(Offset position, CaptureMonitor monitor) {
    final bounds = monitor.bounds;
    final size = _toolbarSize * _scale(monitor);
    return Offset(
      position.dx.clamp(bounds.left, bounds.right - size.width),
      position.dy.clamp(bounds.top, bounds.bottom - size.height),
    );
  }

  void _beginDrag(int pointer, Offset global) {
    if (_dragPointer != null || _pickingColor || _busy || _disposed) return;
    _holdOpen();
    _dockWatch?.cancel();
    _dragPointer = pointer;
    _dragOffset = global - _position;
  }

  void _moveDrag(int pointer, Offset global) {
    if (_dragPointer != pointer) return;
    for (final monitor in monitors) {
      if (monitor.bounds.contains(global)) {
        if (monitor != _toolbarMonitor) {
          _dragOffset *= _scale(monitor) / _scale(_toolbarMonitor);
          _toolbarMonitor = monitor;
        }
        break;
      }
    }
    _docked = null;
    _position = global - _dragOffset;
    notifyListeners();
  }

  void _endDrag(int pointer, Offset global, {bool cancelled = false}) {
    if (_dragPointer != pointer) return;
    if (!cancelled) _moveDrag(pointer, global);
    _dragPointer = null;
    _settle();
    final local = global - _toolbarMonitor.bounds.topLeft;
    if (!(_placement(_toolbarMonitor)?.toolbar.contains(local) ?? false)) {
      _leave();
    }
  }

  void _settle() {
    final monitor = _toolbarMonitor;
    final bounds = monitor.bounds;
    final toolbar = _toolbar;
    final distances = {
      AxisDirection.up: toolbar.top - bounds.top,
      AxisDirection.down: bounds.bottom - toolbar.bottom,
      AxisDirection.left: toolbar.left - bounds.left,
      AxisDirection.right: bounds.right - toolbar.right,
    };
    final nearest = distances.entries.reduce(
      (a, b) => a.value <= b.value ? a : b,
    );
    _docked = nearest.value <= _dockDistance ? nearest.key : null;
    final clamped = _clamp(_position, monitor);
    _position = switch (_docked) {
      .up => Offset(clamped.dx, bounds.top),
      .down => Offset(clamped.dx, bounds.bottom - toolbar.height),
      .left => Offset(bounds.left, clamped.dy),
      .right => Offset(bounds.right - toolbar.width, clamped.dy),
      null => clamped,
    };
    notifyListeners();
    _watchDockedCursor();
  }

  void _holdOpen() {
    if (_disposed) return;
    _hideRequested = false;
    _hideTimer?.cancel();
    if (!_hidden) return;
    _hidden = false;
    notifyListeners();
    _watchDockedCursor();
  }

  void _leave() {
    if (_docked == null || _dragPointer != null || _hidden || _disposed) return;
    _hideRequested = true;
    if (_pickingColor || _busy || _hideTimer?.isActive == true) return;
    _hideTimer = Timer(const Duration(milliseconds: 350), () {
      _hidden = true;
      _dockWatch?.cancel();
      notifyListeners();
    });
  }

  void _watchDockedCursor() {
    _dockWatch?.cancel();
    if (_docked == null) return;
    // Wayland can miss enter/leave when the pointer outruns an input shape update.
    _dockWatch = Timer.periodic(
      const Duration(milliseconds: 200),
      (timer) => unawaited(_checkDockedCursor(timer)),
    );
  }

  Future<void> _checkDockedCursor(Timer timer) async {
    if (_checkingCursor || _busy || _pickingColor) return;
    _checkingCursor = true;
    try {
      final cursor = await _cursorPosition();
      if (!timer.isActive || cursor == null) return;
      final placement = _placement(_toolbarMonitor);
      final local = cursor - _toolbarMonitor.bounds.topLeft;
      if (placement != null &&
          (placement.toolbar.contains(local) ||
              (placement.options?.contains(local) ?? false))) {
        _holdOpen();
      } else {
        _leave();
      }
    } finally {
      _checkingCursor = false;
    }
  }

  ({Rect toolbar, Rect? options, Rect? trigger})? _placement(
    CaptureMonitor monitor,
  ) {
    if (_dragPointer == null && monitor != _toolbarMonitor) return null;
    final toolbar = _toolbar.shift(-monitor.bounds.topLeft);
    final viewport = Offset.zero & monitor.bounds.size;
    if (!toolbar.overlaps(viewport)) return null;
    Rect? options;
    if (_annotation == .marker && _dragPointer == null && !_hidden) {
      final scale = _scale(monitor);
      final size = _optionsSize * scale;
      final gap = _panelGap * scale;
      final x = (toolbar.left - 3 * scale).clamp(
        0.0,
        viewport.width - size.width,
      );
      final below = toolbar.bottom + gap;
      final y = below + size.height <= viewport.height
          ? below
          : math.max(0.0, toolbar.top - gap - size.height);
      options = Offset(x, y) & size;
    }
    final trigger = switch (_docked) {
      .up => Rect.fromLTWH(toolbar.left, 0, toolbar.width, _edgeTrigger),
      .down => Rect.fromLTWH(
        toolbar.left,
        viewport.bottom - _edgeTrigger,
        toolbar.width,
        _edgeTrigger,
      ),
      .left => Rect.fromLTWH(0, toolbar.top, _edgeTrigger, toolbar.height),
      .right => Rect.fromLTWH(
        viewport.right - _edgeTrigger,
        toolbar.top,
        _edgeTrigger,
        toolbar.height,
      ),
      null => null,
    };
    return (toolbar: toolbar, options: options, trigger: trigger);
  }

  void _toggleTool(_Annotation annotation) {
    _endDrawing(_drawingPointer);
    _annotation = _annotation == annotation ? .none : annotation;
    notifyListeners();
  }

  void _setWidth(double width) {
    if (_annotation != .marker) return;
    _markerWidth = width.roundToDouble().clamp(1, 16);
    notifyListeners();
  }

  void _setColor(Color color, {bool custom = false}) {
    _markerColor = color;
    _customColor = custom;
    notifyListeners();
  }

  Future<void> _pickColor(BuildContext context) async {
    _holdOpen();
    _pickingColor = true;
    notifyListeners();
    final color = await showCaptureColorPicker(
      context,
      color: _markerColor,
      recentColors: _recentColors,
    );
    if (_disposed) return;
    _pickingColor = false;
    if (color != null) {
      _recentColors
        ..remove(color)
        ..insert(0, color);
      if (_recentColors.length > 5) _recentColors.removeLast();
      _setColor(color, custom: true);
    } else {
      notifyListeners();
    }
    if (_hideRequested) _leave();
  }

  void _beginDrawing(int pointer, Offset point) {
    if (_drawingPointer != null || _annotation == .none || _disposed) return;
    _drawingPointer = pointer;
    if (_annotation == .marker) {
      _strokes.add(_MarkerStroke(point, _markerColor, _markerWidth));
    } else {
      _laserClock
        ..reset()
        ..start();
      _laser.add((point: point, time: Duration.zero));
      _laserTimer = Timer.periodic(const Duration(milliseconds: 24), (_) {
        final oldest = _laserClock.elapsed - _laserLifetime;
        if (_laser.length > 1) {
          final head = _laser.removeLast();
          _laser.removeWhere((sample) => sample.time <= oldest);
          _laser.add(head);
        }
        _ink.notifyListeners();
      });
    }
    _ink.notifyListeners();
  }

  void _moveDrawing(int pointer, Offset point) {
    if (pointer != _drawingPointer) return;
    if (_annotation == .marker && _strokes.isNotEmpty) {
      final stroke = _strokes.last;
      stroke.path.lineTo(point.dx, point.dy);
      stroke.extended = true;
    } else if (_annotation == .laser) {
      _laser.add((point: point, time: _laserClock.elapsed));
    }
    _ink.notifyListeners();
  }

  void _endDrawing(int? pointer) {
    if (pointer == null || pointer != _drawingPointer) return;
    _drawingPointer = null;
    _laserTimer?.cancel();
    _laserClock.stop();
    _laser.clear();
    _ink.notifyListeners();
  }

  void _clear() {
    _endDrawing(_drawingPointer);
    _strokes.clear();
    _ink.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _dragPointer = null;
    _drawingPointer = null;
    _clockTimer.cancel();
    _dockWatch?.cancel();
    _hideTimer?.cancel();
    _laserTimer?.cancel();
    _errorTimer?.cancel();
    _seconds.dispose();
    _ink.dispose();
    super.dispose();
  }
}

Future<Offset?> _readHyprlandCursor() async {
  final runtime = Platform.environment['XDG_RUNTIME_DIR'];
  final instance = Platform.environment['HYPRLAND_INSTANCE_SIGNATURE'];
  if (runtime == null || instance == null) return null;
  const timeout = Duration(milliseconds: 150);
  Socket? socket;
  try {
    socket = await Socket.connect(
      InternetAddress('$runtime/hypr/$instance/.socket.sock', type: .unix),
      0,
      timeout: timeout,
    );
    socket.write('j/cursorpos');
    await socket.flush().timeout(timeout);
    final reply = await socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    return switch (jsonDecode(reply)) {
      {'x': num x, 'y': num y} => Offset(x.toDouble(), y.toDouble()),
      _ => null,
    };
  } on Exception {
    return null;
  } finally {
    socket?.destroy();
  }
}

class RecordingHud extends StatefulWidget {
  const RecordingHud({
    super.key,
    required this.controller,
    required this.monitor,
    required this.onInputChanged,
  });

  final RecordingHudController controller;
  final CaptureMonitor monitor;
  final void Function(List<Rect> regions, bool keyboard) onInputChanged;

  @override
  State<RecordingHud> createState() => _RecordingHudState();
}

class _RecordingHudState extends State<RecordingHud> {
  final _focus = FocusNode(skipTraversal: true);
  List<Rect>? _lastRegions;
  bool? _lastKeyboard;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _publishInput(List<Rect> regions, bool keyboard) {
    if (listEquals(_lastRegions, regions) && _lastKeyboard == keyboard) return;
    _lastRegions = regions;
    _lastKeyboard = keyboard;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_lastRegions, regions)) {
        widget.onInputChanged(regions, keyboard);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final monitor = widget.monitor;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final placement = controller._placement(monitor);
        final onTarget = monitor == controller.target;
        final drawing = onTarget && controller._annotation != .none;
        final visible = placement != null && !controller._hidden;
        final ownsToolbar = monitor == controller._toolbarMonitor;
        final picker = ownsToolbar && controller._pickingColor;
        final viewport = Offset.zero & monitor.bounds.size;
        final input = <Rect>[
          if (drawing) controller._drawingBounds,
          if (visible) placement.toolbar.intersect(viewport),
          ?placement?.options,
          if (!visible && placement?.trigger != null) placement!.trigger!,
        ];
        // Map the destination input before the implicit Wayland drag grab ends.
        _publishInput(
          picker ? [viewport] : input,
          visible || drawing || picker,
        );

        Offset global(PointerEvent event) =>
            event.localPosition + monitor.bounds.topLeft;

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.backspace, control: true):
                controller._clear,
            const SingleActivator(LogicalKeyboardKey.bracketLeft): () =>
                controller._setWidth(controller._markerWidth - 1),
            const SingleActivator(LogicalKeyboardKey.bracketRight): () =>
                controller._setWidth(controller._markerWidth + 1),
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (controller._annotation != .none) {
                controller._toggleTool(controller._annotation);
              }
            },
          },
          child: Focus(
            autofocus: true,
            focusNode: _focus,
            child: Listener(
              onPointerMove: (event) =>
                  controller._moveDrag(event.pointer, global(event)),
              onPointerUp: (event) =>
                  controller._endDrag(event.pointer, global(event)),
              onPointerCancel: (event) => controller._endDrag(
                event.pointer,
                global(event),
                cancelled: true,
              ),
              child: Stack(
                fit: .expand,
                children: [
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _RecordingInk(controller, drawsInk: onTarget),
                    ),
                  ),
                  if (drawing)
                    Positioned.fromRect(
                      rect: controller._drawingBounds,
                      child: _drawingInput(controller),
                    ),
                  if (visible)
                    Positioned.fromRect(
                      rect: placement.toolbar,
                      child: MouseRegion(
                        onEnter: (_) => controller._holdOpen(),
                        onExit: (_) => controller._leave(),
                        child: FittedBox(
                          child: SizedBox.fromSize(
                            size: _toolbarSize,
                            child: _RecordingToolbar(
                              controller: controller,
                              onDragStart: (event) => controller._beginDrag(
                                event.pointer,
                                event.position + monitor.bounds.topLeft,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (placement?.options case final rect?)
                    Positioned.fromRect(
                      rect: rect,
                      child: MouseRegion(
                        onEnter: (_) => controller._holdOpen(),
                        onExit: (_) => controller._leave(),
                        child: FittedBox(
                          child: SizedBox.fromSize(
                            size: _optionsSize,
                            child: _MarkerOptions(controller),
                          ),
                        ),
                      ),
                    ),
                  if (!visible && placement?.trigger != null)
                    Positioned.fromRect(
                      rect: placement!.trigger!,
                      child: MouseRegion(
                        onEnter: (_) => controller._holdOpen(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _drawingInput(RecordingHudController controller) => MouseRegion(
    cursor: SystemMouseCursors.precise,
    child: Listener(
      behavior: .opaque,
      onPointerDown: (event) {
        if (event.buttons != kPrimaryMouseButton) return;
        _focus.requestFocus();
        controller._beginDrawing(
          event.pointer,
          event.localPosition + controller._drawingBounds.topLeft,
        );
      },
      onPointerMove: (event) => controller._moveDrawing(
        event.pointer,
        event.localPosition + controller._drawingBounds.topLeft,
      ),
      onPointerUp: (event) => controller._endDrawing(event.pointer),
      onPointerCancel: (event) => controller._endDrawing(event.pointer),
    ),
  );
}

class _RecordingToolbar extends StatelessWidget {
  const _RecordingToolbar({
    required this.controller,
    required this.onDragStart,
  });

  final RecordingHudController controller;
  final ValueChanged<PointerDownEvent> onDragStart;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final paused = controller._wasPaused;
    return CaptureSurface(
      child: Row(
        spacing: 4,
        children: [
          Expanded(
            child: CaptureTooltip(
              label:
                  controller._error?.detail ??
                  'Drag to move recording controls',
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Listener(
                  behavior: .opaque,
                  onPointerDown: (event) {
                    if (event.buttons == kPrimaryMouseButton) {
                      onDragStart(event);
                    }
                  },
                  child: _RecordingStatus(controller),
                ),
              ),
            ),
          ),
          CaptureIconButton(
            icon: paused ? .play : .pause,
            label: paused ? 'Resume recording' : 'Pause recording',
            onPressed: controller._busy
                ? null
                : () => controller._invoke(
                    controller.onPause,
                    paused ? 'Resume failed' : 'Pause failed',
                  ),
          ),
          CaptureTooltip(
            label: 'Stop recording',
            shortcut: 'Super+R',
            child: IconButton.filled(
              onPressed: controller._busy
                  ? null
                  : () => controller._invoke(controller.onStop, 'Stop failed'),
              style: IconButton.styleFrom(
                fixedSize: const Size.square(40),
                minimumSize: Size.zero,
                padding: .zero,
                tapTargetSize: .shrinkWrap,
                backgroundColor: colors.errorContainer,
                foregroundColor: colors.onErrorContainer,
                shape: RoundedRectangleBorder(borderRadius: .circular(14)),
              ),
              icon: const CaptureIcon(.stop),
            ),
          ),
          const CaptureDivider(),
          CaptureIconButton(
            icon: .laserPointer,
            label: 'Laser pointer',
            selected: controller._annotation == .laser,
            onPressed: () => controller._toggleTool(.laser),
          ),
          CaptureIconButton(
            icon: .highlighter,
            label: 'Marker',
            selected: controller._annotation == .marker,
            onPressed: () => controller._toggleTool(.marker),
          ),
          CaptureIconButton(
            icon: .delete,
            label: 'Clear drawings',
            shortcut: 'Ctrl+Backspace',
            onPressed: controller._clear,
          ),
          const CaptureDivider(),
          _InputStatus(
            label: 'System audio · ${controller.systemAudio ? 'on' : 'off'}',
            icon: controller.systemAudio ? .volumeUp : .volumeOff,
          ),
          _InputStatus(
            label: 'Microphone · ${controller.microphone ? 'on' : 'off'}',
            icon: controller.microphone ? .mic : .micOff,
          ),
          _InputStatus(
            label:
                'Cursor capture · ${controller.cursor ? 'enabled' : 'disabled'}',
            icon: .cursor,
            dimmed: !controller.cursor,
          ),
        ],
      ),
    );
  }
}

class _RecordingStatus extends StatelessWidget {
  const _RecordingStatus(this.controller);

  final RecordingHudController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final paused = controller._wasPaused;
    if (controller._error case final error?) {
      return Semantics(
        liveRegion: true,
        label: error.detail,
        child: Container(
          height: 34,
          alignment: .center,
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: .circular(20),
          ),
          child: Text(
            error.label,
            style: TextStyle(color: colors.onErrorContainer, fontSize: 11),
          ),
        ),
      );
    }
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: paused ? colors.secondaryContainer : colors.errorContainer,
        borderRadius: .circular(20),
      ),
      padding: const .symmetric(horizontal: 8),
      child: Row(
        spacing: 8,
        mainAxisAlignment: .center,
        children: [
          Opacity(
            opacity: paused ? .55 : 1,
            child: SvgPicture.asset(
              'assets/icons/capture/recording-dot.svg',
              width: 10,
              height: 10,
              excludeFromSemantics: true,
            ),
          ),
          Flexible(
            child: ValueListenableBuilder(
              valueListenable: controller._seconds,
              builder: (context, seconds, _) {
                String twoDigits(int value) => value.toString().padLeft(2, '0');
                final elapsed =
                    '${twoDigits(seconds ~/ 60)}:${twoDigits(seconds % 60)}';
                return FittedBox(
                  fit: .scaleDown,
                  child: Text(
                    elapsed,
                    semanticsLabel:
                        '${paused ? 'Paused' : 'Recording'}, $elapsed elapsed',
                    style: TextStyle(
                      color: paused
                          ? colors.onSecondaryContainer
                          : colors.onErrorContainer,
                      fontFamily: 'JetBrains Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontSize: 14,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InputStatus extends StatelessWidget {
  const _InputStatus({
    required this.label,
    required this.icon,
    this.dimmed = false,
  });

  final String label;
  final CaptureSymbol icon;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      label: label,
      child: CaptureTooltip(
        label: label,
        child: SizedBox.square(
          dimension: 40,
          child: Center(
            child: IconTheme(
              data: IconThemeData(
                color: dimmed ? color.withValues(alpha: .5) : color,
              ),
              child: CaptureIcon(icon),
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkerOptions extends StatelessWidget {
  const _MarkerOptions(this.controller);

  final RecordingHudController controller;

  @override
  Widget build(BuildContext context) => CaptureSurface(
    child: Row(
      spacing: 4,
      children: [
        for (final (label, color) in _markerPresets.entries.map(
          (entry) => (entry.key, entry.value),
        ))
          CaptureSwatch(
            color: color,
            label: label,
            selected:
                !controller._customColor && color == controller._markerColor,
            onPressed: () => controller._setColor(color),
          ),
        CaptureSwatch.custom(
          selected: controller._customColor,
          onPressed: () => controller._pickColor(context),
        ),
        const CaptureDivider(),
        Expanded(
          child: CaptureSlider(
            label: 'Marker width',
            value: controller._markerWidth,
            min: 1,
            max: 16,
            formatValue: (value) => '${value.round()} pixels',
            onChanged: controller._setWidth,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${controller._markerWidth.round()} px',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MarkerStroke {
  _MarkerStroke(this.start, this.color, this.width)
    : path = Path()..moveTo(start.dx, start.dy);

  final Offset start;
  final Color color;
  final double width;
  final Path path;
  bool extended = false;
}

class _RecordingInk extends CustomPainter {
  _RecordingInk(this.controller, {required this.drawsInk})
    : super(repaint: drawsInk ? controller._ink : null);

  final RecordingHudController controller;
  final bool drawsInk;

  @override
  void paint(Canvas canvas, Size size) {
    // A transparent-only picture is culled, leaving the last Wayland buffer.
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()..color = const Color(0x01000000),
    );
    canvas.drawColor(Colors.transparent, .src);
    if (!drawsInk) return;

    final region = controller.region;
    if (region != null) {
      final outline = Path()..addRect(region.inflate(1));
      final paint = Paint()
        ..color = _recordingOutline
        ..strokeWidth = 2
        ..style = .stroke;
      for (final contour in outline.computeMetrics()) {
        for (var start = 0.0; start < contour.length; start += 15) {
          canvas.drawPath(
            contour.extractPath(start, math.min(start + 9, contour.length)),
            paint,
          );
        }
      }
    }

    canvas.save();
    canvas.clipRect(controller._drawingBounds);
    for (final stroke in controller._strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = .round
        ..strokeJoin = .round;
      if (stroke.extended) {
        canvas.drawPath(stroke.path, paint..style = .stroke);
      } else {
        canvas.drawCircle(stroke.start, stroke.width / 2, paint);
      }
    }

    final laser = controller._laser;
    if (laser.isNotEmpty) {
      const red = Color(0xfff44336);
      final now = controller._laserClock.elapsed;
      final lifetime = _laserLifetime.inMicroseconds;
      for (final sample in laser.take(laser.length - 1)) {
        final age = (now - sample.time).inMicroseconds;
        final alpha = (1 - age / lifetime).clamp(0.0, 1.0);
        canvas.drawCircle(
          sample.point,
          2 + alpha * 4,
          Paint()..color = red.withValues(alpha: alpha * .75),
        );
      }
      final head = laser.last.point;
      canvas.drawCircle(
        head,
        9,
        Paint()
          ..color = red.withValues(alpha: .75)
          ..maskFilter = const MaskFilter.blur(.normal, 6),
      );
      canvas.drawCircle(head, 8, Paint()..color = Colors.white);
      canvas.drawCircle(head, 6, Paint()..color = red);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RecordingInk oldDelegate) =>
      oldDelegate.controller != controller || oldDelegate.drawsInk != drawsInk;
}
