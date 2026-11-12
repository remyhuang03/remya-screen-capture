import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_screen_capture/features/video_editor/video_media.dart';

void main() {
  test('dragging trim creates one undo entry and preserves a frame', () {
    final trim = VideoTrim(
      const Duration(seconds: 10),
      const Duration(milliseconds: 40),
    );
    trim.startDrag();
    trim.move(start: true, position: const Duration(seconds: 2));
    trim.move(start: true, position: const Duration(seconds: 3));
    trim.finishDrag();
    expect(trim.range.start, const Duration(seconds: 3));
    trim.undo();
    expect(trim.range.start, Duration.zero);
    expect(trim.canUndo, false);
    trim.redo();
    trim.move(start: false, position: const Duration(seconds: 1));
    expect(trim.range.end - trim.range.start, trim.minimum);
    trim.reset();
    expect(trim.range, (start: Duration.zero, end: trim.duration));
  });

  group('FFmpeg integration', () {
    late Directory directory;
    late File source;
    late VideoMedia media;
    VideoExportSettings settings(VideoFormat format, List<int> tracks) =>
        VideoExportSettings(
          format: format,
          range: (
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 3),
          ),
          speed: 1.5,
          size: (width: 96, height: 54),
          fps: 24,
          audioTracks: tracks,
        );

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('remya-video-test-');
      source = File("${directory.path}/Source's video.mkv");
      final fixture = await Process.run('ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'lavfi',
        '-i',
        'testsrc2=duration=4:size=128x72:rate=30,'
            "drawbox=x=0:y=0:w=iw:h=ih:color=red:t=fill:enable='lt(t,1)',"
            "drawbox=x=0:y=0:w=iw:h=ih:color=green:t=fill:enable='gte(t,1)*lt(t,3)',"
            "drawbox=x=0:y=0:w=iw:h=ih:color=blue:t=fill:enable='gte(t,3)'",
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:duration=4',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=880:duration=4',
        '-map',
        '0:v',
        '-map',
        '1:a',
        '-map',
        '2:a',
        '-c:v',
        'libx264',
        '-g',
        '120',
        '-threads',
        '2',
        '-c:a',
        'aac',
        source.path,
      ]);
      expect(fixture.exitCode, 0, reason: fixture.stderr as String);
      media = await VideoMedia.probe(source.path);
      expect(media.audioTracks, hasLength(2));
    });

    tearDownAll(() => directory.delete(recursive: true));

    for (final format in VideoFormat.values) {
      test(
        '${format.label} trims, resizes and exports at the selected speed',
        () async {
          final output = File('${directory.path}/mixed.${format.extension}');
          final progress = <double>[];
          final configuration = settings(format, media.audioTracks);
          final exported = await VideoExport().run(
            source: source.path,
            destination: output.path,
            replace: false,
            settings: configuration,
            onProgress: progress.add,
          );
          expect(exported, true);
          expect(progress.last, 1);
          final result = await VideoMedia.probe(output.path);
          expect((result.width, result.height), (96, 54));
          expect(
            result.duration.inMilliseconds,
            closeTo(configuration.duration.inMilliseconds, 100),
          );
          expect(result.audioTracks, hasLength(format == .gif ? 0 : 1));
          if (format == .mp4) {
            final frame = await _readMediaBytes(output.path, [
              '-frames:v',
              '1',
              '-vf',
              'scale=1:1',
              '-pix_fmt',
              'rgb24',
              '-f',
              'rawvideo',
            ]);
            expect(frame[1], greaterThan(frame[0] + 60));
            expect(frame[1], greaterThan(frame[2] + 60));
            final audio = await _readAudio(output.path);
            expect(_amplitude(audio, 440), greaterThan(700));
            expect(_amplitude(audio, 880), greaterThan(700));
          }
        },
      );
    }

    test('selecting the microphone exports only its tone', () async {
      final destination = '${directory.path}/microphone.mp4';
      await VideoExport().run(
        source: source.path,
        destination: destination,
        replace: false,
        settings: settings(.mp4, [media.audioTracks[1]]),
        onProgress: (_) {},
      );
      final audio = await _readAudio(destination);
      expect(_amplitude(audio, 880), greaterThan(1000));
      expect(_amplitude(audio, 440), lessThan(100));
    });

    test('cancel and output collision preserve existing files', () async {
      final destination = File('${directory.path}/existing.mp4');
      await destination.writeAsString('previous export');
      final originalSize = await source.length();
      final export = VideoExport();
      expect(
        await export.run(
          source: source.path,
          destination: destination.path,
          replace: true,
          settings: settings(.mp4, []),
          onProgress: (_) => export.cancel(),
        ),
        false,
      );
      await expectLater(
        VideoExport().run(
          source: source.path,
          destination: destination.path,
          replace: false,
          settings: settings(.mp4, []),
          onProgress: (_) {},
        ),
        throwsStateError,
      );
      await expectLater(
        VideoExport().run(
          source: source.path,
          destination: source.path,
          replace: true,
          settings: settings(.mkv, []),
          onProgress: (_) {},
        ),
        throwsStateError,
      );
      expect(await source.length(), originalSize);
      expect(await destination.readAsString(), 'previous export');
      expect(
        directory.listSync().any(
          (entity) => entity.uri.pathSegments.any(
            (segment) => segment.startsWith('.remya-export-'),
          ),
        ),
        false,
      );
    });

    test('timeline samples are JPEG frames from the recording', () async {
      final frames = await VideoThumbnails()
          .sample(source.path, media.duration, 3)
          .toList();
      expect(frames, hasLength(3));
      for (final frame in frames) {
        expect(frame?.sublist(0, 2), [0xff, 0xd8]);
      }
    });
  });
}

Future<Uint8List> _readMediaBytes(String path, List<String> options) async {
  final result = await Process.run('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-i',
    path,
    ...options,
    'pipe:1',
  ], stdoutEncoding: null);
  expect(result.exitCode, 0, reason: result.stderr as String);
  return result.stdout as Uint8List;
}

Future<ByteData> _readAudio(String path) async {
  final bytes = await _readMediaBytes(path, [
    '-vn',
    '-ac',
    '1',
    '-ar',
    '8000',
    '-f',
    's16le',
  ]);
  return ByteData.sublistView(bytes);
}

double _amplitude(ByteData audio, int frequency) {
  var sine = 0.0;
  var cosine = 0.0;
  const count = 4000;
  for (var index = 0; index < count; index++) {
    final sample = audio.getInt16((index + 800) * 2, Endian.little);
    final phase = 2 * math.pi * frequency * index / 8000;
    sine += sample * math.sin(phase);
    cosine += sample * math.cos(phase);
  }
  return math.sqrt(sine * sine + cosine * cosine) * 2 / count;
}
