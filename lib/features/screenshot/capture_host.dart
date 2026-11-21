import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:material_ui/material_ui.dart';

import '../../capture_windows.dart';
import '../../hyprland_capture_rendering.dart';
import '../../process_command.dart';
import '../../src/rust_bridge/api.dart' as rust;
import '../../src/rust_bridge/frb_generated.dart';
import '../capture_controls/capture_buttons.dart';
import '../capture_controls/capture_icon.dart';
import '../color_picker/color_data.dart';
import '../color_picker/color_result_panel.dart';
import '../image_editor/image_editor.dart';
import '../settings/open_settings.dart';
import 'capture_geometry.dart';
import 'capture_overlay.dart';
import 'capture_result.dart';
import 'capture_session.dart';

class CaptureHost extends StatefulWidget {
  const CaptureHost({super.key, this.initialMode = .region, this.onFinished});

  final CaptureMode initialMode;
  final Future<void> Function()? onFinished;

  @override
  State<CaptureHost> createState() => _CaptureHostState();
}

class _CaptureHostState extends State<CaptureHost> with WidgetsBindingObserver {
  final _widgets = <int, Widget>{};
  final _overlays = <String, int>{};
  final _closeRequests = ValueNotifier(0);
  final _colors = ColorPickerStore();
  ColorPickerPreferences _colorPreferences = ColorPickerPreferences();
  int? _colorView;
  Timer? _colorToastTimer;
  Future<List<Uint8List>>? _freezing;
  static final Future<void> _backend = _initializeBackend();
  RandomAccessFile? _captureLock;
  CaptureSession? _session;
  _ScrollRun? _scrollRun;
  int? _editorView;
  int? _resultView;
  int? _keyboardView;
  int? _confinedView;
  ui.Image? _resultImage;
  String? _editorPath;
  int _revision = 0;
  bool _initializing = false;
  bool _errorVisible = false;
  bool _closing = false;
  bool _resultOpeningEditor = false;
  Future<void> _inputQueue = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    captureWindows.setMethodCallHandler(_nativeEvent);
    unawaited(_start());
  }

  static Future<void> _initializeBackend() async {
    final bundle = File(Platform.resolvedExecutable).parent.path;
    await ScreenshotRustLib.init(
      externalLibrary: ExternalLibrary.open('$bundle/lib/libremya_capture.so'),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    captureWindows.setMethodCallHandler(null);
    _closeRequests.dispose();
    _colorToastTimer?.cancel();
    _resultImage?.dispose();
    _disposeSession();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => CaptureViews(_widgets);

  Future<Object?> _nativeEvent(MethodCall call) async {
    switch (call.method) {
      case 'outputsChanged':
        if (_colorToastTimer?.isActive == true) {
          await _quit();
        } else if (!_errorVisible && (_initializing || _session != null)) {
          _revision++;
          _errorVisible = true;
          await _endCapture();
          await _showError('The display layout changed. Start a new capture.');
        }
      case 'closeRequested':
        final id = (call.arguments as Map?)?['id'];
        if (_errorVisible || (_colorView != null && id == _colorView)) {
          await _quit();
        } else {
          // Native close and the editor's Close button use the same dirty check.
          _closeRequests.value++;
        }
      case 'closed':
        final id = (call.arguments as Map?)?['id'];
        if (_colorView != null && id == _colorView) await _quit();
    }
    return null;
  }

  Future<void> _start() async {
    if (_closing || _initializing) return;
    final revision = ++_revision;
    _initializing = true;
    final frozen = <FrozenOutput>[];
    var handedOff = false;
    try {
      if (!await _lockCapture()) {
        await _quit();
        return;
      }
      if (widget.onFinished != null) {
        await captureWindows.invokeMethod<void>('prefetch');
      }
      final editor = _editorView;
      if (_errorVisible && editor != null) {
        _errorVisible = false;
        await changeCaptureWindow('hide', editor);
      }
      if (widget.initialMode == .color) {
        unawaited(_readColorPreferences(revision));
      }
      final (snapshot, connected) = await (
        _backend
            .then((_) => rust.takeStartupCapture())
            .timeout(const Duration(seconds: 3), onTimeout: () => null),
        captureWindows.invokeListMethod<String>('outputs'),
      ).wait;
      final (allMonitors, windows, cursor) = await (
        readMonitors(snapshot: snapshot?.monitors),
        readWindows(snapshot: snapshot?.windows),
        readCursor(snapshot: snapshot?.cursor),
      ).wait;
      final monitors = allMonitors
          .where((monitor) => connected?.contains(monitor.name) ?? false)
          .toList();
      if (monitors.isEmpty) {
        throw StateError('No Hyprland output supports the capture overlay.');
      }
      if (!_current(revision)) return;
      final prefetched = {
        for (final frame in snapshot?.frames ?? <rust.StartupFrame>[])
          frame.name: frame.png,
      };
      final freezing = _freezing =
          monitors.every((monitor) => prefetched.containsKey(monitor.name))
          ? Future.value([
              for (final monitor in monitors) prefetched[monitor.name]!,
            ])
          : _freeze(monitors);
      final List<Uint8List> frames;
      try {
        frames = await freezing;
      } finally {
        _freezing = null;
      }
      if (!_current(revision)) return;
      await Future.wait(
        monitors.indexed.map((entry) async {
          final (index, monitor) = entry;
          final png = frames[index];
          final image = await _decodePng(png);
          try {
            final pixels = await image.toByteData();
            if (pixels == null) {
              throw StateError('Could not read pixels from ${monitor.name}.');
            }
            frozen.add(FrozenOutput(monitor, png, image, pixels));
          } catch (_) {
            image.dispose();
            rethrow;
          }
        }),
      );
      if (!_current(revision)) return;
      final active = frozen.firstWhere(
        (output) => cursor != null && output.monitor.bounds.contains(cursor),
        orElse: () => frozen.firstWhere(
          (output) => output.monitor.focused,
          orElse: () => frozen.first,
        ),
      );
      final session = CaptureSession(
        frozen,
        windows,
        active,
        mode: widget.initialMode,
        uppercaseHex: _colorPreferences.uppercase,
      );
      if (cursor != null && active.monitor.bounds.contains(cursor)) {
        session.hover(
          active,
          cursor - active.monitor.bounds.topLeft,
          active.monitor.bounds.size,
        );
      } else if (session.mode == .color) {
        session.nudgeColor(Offset.zero);
      }
      _session = session;
      handedOff = true;
      for (final output in frozen) {
        final id = await openCaptureWindow('overlay', output: output.name);
        if (!_current(revision)) {
          await changeCaptureWindow('close', id);
          return;
        }
        _overlays[output.name] = id;
        final native = await setFrozenBackground(id, output.png);
        if (!_current(revision)) return;
        _setView(
          id,
          CaptureOverlay(
            session: session,
            output: output,
            nativeBackground: native,
            onCapture: (request) => unawaited(_capture(request)),
            onPickColor: (sample, {required keepPicking}) =>
                unawaited(_pickColor(sample, keepPicking: keepPicking)),
            onColorHistory: () => unawaited(_showColorHistory()),
            onScroll: () => unawaited(_startScrolling()),
            onBack: () => unawaited(_back()),
            onDone: () => unawaited(_finishScrolling()),
          ),
        );
      }
      await _configureInput(session);
      if (!_current(revision)) return;
      session.addListener(_syncOverlayInput);
      await Future.wait([
        for (final id in _overlays.values.toList())
          changeCaptureWindow('show', id),
      ]);
    } catch (error) {
      if (!_current(revision)) return;
      await _endCapture();
      await _showError('Could not start screen capture. ${_message(error)}');
    } finally {
      if (!handedOff) {
        for (final output in frozen) {
          output.image.dispose();
        }
      }
      _initializing = false;
    }
  }

  Future<void> _readColorPreferences(int revision) async {
    try {
      final preferences = await _colors.readPreferences();
      if (!_current(revision)) return;
      _colorPreferences = preferences;
      _session?.setUppercaseHex(preferences.uppercase);
    } catch (error) {
      debugPrint('Could not read color picker settings. ${_message(error)}');
    }
  }

  Future<List<Uint8List>> _freeze(List<CaptureMonitor> monitors) async {
    final shader = await HyprlandCaptureRendering.suspend(hardwareCursor: true);
    try {
      return await Future.wait(
        monitors.map((monitor) => rust.captureOutput(name: monitor.name)),
      );
    } finally {
      await shader.restore();
    }
  }

  Future<void> _pickColor(
    PickedColor picked, {
    required bool keepPicking,
  }) async {
    final session = _session;
    if (session == null || session.mode != .color || session.busy) return;
    final revision = _revision;
    final output = session.active.monitor;
    final preferences = _colorPreferences;
    session.setBusy(true);
    List<PickedColor> history = [];
    String? error;
    try {
      history = await _colors.add(picked, preferences.historySize);
    } catch (exception) {
      error = 'Could not save the color to history. ${_message(exception)}';
    }
    if (!_current(revision)) return;
    if (keepPicking) {
      session.setBusy(false, error: error);
      return;
    }
    ColorFormat? copied;
    try {
      await _endCapture();
      if (!_current(revision)) return;
      if (preferences.action != .openOnly) {
        final format = preferences.defaultFormat;
        try {
          await _colors.copy(
            format.format(picked.color, uppercase: preferences.uppercase),
          );
          copied = format;
        } catch (exception) {
          final failure = _message(exception);
          error = error == null ? failure : '$error $failure';
        }
      }
      if (!_current(revision)) return;
      await _showColorResult(
        output,
        picked,
        history,
        copied: copied,
        error: error,
        toast: preferences.action == .copyOnly && error == null,
      );
    } catch (exception) {
      if (_current(revision)) await _showError(_message(exception));
    }
  }

  Future<void> _showColorHistory() async {
    final session = _session;
    if (session == null || session.mode != .color || session.busy) return;
    final revision = _revision;
    final output = session.active.monitor;
    session.setBusy(true);
    try {
      final history = await _colors.readHistory(
        limit: _colorPreferences.historySize,
      );
      if (!_current(revision)) return;
      if (history.isEmpty) {
        session.setBusy(false, error: 'No colors in history yet.');
        return;
      }
      await _endCapture();
      if (_current(revision)) {
        await _showColorResult(output, history.first, history);
      }
    } catch (error) {
      if (!_current(revision)) return;
      if (_session == session) {
        session.setBusy(false, error: _message(error));
      } else {
        await _showError(_message(error));
      }
    }
  }

  Future<void> _showColorResult(
    CaptureMonitor output,
    PickedColor picked,
    List<PickedColor> history, {
    ColorFormat? copied,
    String? error,
    bool toast = false,
  }) async {
    final revision = _revision;
    final height = ColorResultPanel.preferredHeight(_colorPreferences)
        .ceil()
        .clamp(340, math.max(340, output.bounds.height.toInt() - 16))
        .toInt();
    final id = toast
        ? await openCaptureWindow('result', output: output.name)
        : await openCaptureWindow('colorPanel', height: height);
    if (!_current(revision)) {
      await changeCaptureWindow('close', id);
      return;
    }
    _colorView = id;
    try {
      if (toast) {
        final size = output.bounds.size;
        final width = math.min(480.0, size.width - 16);
        final bounds = Rect.fromLTWH(
          (size.width - width) / 2,
          math.max(8, size.height - 120),
          width,
          64,
        );
        _setView(
          id,
          LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Positioned.fromRect(
                  rect: scaleRect(bounds, size, constraints.biggest),
                  child: ColorCopyToast(
                    picked: picked,
                    preferences: _colorPreferences,
                    onDetails: () => unawaited(
                      _continueColorResult(
                        id,
                        () => _showColorResult(
                          output,
                          picked,
                          history,
                          copied: copied,
                        ),
                      ),
                    ),
                    onClose: () => unawaited(_quit()),
                  ),
                ),
              ],
            ),
          ),
        );
        await setCaptureInput(id, [bounds], 'none');
      } else {
        _setView(
          id,
          ColorResultPanel(
            picked: picked,
            history: history,
            preferences: _colorPreferences,
            copied: copied,
            error: error,
            onCopy: _colors.copy,
            onRemember: (entry) =>
                _colors.add(entry, _colorPreferences.historySize),
            onDelete: (entry) =>
                _colors.remove(entry, _colorPreferences.historySize),
            onOpenSettings: () => openCaptureSettings(page: 'color-picker'),
            onPickAgain: () => unawaited(_continueColorResult(id, _start)),
            onClose: () => unawaited(_quit()),
            onMoveWindow: () => unawaited(changeCaptureWindow('beginMove', id)),
          ),
        );
      }
      await changeCaptureWindow('show', id);
      if (!_current(revision) || _colorView != id) return;
      if (toast) {
        _colorToastTimer = Timer(
          const Duration(seconds: 4),
          () => unawaited(_quit()),
        );
      } else {
        await _releaseCaptureLock();
        unawaited(_floatColorWindow(id, output.name, height));
      }
    } catch (_) {
      if (_colorView == id) {
        _colorView = null;
        await _removeView(id);
      }
      rethrow;
    }
  }

  Future<void> _floatColorWindow(int id, String output, int height) async {
    // The first rendered frame maps the toplevel after the show request.
    final revision = _revision;
    final script =
        """
for _, w in ipairs(hl.get_windows()) do
  if w.pid == $pid and w.initial_title == "Remy'a Color Picker" and w.monitor then
    hl.dispatch(hl.dsp.window.float({ window = w, action = "set" }))
    if w.monitor.name ~= ${jsonEncode(output)} then
      hl.dispatch(hl.dsp.window.move({ window = w, monitor = ${jsonEncode(output)} }))
    end
    hl.dispatch(hl.dsp.window.resize({ window = w, x = 640, y = $height }))
    hl.dispatch(hl.dsp.window.center({ window = w }))
    return "mapped"
  end
end
return "pending"
""";
    try {
      for (
        var attempt = 0;
        _colorView == id && _current(revision) && attempt < 20;
        attempt++
      ) {
        final result = await runCommand('hyprctl', [
          'repl',
          script,
        ], timeout: const Duration(milliseconds: 500));
        if (result.exitCode == 0 &&
            result.stdout.toString().trim() == 'mapped') {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (_colorView == id && _current(revision)) {
        debugPrint('Could not set the color picker window to float.');
      }
    } catch (error) {
      debugPrint(
        'Setting the color picker window to float: ${_message(error)}',
      );
    }
  }

  Future<void> _continueColorResult(
    int id,
    Future<void> Function() next,
  ) async {
    if (_colorView != id || _closing) return;
    _colorView = null;
    _colorToastTimer?.cancel();
    try {
      await _removeView(id);
      if (mounted && !_closing) await next();
    } catch (error) {
      await _showError(_message(error));
    }
  }

  Future<bool> _lockCapture() async {
    _captureLock ??= await tryCaptureLock();
    return _captureLock != null;
  }

  Future<void> _releaseCaptureLock() async {
    final lock = _captureLock;
    _captureLock = null;
    await lock?.close();
  }

  bool _current(int revision) => mounted && !_closing && revision == _revision;

  Future<void> _capture(CaptureRequest request) async {
    final session = _session;
    if (session == null || session.busy || session.scroll != null) return;
    final revision = _revision;
    session.setBusy(true);
    try {
      final rect = request.rect;
      final window = request.window;
      final Uint8List png;
      if (window != null) {
        png = await rust.captureWindow(stableId: window.id);
      } else if (rect == (Offset.zero & request.output.size)) {
        png = request.output.png;
      } else {
        png = await rust.cropPng(
          png: request.output.png,
          x: rect.left.toInt(),
          y: rect.top.toInt(),
          width: rect.width.toInt(),
          height: rect.height.toInt(),
        );
      }
      if (_current(revision)) await _deliver(png, request);
    } catch (error) {
      if (_current(revision) && _session == session) {
        session.setBusy(false, error: _windowError(request, error));
      } else if (_current(revision)) {
        await _showError(_message(error));
      }
    }
  }

  String _windowError(CaptureRequest request, Object error) =>
      request.window == null
      ? _message(error)
      : 'Could not capture the window. Select a window and try again. ${_message(error)}';

  Future<void> _startScrolling() async {
    final session = _session;
    final rect = session?.selection;
    if (session == null || rect == null || session.busy || _scrollRun != null) {
      return;
    }
    final revision = _revision;
    final output = session.active;
    final panel = placeScrollPanel(
      output.monitor,
      scaleRect(rect, output.size, output.monitor.bounds.size),
      session.outputs.map((output) => output.monitor),
    );
    if (panel == null) {
      session.setBusy(
        false,
        error:
            'Make the selection smaller to leave room for the scrolling panel.',
      );
      return;
    }
    if (rect.height < 81) {
      session.setBusy(
        false,
        error: 'Select at least 81 pixels of scrollable content.',
      );
      return;
    }
    session.setBusy(true);
    final _ScrollRun run;
    try {
      // Live frames must match the content: no screen shader, no cursor.
      run = _ScrollRun(
        await HyprlandCaptureRendering.suspend(hardwareCursor: true),
      );
    } catch (error) {
      if (_current(revision)) session.setBusy(false, error: _message(error));
      return;
    }
    if (!_current(revision)) {
      await run.rendering.restore();
      return;
    }
    _scrollRun = run;
    session.setScroll((
      panel: panel,
      frames: 0,
      width: rect.width.toInt(),
      height: rect.height.toInt(),
      png: null,
      message: 'Starting…',
      ready: false,
    ));
    try {
      await _configureInput(session);
      // Let the overlay replace the frozen screenshot before the first frame.
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!_current(revision) || _scrollRun != run) return;
      final capture = await rust.beginScroll(
        output: output.name,
        x: rect.left.toInt(),
        y: rect.top.toInt(),
        width: rect.width.toInt(),
        height: rect.height.toInt(),
      );
      if (!_current(revision) || _scrollRun != run) {
        capture.dispose();
        return;
      }
      run.capture = capture;
      _showScroll(session, await capture.seed(), _scrollingMessage);
      session.setBusy(false);
      run.loop = _runScroll(run, session);
    } catch (error) {
      if (!_current(revision) || _scrollRun != run) return;
      _stopScroll();
      session.setScroll(null);
      session.setBusy(false, error: _message(error));
      await _configureInput(session);
    }
  }

  static const _scrollingMessage =
      'Scrolling automatically. Select Done to stop early.';

  Future<void> _runScroll(_ScrollRun run, CaptureSession session) async {
    while (_scrollRun == run && !run.finishing) {
      final rust.ScrollUpdate update;
      try {
        update = await run.capture!.step();
      } catch (error) {
        if (_scrollRun == run && !run.finishing) {
          _showScroll(
            session,
            null,
            'Scrolling stopped. ${_message(error)} Select Done to keep the captured part.',
            stopped: true,
          );
        }
        return;
      }
      if (_scrollRun != run || run.finishing) return;
      switch (update.status) {
        case .appended:
          _showScroll(session, update, _scrollingMessage);
        case .end || .full:
          _showScroll(
            session,
            update,
            update.status == .end
                ? 'Reached the end of the content.'
                : 'Reached the maximum image size.',
            stopped: true,
          );
          unawaited(_finishScrolling());
          return;
        case .noMatch:
          _showScroll(
            session,
            update,
            'Could not line up the scrolled content. Select Done to keep the captured part.',
            stopped: true,
          );
          return;
      }
    }
  }

  void _showScroll(
    CaptureSession session,
    rust.ScrollUpdate? update,
    String message, {
    bool stopped = false,
  }) {
    final previous = session.scroll;
    if (previous == null) return;
    session.setScroll((
      panel: previous.panel,
      frames: update?.frames ?? previous.frames,
      width: update?.width ?? previous.width,
      height: update?.height ?? previous.height,
      png: update?.preview ?? previous.png,
      message: message,
      ready: stopped,
    ));
  }

  Future<void> _finishScrolling() async {
    final run = _scrollRun;
    final session = _session;
    final capture = run?.capture;
    if (run == null || capture == null || session == null || run.finishing) {
      return;
    }
    final revision = _revision;
    run.finishing = true;
    session.setBusy(true);
    try {
      // Stop after the scroll step in flight, keeping what it stitched.
      await run.loop;
      final png = await capture.finish();
      if (_current(revision)) await _deliver(png, session.request);
    } catch (error) {
      if (!_current(revision)) return;
      if (_session == session && session.scroll != null) {
        run.finishing = false;
        session.setBusy(false);
        _showScroll(session, null, _message(error), stopped: true);
      } else {
        await _showError(_message(error));
      }
    }
  }

  Future<void> _back() async {
    final session = _session;
    if (session == null || _scrollRun?.finishing == true) return;
    if (session.scroll != null) {
      _stopScroll();
      session.setScroll(null);
      session.setBusy(false);
      await _configureInput(session);
    } else if (session.busy) {
      return;
    } else if (session.mode == .color) {
      await _quit();
    } else if (session.selection != null) {
      session.clearSelection();
    } else if (session.dragging) {
      session.cancelDrag();
      session.endToolbarDrag();
    } else {
      await _quit();
    }
  }

  void _stopScroll() {
    final run = _scrollRun;
    _scrollRun = null;
    if (run == null) return;
    run.finishing = true;
    run.capture?.dispose();
    unawaited(run.rendering.restore().catchError((Object _) {}));
  }

  void _syncOverlayInput() {
    final session = _session;
    if (session == null || session.scroll != null) return;
    _setConfinedView(_overlays[session.confinedOutput?.name]);
    final target = _overlays[session.active.name];
    if (_keyboardView == target) return;
    unawaited(
      _configureInput(session).catchError((Object error) {
        if (_session == session) session.setBusy(false, error: _message(error));
      }),
    );
  }

  void _setConfinedView(int? id) {
    final previous = _confinedView;
    if (previous == id) return;
    _confinedView = id;
    if (previous != null) {
      unawaited(changeCaptureWindow('releasePointer', previous));
    }
    if (id != null) unawaited(changeCaptureWindow('confinePointer', id));
  }

  Future<void> _configureInput(CaptureSession session) {
    final panel = session.scroll?.panel;
    final target = panel?.output ?? session.active.name;
    _keyboardView = _overlays[target];
    final overlays = Map.of(_overlays);
    // Releasing the previous exclusive surface first gives the new one focus.
    final ordered = overlays.entries.toList()
      ..sort(
        (a, b) => (a.key == target ? 1 : 0).compareTo(b.key == target ? 1 : 0),
      );
    final update = _inputQueue.then((_) async {
      for (final entry in ordered) {
        if (_session != session ||
            session.scroll?.panel != panel ||
            _keyboardView != overlays[target]) {
          return;
        }
        final rects = panel == null
            ? null
            : panel.output == entry.key
            ? [panel.rect]
            : <Rect>[];
        try {
          await setCaptureInput(
            entry.value,
            rects,
            entry.key == target ? 'exclusive' : 'none',
            frozen: panel == null,
          );
        } on PlatformException {
          if (_session == session && !_closing) rethrow;
        }
      }
    });
    _inputQueue = update.catchError((Object _) {});
    return update;
  }

  Future<void> _endCapture() async {
    _setConfinedView(null);
    final ids = _overlays.values.toList();
    _overlays.clear();
    _keyboardView = null;
    final session = _session;
    _session = null;
    _stopScroll();
    session?.removeListener(_syncOverlayInput);
    if (mounted && ids.isNotEmpty) setState(() => ids.forEach(_widgets.remove));
    for (final id in ids) {
      await changeCaptureWindow('hide', id);
      await changeCaptureWindow('close', id);
    }
    _releaseSession(session);
  }

  void _disposeSession() {
    _setConfinedView(null);
    _stopScroll();
    final session = _session;
    _session = null;
    session?.removeListener(_syncOverlayInput);
    _releaseSession(session);
  }

  void _releaseSession(CaptureSession? session) {
    if (session == null) return;
    session.dispose();
    for (final output in session.outputs) {
      output.image.dispose();
    }
  }

  Future<void> _deliver(Uint8List png, CaptureRequest request) async {
    final revision = _revision;
    await _endCapture();
    if (!_current(revision)) return;
    final image = await _decodePng(png);
    if (!_current(revision)) {
      image.dispose();
      return;
    }
    _resultImage = image;
    final name = _screenshotName(DateTime.now());
    if (request.edit) {
      await _showEditor(image, name);
      await _releaseCaptureLock();
    } else {
      final receipt = await _copyAndSave(png, name);
      if (_current(revision)) {
        await _showResult(png, image, request.output.monitor, name, receipt);
      }
    }
  }

  Future<CaptureReceipt> _copyAndSave(
    Uint8List png,
    String name, [
    CaptureReceipt? previous,
  ]) async {
    var copied = previous?.copied ?? false;
    var path = previous?.path;
    String? copyError;
    String? saveError;
    await Future.wait([
      if (!copied)
        () async {
          try {
            await rust.copyPng(png: png);
            copied = true;
          } catch (error) {
            copyError = _message(error);
          }
        }(),
      if (path == null)
        () async {
          try {
            path = await _saveDefault(png, name);
          } catch (error) {
            saveError = _message(error);
          }
        }(),
    ]);
    return (
      copied: copied,
      path: path,
      copyError: copyError,
      saveError: saveError,
    );
  }

  Future<void> _showResult(
    Uint8List png,
    ui.Image image,
    CaptureMonitor output,
    String name,
    CaptureReceipt receipt,
  ) async {
    final id = await openCaptureWindow('result', output: output.name);
    _resultView = id;
    final size = output.bounds.size;
    final width = math.min(590.0, size.width - 16);
    final height = receipt.copied && receipt.path != null ? 66.0 : 118.0;
    final box = Rect.fromLTWH(
      (size.width - width) / 2,
      math.max(8.0, size.height - height - 56),
      width,
      height,
    );
    _setView(
      id,
      LayoutBuilder(
        builder: (context, constraints) {
          final rect = scaleRect(box, size, constraints.biggest);
          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: CaptureResult(
                  image: image,
                  receipt: receipt,
                  onRetry: (previous) => _copyAndSave(png, name, previous),
                  onEdit: () => unawaited(_editResult(image, name)),
                  onClose: () {
                    if (!_resultOpeningEditor) unawaited(_quit());
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
    await setCaptureInput(id, [box], 'onDemand');
    await changeCaptureWindow('show', id);
  }

  Future<void> _editResult(ui.Image image, String name) async {
    if (_resultOpeningEditor) return;
    _resultOpeningEditor = true;
    final id = _resultView;
    try {
      if (id != null) await changeCaptureWindow('hide', id);
      await _showEditor(
        image,
        '${name.substring(0, name.length - 4)}-edited.png',
      );
      if (id != null) await _removeView(id);
      _resultView = null;
      await _releaseCaptureLock();
    } catch (error) {
      if (id != null) await _removeView(id);
      _resultView = null;
      await _showError(_message(error));
    } finally {
      _resultOpeningEditor = false;
    }
  }

  Future<void> _showEditor(ui.Image image, String name) async {
    final id = _editorView ??= await openCaptureWindow('editor');
    _editorPath = null;
    _errorVisible = false;
    _setView(
      id,
      ImageEditor(
        image: image,
        initialName: name,
        onCopy: (png) => rust.copyPng(png: png),
        onSave: (png, {required saveAs}) => _saveEdited(id, png, name, saveAs),
        onClose: () => unawaited(_quit()),
        closeRequests: _closeRequests,
        onMoveWindow: () => unawaited(changeCaptureWindow('beginMove', id)),
      ),
    );
    await changeCaptureWindow('show', id);
  }

  Future<String?> _saveEdited(
    int id,
    Uint8List png,
    String name,
    bool saveAs,
  ) async {
    final path = _editorPath;
    if (!saveAs) {
      final saved = path == null
          ? await _saveDefault(png, name)
          : await rust.savePng(
              png: png,
              path: path,
              replace: true,
              unique: false,
            );
      _editorPath = saved;
      return saved;
    }
    final location = await getSaveLocation(
      suggestedName: path?.split('/').last ?? name,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG image', extensions: ['png']),
      ],
      initialDirectory: path == null
          ? await _picturesDirectory()
          : File(path).parent.path,
    );
    if (location == null) return null;
    final chosen = location.path.toLowerCase().endsWith('.png')
        ? location.path
        : '${location.path}.png';
    final existing = await FileSystemEntity.type(chosen, followLinks: false);
    final replace = existing != FileSystemEntityType.notFound;
    if (replace) {
      final context = _editorContext.currentContext;
      if (context == null || !context.mounted) return null;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace this file?'),
          content: Text(chosen),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (confirm != true) return null;
    }
    if (!mounted || _editorView != id || _closing) return null;
    final saved = await rust.savePng(
      png: png,
      path: chosen,
      replace: replace,
      unique: false,
    );
    _editorPath = saved;
    return saved;
  }

  final _editorContext = GlobalKey();

  Future<String> _picturesDirectory() async {
    final path = await captureWindows.invokeMethod<String>('picturesDirectory');
    if (path != null && path.startsWith('/')) return path;
    final home = Platform.environment['HOME'];
    if (home == null || !home.startsWith('/')) {
      throw StateError('A home directory is required to save the screenshot.');
    }
    return '$home/Pictures';
  }

  Future<String> _saveDefault(Uint8List png, String name) async => rust.savePng(
    png: png,
    path: '${await _picturesDirectory()}/Screenshots/$name',
    replace: false,
    unique: true,
  );

  Future<void> _showError(String message) async {
    if (!mounted || _closing) return;
    _errorVisible = true;
    try {
      final id = _editorView ??= await openCaptureWindow('editor');
      _setView(
        id,
        Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const .all(24),
                child: Column(
                  mainAxisSize: .min,
                  spacing: 16,
                  children: [
                    Text(message, textAlign: .center),
                    Wrap(
                      spacing: 8,
                      children: [
                        CaptureButton(
                          label: 'Retry',
                          onPressed: () => unawaited(_start()),
                        ),
                        CaptureButton(
                          label: 'Close',
                          variant: .text,
                          icon: const CaptureIcon(.close),
                          onPressed: () => unawaited(_quit()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await changeCaptureWindow('show', id);
    } catch (error) {
      debugPrint(message);
      await _quit();
    }
  }

  Future<void> _quit() async {
    if (_closing) return;
    _closing = true;
    _revision++;
    _colorToastTimer?.cancel();
    try {
      await _freezing;
    } catch (error) {
      debugPrint(_message(error));
    }
    if (widget.onFinished case final finish?) {
      await _endCapture();
      await _releaseCaptureLock();
      await finish();
    } else {
      await captureWindows.invokeMethod<void>('quit');
    }
  }

  Future<void> _removeView(int id) async {
    if (mounted) setState(() => _widgets.remove(id));
    await changeCaptureWindow('close', id);
  }

  void _setView(int id, Widget child) {
    if (!mounted) return;
    setState(
      () => _widgets[id] = id == _editorView && !_errorVisible
          ? KeyedSubtree(key: _editorContext, child: child)
          : child,
    );
  }
}

class _ScrollRun {
  _ScrollRun(this.rendering);

  final HyprlandCaptureRendering rendering;
  rust.ScrollCapture? capture;
  Future<void> loop = Future.value();
  bool finishing = false;
}

Future<ui.Image> _decodePng(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

String _screenshotName(DateTime date) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return 'Screenshot_${date.year}-${pad(date.month)}-${pad(date.day)}_'
      '${pad(date.hour)}-${pad(date.minute)}-${pad(date.second)}.png';
}

String _message(Object error) =>
    error.toString().replaceFirst('Bad state: ', '');
