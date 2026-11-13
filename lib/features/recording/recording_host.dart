import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../capture_windows.dart';
import '../../hyprland_capture_rendering.dart';
import '../capture_controls/capture_buttons.dart';
import '../screenshot/capture_geometry.dart';
import '../video_editor/video_editor.dart';
import 'recording_backend.dart';
import 'recording_hud.dart';
import 'recording_setup.dart';
import 'recording_shortcut.dart';

enum _Phase {
  opening,
  selecting,
  countdown,
  starting,
  recording,
  finishing,
  editor,
  closing,
}

class RecordingHost extends StatefulWidget {
  const RecordingHost({super.key});

  @override
  State<RecordingHost> createState() => _RecordingHostState();
}

class _RecordingHostState extends State<RecordingHost>
    with WidgetsBindingObserver {
  final _setupViews = <String, int>{};
  final _hudViews = <String, int>{};
  final _closeRequests = ValueNotifier(0);
  final _signals = <StreamSubscription<ProcessSignal>>[];
  _Phase _phase = .opening;
  List<CaptureMonitor> _monitors = [];
  CaptureMonitor? _active;
  Rect? _region;
  int? _countdown;
  int? _editorView;
  Widget? _editor;
  bool _showingError = false;
  String? _message;
  String? _interruption;
  bool _quitAfterAttempt = false;
  bool _exitRequested = false;
  RandomAccessFile? _captureLock;
  RecordingShortcut? _shortcut;
  HyprlandCaptureRendering? _shader;
  Completer<void>? _cancelStart;
  RecordingOptions _options = const RecordingOptions();
  RecordingRun? _run;
  RecordingHudController? _hud;
  Future<void> _setupInput = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    captureWindows.setMethodCallHandler(_nativeEvent);
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      _signals.add(signal.watch().listen((_) => _exitSignal()));
    }
    unawaited(_prepare());
  }

  @override
  void didChangeMetrics() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    captureWindows.setMethodCallHandler(null);
    for (final signal in _signals) {
      unawaited(signal.cancel());
    }
    _closeRequests.dispose();
    _hud?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CaptureViews({
    for (final monitor in _monitors)
      ?_setupViews[monitor.name]: RecordingSetup(
        monitor: monitor,
        active: monitor == _active,
        region: _region,
        options: _options,
        countdown: _countdown,
        message: _message,
        onFocus: () => _focusOutput(monitor),
        onSelect: (region) => _select(monitor, region),
        onOptions: (options) => setState(() => _options = options),
        onStart: () => unawaited(_start()),
        onCancel: _toggle,
      ),
    if (_hud case final hud?)
      for (final monitor in _monitors)
        ?_hudViews[monitor.name]: RecordingHud(
          controller: hud,
          monitor: monitor,
          onInputChanged: (regions, keyboard) =>
              _updateHudInput(monitor.name, regions, keyboard),
        ),
    ?_editorView: ?_editor,
  });

  void _updateHudInput(String output, List<Rect> regions, bool keyboard) {
    final id = _hudViews[output];
    if (_phase != .recording || id == null) return;
    unawaited(
      setCaptureInput(id, regions, keyboard ? 'onDemand' : 'none').catchError((
        Object error,
      ) {
        if (_hudViews[output] == id) debugPrint('$error');
      }),
    );
  }

  Future<void> _prepare() async {
    setState(() {
      _phase = .opening;
      _region = null;
      _message = null;
      _countdown = null;
      _interruption = null;
    });
    try {
      _captureLock ??= await tryCaptureLock();
      if (_captureLock == null) {
        // Another invocation may have acquired the lock while its socket opened.
        await forwardRecordingShortcut(recordingShortcutPath());
        await _quit();
        return;
      }
      _shortcut ??= await RecordingShortcut.listen(
        recordingShortcutPath(),
        _toggle,
      );
      if (_phase == .closing) return;
      final editor = _editorView;
      if (editor != null) {
        await changeCaptureWindow('hide', editor);
        if (_phase == .closing) return;
        setState(() => _editor = null);
      }
      _options = await RecordingOptions.read();
      final outputs = await captureWindows.invokeListMethod<String>('outputs');
      final monitors = (await readMonitors())
          .where((monitor) => outputs?.contains(monitor.name) ?? false)
          .toList();
      if (monitors.isEmpty) {
        throw StateError('No Hyprland output supports the recording overlay.');
      }
      final cursor = await readCursor();
      if (_phase == .closing) return;
      _active = monitors.firstWhere(
        (monitor) => cursor != null && monitor.bounds.contains(cursor),
        orElse: () => monitors.firstWhere(
          (monitor) => monitor.focused,
          orElse: () => monitors.first,
        ),
      );
      _monitors = monitors;
      for (final monitor in monitors) {
        final id = await openCaptureWindow(
          'recordingSetup',
          output: monitor.name,
        );
        if (_phase == .closing) return;
        _setupViews[monitor.name] = id;
      }
      await _configureSetupInput();
      if (_phase == .closing) return;
      setState(() => _phase = .selecting);
      await _showSetup();
    } catch (error) {
      if (_phase != .closing) {
        await _showError('Could not prepare recording. ${_describe(error)}');
      }
    }
  }

  Future<void> _showSetup() async {
    for (final id in _setupViews.values.toList()) {
      if (_phase != .selecting) return;
      await changeCaptureWindow('show', id);
    }
  }

  Future<Object?> _nativeEvent(MethodCall call) async {
    if (_phase == .closing) return null;
    switch (call.method) {
      case 'outputsChanged':
        const message = 'The display layout changed during capture.';
        switch (_phase) {
          case .recording:
            _interruption = message;
            unawaited(_stop());
          case .countdown || .starting:
            _interruption = message;
            _cancelPendingStart();
          case .selecting:
            _interruption = message;
            await _showError(message);
          default:
            break;
        }
      case 'closeRequested':
        if (_showingError) {
          await _quit();
        } else {
          _closeRequests.value++;
        }
      case 'closed':
        final id = (call.arguments as Map)['id'];
        if (_phase == .recording && _hudViews.containsValue(id)) {
          _interruption = 'A recording control window closed unexpectedly.';
          unawaited(_stop());
        }
    }
    return null;
  }

  void _focusOutput(CaptureMonitor monitor) {
    if (_phase != .selecting || _active == monitor || _region != null) return;
    _select(monitor, null);
  }

  void _select(CaptureMonitor monitor, Rect? region) {
    if (_phase != .selecting) return;
    final switched = monitor != _active;
    setState(() {
      _active = monitor;
      _region = region;
      _message = null;
    });
    if (switched) {
      unawaited(
        _configureSetupInput().catchError((Object error) {
          if (_phase == .selecting) setState(() => _message = _describe(error));
        }),
      );
    }
  }

  Future<void> _configureSetupInput() {
    final update = _setupInput.then((_) async {
      final active = _setupViews[_active?.name];
      if (_phase == .closing || active == null) return;
      for (final id in _setupViews.values.toList()) {
        if (id != active) await setCaptureInput(id, null, 'none');
      }
      await setCaptureInput(active, null, 'exclusive');
    });
    _setupInput = update.catchError((Object _) {});
    return update;
  }

  void _toggle() {
    switch (_phase) {
      case .opening || .selecting:
        unawaited(_quit());
      case .countdown || .starting:
        _quitAfterAttempt = true;
        _cancelPendingStart();
      case .recording:
        unawaited(_stop());
      case .finishing || .editor || .closing:
        break;
    }
  }

  void _exitSignal() {
    _exitRequested = true;
    _quitAfterAttempt = true;
    if (_phase == .finishing) return;
    if (_phase == .editor) {
      unawaited(_quit());
    } else {
      _toggle();
    }
  }

  void _cancelPendingStart() {
    final cancel = _cancelStart;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
  }

  Future<void> _start() async {
    final monitor = _active;
    if (_phase != .selecting || monitor == null) return;
    final cancel = _cancelStart = Completer<void>();
    final target = RecordingTarget(monitor, _region);
    final options = _options;
    setState(() {
      _phase = .countdown;
      _countdown = 3;
      _message = null;
    });
    RecordingResult? recovered;
    try {
      await options.save();
      if (cancel.isCompleted) return;
      _shader = await HyprlandCaptureRendering.suspend();
      for (var value = 3; value > 0 && !cancel.isCompleted; value--) {
        setState(() => _countdown = value);
        await Future.any([
          Future<void>.delayed(const Duration(seconds: 1)),
          cancel.future,
        ]);
      }
      if (cancel.isCompleted) return;
      setState(() => _countdown = 0);
      await Future.any([
        Future<void>.delayed(const Duration(milliseconds: 180)),
        cancel.future,
      ]);
      if (cancel.isCompleted) return;
      setState(() => _phase = .starting);
      for (final id in _setupViews.values.toList()) {
        await changeCaptureWindow('hide', id);
      }
      if (cancel.isCompleted) return;
      final run = await RecordingRun.start(
        target: target,
        options: options,
        directory: await _recordingsDirectory(),
        cancel: cancel.future,
      );
      _run = run;
      setState(() => _phase = .recording);
      unawaited(_watch(run));
      if (cancel.isCompleted) {
        unawaited(_stop());
        return;
      }
      await _closeSetup();
      if (_phase == .recording) await _showHud(run, target);
    } on RecordingStartCancelled catch (error) {
      recovered = error.recording;
    } catch (error) {
      if (_run != null) {
        _interruption =
            'Recording controls could not open. ${_describe(error)}';
        unawaited(_stop());
      } else if (!cancel.isCompleted) {
        _message = 'Could not start recording. ${_describe(error)}';
      }
    } finally {
      _cancelStart = null;
      if (recovered != null) {
        await _deliverResult(recovered);
      } else if (_phase == .countdown || _phase == .starting) {
        final shaderWarning = await _restoreShader();
        if (_quitAfterAttempt) {
          await _quit();
        } else if (_interruption case final interruption?) {
          await _showError(_withWarning(interruption, shaderWarning));
        } else {
          setState(() {
            _phase = .selecting;
            _countdown = null;
            if (shaderWarning != null) {
              _message = _withWarning(_message, shaderWarning);
            }
          });
          try {
            await _showSetup();
          } catch (error) {
            await _showError(_withWarning(_message, _describe(error)));
          }
        }
      }
    }
  }

  Future<void> _showHud(RecordingRun run, RecordingTarget target) async {
    _hud = RecordingHudController(
      monitors: _monitors,
      target: target.monitor,
      region: target.region,
      systemAudio: run.systemAudio,
      microphone: run.microphone,
      cursor: run.options.cursor,
      elapsed: () => run.elapsed,
      paused: () => run.paused,
      onPause: () => run.setPaused(!run.paused),
      onStop: _stop,
    );
    for (final monitor in _monitors) {
      final id = await openCaptureWindow('recordingHud', output: monitor.name);
      if (_phase != .recording) {
        await changeCaptureWindow('close', id);
        return;
      }
      _hudViews[monitor.name] = id;
      await setCaptureInput(id, const [], 'none');
      if (_phase != .recording) return;
    }
    setState(() {});
    for (final id in _hudViews.values.toList()) {
      if (_phase != .recording) return;
      await changeCaptureWindow('show', id);
    }
  }

  Future<void> _stop() async {
    final run = _run;
    if (run == null || _phase != .recording) return;
    setState(() => _phase = .finishing);
    try {
      await run.stop();
    } catch (error) {
      // The exit watcher owns recovery and file delivery.
      debugPrint('Stopping the recorder: ${_describe(error)}');
    }
  }

  Future<void> _watch(RecordingRun run) async {
    RecordingResult? result;
    String? failure;
    try {
      result = await run.finished;
    } catch (error) {
      failure = _describe(error);
    }
    if (_run != run || _phase == .closing) return;
    _run = null;
    await _deliverResult(result, failure: failure);
  }

  Future<void> _deliverResult(
    RecordingResult? result, {
    String? failure,
  }) async {
    setState(() => _phase = .finishing);
    await _closeSetup();
    await _closeHud();
    final shaderWarning = await _restoreShader();
    await _releaseSession();
    if (_exitRequested) {
      await _quit();
      return;
    }
    final warning = [
      _interruption,
      shaderWarning,
      result?.warning,
    ].nonNulls.join(' ');
    if (result != null) {
      try {
        await _showEditor(result, warning.isEmpty ? null : warning);
      } catch (error) {
        await _showError(
          'Could not open the video editor. ${_describe(error)}\n'
          'Original saved to ${result.path}',
        );
      }
    } else {
      await _showError(_withWarning(failure, warning));
    }
  }

  Future<void> _showEditor(RecordingResult result, String? warning) async {
    final id = _editorView ??= await openCaptureWindow('editor');
    _showingError = false;
    setState(() {
      _phase = .editor;
      _editor = VideoEditor(
        path: result.path,
        systemAudio: result.systemAudio,
        microphone: result.microphone,
        warning: warning,
        onClose: () => unawaited(_quit()),
        closeRequests: _closeRequests,
        onMoveWindow: () => unawaited(changeCaptureWindow('beginMove', id)),
      );
    });
    await changeCaptureWindow('show', id);
  }

  Future<void> _showError(String message) async {
    if (_phase == .closing || _showingError) return;
    _showingError = true;
    setState(() => _phase = .editor);
    await _closeSetup();
    try {
      final id = _editorView ??= await openCaptureWindow('editor');
      if (_phase == .closing) return;
      setState(
        () => _editor = Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const .all(24),
                child: Column(
                  mainAxisSize: .min,
                  spacing: 16,
                  children: [
                    SelectableText(message, textAlign: .center),
                    Wrap(
                      spacing: 8,
                      children: [
                        CaptureButton(
                          label: 'Retry',
                          onPressed: () {
                            _showingError = false;
                            unawaited(_prepare());
                          },
                        ),
                        CaptureButton(
                          label: 'Close',
                          variant: .text,
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

  Future<void> _closeSetup() => _closeViews(_setupViews);

  Future<void> _closeHud() async {
    final hud = _hud;
    _hud = null;
    await _closeViews(_hudViews);
    hud?.dispose();
  }

  Future<void> _closeViews(Map<String, int> views) async {
    final ids = views.values.toList();
    views.clear();
    if (mounted) setState(() {});
    for (final id in ids) {
      try {
        await changeCaptureWindow('close', id);
      } catch (error) {
        debugPrint('Closing recording overlay: ${_describe(error)}');
      }
    }
  }

  Future<String?> _restoreShader() async {
    final shader = _shader;
    _shader = null;
    try {
      await shader?.restore();
      return null;
    } catch (error) {
      return 'Could not restore the screen shader. ${_describe(error)}';
    }
  }

  Future<void> _releaseSession() async {
    final shortcut = _shortcut;
    final lock = _captureLock;
    _shortcut = null;
    _captureLock = null;
    try {
      await shortcut?.close();
    } catch (error) {
      debugPrint('Closing recording shortcut: ${_describe(error)}');
    } finally {
      await lock?.close();
    }
  }

  Future<void> _quit() async {
    if (_phase == .closing) return;
    _phase = .closing;
    await _closeSetup();
    await _closeHud();
    await _releaseSession();
    await captureWindows.invokeMethod<void>('quit');
  }
}

Future<String> _recordingsDirectory() async {
  final path = await captureWindows.invokeMethod<String>('videosDirectory');
  if (path != null && path.startsWith('/')) return '$path/Recordings';
  final home = Platform.environment['HOME'];
  if (home == null || !home.startsWith('/')) {
    throw StateError('A home directory is required to save the recording.');
  }
  return '$home/Videos/Recordings';
}

String _describe(Object error) => switch (error) {
  StateError(:final message) => message,
  PlatformException(:final message, :final code) => message ?? code,
  _ => error.toString(),
};

String _withWarning(String? message, String? warning) =>
    [message, warning].nonNulls.where((value) => value.isNotEmpty).join(' ');
