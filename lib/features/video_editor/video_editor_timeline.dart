part of 'video_editor.dart';

const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 4.0];

class _Transport extends StatelessWidget {
  const _Transport({
    required this.position,
    required this.playing,
    required this.range,
    required this.speed,
    required this.muted,
    required this.enabled,
    required this.onPlay,
    required this.onSkip,
    required this.onSpeed,
    required this.onMute,
  });

  final ValueListenable<Duration> position;
  final ValueListenable<bool> playing;
  final VideoRange range;
  final double speed;
  final bool muted;
  final bool enabled;
  final VoidCallback onPlay;
  final ValueChanged<int> onSkip;
  final ValueChanged<double> onSpeed;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, bounds) {
        final compact = bounds.maxWidth < 450;
        final playback = Row(
          mainAxisSize: .min,
          spacing: compact ? 2 : 8,
          children: [
            CaptureIconButton(
              icon: .replay5,
              label: 'Back 5 seconds',
              shortcut: '←',
              onPressed: enabled ? () => onSkip(-5) : null,
            ),
            ValueListenableBuilder(
              valueListenable: playing,
              builder: (context, value, _) => Tooltip(
                message: value ? 'Pause (Space)' : 'Play (Space)',
                child: Semantics(
                  label: value ? 'Pause' : 'Play',
                  child: FilledButton(
                    onPressed: enabled ? onPlay : null,
                    style: FilledButton.styleFrom(
                      fixedSize: Size(compact ? 54 : 80, 56),
                      padding: .zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: .circular(20),
                      ),
                    ),
                    child: value
                        ? const CaptureIcon(.pause)
                        : const _EditorIcon('play', 28),
                  ),
                ),
              ),
            ),
            CaptureIconButton(
              icon: .forward5,
              label: 'Forward 5 seconds',
              shortcut: '→',
              onPressed: enabled ? () => onSkip(5) : null,
            ),
          ],
        );
        final clock = ValueListenableBuilder(
          valueListenable: position,
          builder: (context, value, _) => Text(
            '${_time(value)} / ${_time(range.end - range.start)}',
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: colors.onSurfaceVariant,
            ),
          ),
        );
        final controls = Row(
          mainAxisSize: .min,
          spacing: compact ? 0 : 4,
          children: [
            _SpeedMenu(speed: speed, onSelected: onSpeed),
            CaptureIconButton(
              icon: muted ? .volumeOff : .volumeUp,
              label: muted ? 'Unmute preview' : 'Mute preview',
              onPressed: enabled ? onMute : null,
            ),
          ],
        );
        if (compact) {
          return Column(
            spacing: 2,
            children: [
              playback,
              Row(
                children: [
                  Expanded(child: clock),
                  controls,
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: clock),
            playback,
            Expanded(
              child: Align(alignment: .centerRight, child: controls),
            ),
          ],
        );
      },
    );
  }
}

class _SpeedMenu extends StatelessWidget {
  const _SpeedMenu({required this.speed, required this.onSelected});

  final double speed;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      initialValue: speed,
      onSelected: onSelected,
      color: colors.surfaceContainerHigh,
      padding: .zero,
      shape: RoundedRectangleBorder(borderRadius: .circular(20)),
      itemBuilder: (context) => [
        for (final option in _speeds)
          PopupMenuItem(
            value: option,
            height: 40,
            child: Row(
              children: [
                Expanded(child: Text('${_number(option)}×')),
                if (option == speed) const CaptureIcon(.check),
              ],
            ),
          ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: .circular(12),
        ),
        child: Padding(
          padding: const .fromLTRB(10, 8, 8, 8),
          child: Row(
            mainAxisSize: .min,
            spacing: 4,
            children: [
              const CaptureIcon(.speed),
              Text('${_number(speed)}×'),
              const CaptureIcon(.dropdown),
            ],
          ),
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.duration,
    required this.frameDuration,
    required this.range,
    required this.position,
    required this.frames,
    required this.onReset,
    required this.onStartTrim,
    required this.onTrim,
    required this.onEndTrim,
    required this.onStartScrub,
    required this.onScrub,
    required this.onEndScrub,
  });

