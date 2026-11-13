import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../capture_controls/capture_buttons.dart';
import '../capture_controls/capture_icon.dart';
import 'video_media.dart';

part 'video_editor_timeline.dart';
part 'video_export_panel.dart';

class VideoEditor extends StatefulWidget {
  const VideoEditor({
    super.key,
    required this.path,
    required this.systemAudio,
    required this.microphone,
    this.warning,
    required this.onClose,
    required this.closeRequests,
    required this.onMoveWindow,
  });

  final String path;
  final bool systemAudio;
  final bool microphone;
  final String? warning;
  final VoidCallback onClose;
  final Listenable closeRequests;
  final VoidCallback onMoveWindow;

  @override
  State<VideoEditor> createState() => _VideoEditorState();
}

class _VideoEditorState extends State<VideoEditor> {
  final _thumbnails = VideoThumbnails();
  final _frames = List<Uint8List?>.filled(8, null);
  final _progress = ValueNotifier<double>(0);
  final _position = ValueNotifier(Duration.zero);
  final _playing = ValueNotifier(false);
  final _playerSubscriptions = <StreamSubscription<dynamic>>[];
  Player? _player;
  VideoController? _video;
  VideoMedia? _media;
  VideoTrim? _trim;
  String? _error;
  String? _previewError;
  String? _destination;
  VideoExport? _export;
  Future<void>? _exportDone;
  VideoFormat _format = .mp4;
  double _previewSpeed = 1;
  double _exportSpeed = 1;
  int _height = 0;
  double _fps = 0;
  bool _muted = false;
  bool _systemAudio = false;
  bool _microphone = false;
  bool _closing = false;
  bool _ready = false;
  bool _scrubbing = false;
  bool _atEnd = false;
  bool _transportBusy = false;
  bool _choosingFile = false;

  File get _file => File(widget.path);
  String get _fileName => _file.uri.pathSegments.last;
  String get _title => _fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
  String get _defaultDestination =>
      '${_file.parent.path}/${_title}_edited.${_format.extension}';
  int? get _systemTrack =>
      widget.systemAudio ? _media?.audioTracks.firstOrNull : null;
  int? get _microphoneTrack => widget.microphone
      ? _media?.audioTracks.elementAtOrNull(widget.systemAudio ? 1 : 0)
      : null;

  @override
  void initState() {
    super.initState();
    widget.closeRequests.addListener(_requestClose);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final media = await VideoMedia.probe(widget.path);
      if (!mounted) return;
      setState(() {
        _media = media;
        _trim = VideoTrim(media.duration, media.frameDuration);
        _systemAudio = _systemTrack != null;
        _microphone = _microphoneTrack != null;
      });
      unawaited(_loadThumbnails(media));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
      return;
    }

