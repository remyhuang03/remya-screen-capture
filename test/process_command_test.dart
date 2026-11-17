import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_screen_capture/process_command.dart';

void main() {
  test('short commands return exit status and both streams', () async {
    final result = await runCommand('sh', [
      '-c',
      'printf result; printf failure >&2; exit 4',
    ], timeout: const Duration(seconds: 2));
    expect(result.exitCode, 4);
    expect(result.stdout, 'result');
    expect(result.stderr, 'failure');
  });

  test('timed out commands are terminated', () async {
    late Process child;
    await expectLater(
      runCommand(
        'sleep',
        ['60'],
        timeout: const Duration(milliseconds: 100),
        launch: (executable, arguments) async {
          return child = await Process.start(executable, arguments);
        },
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(await child.exitCode.timeout(const Duration(seconds: 2)), -9);
  });
}
