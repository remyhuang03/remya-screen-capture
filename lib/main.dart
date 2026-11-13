import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'features/recording/recording_host.dart';
import 'features/recording/recording_shortcut.dart';
import 'features/screenshot/capture_host.dart';
import 'features/screenshot/capture_session.dart';
import 'features/settings/settings_window.dart';

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
  if (page.isNotEmpty && !settingsPages.any((entry) => entry.id == page)) {
    throw ArgumentError.value(page, 'page', 'Unknown settings page');
  }
  return page.isEmpty ? null : page;
}

Future<void> main(List<String> args) async {
  final entrypoint = parseEntrypoint(args);
  final page = entrypoint == .settings ? settingsPage(args) : null;
  final recording = entrypoint == .recording;
  if (recording &&
      Platform.environment['XDG_RUNTIME_DIR']?.startsWith('/') == true) {
    if (await forwardRecordingShortcut(recordingShortcutPath())) exit(0);
  }
  WidgetsFlutterBinding.ensureInitialized();
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
  if (entrypoint == .settings) {
    // The settings window waits for the shared theme to avoid a recolor.
    await themeController.start();
    runApp(ScreenCaptureSettingsApp(page: page));
    return;
  }
  // Capture starts immediately; the shared theme applies once it loads.
  unawaited(themeController.start());
  runWidget(switch (entrypoint) {
    .settings => throw StateError('unreachable'),
    .screenshot => const CaptureHost(),
    .recording => const RecordingHost(),
    .colorPicker => const CaptureHost(initialMode: CaptureMode.color),
  });
}
