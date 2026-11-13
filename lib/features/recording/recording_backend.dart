import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:remya_client/remya_client.dart';

import '../screenshot/capture_geometry.dart';

class RecordingOptions {
  const RecordingOptions({
    this.systemAudio = true,
    this.microphone = false,
    this.cursor = true,
  });

  final bool systemAudio;
  final bool microphone;
  final bool cursor;

  RecordingOptions copyWith({
    bool? systemAudio,
    bool? microphone,
    bool? cursor,
  }) => RecordingOptions(
    systemAudio: systemAudio ?? this.systemAudio,
    microphone: microphone ?? this.microphone,
    cursor: cursor ?? this.cursor,
  );

  static RecordingOptions fromValue(Object? value) {
    if (value case {
      'systemAudio': final bool systemAudio,
      'microphone': final bool microphone,
      'cursor': final bool cursor,
    }) {
      return RecordingOptions(
        systemAudio: systemAudio,
        microphone: microphone,
        cursor: cursor,
      );
    }
    throw const FormatException(
      'Invalid recording preferences from Remya Core.',
    );
  }

  static Future<RecordingOptions> read({AppPreferences? preferences}) async {
    final store = preferences ?? AppPreferences('remya-screen-capture');
    try {
      return fromValue((await store.get('recording'))['value']);
    } finally {
      if (preferences == null) await store.close();
    }
  }

  Future<void> save({AppPreferences? preferences}) async {
    final store = preferences ?? AppPreferences('remya-screen-capture');
    try {
      fromValue(
        (await store.set('recording', {
          'systemAudio': systemAudio,
          'microphone': microphone,
          'cursor': cursor,
        }))['value'],
      );
    } finally {
      if (preferences == null) await store.close();
    }
  }
}

class RecordingTarget {
  const RecordingTarget(this.monitor, this.region);

  final CaptureMonitor monitor;

  /// Monitor-local logical coordinates. Null selects the entire output.
  final Rect? region;

  List<String> get captureArguments {
    final selection = region;
    if (selection == null) {
      return ['-w', monitor.name];
    }
    if (!selection.isFinite) {
      throw ArgumentError.value(
        selection,
        'region',
        'Select an area on the monitor.',
      );
    }
    final area = selection.intersect(
      monitor.bounds.shift(-monitor.bounds.topLeft),
    );
    if (!area.isFinite || area.isEmpty) {
      throw ArgumentError.value(
        region,
        'region',
        'Select an area on the monitor.',
      );
    }

    final global = area.shift(monitor.bounds.topLeft);
    final left = global.left.ceil();
    final top = global.top.ceil();
    final width = global.right.floor() - left;
    final height = global.bottom.floor() - top;
    final shortestPixels = math.min(width, height) * monitor.scale;
    if (width < 2 || height < 2 || shortestPixels < 2) {
      throw ArgumentError.value(
        region,
        'region',
        'Select an area at least 2 × 2.',
      );
    }
    return [
      '-w',
      'region',
      '-region',
      '${width}x$height+$left+$top',
      // GSR hardware encoders expand small frames to at least 128 pixels.
      if (shortestPixels < 129) ...['-encoder', 'cpu'],
    ];
  }
}

class RecordingResult {
  const RecordingResult({
    required this.path,
    required this.systemAudio,
    required this.microphone,
    this.warning,
  });

  final String path;
  final bool systemAudio;
  final bool microphone;
  final String? warning;
}

class RecordingStartCancelled implements Exception {
  const RecordingStartCancelled({this.recording});

  final RecordingResult? recording;

  @override
  String toString() => recording == null
      ? 'Recording cancelled.'
      : 'Recording cancelled. Saved the frames already recorded to ${recording!.path}.';
}

typedef RecordingProcessLauncher = Future<Process> Function(
  String executable,
  List<String> arguments,
);

class RecordingRun {
  RecordingRun._(
    this._process,
    this._staging,
    this._runtime,
    this._launch,
    this.options,
  ) {
    _process.stdin.close().ignore();
    final stdout = _process.stdout.listen((_) {});
    final stderr = _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((chunk) {
          final text = _diagnostics + chunk;
          _diagnostics = text.length > 8000
              ? text.substring(text.length - 8000)
              : text;
        });
    final drained = Future.wait([
      stdout.asFuture<void>(),
      stderr.asFuture<void>(),
    ]);
    _exit = _process.exitCode.then((code) async {
      _exitCode = code;
      _clock.stop();
      await drained.timeout(
        const Duration(seconds: 2),
        onTimeout: () async {
          await stdout.cancel();
          await stderr.cancel();
          return [];
        },
      );
      return code;
    });
  }

