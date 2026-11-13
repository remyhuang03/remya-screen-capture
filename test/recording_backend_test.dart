import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_screen_capture/features/recording/recording_backend.dart';
import 'package:remya_screen_capture/features/screenshot/capture_geometry.dart';

import 'fake_app_preferences.dart';

void main() {
  test(
    'recording defaults and writes use the registered Core preference',
    () async {
      final preferences = FakeAppPreferences();
      final defaults = await RecordingOptions.read(preferences: preferences);
      expect(defaults.systemAudio, isTrue);
      expect(defaults.microphone, isFalse);
      expect(defaults.cursor, isTrue);
      await defaults
          .copyWith(cursor: false, microphone: true)
          .save(preferences: preferences);
      final saved = await RecordingOptions.read(preferences: preferences);
      expect(saved.cursor, isFalse);
      expect(saved.microphone, isTrue);
      expect(preferences.writes, ['recording']);
      preferences.values['recording'] = {'cursor': 'invalid'};
      await expectLater(
        RecordingOptions.read(preferences: preferences),
        throwsFormatException,
      );
      preferences.unavailable = true;
      await expectLater(
        RecordingOptions.read(preferences: preferences),
        throwsStateError,
      );
      await expectLater(saved.save(preferences: preferences), throwsStateError);
      expect(saved.cursor, isFalse);
    },
  );

  final output = CaptureMonitor({
    'id': 2,
    'name': 'DP-TEST',
    'focused': true,
    'activeWorkspace': {'id': 3},
    'specialWorkspace': {},
    'x': -1600,
    'y': 20,
    'width': 2560,
    'height': 1440,
    'scale': 1.6,
    'transform': 0,
  });

  test(
    'recording uses output names or logical coordinates with signed origins',
    () {
      expect(RecordingTarget(output, null).captureArguments, ['-w', 'DP-TEST']);
      expect(
        RecordingTarget(
          output,
          const Rect.fromLTRB(-5.3, 39.6, 100.2, 130.1),
        ).captureArguments,
        ['-w', 'region', '-region', '100x90+-1600+60'],
      );
      expect(
        RecordingTarget(
          output,
          const Rect.fromLTRB(10.2, 20.1, 109.8, 79.9),
        ).captureArguments,
        ['-w', 'region', '-region', '98x58+-1589+41', '-encoder', 'cpu'],
      );
      expect(
        () => RecordingTarget(
          output,
          const Rect.fromLTWH(1600, 0, 25, 25),
        ).captureArguments,
        throwsArgumentError,
      );
    },
  );

  late Directory directory;
  late _RecordingFixture fixture;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('remya-recording-test-');
    fixture = _RecordingFixture();
  });
  tearDown(() async {
    fixture.process?.kill(.sigkill);
    await directory.delete(recursive: true);
  });

  Future<RecordingRun> start({
    RecordingOptions options = const RecordingOptions(),
    Future<void>? cancel,
  }) => RecordingRun.start(
    target: RecordingTarget(output, null),
    options: options,
    directory: directory.path,
    runtimeDirectory: directory,
    launch: fixture.launch,
    cancel: cancel,
  );

  test('acknowledges pause and repeated stop publishes one original', () async {
    final run = await start(
      options: const RecordingOptions(microphone: true, cursor: false),
    );
    expect(
      fixture.arguments,
      containsAllInOrder(['-a', 'default_output', '-a', 'default_input']),
    );
    expect(fixture.arguments, containsAllInOrder(['-cursor', 'no']));

    fixture.rejectNextPause = true;
    await expectLater(run.setPaused(true), throwsStateError);
    expect(run.paused, isFalse);
    await run.setPaused(true);
    final pausedElapsed = run.elapsed;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(run.paused, isTrue);
    expect(run.elapsed, pausedElapsed);
    final stop = run.stop();
    expect(run.stop(), same(stop));
    final result = await stop;
    expect(await run.finished, same(result));
    expect(result.warning, isNull);
    expect(result.systemAudio, isTrue);
    expect(result.microphone, isTrue);
    expect(await File(result.path).readAsString(), 'video fixture');
    expect(await directory.list().map((file) => file.path).toList(), [
      result.path,
    ]);
  });

  test(
    'publishes a usable take after the recorder exits unexpectedly',
    () async {
      fixture.exitCode = 4;
      final run = await start(
        options: const RecordingOptions(microphone: true),
      );
      fixture.process!.kill(.sigterm);
      final result = await run.finished;
      expect(result.warning, contains('exit 4'));
      expect(await File(result.path).exists(), isTrue);
    },
  );

  test(
    'cancels startup and clears empty staging after the process exits',
    () async {
      fixture.producesFrames = false;
      final cancel = Completer<void>();
      final pending = start(cancel: cancel.future);
      await fixture.launched.future;
      final rejected = expectLater(
        pending,
        throwsA(isA<RecordingStartCancelled>()),
      );
      cancel.complete();
      await rejected;
      expect(await fixture.process!.exitCode, 0);
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test('reports missing audio device before recording starts', () async {
    fixture.hasMicrophone = false;
    await expectLater(
      start(options: const RecordingOptions(microphone: true)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('microphone'),
        ),
      ),
    );
    expect(fixture.process, isNull);
  });

  test('reports a missing controller before recording starts', () async {
    fixture.hasController = false;
    await expectLater(
      start(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Could not run gsr-cli'),
        ),
      ),
    );
    expect(fixture.process, isNull);
  });

  test('falls back to interrupt when stop IPC fails', () async {
    fixture.rejectStop = true;
    final run = await start();
    final result = await run.stop();
    expect(result.warning, contains('did not acknowledge Stop'));
    expect(await File(result.path).exists(), isTrue);
  });

  test('retains a partial file when ffprobe cannot validate it', () async {
    fixture.validMedia = false;
    final run = await start();
    final finished = expectLater(
      run.finished,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Recovery file:'),
        ),
      ),
    );
    await expectLater(run.stop(), throwsStateError);
    await finished;
    final files = await directory.list(recursive: true).toList();
    expect(
      files.whereType<File>().any(
        (file) => file.path.endsWith('/recording.mkv'),
      ),
      isTrue,
    );
  });
}

