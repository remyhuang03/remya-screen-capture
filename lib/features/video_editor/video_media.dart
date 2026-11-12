import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class VideoMedia {
  const VideoMedia({
    required this.duration,
    required this.width,
    required this.height,
    required this.fps,
    required this.videoBitRate,
    required this.audioTracks,
  });

  final Duration duration;
  final int width;
  final int height;
  final double fps;
  final int videoBitRate;
  final List<int> audioTracks;

  Duration get frameDuration =>
      Duration(microseconds: (Duration.microsecondsPerSecond / fps).round());

  static Future<VideoMedia> probe(String path) async {
    final result = await Process.run('ffprobe', [
      '-v',
      'error',
      '-show_streams',
      '-show_format',
      '-of',
      'json',
      path,
    ]);
    if (result.exitCode != 0) {
      throw StateError('Could not read video details. ${result.stderr}'.trim());
    }
    final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final streams = (data['streams'] as List).cast<Map<String, dynamic>>();
    final video = streams.firstWhere((track) => track['codec_type'] == 'video');
    final format = data['format'] as Map<String, dynamic>;
    final seconds = double.tryParse(format['duration']?.toString() ?? '');
    final width = video['width'] as int;
    final height = video['height'] as int;
    final fps = _rate(video['avg_frame_rate']) ?? _rate(video['r_frame_rate']);
    if (seconds == null ||
        !seconds.isFinite ||
        seconds <= 0 ||
        width <= 0 ||
        height <= 0 ||
        fps == null) {
      throw StateError('The recording has incomplete video metadata.');
    }
    final audioTracks = streams.where(
      (track) => track['codec_type'] == 'audio',
    );
    final containerRate = int.tryParse(format['bit_rate']?.toString() ?? '');
    final streamRate = int.tryParse(video['bit_rate']?.toString() ?? '');
    final audioRate = audioTracks.fold(
      0,
      (rate, track) =>
          rate + (int.tryParse(track['bit_rate']?.toString() ?? '') ?? 160000),
    );
    return VideoMedia(
      duration: Duration(
        microseconds: (seconds * Duration.microsecondsPerSecond).round(),
      ),
      width: width,
      height: height,
      fps: fps,
      videoBitRate: math.max(
        1000,
        streamRate ?? (containerRate ?? 0) - audioRate,
      ),
      audioTracks: [for (final track in audioTracks) track['index'] as int],
    );
  }

  static double? _rate(Object? value) {
    final parts = value?.toString().split('/');
    if (parts == null || parts.length != 2) return null;
    final numerator = double.tryParse(parts[0]);
    final denominator = double.tryParse(parts[1]);
    if (numerator == null || denominator == null) return null;
    final rate = numerator / denominator;
    return rate.isFinite && rate > 0 ? rate : null;
  }
}

enum VideoFormat {
  mp4('MP4', 'H.264', 'AAC'),
  webm('WebM', 'VP9', 'Opus'),
  gif('GIF', 'GIF', null),
  mkv('MKV', 'H.264', 'AAC');

  const VideoFormat(this.label, this.videoCodec, this.audioCodec);
  final String label;
  final String videoCodec;
  final String? audioCodec;

  String get extension => name;
}

typedef VideoRange = ({Duration start, Duration end});
typedef VideoSize = ({int width, int height});

class VideoExportSettings {
  const VideoExportSettings({
    required this.format,
    required this.range,
    required this.speed,
    required this.size,
    required this.fps,
    required this.audioTracks,
  });

  final VideoFormat format;
  final VideoRange range;
  final double speed;
  final VideoSize size;
  final double fps;
  final List<int> audioTracks;

  Duration get duration => Duration(
    microseconds: ((range.end - range.start).inMicroseconds / speed).round(),
  );

  int estimateBytes(VideoMedia media) {
    final pixelRatio = size.width * size.height / (media.width * media.height);
    final frameRatio = fps / media.fps;
    final videoRate = switch (format) {
      .gif => size.width * size.height * fps * 0.75,
      .webm => media.videoBitRate * pixelRatio * frameRatio * 0.8,
      _ => media.videoBitRate * pixelRatio * frameRatio,
    };
    final audioRate = format.audioCodec != null && audioTracks.isNotEmpty
        ? 160000
        : 0;
    return ((videoRate + audioRate) * duration.inMilliseconds / 8000).round();
  }
}

class VideoExport {
  Process? _process;
  bool _cancelled = false;
  bool _publishing = false;

  bool get cancellable => !_cancelled && !_publishing;

  void cancel() {
    if (_publishing) return;
    _cancelled = true;
    _process?.kill(.sigkill);
  }

