import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'features/recording/recording_host.dart';
import 'features/recording/recording_shortcut.dart';
import 'features/screenshot/capture_host.dart';
import 'features/screenshot/capture_session.dart';

/// Launch modes supported by the `remya_screen_capture` executable.
enum CaptureEntrypoint { screenshot, recording, colorPicker }

/// Maps CLI flags to the requested capture mode.
CaptureEntrypoint parseEntrypoint(List<String> args) {
  final mode = args.indexOf('--mode');
  if (args.contains('--color-picker') ||
      (mode >= 0 && mode + 1 < args.length && args[mode + 1] == 'color')) {
    return .colorPicker;
  }
  if (args.contains('--record')) return .recording;
  return .screenshot;
}

Future<void> main(List<String> args) async {
  final entrypoint = parseEntrypoint(args);
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
  runWidget(switch (entrypoint) {
    .screenshot => const CaptureHost(),
    .recording => const RecordingHost(),
    .colorPicker => const CaptureHost(initialMode: CaptureMode.color),
  });
}
