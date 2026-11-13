import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../capture_controls/capture_buttons.dart';
import '../capture_controls/capture_icon.dart';
import '../capture_controls/capture_labels.dart';
import '../capture_controls/capture_selection.dart';
import '../screenshot/capture_geometry.dart';
import 'recording_backend.dart';

class RecordingSetup extends StatefulWidget {
  const RecordingSetup({
    super.key,
    required this.monitor,
    required this.active,
    required this.region,
    required this.options,
    required this.onFocus,
    required this.onSelect,
    required this.onOptions,
    required this.onStart,
    required this.onCancel,
    this.countdown,
    this.message,
  });

  final CaptureMonitor monitor;
  final bool active;
  final Rect? region;
  final RecordingOptions options;
  final VoidCallback onFocus;
  final ValueChanged<Rect?> onSelect;
  final ValueChanged<RecordingOptions> onOptions;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final int? countdown;
  final String? message;

  @override
  State<RecordingSetup> createState() => _RecordingSetupState();
}

class _RecordingSetupState extends State<RecordingSetup> {
  Offset? _dragOrigin;
  Rect? _draft;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      if (widget.countdown == null)
        const SingleActivator(LogicalKeyboardKey.enter): widget.onStart,
    },
    child: Focus(
      autofocus: true,
      child: Material(
        type: .transparency,
        child: LayoutBuilder(builder: _buildOverlay),
      ),
    ),
  );

  Widget _buildOverlay(BuildContext context, BoxConstraints constraints) {
    final size = constraints.biggest;
    final countdown = widget.countdown;
    final selecting = countdown == null;
    final selection = widget.active ? widget.region : null;
    final selected = selection == null
        ? null
        : scaleRect(selection, widget.monitor.bounds.size, size);
    final highlight = _draft ?? selected;
    return AnimatedOpacity(
      opacity: countdown == 0 ? 0 : 1,
      duration: const Duration(milliseconds: 150),
      child: Stack(
        fit: .expand,
        children: [
          CustomPaint(
            painter: _SetupScrim(
              highlight,
              countdown: !selecting,
              wholeMonitor: widget.active && !selecting && highlight == null,
            ),
          ),
          if (selecting) ...[
            MouseRegion(
              onHover: (_) {
                if (_dragOrigin == null) widget.onFocus();
              },
              child: GestureDetector(
                behavior: .opaque,
                dragStartBehavior: .down,
                onTap: () => widget.onSelect(null),
                onPanStart: (details) {
                  widget.onFocus();
                  _dragOrigin = details.localPosition;
                },
                onPanUpdate: (details) {
                  final origin = _dragOrigin;
                  if (origin == null) return;
                  setState(() {
                    _draft = _draftRect(origin, details.localPosition, size);
                  });
                },
                onPanCancel: _clearDraft,
                onPanEnd: (_) {
                  final draft = _draft;
                  _clearDraft();
                  if (draft != null) {
                    widget.onSelect(
                      scaleRect(draft, size, widget.monitor.bounds.size),
                    );
                  }
                },
              ),
            ),
            if (highlight != null)
              CaptureSelection(
                rect: highlight,
                onChanged: _draft != null
                    ? null
                    : (value) => widget.onSelect(
                        scaleRect(value, size, widget.monitor.bounds.size),
                      ),
              ),
            if (widget.active) ...[
              if (highlight != null)
                Positioned(
                  left: highlight.left.clamp(
                    0.0,
                    math.max(0.0, size.width - 105),
                  ),
                  top: highlight.bottom + 33 <= size.height
                      ? highlight.bottom + 10
                      : math.max(0.0, highlight.top - 33),
                  child: IgnorePointer(
                    child: CaptureSizeBadge(
                      scaleRect(highlight, size, widget.monitor.pixelSize).size,
                    ),
                  ),
                ),
              Positioned(
                top: 24,
                left: 12,
                right: 12,
                child: _SetupControls(
                  options: widget.options,
                  onOptions: widget.onOptions,
                  onStart: widget.onStart,
                  onCancel: widget.onCancel,
                  message: widget.message,
                ),
              ),
            ],
          ] else if (widget.active)
            Positioned.fromRect(
              rect: selected ?? (Offset.zero & size),
              child: Center(child: _Countdown(countdown)),
            ),
        ],
      ),
    );
  }

  void _clearDraft() {
    setState(() {
      _draft = null;
      _dragOrigin = null;
    });
  }
}

Rect? _draftRect(Offset origin, Offset current, Size bounds) {
  if ((origin - current).distance < 4) return null;
  final delta = current - origin;
  var rect = Rect.fromPoints(origin, current).intersect(Offset.zero & bounds);
  if (HardwareKeyboard.instance.isShiftPressed) {
    final left = delta.dx < 0;
    final up = delta.dy < 0;
    final width = math.min(
      math.max(rect.width, rect.height * 16 / 9),
      math.min(
        left ? origin.dx : bounds.width - origin.dx,
        (up ? origin.dy : bounds.height - origin.dy) * 16 / 9,
      ),
    );
    final height = width * 9 / 16;
    rect = .fromLTWH(
      left ? origin.dx - width : origin.dx,
      up ? origin.dy - height : origin.dy,
      width,
      height,
    );
  }
  return rect.width >= CaptureSelection.minimumExtent &&
          rect.height >= CaptureSelection.minimumExtent
      ? rect
      : null;
}