  final Duration duration;
  final Duration frameDuration;
  final VideoRange range;
  final ValueListenable<Duration> position;
  final List<Uint8List?> frames;
  final VoidCallback onReset;
  final VoidCallback onStartTrim;
  final void Function(bool start, Duration position) onTrim;
  final VoidCallback onEndTrim;
  final VoidCallback onStartScrub;
  final ValueChanged<Duration> onScrub;
  final VoidCallback onEndScrub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const .fromLTRB(24, 4, 24, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: .circular(24),
      ),
      child: Column(
        mainAxisSize: .min,
        children: [
          Row(
            children: [
              const _EditorIcon('trim', 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Trim ${_time(range.start)} – ${_time(range.end)} · ${_time(range.end - range.start)}',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              CaptureButton(
                label: 'Reset trim',
                icon: const CaptureIcon(.undo),
                variant: .text,
                onPressed: range.start != Duration.zero || range.end != duration
                    ? onReset
                    : null,
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              double x(Duration time) =>
                  width *
                  (time.inMicroseconds / duration.inMicroseconds).clamp(
                    0.0,
                    1.0,
                  );
              Duration time(double dx) =>
                  duration * (dx / width).clamp(0.0, 1.0);
              final start = x(range.start);
              final end = x(range.end);
              final handleCenter = (start + end) / 2;
              final startHandle = math.min(start - 8, handleCenter - 16);
              final endHandle = math.max(end - 8, handleCenter);
              final trackColor = colors.surfaceContainerLowest;
              return Column(
                children: [
                  SizedBox(
                    height: 70,
                    child: Stack(
                      clipBehavior: .none,
                      children: [
                        Positioned.fill(
                          top: 3,
                          bottom: 3,
                          child: Semantics(
                            slider: true,
                            label: 'Video timeline',
                            onIncrease: () {
                              onStartScrub();
                              onScrub(time(x(position.value + frameDuration)));
                              onEndScrub();
                            },
                            onDecrease: () {
                              onStartScrub();
                              onScrub(time(x(position.value - frameDuration)));
                              onEndScrub();
                            },
                            child: GestureDetector(
                              behavior: .opaque,
                              onTapUp: (event) {
                                onStartScrub();
                                onScrub(time(event.localPosition.dx));
                                onEndScrub();
                              },
                              onHorizontalDragStart: (event) {
                                onStartScrub();
                                onScrub(time(event.localPosition.dx));
                              },
                              onHorizontalDragUpdate: (event) =>
                                  onScrub(time(event.localPosition.dx)),
                              onHorizontalDragEnd: (_) => onEndScrub(),
                              onHorizontalDragCancel: onEndScrub,
                              child: ClipRRect(
                                borderRadius: .circular(8),
                                child: ColoredBox(
                                  color: trackColor,
                                  child: Row(
                                    crossAxisAlignment: .stretch,
                                    children: [
                                      for (final frame in frames)
                                        Expanded(
                                          child: frame == null
                                              ? const SizedBox()
                                              : Image.memory(
                                                  frame,
                                                  fit: .cover,
                                                  gaplessPlayback: true,
                                                  excludeFromSemantics: true,
                                                ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _TrimShade(start: start, end: end, width: width),
                        Positioned(
                          left: start,
                          width: math.max(0, end - start),
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.symmetric(
                                  horizontal: BorderSide(
                                    color: colors.primary,
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        for (final isStart in [true, false])
                          Positioned(
                            left: (isStart ? startHandle : endHandle).clamp(
                              -4.0,
                              math.max(-4.0, width - 12),
                            ),
                            top: 0,
                            bottom: 0,
                            child: _TrimHandle(
                              start: isStart,
                              time: isStart ? range.start : range.end,
                              frameDuration: frameDuration,
                              microsPerPixel: duration.inMicroseconds / width,
                              onStart: onStartTrim,
                              onChange: (value) => onTrim(isStart, value),
                              onEnd: onEndTrim,
                            ),
                          ),
                        ValueListenableBuilder(
                          valueListenable: position,
                          builder: (context, value, _) => _Playhead(
                            x: x(value),
                            width: width,
                            label: _time(value),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _TimelineTicks(duration: duration, width: width),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TrimShade extends StatelessWidget {
  const _TrimShade({
    required this.start,
    required this.end,
    required this.width,
  });

  final double start;
  final double end;
  final double width;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.scrim.withValues(alpha: 0.58);
    return Positioned.fill(
      top: 3,
      bottom: 3,
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: .circular(8),
          child: Row(
            children: [
              SizedBox(
                width: start,
                height: double.infinity,
                child: ColoredBox(color: color),
              ),
              const Spacer(),
              SizedBox(
                width: width - end,
                height: double.infinity,
                child: ColoredBox(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrimHandle extends StatefulWidget {
  const _TrimHandle({
    required this.start,
    required this.time,
    required this.frameDuration,
    required this.microsPerPixel,
    required this.onStart,
    required this.onChange,
    required this.onEnd,
  });

  final bool start;
  final Duration time;
  final Duration frameDuration;
  final double microsPerPixel;
  final VoidCallback onStart;
  final ValueChanged<Duration> onChange;
  final VoidCallback onEnd;

  @override
  State<_TrimHandle> createState() => _TrimHandleState();
}

class _TrimHandleState extends State<_TrimHandle> {
  Duration _initial = Duration.zero;
  double _delta = 0;
  bool _focused = false;

  void _nudge(int frames) =>
      widget.onChange(widget.time + widget.frameDuration * frames);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      slider: true,
      label: widget.start ? 'Trim start' : 'Trim end',
      value: _time(widget.time),
      onIncrease: () => _nudge(1),
      onDecrease: () => _nudge(-1),
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is KeyUpEvent) return .ignored;
          if (event.logicalKey == .arrowLeft) {
            _nudge(-1);
            return .handled;
          }
          if (event.logicalKey == .arrowRight) {
            _nudge(1);
            return .handled;
          }
          return .ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: .opaque,
            onHorizontalDragStart: (_) {
              _initial = widget.time;
              _delta = 0;
              widget.onStart();
            },
            onHorizontalDragUpdate: (event) {
              _delta += event.delta.dx;
              widget.onChange(
                _initial +
                    Duration(
                      microseconds: (_delta * widget.microsPerPixel).round(),
                    ),
              );
            },
            onHorizontalDragEnd: (_) => widget.onEnd(),
            onHorizontalDragCancel: widget.onEnd,
            child: Container(
              width: 16,
              alignment: .center,
              decoration: BoxDecoration(
                color: colors.primary,
                border: _focused
                    ? Border.all(color: colors.onSurface, width: 2)
                    : null,
                borderRadius: widget.start
                    ? .horizontal(left: const Radius.circular(8))
                    : .horizontal(right: const Radius.circular(8)),
              ),
              child: Container(
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: colors.onPrimary,
                  borderRadius: .circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Playhead extends StatelessWidget {
  const _Playhead({required this.x, required this.width, required this.label});

  final double x;
  final double width;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          clipBehavior: .none,
          children: [
            Positioned(
              left: x - 1,
              top: -3,
              bottom: -5,
              width: 2,
              child: ColoredBox(color: colors.onSurface),
            ),
            Positioned(
              left: x - 6,
              top: -10,
              child: _EditorIcon('knob', 12, color: colors.onSurface),
            ),
            Positioned(
              left: (x - 38).clamp(0.0, math.max(0.0, width - 76)),
              top: 6,
              width: 76,
              child: Align(
                alignment: .center,
                child: Container(
                  padding: const .symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.inverseSurface,
                    borderRadius: .circular(8),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onInverseSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineTicks extends StatelessWidget {
  const _TimelineTicks({required this.duration, required this.width});

  final Duration duration;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seconds = duration.inMilliseconds / 1000;
    final interval = const [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600]
        .firstWhere(
          (step) => step >= seconds / math.max(2, width / 120),
          orElse: () => (seconds / 4).ceil(),
        );
    return SizedBox(
      height: 17,
      child: Stack(
        children: [
          for (var at = 0; at < seconds; at += interval)
            Positioned(
              left: (width * at / seconds).clamp(
                0.0,
                math.max(0.0, width - 52),
              ),
              child: Text(
                _time(Duration(seconds: at), fraction: false),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
