import 'dart:io';

Future<void> openCaptureSettings({String? page}) async {
  await Process.start(Platform.resolvedExecutable, [
    '--settings',
    ?page,
  ], mode: .detached);
}
