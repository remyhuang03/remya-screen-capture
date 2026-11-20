import 'dart:io';

import 'package:remya_client/remya_client.dart';

const capturePreferencesId = 'remya-screen-capture';
const residentStartupKey = 'resident-startup';

Future<void> saveResidentStartup(
  AppPreferences preferences,
  bool enabled,
) async {
  await preferences.set(residentStartupKey, enabled);
  if (!enabled) return;
  final result = await Process.run('systemctl', [
    '--user',
    'start',
    'top.remya.screen_capture.gui.service',
  ]);
  if (result.exitCode != 0) {
    throw StateError('Could not prewarm Screen Capture. ${result.stderr}');
  }
}
