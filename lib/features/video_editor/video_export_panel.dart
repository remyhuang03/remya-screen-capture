part of 'video_editor.dart';

class _ExportPanel extends StatelessWidget {
  const _ExportPanel({
    required this.media,
    required this.settings,
    required this.progress,
    required this.systemAvailable,
    required this.micAvailable,
    required this.systemAudio,
    required this.microphone,
    required this.selectedHeight,
    required this.selectedFps,
    required this.destination,
    required this.exporting,
    required this.onFormat,
    required this.onSpeed,
    required this.onHeight,
    required this.onFps,
    required this.onSystemAudio,
    required this.onMicrophone,
    required this.onChoose,
    required this.onExport,
    required this.onCancel,
    required this.cancellable,
  });

  final VideoMedia media;
  final VideoExportSettings settings;
  final ValueListenable<double> progress;
  final bool systemAvailable;
  final bool micAvailable;
  final bool systemAudio;
  final bool microphone;
  final int selectedHeight;
  final double selectedFps;
  final String destination;
  final bool exporting;
  final ValueChanged<VideoFormat> onFormat;
  final ValueChanged<double> onSpeed;
  final ValueChanged<int> onHeight;
  final ValueChanged<double> onFps;
  final ValueChanged<bool> onSystemAudio;
  final ValueChanged<bool> onMicrophone;
  final VoidCallback onChoose;
  final VoidCallback onExport;
  final VoidCallback onCancel;
  final bool cancellable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, bounds) {
        final options = _buildOptions(theme);
        return Container(
          padding: const .all(24),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: .circular(28),
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: .min,
            spacing: 16,
            children: [
              if (bounds.hasBoundedHeight)
                Expanded(child: SingleChildScrollView(child: options))
              else
                options,
              _ExportFooter(
                settings: settings,
                bytes: settings.estimateBytes(media),
                progress: progress,
                exporting: exporting,
                onExport: onExport,
                onCancel: cancellable ? onCancel : null,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOptions(ThemeData theme) {
    final colors = theme.colorScheme;
    final audioAllowed = settings.format.audioCodec != null;
    final home = Platform.environment['HOME'];
    final displayPath = home != null && destination.startsWith('$home/')
        ? '~${destination.substring(home.length)}'
        : destination;
    final speeds = <double>{0.5, 1, 1.5, 2, settings.speed}.toList()..sort();
    return Column(
      crossAxisAlignment: .start,
      spacing: 18,
      children: [
        Text(
          'Export',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .w700),
        ),
        _ExportSection(
          label: 'Format',
          child: _FitOptions(
            child: CaptureSegmentedControl(
              segments: [
                for (final format in VideoFormat.values)
                  CaptureSegment(format, format.label),
              ],
              value: settings.format,
              onChanged: exporting ? null : onFormat,
            ),
          ),
        ),
        _ExportSection(
          label: 'Speed',
          child: Column(
            crossAxisAlignment: .start,
            spacing: 6,
            children: [
              _FitOptions(
                child: CaptureSegmentedControl(
                  segments: [
                    for (final speed in speeds)
                      CaptureSegment(speed, '${_number(speed)}×'),
                  ],
                  value: settings.speed,
                  onChanged: exporting ? null : onSpeed,
                ),
              ),
              Text(
                'Audio pitch is preserved · GIF has no audio',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _ExportSection(
          label: 'Resolution & frame rate',
          child: Row(
            spacing: 8,
            children: [
              Expanded(
                child: CaptureDropdown(
                  label: 'Resolution',
                  fillWidth: true,
                  options: {
                    0: 'Original · ${media.width} × ${media.height}',
                    for (final height in [1080, 720, 480, 360])
                      if (height < media.height) height: '${height}p',
                  },
                  value: selectedHeight,
                  onChanged: exporting ? null : onHeight,
                ),
              ),
              CaptureDropdown(
                label: 'Frame rate',
                options: {
                  0.0: '${_number(media.fps)} fps',
                  for (final fps in [60.0, 30.0, 24.0, 15.0])
                    if (fps < media.fps) fps: '${_number(fps)} fps',
                },
                value: selectedFps,
                onChanged: exporting ? null : onFps,
              ),
            ],
          ),
        ),
        _ExportSection(
          label: 'Audio',
          child: Column(
            spacing: 8,
            children: [
              _AudioOption(
                title: 'System audio',
                available: systemAvailable,
                value: systemAudio && audioAllowed,
                onChanged: !exporting && audioAllowed && systemAvailable
                    ? onSystemAudio
                    : null,
              ),
              _AudioOption(
                title: 'Microphone',
                available: micAvailable,
                value: microphone && audioAllowed,
                onChanged: !exporting && audioAllowed && micAvailable
                    ? onMicrophone
                    : null,
              ),
            ],
          ),
        ),
        _ExportSection(
          label: 'Save to',
          child: Tooltip(
            message: destination,
            child: FilledButton(
              onPressed: exporting ? null : onChoose,
              style: FilledButton.styleFrom(
                backgroundColor: colors.surfaceContainerHighest,
                foregroundColor: colors.onSurface,
                minimumSize: const Size(0, 44),
                padding: const .symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: .circular(12)),
              ),
              child: Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Text(
                      displayPath,
                      maxLines: 1,
                      overflow: .ellipsis,
                      textDirection: .rtl,
                    ),
                  ),
                  const CaptureIcon(.folder),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FitOptions extends StatelessWidget {
  const _FitOptions({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SingleChildScrollView(scrollDirection: .horizontal, child: child);
}

class _ExportSection extends StatelessWidget {
  const _ExportSection({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .start,
      spacing: 6,
      children: [
        Semantics(
          header: true,
          child: Text(
            label.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: .w700,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _AudioOption extends StatelessWidget {
  const _AudioOption({
    required this.title,
    required this.available,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool available;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(title, style: theme.textTheme.bodyMedium),
              Text(
                available ? 'Recorded' : 'Not recorded',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Semantics(
          label: 'Export ${title.toLowerCase()}',
          child: Switch(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

class _ExportFooter extends StatelessWidget {
  const _ExportFooter({
    required this.settings,
    required this.bytes,
    required this.progress,
    required this.exporting,
    required this.onExport,
    required this.onCancel,
  });

  final VideoExportSettings settings;
  final int bytes;
  final ValueListenable<double> progress;
  final bool exporting;
  final VoidCallback onExport;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seconds = settings.duration.inMilliseconds / 1000;
    final codec = settings.format.audioCodec;
    final size = bytes >= 1000000
        ? '${(bytes / 1000000).toStringAsFixed(1)} MB'
        : '${math.max(1, (bytes / 1000).round())} kB';
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      spacing: 12,
      children: [
        Wrap(
          spacing: 10,
          crossAxisAlignment: .center,
          children: [
            Text('≈ $size', style: theme.textTheme.titleSmall),
            Text(
              '${_number(seconds)} s at ${_number(settings.speed)}× · ${settings.format.videoCodec}'
              '${codec != null && settings.audioTracks.isNotEmpty ? ' / $codec' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (exporting)
          ValueListenableBuilder(
            valueListenable: progress,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value == 0 ? null : value,
              semanticsLabel: 'Export progress',
            ),
          ),
        if (exporting)
          CaptureButton(
            label: 'Cancel export',
            icon: const CaptureIcon(.close),
            variant: .tonal,
            onPressed: onCancel,
          )
        else
          FilledButton.icon(
            onPressed: onExport,
            icon: const _EditorIcon('export', 20),
            label: const Text('Export'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(borderRadius: .circular(20)),
            ),
          ),
      ],
    );
  }
}