  Future<bool> run({
    required String source,
    required String destination,
    required bool replace,
    required VideoExportSettings settings,
    required void Function(double) onProgress,
  }) async {
    final output = File(destination);
    if (await FileSystemEntity.type(destination) != .notFound &&
        await FileSystemEntity.identical(source, destination)) {
      throw StateError('Choose an export path different from the original.');
    }
    final work = await output.parent.createTemp('.remya-export-');
    try {
      if (_cancelled) return false;
      final staged = '${work.path}/export.${settings.format.extension}';
      String? palette;
      if (settings.format == .gif) {
        palette = '${work.path}/palette.png';
        // A separate palette pass keeps long GIF exports from buffering every frame.
        await _encode([
          ..._inputArguments(source, settings.range),
          '-filter_threads',
          '2',
          '-vf',
          '${_videoFilter(settings)},palettegen=stats_mode=diff',
          '-frames:v',
          '1',
          '-update',
          '1',
          palette,
        ]);
        if (_cancelled) return false;
        onProgress(0.4);
      }
      final phaseStart = palette == null ? 0.0 : 0.4;
      await _encode(
        _exportArguments(source, staged, settings, palette: palette),
        onTime: (micros) {
          final fraction = (micros / settings.duration.inMicroseconds).clamp(
            0.0,
            1.0,
          );
          onProgress(phaseStart + fraction * (0.99 - phaseStart));
        },
      );
      if (_cancelled) return false;
      final result = await VideoMedia.probe(staged);
      if (_cancelled) return false;
      final expectedTracks =
          settings.format.audioCodec != null && settings.audioTracks.isNotEmpty
          ? 1
          : 0;
      if (result.width != settings.size.width ||
          result.height != settings.size.height ||
          result.audioTracks.length != expectedTracks) {
        throw StateError('The exported video has unexpected media streams.');
      }
      final durationTolerance = math.max(
        150000,
        result.frameDuration.inMicroseconds,
      );
      if ((result.duration - settings.duration).inMicroseconds.abs() >
          durationTolerance) {
        throw StateError('The exported video has an unexpected duration.');
      }
      final completedFile = await File(staged).open(mode: .append);
      try {
        await completedFile.flush();
      } finally {
        await completedFile.close();
      }
      if (_cancelled) return false;
      _publishing = true;
      if (replace) {
        if (await FileSystemEntity.type(destination) != .notFound &&
            await FileSystemEntity.identical(source, destination)) {
          throw StateError(
            'Choose an export path different from the original.',
          );
        }
        await File(staged).rename(destination);
      } else {
        final move = await Process.run('mv', [
          '-T',
          '-n',
          '--',
          staged,
          destination,
        ]);
        if (move.exitCode != 0 || await File(staged).exists()) {
          final detail = (move.stderr as String).trim();
          throw StateError(
            detail.isEmpty
                ? 'The export path already exists.'
                : 'Could not save the export. $detail',
          );
        }
      }
      onProgress(1);
      return true;
    } finally {
      _process = null;
      await work.delete(recursive: true);
    }
  }

  Future<void> _encode(
    List<String> arguments, {
    void Function(int)? onTime,
  }) async {
    if (_cancelled) return;
    final process = _process = await Process.start('ffmpeg', [
      '-hide_banner',
      '-loglevel',
      'error',
      '-nostdin',
      '-nostats',
      if (onTime != null) ...['-progress', 'pipe:1'],
      ...arguments,
    ]);
    if (_cancelled) process.kill(.sigkill);
    final errors = process.stderr.transform(utf8.decoder).join();
    await for (final line
        in process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (onTime != null && line.startsWith('out_time_us=')) {
        final micros = int.tryParse(line.substring('out_time_us='.length));
        if (micros != null) onTime(micros);
      }
    }
    final exit = await process.exitCode;
    _process = null;
    final stderr = await errors;
    if (!_cancelled && exit != 0) {
      final detail = stderr.contains('Unknown encoder')
          ? 'Install an FFmpeg build with the required encoder. $stderr'
          : stderr;
      throw StateError('FFmpeg could not export this video. $detail'.trim());
    }
  }
}