  final Process _process;
  final Directory _staging;
  final Directory _runtime;
  final RecordingProcessLauncher _launch;
  final RecordingOptions options;
  final Stopwatch _clock = Stopwatch();
  late final Future<int> _exit;
  Future<RecordingResult>? _stop;
  Future<void> _controls = Future.value();
  DateTime? _firstFrame;
  Duration _initialElapsed = Duration.zero;
  int? _exitCode;
  String _diagnostics = '';
  String? _stopWarning;

  String get _socket => '${_runtime.path}/gsr.sock';
  File get _video => File('${_staging.path}/recording.mkv');
  bool get paused => _firstFrame != null && !_clock.isRunning;
  Duration get elapsed => _initialElapsed + _clock.elapsed;
  bool get systemAudio => options.systemAudio;
  bool get microphone => options.microphone;

  /// Also completes if the process exits without a stop request.
  late final Future<RecordingResult> finished = _exit.then(_finalize);

  static Future<RecordingRun> start({
    required RecordingTarget target,
    required RecordingOptions options,
    required String directory,
    Future<void>? cancel,
    RecordingProcessLauncher launch = Process.start,
    Directory? runtimeDirectory,
  }) async {
    final captureArguments = target.captureArguments;
    final runtimePath =
        runtimeDirectory?.path ?? Platform.environment['XDG_RUNTIME_DIR'];
    if (runtimePath == null || !runtimePath.startsWith('/')) {
      throw StateError(
        'A Wayland runtime directory is required for recording.',
      );
    }
    if (!directory.startsWith('/')) {
      throw ArgumentError.value(
        directory,
        'directory',
        'Use an absolute path.',
      );
    }

    var cancelled = false;
    cancel?.then((_) => cancelled = true).ignore();
    final preflight = await Future.wait([
      _checked(launch, 'gsr-cli', ['--help']),
      _checked(launch, 'ffprobe', ['-version']),
    ]);
    if (!preflight.first.stdout.contains('set-paused')) {
      throw StateError(
        'GPU Screen Recorder with pause IPC is required. Install version 6.1.7 or newer.',
      );
    }
    if (cancelled) throw const RecordingStartCancelled();

    await _checkAudioDevices(launch, options);
    if (cancelled) throw const RecordingStartCancelled();
    final parent = await Directory(directory).create(recursive: true);
    final staging = await parent.createTemp('.remya-recording-');
    Directory? runtime;
    RecordingRun? run;
    try {
      runtime = await Directory(runtimePath).createTemp('remya-gsr-');
      if (cancelled) throw const RecordingStartCancelled();
      final process = await launch('gpu-screen-recorder', [
        ...captureArguments,
        '-f',
        '60',
        '-fm',
        'cfr',
        '-k',
        'h264',
        '-fallback-cpu-encoding',
        'yes',
        '-ac',
        'aac',
        if (options.systemAudio) ...['-a', 'default_output'],
        if (options.microphone) ...['-a', 'default_input'],
        '-cursor',
        options.cursor ? 'yes' : 'no',
        '-exclude-metadata',
        'yes',
        '-v',
        'no',
        '-write-first-frame-ts',
        'yes',
        '-ipc',
        '${runtime.path}/gsr.sock',
        '-o',
        '${staging.path}/recording.mkv',
      ]);
      run = RecordingRun._(process, staging, runtime, launch, options);
      await run._waitForFirstFrame(() => cancelled);
      return run;
    } on ProcessException catch (error) {
      throw _launchError(error);
    } catch (error) {
      if (run != null) {
        await run._endProcess(useIpc: false);
        if (await run._mightHaveVideo()) {
          final saved = await run.finished;
          if (error is RecordingStartCancelled) {
            throw RecordingStartCancelled(recording: saved);
          }
          throw StateError(
            '$error\nSaved the frames already recorded to ${saved.path}.',
          );
        }
      }
      rethrow;
    } finally {
      if (run == null || run._firstFrame == null) {
        await _removeDirectory(runtime);
        if (run == null || !await run._mightHaveVideo()) {
          await _removeDirectory(staging);
        }
      }
    }
  }