class _RecordingFixture {
  final launched = Completer<void>();
  Process? process;
  List<String> arguments = [];
  int exitCode = 0;
  bool rejectNextPause = false;
  bool producesFrames = true;
  bool hasMicrophone = true;
  bool hasController = true;
  bool rejectStop = false;
  bool validMedia = true;

  Future<Process> launch(String program, List<String> args) async {
    switch (program) {
      case 'gsr-cli' when args.first == '--help':
        if (!hasController) throw ProcessException(program, args, 'Not found');
        return _reply('set-paused true|false');
      case 'gsr-cli' when args[2] == 'set-paused':
        final reject = rejectNextPause;
        rejectNextPause = false;
        return _reply('', exitCode: reject ? 1 : 0);
      case 'gsr-cli':
        if (rejectStop) return _reply('', exitCode: 1);
        process!.kill(.sigterm);
        return _reply('saved');
      case 'ffprobe' when args.first == '-version':
        return _reply('ffprobe fixture');
      case 'ffprobe':
        return _reply(
          jsonEncode({
            'streams': [
              {
                'codec_type': 'video',
                'nb_read_packets': validMedia ? '12' : '0',
              },
              for (final _ in arguments.where((arg) => arg == '-a'))
                {'codec_type': 'audio'},
            ],
          }),
        );
      case 'gpu-screen-recorder' when args.first == '--list-audio-devices':
        return _reply(
          'default_output|Default output\n${hasMicrophone ? 'default_input|Default input' : ''}',
        );
      case 'gpu-screen-recorder':
        arguments = args;
        final recorder = await Process.start('sh', [
          '-c',
          r'''
trap "exit $1" INT TERM
if [ "$2" = true ]; then
  printf 'video fixture' > "$3"
  printf 'monotonic_microsec\trealtime_microsec\n1\t%s\n' "$4" > "$3.ts"
fi
while :; do sleep 0.02; done
''',
          'recording-fixture',
          '$exitCode',
          '$producesFrames',
          args.last,
          '${DateTime.now().microsecondsSinceEpoch}',
        ]);
        process = recorder;
        launched.complete();
        return recorder;
      default:
        return Process.start(program, args);
    }
  }

  Future<Process> _reply(String text, {int exitCode = 0}) =>
      Process.start('sh', [
        '-c',
        r'printf "%s\n" "$1"; exit "$2"',
        'recording-reply',
        text,
        '$exitCode',
      ]);
}