class _SetupScrim extends CustomPainter {
  const _SetupScrim(
    this.highlight, {
    required this.countdown,
    required this.wholeMonitor,
  });

  final Rect? highlight;
  final bool countdown;
  final bool wholeMonitor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hole = wholeMonitor ? rect : highlight;
    final outside = Path()..addRect(rect);
    if (hole != null) {
      outside
        ..fillType = .evenOdd
        ..addRect(hole);
    }
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    if (countdown && hole != null) {
      canvas.drawRect(hole, Paint()..color = Colors.black26);
    }
  }

  @override
  bool shouldRepaint(_SetupScrim oldDelegate) =>
      oldDelegate.highlight != highlight ||
      oldDelegate.countdown != countdown ||
      oldDelegate.wholeMonitor != wholeMonitor;
}

class _SetupControls extends StatelessWidget {
  const _SetupControls({
    required this.options,
    required this.onOptions,
    required this.onStart,
    required this.onCancel,
    required this.message,
  });

  final RecordingOptions options;
  final ValueChanged<RecordingOptions> onOptions;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final String? message;

  @override
  Widget build(BuildContext context) => Column(
    spacing: 10,
    children: [
      CaptureSurface(
        child: Wrap(
          alignment: .center,
          crossAxisAlignment: .center,
          spacing: 4,
          runSpacing: 6,
          children: [
            CaptureToggleChip(
              label: 'System audio',
              selected: options.systemAudio,
              icon: CaptureIcon(options.systemAudio ? .volumeUp : .volumeOff),
              onChanged: (value) =>
                  onOptions(options.copyWith(systemAudio: value)),
            ),
            CaptureToggleChip(
              label: 'Microphone',
              selected: options.microphone,
              icon: CaptureIcon(options.microphone ? .mic : .micOff),
              onChanged: (value) =>
                  onOptions(options.copyWith(microphone: value)),
            ),
            CaptureToggleChip(
              label: 'Show cursor',
              selected: options.cursor,
              icon: const CaptureIcon(.cursor),
              onChanged: (value) => onOptions(options.copyWith(cursor: value)),
            ),
            const Padding(
              padding: .symmetric(horizontal: 4),
              child: CaptureDivider(),
            ),
            CaptureButton(
              label: 'Cancel',
              icon: const CaptureIcon(.close),
              variant: .text,
              onPressed: onCancel,
            ),
            CaptureButton(
              label: 'Record',
              icon: const CaptureIcon(.record),
              onPressed: onStart,
            ),
          ],
        ),
      ),
      const Wrap(
        alignment: .center,
        spacing: 12,
        runSpacing: 4,
        children: [
          _SetupHint('Enter', 'Start'),
          _SetupHint('Esc', 'Cancel'),
          _SetupHint('Shift', 'Keep ratio'),
        ],
      ),
      if (!options.cursor)
        const CaptureTooltipLabel(
          'A display that cannot use a hardware cursor can still show it.',
        ),
      if (message case final message?)
        Semantics(
          liveRegion: true,
          child: CaptureSurface(
            child: Text(
              message,
              textAlign: .center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
    ],
  );
}

class _SetupHint extends StatelessWidget {
  const _SetupHint(this.keyLabel, this.label);

  final String keyLabel;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: .min,
    spacing: 5,
    children: [
      CaptureKeycap(keyLabel),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _Countdown extends StatefulWidget {
  const _Countdown(this.seconds);

  final int seconds;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();

  @override
  void didUpdateWidget(_Countdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.seconds != oldWidget.seconds && widget.seconds > 0) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shape = switch (widget.seconds) {
      3 => MaterialShapes.softBurst,
      2 => MaterialShapes.cookie9Sided,
      _ => MaterialShapes.circle,
    };
    final remaining = math.max(1, widget.seconds);
    return FittedBox(
      fit: .scaleDown,
      child: Column(
        mainAxisSize: .min,
        spacing: 34,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Transform.scale(
              scale: .82 + .18 * Curves.easeOutBack.transform(_pulse.value),
              child: child,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: 184,
              height: 184,
              alignment: .center,
              decoration: ShapeDecoration(
                color: colors.primary,
                shape: MaterialShapeBorder(shape: shape),
              ),
              child: Text(
                '$remaining',
                style: TextStyle(
                  color: colors.onPrimary,
                  fontSize: 116,
                  fontWeight: .w700,
                  height: 1,
                ),
              ),
            ),
          ),
          CaptureTooltipLabel(
            'Recording starts in $remaining s',
            shortcut: 'Esc',
          ),
        ],
      ),
    );
  }
}