  Future<void> _waitForFirstFrame(bool Function() isCancelled) async {
    final timestamp = File('${_video.path}.ts');
    final startup = Stopwatch()..start();
    while (_exitCode == null && startup.elapsed < const Duration(seconds: 12)) {
      if (isCancelled()) throw const RecordingStartCancelled();
      final stamp = await _readFirstFrame(timestamp);
      if (stamp != null) {
        if (isCancelled()) throw const RecordingStartCancelled();
        if (_exitCode != null) break;
        _firstFrame = stamp;
        final offset = DateTime.now().difference(stamp);
        if (!offset.isNegative && offset <= startup.elapsed) {
          _initialElapsed = offset;
        }
        _clock.start();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_exitCode != null) await _exit;
    if (isCancelled()) throw const RecordingStartCancelled();
    final detail = _diagnostics.trim();
    throw StateError(
      'GPU Screen Recorder did not produce a frame.'
      '${detail.isEmpty ? '' : '\n$detail'}',
    );
  }

  static Future<DateTime?> _readFirstFrame(File timestamp) async {
    try {
      final lines = const LineSplitter().convert(
        await timestamp.readAsString(),
      );
      if (lines.length < 2) return null;
      final values = lines[1].trim().split(RegExp(r'\s+'));
      if (values.length != 2 || int.tryParse(values[0]) == null) return null;
      final micros = int.tryParse(values[1]);
      return micros == null || micros <= 0
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(micros);
    } on FileSystemException {
      return null;
    }
  }

  Future<void> setPaused(bool value) {
    final request = _controls.then((_) async {
      if (_stop != null || _exitCode != null || paused == value) return;
      await _checked(_launch, 'gsr-cli', [
        '-ipc',
        _socket,
        'set-paused',
        '$value',
      ]);
      if (_exitCode != null) return;
      if (value) {
        _clock.stop();
      } else {
        _clock.start();
      }
    });
    _controls = request.then((_) {}, onError: (Object _, StackTrace _) {});
    return request;
  }

  Future<RecordingResult> stop() => _stop ??= _stopAndWait();

  Future<RecordingResult> _stopAndWait() async {
    await _controls;
    await _endProcess(useIpc: true);
    return finished;
  }

  Future<void> _endProcess({required bool useIpc}) async {
    if (_exitCode != null) return;
    if (useIpc) {
      try {
        await _checked(_launch, 'gsr-cli', [
          '-ipc',
          _socket,
          'stop',
        ], timeout: const Duration(seconds: 12));
      } on StateError {
        _stopWarning = 'The recorder did not acknowledge Stop.';
      }
    }
    if (!useIpc || _stopWarning != null) _process.kill(.sigint);
    try {
      await _exit.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      _stopWarning = 'The recorder had to be terminated.';
      _process.kill(.sigterm);
      try {
        await _exit.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        _process.kill(.sigkill);
        await _exit;
      }
    }
  }

  Future<bool> _mightHaveVideo() async {
    try {
      return await _video.length() > 0;
    } on FileSystemException catch (error) {
      // An I/O failure does not establish that the file can be discarded.
      return error.osError?.errorCode != 2;
    }
  }

  Future<RecordingResult> _finalize(int exitCode) async {
    final warnings = [
      ?_stopWarning,
      if (_stop == null || exitCode != 0)
        'The recorder ended unexpectedly (exit $exitCode).',
    ];
    try {
      if (!await _mightHaveVideo()) {
        final detail = _diagnostics.trim();
        throw StateError(
          'No recording was saved.'
          '${detail.isEmpty ? '' : '\n$detail'}',
        );
      }
      final probe = await _checked(_launch, 'ffprobe', [
        '-v',
        'error',
        '-read_intervals',
        '%+1',
        '-count_packets',
        '-show_entries',
        'stream=codec_type,nb_read_packets',
        '-of',
        'json',
        _video.path,
      ]);
      final media = jsonDecode(probe.stdout) as Map<String, dynamic>;
      final streams = (media['streams'] as List<dynamic>)
          .whereType<Map<String, dynamic>>();
      if (!streams.any(
        (stream) =>
            stream['codec_type'] == 'video' &&
            (int.tryParse('${stream['nb_read_packets']}') ?? 0) > 0,
      )) {
        throw StateError('The recording contains no readable video packets.');
      }
      final tracks = streams
          .where((stream) => stream['codec_type'] == 'audio')
          .length;
      final expected =
          (options.systemAudio ? 1 : 0) + (options.microphone ? 1 : 0);
      if (tracks != expected) {
        warnings.add(
          'The recorder produced $tracks of $expected requested audio tracks.',
        );
      }
      // GSR adds one stream per -a, in argument order, including silent devices.
      final systemAudio = options.systemAudio && tracks == expected;
      final microphone = options.microphone && tracks == expected;
      final file = await _video.open(mode: .append);
      try {
        await file.flush();
      } finally {
        await file.close();
      }
      final path = await _publish();
      return RecordingResult(
        path: path,
        systemAudio: systemAudio,
        microphone: microphone,
        warning: warnings.isEmpty ? null : warnings.join(' '),
      );
    } catch (error) {
      if (await _mightHaveVideo()) {
        throw StateError('$error\nRecovery file: ${_video.path}');
      }
      rethrow;
    } finally {
      await _removeDirectory(_runtime);
      if (!await _mightHaveVideo()) await _removeDirectory(_staging);
    }
  }

  Future<String> _publish() async {
    final time = (_firstFrame ?? DateTime.now()).toLocal().toIso8601String();
    final name =
        'Recording_${time.substring(0, 19).replaceFirst('T', '_').replaceAll(':', '-')}';
    for (var index = 0; index < 10000; index++) {
      final suffix = index == 0 ? '' : ' ($index)';
      final target = '${_staging.parent.path}/$name$suffix.mkv';
      final result = await _command(_launch, 'mv', [
        '-T',
        '-n',
        '--',
        _video.path,
        target,
      ]);
      if (!await _video.exists()) return target;
      if (await FileSystemEntity.type(target, followLinks: false) ==
          .notFound) {
        throw StateError(
          'Could not save the recording. ${result.stderr.trim()}',
        );
      }
    }
    throw StateError('Could not find an unused recording name.');
  }

  static Future<void> _checkAudioDevices(
    RecordingProcessLauncher launch,
    RecordingOptions options,
  ) async {
    if (!options.systemAudio && !options.microphone) return;
    final result = await _checked(launch, 'gpu-screen-recorder', [
      '--list-audio-devices',
    ]);
    final devices = const LineSplitter()
        .convert(result.stdout)
        .map((line) => line.split('|').first.trim())
        .toSet();
    final unavailable = [
      if (options.systemAudio && !devices.contains('default_output'))
        'system audio',
      if (options.microphone && !devices.contains('default_input'))
        'microphone',
    ];
    if (unavailable.isNotEmpty) {
      throw StateError(
        'No default device for ${unavailable.join(' or ')}. Select a device in system settings or disable its recording switch.',
      );
    }
  }
}

typedef _CommandResult = ({int exitCode, String stdout, String stderr});

Future<_CommandResult> _command(
  RecordingProcessLauncher launch,
  String program,
  List<String> args, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final Process process;
  try {
    process = await launch(program, args);
  } on ProcessException catch (error) {
    throw _launchError(error);
  }
  process.stdin.close().ignore();
  const decoder = Utf8Decoder(allowMalformed: true);
  final output = process.stdout.transform(decoder).join();
  final error = process.stderr.transform(decoder).join();
  try {
    final (exitCode, stdout, stderr) = await (
      process.exitCode,
      output,
      error,
    ).wait.timeout(timeout);
    return (exitCode: exitCode, stdout: stdout, stderr: stderr);
  } on TimeoutException {
    process.kill(.sigkill);
    throw StateError('$program did not respond in time.');
  }
}

Future<_CommandResult> _checked(
  RecordingProcessLauncher launch,
  String program,
  List<String> args, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final result = await _command(launch, program, args, timeout: timeout);
  if (result.exitCode != 0) {
    throw StateError(
      '$program exited with ${result.exitCode}. ${result.stderr.trim()}',
    );
  }
  return result;
}

StateError _launchError(ProcessException error) => StateError(
  'Could not run ${error.executable}. Install the required recording tools and check their permissions. ${error.message}',
);

Future<void> _removeDirectory(Directory? directory) async {
  try {
    await directory?.delete(recursive: true);
  } on FileSystemException {
    // Cleanup failure must preserve the recording result.
  }
}