    try {
      MediaKit.ensureInitialized();
    } catch (error) {
      if (mounted) setState(() => _previewError = _message(error));
      return;
    }
    for (final hardware in [true, false]) {
      if (!mounted) return;
      final player = Player();
      try {
        final video = VideoController(
          player,
          configuration: VideoControllerConfiguration(
            enableHardwareAcceleration: hardware,
            hwdec: hardware ? 'auto-safe' : 'no',
          ),
        );
        setState(() {
          _player = player;
          _video = video;
        });
        await player
            .open(Media(widget.path), play: false)
            .timeout(const Duration(seconds: 8));
        await video.waitUntilFirstFrameRendered.timeout(
          const Duration(seconds: 5),
        );
        if (!mounted) return;
        _playerSubscriptions.addAll([
          player.stream.playing.listen((playing) => _playing.value = playing),
          player.stream.position.listen(_updatePosition),
          player.stream.completed.listen((completed) {
            if (completed && mounted) {
              _atEnd = true;
              _position.value = _trim!.range.end;
            }
          }),
          player.stream.error.listen((error) {
            if (mounted) _notify(error);
          }),
        ]);
        setState(() => _ready = true);
        if (_previewSpeed != 1) await player.setRate(_previewSpeed);
        if (player.platform case final NativePlayer native
            when _systemTrack != null && _microphoneTrack != null) {
          await native.setProperty(
            'lavfi-complex',
            '[aid1][aid2]amix=inputs=2:duration=longest[ao]',
          );
        }
        return;
      } catch (error) {
        if (!mounted) return;
        if (_ready) return;
        setState(() {
          _player = null;
          _video = null;
          if (!hardware) _previewError = _message(error);
        });
        // A stalled native renderer must not block opening the software preview.
        unawaited(player.dispose().catchError((Object _) {}));
      }
    }
  }

  Future<void> _loadThumbnails(VideoMedia media) async {
    var index = 0;
    try {
      await for (final frame in _thumbnails.sample(
        widget.path,
        media.duration,
        _frames.length,
      )) {
        if (!mounted) return;
        final slot = index++;
        if (frame != null) setState(() => _frames[slot] = frame);
      }
    } on ProcessException {
      // Preview and export can still be used without timeline thumbnails.
    }
  }

  @override
  void dispose() {
    widget.closeRequests.removeListener(_requestClose);
    _thumbnails.cancel();
    _export?.cancel();
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    final player = _player;
    if (player != null) unawaited(player.dispose().catchError((Object _) {}));
    _playing.dispose();
    _position.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _updatePosition(Duration position) {
    if (!mounted || _scrubbing || _atEnd) return;
    final trim = _trim!;
    if (position >= trim.range.end && _playing.value) {
      _atEnd = true;
      _position.value = trim.range.end;
      final player = _player;
      if (player != null) unawaited(_pauseAtCut(player, trim.range.end));
      return;
    }
    _position.value = position;
  }

  Future<void> _pauseAtCut(Player player, Duration end) async {
    try {
      await player.pause();
      await player.seek(_lastPlayablePosition(end));
    } catch (error) {
      if (mounted) _notify('Playback error. ${_message(error)}');
    }
  }

  Duration _lastPlayablePosition(Duration position) {
    final media = _media!;
    return position >= media.duration && media.duration > media.frameDuration
        ? media.duration - media.frameDuration
        : position;
  }

  Future<void> _transport(Future<void> Function(Player) action) async {
    final player = _player;
    if (!_ready || player == null || _transportBusy) return;
    _transportBusy = true;
    try {
      await action(player);
    } catch (error) {
      if (mounted) _notify('Playback error. ${_message(error)}');
    } finally {
      _transportBusy = false;
    }
  }

  Future<void> _playPause() => _transport((player) async {
    if (_playing.value) {
      await player.pause();
      return;
    }
    final range = _trim!.range;
    if (_atEnd ||
        _position.value < range.start ||
        _position.value >= range.end) {
      _atEnd = false;
      await player.seek(range.start);
    }
    await player.play();
  });

  Future<void> _seek(Duration position) => _transport((player) async {
    _atEnd = false;
    await player.seek(_lastPlayablePosition(position));
  });

  Future<void> _skip(int seconds) {
    final range = _trim!.range;
    final requested = _position.value + Duration(seconds: seconds);
    return _seek(
      Duration(
        microseconds: requested.inMicroseconds.clamp(
          range.start.inMicroseconds,
          range.end.inMicroseconds,
        ),
      ),
    );
  }

  Future<void> _step({required bool forward}) => _transport((player) async {
    if (player.platform case final NativePlayer native) {
      _atEnd = false;
      if (_playing.value) await player.pause();
      await native.command([forward ? 'frame-step' : 'frame-back-step']);
    }
  });

  void _setSpeed(double speed) {
    setState(() {
      _previewSpeed = speed;
      if (speed >= 0.5 && speed <= 2) _exportSpeed = speed;
    });
    if (_player case final player? when _ready) {
      unawaited(_setPlayerOption(player.setRate(speed)));
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    if (_player case final player? when _ready) {
      unawaited(_setPlayerOption(player.setVolume(_muted ? 0 : 100)));
    }
  }

  Future<void> _setPlayerOption(Future<void> command) async {
    try {
      await command;
    } catch (error) {
      if (mounted) _notify('Playback error. ${_message(error)}');
    }
  }

  void _moveTrim(bool start, Duration position) {
    final player = _player;
    if (_playing.value && player != null) unawaited(player.pause());
    setState(() => _trim!.move(start: start, position: position));
  }

  void _finishTrimDrag() {
    setState(_trim!.finishDrag);
  }

  Future<void> _showFolder(String path) async {
    try {
      final uri = File(path).uri.toString();
      ProcessResult? result;
      try {
        final quoted = uri.replaceAll("'", r"\'");
        result = await Process.run('gdbus', [
          'call',
          '--session',
          '--timeout',
          '2',
          '--dest',
          'org.freedesktop.FileManager1',
          '--object-path',
          '/org/freedesktop/FileManager1',
          '--method',
          'org.freedesktop.FileManager1.ShowItems',
          "['$quoted']",
          "''",
        ]);
      } on ProcessException {
        // xdg-open also works when the file manager does not expose ShowItems.
      }
      if (result?.exitCode != 0) {
        final fallback = await Process.run('xdg-open', [
          File(path).parent.path,
        ]);
        if (fallback.exitCode != 0) throw StateError(fallback.stderr);
      }
    } catch (error) {
      if (mounted) _notify('Could not open the folder. ${_message(error)}');
    }
  }

  Future<void> _copyPath(String path) async {
    try {
      await Clipboard.setData(ClipboardData(text: path));
      if (mounted) _notify('Path copied');
    } catch (error) {
      if (mounted) _notify('Could not copy the path. ${_message(error)}');
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _chooseDestination() async {
    if (_choosingFile || _export != null) return;
    _choosingFile = true;
    try {
      final current = File(_destination ?? _defaultDestination);
      final location = await getSaveLocation(
        suggestedName: current.uri.pathSegments.last,
        initialDirectory: current.parent.path,
        acceptedTypeGroups: [
          XTypeGroup(label: _format.label, extensions: [_format.extension]),
        ],
      );
      if (!mounted || location == null) return;
      final path = location.path;
      final suffix = '.${_format.extension}';
      setState(
        () => _destination = path.toLowerCase().endsWith(suffix)
            ? path
            : '$path$suffix',
      );
    } catch (error) {
      if (mounted) _notify('Could not choose a path. ${_message(error)}');
    } finally {
      _choosingFile = false;
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  void _requestClose() => unawaited(_close());

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      final export = _export;
      if (export != null) {
        if (export.cancellable) {
          if (!await _confirm(
            title: 'Cancel the export?',
            body: 'Your original recording is saved.',
            action: 'Cancel export and close',
          )) {
            return;
          }
          export.cancel();
        }
        await _exportDone;
      }
      if (mounted) widget.onClose();
    } finally {
      _closing = false;
    }
  }

  void _changeFormat(VideoFormat format) {
    setState(() {
      _format = format;
      if (_destination case final path?) {
        _destination =
            '${path.substring(0, path.lastIndexOf('.'))}.${format.extension}';
      }
    });
  }

  VideoExportSettings get _settings {
    final media = _media!;
    final height = _height == 0 ? media.height : _height;
    final width = (media.width * height / media.height).round();
    int even(int pixels) => math.max(2, pixels - pixels % 2);
    return VideoExportSettings(
      format: _format,
      range: _trim!.range,
      speed: _exportSpeed,
      size: (width: even(width), height: even(height)),
      fps: _fps == 0 ? media.fps : _fps,
      audioTracks: [
        if (_systemTrack case final track? when _systemAudio) track,
        if (_microphoneTrack case final track? when _microphone) track,
      ],
    );
  }

  Future<void> _startExport() async {
    if (_export != null || _choosingFile || _closing) return;
    final export = VideoExport();
    final destination = _destination ?? _defaultDestination;
    final settings = _settings;
    _progress.value = 0;
    setState(() => _export = export);
    final done = _runExport(export, destination, settings);
    _exportDone = done;
    await done;
  }

  Future<void> _runExport(
    VideoExport export,
    String destination,
    VideoExportSettings settings,
  ) async {
    try {
      final replace =
          await FileSystemEntity.type(destination, followLinks: false) !=
          .notFound;
      if (!mounted || !export.cancellable) return;
      if (replace &&
          !await _confirm(
            title: 'Replace this file?',
            body: destination,
            action: 'Replace',
          )) {
        return;
      }
      if (!mounted) return;
      final saved = await export.run(
        source: widget.path,
        destination: destination,
        replace: replace,
        settings: settings,
        onProgress: (value) {
          if (mounted) _progress.value = value;
        },
      );
      if (!mounted || !saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Wrap(
            spacing: 8,
            crossAxisAlignment: .center,
            children: [
              const Text('Video exported'),
              SnackBarAction(
                label: 'Show in folder',
                onPressed: () => unawaited(_showFolder(destination)),
              ),
              SnackBarAction(
                label: 'Copy path',
                onPressed: () => unawaited(_copyPath(destination)),
              ),
            ],
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (error) {
      if (mounted) _notify(_message(error));
    } finally {
      if (mounted) setState(() => _export = null);
      _exportDone = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = _media;
    final colors = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(.escape): _requestClose,
        if (media != null) ...{
          const SingleActivator(.space): () => unawaited(_playPause()),
          const SingleActivator(.arrowLeft): () => unawaited(_skip(-5)),
          const SingleActivator(.arrowRight): () => unawaited(_skip(5)),
          const SingleActivator(.comma): () => unawaited(_step(forward: false)),
          const SingleActivator(.period): () => unawaited(_step(forward: true)),
          const SingleActivator(.keyI): () => _moveTrim(true, _position.value),
          const SingleActivator(.keyO): () => _moveTrim(false, _position.value),
          const SingleActivator(.keyZ, control: true): () =>
              setState(_trim!.undo),
          const SingleActivator(.keyY, control: true): () =>
              setState(_trim!.redo),
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colors.surface,
          body: Column(
            children: [
              _EditorBar(
                title: _title,
                subtitle: media == null
                    ? null
                    : [
                        _time(media.duration),
                        '${media.width} × ${media.height}',
                        '${_number(media.fps)} fps',
                        if (_systemTrack != null) 'System audio',
                        if (_microphoneTrack != null) 'Microphone',
                      ].join(' · '),
                onMove: widget.onMoveWindow,
                onUndo: _trim?.canUndo == true
                    ? () => setState(_trim!.undo)
                    : null,
                onRedo: _trim?.canRedo == true
                    ? () => setState(_trim!.redo)
                    : null,
                onFolder: () => unawaited(_showFolder(widget.path)),
                onCopy: () => unawaited(_copyPath(widget.path)),
                onShortcuts: _showShortcuts,
                onClose: _requestClose,
              ),
              if (widget.warning case final warning?)
                Material(
                  color: colors.errorContainer,
                  child: Padding(
                    padding: const .all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        warning,
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: _error != null
                    ? Center(
                        child: Padding(
                          padding: const .all(24),
                          child: Text(_error!),
                        ),
                      )
                    : media == null
                    ? const Center(child: CircularProgressIndicator())
                    : LayoutBuilder(
                        builder: (context, bounds) {
                          final preview = _buildPreview(media);
                          final panel = _buildExportPanel(media);
                          if (bounds.maxWidth < 820 || bounds.maxHeight < 420) {
                            return ListView(
                              padding: const .all(12),
                              children: [
                                SizedBox(height: 410, child: preview),
                                const SizedBox(height: 12),
                                panel,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: .stretch,
                            children: [
                              Expanded(child: preview),
                              SizedBox(
                                width:
                                    math.min(360, bounds.maxWidth * 0.4) + 12,
                                child: Padding(
                                  padding: const .only(right: 12, bottom: 12),
                                  child: panel,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(VideoMedia media) {
    final colors = Theme.of(context).colorScheme;
    final video = _video;
    final error = _previewError;
    final trim = _trim!;
    return Padding(
      padding: const .fromLTRB(24, 18, 24, 20),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: AspectRatio(
                  aspectRatio: media.width / media.height,
                  child: ClipRRect(
                    borderRadius: .circular(20),
                    child: ColoredBox(
                      color: colors.surfaceContainerLowest,
                      child: Stack(
                        fit: .expand,
                        children: [
                          if (video != null && error == null)
                            Video(
                              controller: video,
                              controls: NoVideoControls,
                              wakelock: false,
                            ),
                          if (error != null)
                            Center(
                              child: Padding(
                                padding: const .all(20),
                                child: Text('Preview unavailable. $error'),
                              ),
                            )
                          else if (!_ready)
                            const Center(child: CircularProgressIndicator()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _Transport(
              position: _position,
              playing: _playing,
              range: trim.range,
              speed: _previewSpeed,
              muted: _muted,
              enabled: _ready,
              onPlay: () => unawaited(_playPause()),
              onSkip: (seconds) => unawaited(_skip(seconds)),
              onSpeed: _setSpeed,
              onMute: _toggleMute,
            ),
          ),
          const SizedBox(height: 24),
          _Timeline(
            duration: media.duration,
            frameDuration: media.frameDuration,
            range: trim.range,
            position: _position,
            frames: _frames,
            onReset: () => setState(trim.reset),
            onStartTrim: trim.startDrag,
            onTrim: _moveTrim,
            onEndTrim: _finishTrimDrag,
            onStartScrub: () {
              _scrubbing = true;
              final player = _player;
              if (player != null) unawaited(player.pause());
            },
            onScrub: (time) => _position.value = time,
            onEndScrub: () {
              _scrubbing = false;
              unawaited(_seek(_position.value));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildExportPanel(VideoMedia media) => _ExportPanel(
    media: media,
    settings: _settings,
    progress: _progress,
    systemAvailable: _systemTrack != null,
    micAvailable: _microphoneTrack != null,
    systemAudio: _systemAudio,
    microphone: _microphone,
    selectedHeight: _height,
    selectedFps: _fps,
    destination: _destination ?? _defaultDestination,
    exporting: _export != null,
    onFormat: _changeFormat,
    onSpeed: _setSpeed,
    onHeight: (height) => setState(() => _height = height),
    onFps: (fps) => setState(() => _fps = fps),
    onSystemAudio: (value) => setState(() => _systemAudio = value),
    onMicrophone: (value) => setState(() => _microphone = value),
    onChoose: () => unawaited(_chooseDestination()),
    onExport: () => unawaited(_startExport()),
    onCancel: () {
      _export?.cancel();
      setState(() {});
    },
    cancellable: _export?.cancellable ?? false,
  );

  void _showShortcuts() => unawaited(
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Video editor shortcuts'),
        content: const Text(
          'Space   Play or pause\n'
          '← / →   Jump 5 seconds\n'
          ', / .   Step one frame\n'
          'I / O   Set the trim start or end\n'
          'Ctrl+Z   Undo trim\n'
          'Ctrl+Y   Redo trim\n'
          'Esc   Close',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
}

String _message(Object error) => error is StateError ? error.message : '$error';

String _number(num value) => value.toInt() == value
    ? value.toInt().toString()
    : value.toStringAsFixed(value * 10 == (value * 10).round() ? 1 : 2);

String _time(Duration value, {bool fraction = true}) {
  final hours = value.inHours;
  final minutes = hours == 0 ? value.inMinutes : value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  final tenths = value.inMilliseconds.remainder(1000) ~/ 100;
  return [
    if (hours != 0) hours.toString(),
    minutes.toString().padLeft(2, '0'),
    '$seconds${fraction ? '.$tenths' : ''}',
  ].join(':');
}

class _EditorBar extends StatelessWidget {
  const _EditorBar({
    required this.title,
    required this.subtitle,
    required this.onMove,
    required this.onUndo,
    required this.onRedo,
    required this.onFolder,
    required this.onCopy,
    required this.onShortcuts,
    required this.onClose,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onMove;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback onFolder;
  final VoidCallback onCopy;
  final VoidCallback onShortcuts;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainer,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const .symmetric(horizontal: 12),
          child: Row(
            spacing: 8,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: .opaque,
                  onPanStart: (_) => onMove(),
                  child: Row(
                    spacing: 8,
                    children: [
                      const CaptureAppIcon(),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: .center,
                          crossAxisAlignment: .start,
                          spacing: 2,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            if (subtitle case final text?)
                              Text(
                                text,
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              CaptureIconButton(
                icon: .undo,
                label: 'Undo trim',
                shortcut: 'Ctrl+Z',
                onPressed: onUndo,
              ),
              CaptureIconButton(
                icon: .redo,
                label: 'Redo trim',
                shortcut: 'Ctrl+Y',
                onPressed: onRedo,
              ),
              const SizedBox(height: 24, child: VerticalDivider(width: 1)),
              CaptureIconButton(
                icon: .folder,
                label: 'Show recording in folder',
                onPressed: onFolder,
              ),
              PopupMenuButton<VoidCallback>(
                tooltip: 'More options',
                icon: const CaptureIcon(.more),
                onSelected: (action) => action(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: onCopy,
                    child: const Text('Copy recording path'),
                  ),
                  PopupMenuItem(
                    value: onShortcuts,
                    child: const Text('Keyboard shortcuts'),
                  ),
                ],
              ),
              CaptureIconButton(
                icon: .close,
                label: 'Close',
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorIcon extends StatelessWidget {
  const _EditorIcon(this.name, this.size, {this.color});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/capture/video-editor-$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(
      color ??
          IconTheme.of(context).color ??
          Theme.of(context).colorScheme.onSurface,
      .srcIn,
    ),
    excludeFromSemantics: true,
  );
}
