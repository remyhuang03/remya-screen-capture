part of 'recording_backend.dart';

class _RecordingAudio {
  _RecordingAudio(RecordingProcessLauncher launch, String name)
    : system = _RecordingAudioTrack(launch, '${name}_system', true),
      mic = _RecordingAudioTrack(launch, '${name}_mic', false);

  final _RecordingAudioTrack system;
  final _RecordingAudioTrack mic;

  static Future<_RecordingAudio?> tryStart(
    RecordingProcessLauncher launch,
    Directory runtime,
    RecordingOptions options,
  ) async {
    try {
      final server = await _checked(launch, 'pactl', ['info']);
      if (!server.stdout.contains('PipeWire')) return null;
      await _checked(launch, 'pw-loopback', ['--version']);
      await _checked(launch, 'pw-link', ['--version']);
    } on StateError {
      return null;
    }

    final name = runtime.path.split('/').last.replaceAll('-', '_');
    final audio = _RecordingAudio(launch, name);
    try {
      await audio.system.start();
      await audio.mic.start();
      final ready = Stopwatch()..start();
      while (audio.system.available &&
          audio.mic.available &&
          ready.elapsed < const Duration(seconds: 2)) {
        final devices = await _listAudioDevices(launch);
        if (devices.contains(audio.system.name) &&
            devices.contains(audio.mic.name)) {
          await audio.system.setEnabled(options.systemAudio);
          await audio.mic.setEnabled(options.microphone);
          return audio;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      throw StateError('The recording audio sources did not start.');
    } on StateError {
      await audio.close();
      return null;
    }
  }

  Future<void> close() async => Future.wait([system.close(), mic.close()]);
}

class _RecordingAudioTrack {
  _RecordingAudioTrack(this._launch, this.name, this._system);

  final RecordingProcessLauncher _launch;
  final String name;
  final bool _system;
  Process? _source;
  Future<void>? _closing;
  List<(String, String)> _links = [];
  bool wasEnabled = false;

  bool get available => _source != null && _closing == null;
  bool get enabled => available && _links.isNotEmpty;

  Future<void> start() async {
    // The disconnected input produces silence without opening a real device.
    final Process process;
    try {
      process = await _launch('pw-loopback', [
        '-n',
        name,
        '-i',
        'node.name=$name.in node.autoconnect=false',
        '-o',
        'node.name=$name media.class=Audio/Source node.virtual=true priority.session=0',
      ]);
    } on ProcessException catch (error) {
      throw _launchError(error);
    }
    _source = process;
    process.stdin.close().ignore();
    process.stdout.drain<void>().ignore();
    process.stderr.drain<void>().ignore();
    process.exitCode.then((_) => _source = null).ignore();
  }

  Future<void> setEnabled(bool value) async {
    if (!available) throw StateError('The recording audio source stopped.');
    if (value == enabled) return;
    final pairs = value ? await _deviceLinks() : _links;
    try {
      for (final (output, input) in pairs) {
        final command = await _command(_launch, 'pw-link', [
          value ? '-w' : '-d',
          output,
          input,
        ]);
        if (command.exitCode == 0) continue;
        if (!value && !(await _outputPorts()).contains(output)) continue;
        throw StateError(
          'Could not change the recording audio link. ${command.stderr.trim()}',
        );
      }
      _links = value ? pairs : [];
      wasEnabled = wasEnabled || value;
    } catch (_) {
      // Removing the private source also removes any links left by a failure.
      await close();
      rethrow;
    }
  }

  Future<List<(String, String)>> _deviceLinks() async {
    final device = await _checked(_launch, 'pactl', [
      _system ? 'get-default-sink' : 'get-default-source',
    ]);
    var node = device.stdout.trim();
    final monitor = _system || node.endsWith('.monitor');
    if (!_system && monitor) {
      node = node.substring(0, node.length - '.monitor'.length);
    }
    final prefix = '$node:${monitor ? 'monitor' : 'capture'}_';
    final outputs = (await _outputPorts())
        .where((port) => port.startsWith(prefix))
        .toList();
    if (outputs.isEmpty || node.startsWith('remya_gsr_')) {
      throw StateError(
        _system ? 'No default system audio device.' : 'No default microphone.',
      );
    }
    return [
      (
        outputs.firstWhere(
          (port) => port == '${prefix}FL',
          orElse: () => outputs.first,
        ),
        '$name.in:input_FL',
      ),
      (
        outputs.firstWhere(
          (port) => port == '${prefix}FR',
          orElse: () => outputs.length == 1 ? outputs.first : outputs[1],
        ),
        '$name.in:input_FR',
      ),
    ];
  }

  Future<Iterable<String>> _outputPorts() async {
    final result = await _checked(_launch, 'pw-link', ['-o']);
    return const LineSplitter()
        .convert(result.stdout)
        .map((line) => line.trim());
  }

  Future<void> close() => _closing ??= _stopSource();

  Future<void> _stopSource() async {
    final process = _source;
    if (process == null) return;
    process.kill(.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      process.kill(.sigkill);
      await process.exitCode;
    }
  }
}
