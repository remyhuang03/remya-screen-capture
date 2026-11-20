import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/settings_ui.dart';

import 'app.dart';
import 'capture_windows.dart';
import 'features/recording/recording_host.dart';
import 'features/recording/recording_shortcut.dart';
import 'features/screenshot/capture_host.dart';
import 'features/settings/preference_controller.dart';
import 'features/settings/settings_window.dart';
import 'features/settings/startup_mode.dart';

/// Launch modes supported by the `remya_screen_capture` executable.
enum CaptureEntrypoint { screenshot, recording, colorPicker, settings }

/// Maps CLI flags to the requested capture mode.
CaptureEntrypoint parseEntrypoint(List<String> args) {
  if (args.contains('--settings')) return .settings;
  final mode = args.indexOf('--mode');
  if (args.contains('--color-picker') ||
      (mode >= 0 && mode + 1 < args.length && args[mode + 1] == 'color')) {
    return .colorPicker;
  }
  if (args.contains('--record')) return .recording;
  return .screenshot;
}

/// Core app registration page ID; null opens the first page.
String? settingsPage(List<String> args) {
  final index = args.indexOf('--settings');
  final page = index >= 0 && index + 1 < args.length ? args[index + 1] : '';
  if (page.isNotEmpty &&
      page != remyaMaterialThemePageId &&
      !settingsPages.any((entry) => entry.id == page)) {
    throw ArgumentError.value(page, 'page', 'Unknown settings page');
  }
  return page.isEmpty ? null : page;
}

Future<void> main(List<String> args) async {
  final entrypoint = parseEntrypoint(args);
  String? page;
  if (entrypoint == .settings) {
    try {
      page = settingsPage(args);
    } on ArgumentError catch (error) {
      stderr.writeln(error);
      exit(64);
    }
  }
  final recording = entrypoint == .recording;
  if (recording &&
      Platform.environment['XDG_RUNTIME_DIR']?.startsWith('/') == true) {
    if (await forwardRecordingShortcut(recordingShortcutPath())) exit(0);
  }
  WidgetsFlutterBinding.ensureInitialized();
  final background = entrypoint != .settings && args.contains('--background');
  final preferences = background ? AppPreferences(capturePreferencesId) : null;
  if (preferences != null) {
    try {
      final reply = await preferences
          .get(residentStartupKey)
          .timeout(const Duration(seconds: 3));
      if (reply['value'] != true) {
        await captureWindows.invokeMethod<void>('quit');
        return;
      }
    } catch (error) {
      debugPrint('Reading Screen Capture startup mode: $error');
      await captureWindows.invokeMethod<void>('quit');
      return;
    }
  }
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      "Remy'a Screen Capture",
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'Google Material Symbols Rounded',
    ], await rootBundle.loadString('assets/licenses/material-symbols.txt'));
    yield LicenseEntryWithLineBreaks(
      ['Screenshot backend and third-party libraries'],
      await rootBundle.loadString(
        'lib/src/rust/capture/THIRD_PARTY_NOTICES.txt',
      ),
    );
  });
  await themeController.start();
  if (entrypoint == .settings) {
    runApp(ScreenCaptureSettingsApp(page: page));
    return;
  }
  runWidget(
    preferences == null
        ? _captureHost(entrypoint)
        : _ResidentCapture(preferences: preferences),
  );
}

Widget _captureHost(
  CaptureEntrypoint entrypoint, {
  Future<void> Function()? onFinished,
}) => switch (entrypoint) {
  .settings => throw StateError('Settings is not a capture session'),
  .screenshot => CaptureHost(onFinished: onFinished),
  .recording => RecordingHost(onFinished: onFinished),
  .colorPicker => CaptureHost(initialMode: .color, onFinished: onFinished),
};

class _ResidentCapture extends StatefulWidget {
  const _ResidentCapture({required this.preferences});

  final AppPreferences preferences;

  @override
  State<_ResidentCapture> createState() => _ResidentCaptureState();
}

class _ResidentCaptureState extends State<_ResidentCapture> {
  late final _startup = PreferenceController<bool>(
    preferences: widget.preferences,
    key: residentStartupKey,
    parse: (value) => value as bool,
    save: (_) async {},
  );
  CaptureEntrypoint? _entrypoint;
  bool _finishing = false;
  bool _quitting = false;

  @override
  void initState() {
    super.initState();
    captureSessions.setMethodCallHandler((call) async {
      if (call.method != 'startSession' || _finishing || _quitting) {
        return false;
      }
      final mode = CaptureEntrypoint.values.byName(call.arguments as String);
      if (_entrypoint != null) {
        return mode == .recording &&
            _entrypoint == .recording &&
            await forwardRecordingShortcut(recordingShortcutPath());
      }
      if (_startup.value == false) {
        return false;
      }
      setState(() => _entrypoint = mode);
      // The hidden bootstrap view cannot drive a normal frame.
      WidgetsBinding.instance.scheduleWarmUpFrame();
      return true;
    });
    _startup.addListener(_startupChanged);
    _startup.start();
    unawaited(_ready());
  }

  Future<void> _ready() async {
    try {
      await captureWindows.invokeMethod<void>('residentReady');
    } catch (error) {
      debugPrint('Registering Screen Capture startup service: $error');
      await _quit();
    }
  }

  void _startupChanged() {
    if (_startup.value == false && _entrypoint == null && !_finishing) {
      unawaited(_quit());
    }
  }

  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    await captureWindows.invokeMethod<void>('quit');
  }

  Future<void> _finish() async {
    _finishing = true;
    await captureWindows.invokeMethod<void>('finishSession');
    if (!mounted) return;
    setState(() => _entrypoint = null);
    final binding = WidgetsBinding.instance;
    final closed = binding.endOfFrame;
    binding.scheduleWarmUpFrame();
    await closed;
    _finishing = false;
    if (_startup.value == false) await _quit();
  }

  @override
  void dispose() {
    captureSessions.setMethodCallHandler(null);
    _startup.dispose();
    unawaited(widget.preferences.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _entrypoint == null
      ? const ViewCollection(views: [])
      : _captureHost(_entrypoint!, onFinished: _finish);
}