List<String> _exportArguments(
  String source,
  String output,
  VideoExportSettings settings, {
  required String? palette,
}) {
  final speed = settings.speed;
  final audio = palette == null && settings.audioTracks.isNotEmpty;
  final videoFilter = _videoFilter(settings);
  final audioInputs = settings.audioTracks.map((track) => '[0:$track]').join();
  final audioFilter = settings.audioTracks.length == 1
      ? '${audioInputs}atempo=$speed[a]'
      : '${audioInputs}amix=inputs=${settings.audioTracks.length}:duration=longest,atempo=$speed[a]';
  return [
    ..._inputArguments(source, settings.range),
    if (palette != null) ...['-i', palette],
    '-filter_complex_threads',
    '2',
    '-filter_complex',
    [
      if (palette != null)
        '[0:v:0]$videoFilter[frames];[frames][1:v:0]paletteuse[v]'
      else
        '[0:v:0]$videoFilter[v]',
      if (audio) audioFilter,
    ].join(';'),
    '-map',
    '[v]',
    if (audio) ...['-map', '[a]'],
    '-map_metadata',
    '-1',
    '-map_chapters',
    '-1',
    ...switch (settings.format) {
      .gif => ['-loop', '0'],
      .webm => [
        '-c:v',
        'libvpx-vp9',
        '-crf',
        '31',
        '-b:v',
        '0',
        '-row-mt',
        '1',
        '-pix_fmt',
        'yuv420p',
        if (audio) ...['-c:a', 'libopus', '-b:a', '160k'],
      ],
      .mp4 || .mkv => [
        '-c:v',
        'libx264',
        '-crf',
        '20',
        '-preset',
        'veryfast',
        '-pix_fmt',
        'yuv420p',
        if (audio) ...['-c:a', 'aac', '-b:a', '160k'],
        if (settings.format == .mp4) ...['-movflags', '+faststart'],
      ],
    },
    output,
  ];
}

List<String> _inputArguments(String source, VideoRange range) => [
  '-ss',
  _seconds(range.start),
  '-t',
  _seconds(range.end - range.start),
  '-i',
  source,
];

String _videoFilter(VideoExportSettings settings) =>
    'setpts=PTS/${settings.speed},fps=${settings.fps}:eof_action=pass,'
    'scale=${settings.size.width}:${settings.size.height}:flags=lanczos,setsar=1';

String _seconds(Duration value) =>
    (value.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(6);

class VideoThumbnails {
  Process? _process;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _process?.kill(.sigkill);
  }

  Stream<Uint8List?> sample(String path, Duration duration, int count) async* {
    for (var index = 0; index < count && !_cancelled; index++) {
      final position = duration * (index / count);
      final process = _process = await Process.start('ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        '-nostdin',
        '-ss',
        _seconds(position),
        '-threads',
        '2',
        '-i',
        path,
        '-frames:v',
        '1',
        '-vf',
        'scale=180:102:force_original_aspect_ratio=decrease',
        '-threads',
        '1',
        '-f',
        'image2pipe',
        '-c:v',
        'mjpeg',
        'pipe:1',
      ]);
      if (_cancelled) process.kill(.sigkill);
      final drainErrors = process.stderr.drain<void>();
      final bytes = await process.stdout.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (builder, chunk) => builder..add(chunk),
      );
      final exit = await process.exitCode;
      _process = null;
      await drainErrors;
      if (!_cancelled) {
        yield exit == 0 && bytes.length > 0 ? bytes.takeBytes() : null;
      }
    }
  }
}

class VideoTrim {
  VideoTrim(this.duration, Duration frame)
    : minimum = frame > duration ? duration : frame,
      range = (start: Duration.zero, end: duration);

  final Duration duration;
  final Duration minimum;
  VideoRange range;
  final _undo = <VideoRange>[];
  final _redo = <VideoRange>[];
  VideoRange? _beforeDrag;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void startDrag() => _beforeDrag ??= range;

  void finishDrag() {
    final previous = _beforeDrag;
    _beforeDrag = null;
    if (previous != null) _record(previous);
  }

  void move({required bool start, required Duration position}) {
    final previous = range;
    if (start) {
      final latest = range.end - minimum;
      range = (
        start: _boundTime(position, Duration.zero, latest),
        end: range.end,
      );
    } else {
      final earliest = range.start + minimum;
      range = (
        start: range.start,
        end: _boundTime(position, earliest, duration),
      );
    }
    if (_beforeDrag == null) _record(previous);
  }

  void reset() {
    final previous = range;
    range = (start: Duration.zero, end: duration);
    _record(previous);
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(range);
    range = _undo.removeLast();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(range);
    range = _redo.removeLast();
  }

  void _record(VideoRange previous) {
    if (previous == range) return;
    _undo.add(previous);
    _redo.clear();
  }
}

Duration _boundTime(Duration value, Duration first, Duration last) => Duration(
  microseconds: value.inMicroseconds.clamp(
    first.inMicroseconds,
    last.inMicroseconds,
  ),
);
