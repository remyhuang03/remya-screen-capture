import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../capture_controls/capture_buttons.dart';
import '../capture_controls/capture_icon.dart';
import '../capture_controls/capture_labels.dart';
import '../capture_controls/capture_selection.dart';
import '../color_picker/color_data.dart';
import '../color_picker/color_loupe.dart';
import 'capture_geometry.dart';
import 'capture_session.dart';

class CaptureOverlay extends StatefulWidget {
  const CaptureOverlay({
    super.key,
    required this.session,
    required this.output,
    required this.onCapture,
    required this.onPickColor,
    required this.onColorHistory,
    required this.onScroll,
    required this.onBack,
    required this.onDone,
  });

  final CaptureSession session;
  final FrozenOutput output;
  final ValueChanged<CaptureRequest> onCapture;
  final void Function(PickedColor sample, {required bool keepPicking})
  onPickColor;
  final VoidCallback onColorHistory;
  final VoidCallback onScroll;
  final VoidCallback onBack;
  final VoidCallback onDone;

  @override
  State<CaptureOverlay> createState() => _CaptureOverlayState();
}

class _CaptureOverlayState extends State<CaptureOverlay> {
  final _focus = FocusNode(debugLabel: 'Screenshot overlay');
  int? _pointerId;
  Offset? _toolbarPosition;

  CaptureSession get session => widget.session;
  FrozenOutput get output => widget.output;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(KeyEvent event, Size viewport) {
    if (event is KeyUpEvent || session.busy) return .ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onBack();
      return .handled;
    }
    final keyboard = HardwareKeyboard.instance;
    if (const SingleActivator(
      .keyC,
      includeRepeats: false,
    ).accepts(event, keyboard)) {
      _focus.requestFocus();
      session.toggleColor(viewport);
      return .handled;
    }
    if (const SingleActivator(
          .tab,
          includeRepeats: false,
        ).accepts(event, keyboard) &&
        _focus.hasPrimaryFocus &&
        session.scroll == null) {
      session.cycleMode(viewport);
      return .handled;
    }
    final move = switch (key) {
      LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, -1),
      LogicalKeyboardKey.arrowRight => const Offset(1, 0),
      LogicalKeyboardKey.arrowDown => const Offset(0, 1),
      _ => null,
    };
    if (session.mode == .color && _focus.hasPrimaryFocus) {
      if (move != null &&
          !keyboard.isControlPressed &&
          !keyboard.isAltPressed &&
          !keyboard.isMetaPressed) {
        session.nudgeColor(move * (keyboard.isShiftPressed ? 10 : 1), viewport);
        return .handled;
      }
      for (final (shortcut, action) in [
        (LogicalKeyboardKey.enter, () => _pick()),
        (LogicalKeyboardKey.space, () => _pick()),
        (LogicalKeyboardKey.keyF, session.cycleColorFormat),
        (LogicalKeyboardKey.keyH, widget.onColorHistory),
      ]) {
        if (SingleActivator(
          shortcut,
          includeRepeats: false,
        ).accepts(event, keyboard)) {
          action();
          return .handled;
        }
      }
      return .ignored;
    }
    if (key == LogicalKeyboardKey.enter &&
        (_focus.hasPrimaryFocus || session.scroll != null)) {
      if (session.scroll != null) {
        widget.onDone();
      } else if (session.mode == .region || session.hoveredWindow != null) {
        widget.onCapture(session.request);
      }
      return .handled;
    }
    final selection = session.selection;
    if (selection != null &&
        session.scroll == null &&
        move != null &&
        _focus.hasPrimaryFocus) {
      final delta = move * (HardwareKeyboard.instance.isShiftPressed ? 10 : 1);
      final bounds = session.active.size;
      session.setSelection(
        selection.translate(
          delta.dx.clamp(-selection.left, bounds.width - selection.right),
          delta.dy.clamp(-selection.top, bounds.height - selection.bottom),
        ),
      );
      return .handled;
    }
    return .ignored;
  }

  void _pick({bool keepPicking = false}) {
    if (!session.busy) {
      widget.onPickColor(session.colorSample, keepPicking: keepPicking);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isEmpty) return const SizedBox.shrink();
        final active = output == session.active;
        final picking = session.mode == .color;
        final scroll = session.scroll;
        final pixelSelection = active ? session.selection : null;
        final selection = pixelSelection == null
            ? null
            : scaleRect(pixelSelection, output.size, size);
        final window = active ? session.hoveredWindow : null;
        final windowOutput = window == null
            ? output
            : session.outputs.firstWhere(
                (candidate) => candidate.monitor.id == window.monitor,
                orElse: () => output,
              );
        final windowRect = window == null
            ? null
            : scaleRect(
                window.bounds
                    .intersect(output.monitor.bounds)
                    .shift(-output.monitor.bounds.topLeft),
                output.monitor.bounds.size,
                size,
              );
        final hole =
            selection ??
            (active ? session.draft : null) ??
            (session.mode == .window ? windowRect : null);
        final pointer = active && hole == null && session.mode == .region
            ? session.pointer
            : null;
        final colors = Theme.of(context).colorScheme;
        final panel = scroll?.panel;
        final panelRect = panel == null || panel.output != output.name
            ? null
            : scaleRect(panel.rect, output.monitor.bounds.size, size);
        final message = session.message;

        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: (_, event) => _key(event, size),
          child: Stack(
            fit: .expand,
            children: [
              if (scroll == null)
                RawImage(image: output.image, fit: .fill, filterQuality: .none),
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: picking ? 0 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: CustomPaint(
                    painter: _OverlayPaint(
                      hole: hole,
                      pointer: pointer,
                      outline: colors.primary,
                      window: windowRect != null,
                      scrolling: scroll != null,
                    ),
                  ),
                ),
              ),
              if (scroll == null)
                Positioned.fill(
                  child: MouseRegion(
                    cursor: picking
                        ? SystemMouseCursors.none
                        : session.mode == .region && selection == null
                        ? SystemMouseCursors.precise
                        : SystemMouseCursors.basic,
                    onHover: (event) =>
                        session.hover(output, event.localPosition, size),
                    child: Listener(
                      behavior: .opaque,
                      onPointerSignal: picking
                          ? (event) {
                              if (event is PointerScrollEvent &&
                                  event.scrollDelta.dy != 0 &&
                                  !session.busy) {
                                session.hover(
                                  output,
                                  event.localPosition,
                                  size,
                                );
                                session.zoomColor(event.scrollDelta.dy < 0);
                              }
                            }
                          : null,
                      onPointerDown: (event) {
                        if (picking) {
                          if (event.buttons != kPrimaryMouseButton ||
                              session.busy) {
                            return;
                          }
                          _focus.requestFocus();
                          session.hover(output, event.localPosition, size);
                          _pick(
                            keepPicking:
                                HardwareKeyboard.instance.isShiftPressed,
                          );
                          return;
                        }
                        if (_pointerId != null ||
                            selection != null ||
                            (event.buttons != kPrimaryMouseButton &&
                                event.buttons != kSecondaryMouseButton)) {
                          return;
                        }
                        _focus.requestFocus();
                        _pointerId = event.pointer;
                        session.startDrag(
                          output,
                          event.localPosition,
                          size,
                          event.buttons == kSecondaryMouseButton,
                        );
                      },
                      onPointerMove: (event) {
                        if (_pointerId == event.pointer) {
                          session.updateDrag(output, event.localPosition, size);
                        }
                      },
                      onPointerUp: (event) {
                        if (_pointerId != event.pointer) return;
                        _pointerId = null;
                        final request = session.endDrag(
                          output,
                          event.localPosition,
                          size,
                        );
                        if (request != null) widget.onCapture(request);
                      },
                      onPointerCancel: (event) {
                        if (_pointerId != event.pointer) return;
                        _pointerId = null;
                        session.cancelDrag();
                      },
                    ),
                  ),
                ),
              if (pointer != null && !session.busy)
                _Loupe(output: output, pointer: pointer, viewport: size),
              if (picking && active)
                if ((session.colorPixel, session.pointer) case (
                  final pixel?,
                  final pointer?,
                ))
                  ColorLoupe(
                    output: output,
                    pointer: pointer,
                    pixel: pixel,
                    position: session.colorPosition,
                    viewport: size,
                    zoom: session.zoom,
                    format: session.colorFormat,
                    uppercase: session.uppercaseHex,
                  ),
              if (window != null &&
                  windowRect != null &&
                  !windowRect.isEmpty &&
                  scroll == null)
                _WindowLabel(
                  window: window,
                  rect: windowRect,
                  viewport: size,
                  pixelSize: scaleRect(
                    window.bounds,
                    windowOutput.monitor.bounds.size,
                    windowOutput.size,
                  ).size,
                ),
              if (active &&
                  selection == null &&
                  session.draft == null &&
                  scroll == null)
                Positioned.fill(
                  child: CustomSingleChildLayout(
                    delegate: _ModeToolbarLayout(_toolbarPosition),
                    child: _ModeToolbar(
                      mode: session.mode,
                      onChanged: (value) {
                        _focus.requestFocus();
                        session.changeMode(value, size);
                      },
                      onDrag: (delta, toolbar) {
                        final layout = _ModeToolbarLayout(_toolbarPosition);
                        setState(
                          () => _toolbarPosition = layout.positionFor(
                            size,
                            toolbar,
                            delta: delta,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (active && selection != null && scroll == null) ...[
                CaptureSelection(
                  rect: selection,
                  nudgeUnit: Offset(
                    size.width / output.size.width,
                    size.height / output.size.height,
                  ),
                  onChanged: session.busy
                      ? null
                      : (rect) => session.setSelection(
                          scaleRect(rect, size, output.size),
                        ),
                ),
                _SelectionTools(
                  selection: selection,
                  pixelSize: pixelSelection!.size,
                  edit: session.edit,
                  busy: session.busy,
                  onCancel: widget.onBack,
                  onScroll: widget.onScroll,
                  onCapture: () => widget.onCapture(session.request),
                ),
              ],
              if (scroll != null && panelRect != null)
                Positioned.fromRect(
                  rect: panelRect,
                  child: _ScrollingPanel(
                    scroll: scroll,
                    onBack: widget.onBack,
                    onDone: widget.onDone,
                    busy: session.busy,
                  ),
                ),
              if (active && message != null && scroll == null)
                Positioned(
                  bottom: 18,
                  left: 16,
                  right: 16,
                  child: Align(
                    child: CaptureSurface(
                      child: Padding(
                        padding: const .symmetric(horizontal: 12, vertical: 5),
                        child: Text(message, textAlign: .center),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _ModeToolbarLayout extends SingleChildLayoutDelegate {
  const _ModeToolbarLayout(this.position);

  final Offset? position;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.deflate(const .all(8)).biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      positionFor(size, childSize);

  Offset positionFor(Size size, Size childSize, {Offset delta = Offset.zero}) {
    final horizontal = size.width - childSize.width;
    final vertical = size.height - childSize.height;
    final target = position ?? Offset(horizontal / 2, 24);
    return Offset(
      (target.dx.clamp(0.0, horizontal) + delta.dx).clamp(0.0, horizontal),
      (target.dy.clamp(0.0, vertical) + delta.dy).clamp(0.0, vertical),
    );
  }

  @override
  bool shouldRelayout(_ModeToolbarLayout oldDelegate) =>
      position != oldDelegate.position;
}

class _ModeToolbar extends StatelessWidget {
  const _ModeToolbar({
    required this.mode,
    required this.onChanged,
    required this.onDrag,
  });

  final CaptureMode mode;
  final ValueChanged<CaptureMode> onChanged;
  final void Function(Offset delta, Size toolbar) onDrag;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.grab,
    child: GestureDetector(
      behavior: .opaque,
      dragStartBehavior: .down,
      onPanUpdate: (details) => onDrag(details.delta, context.size!),
      child: CaptureSurface(
        child: Wrap(
          alignment: .center,
          crossAxisAlignment: .center,
          spacing: 8,
          runSpacing: 8,
          children: [
            CaptureSegmentedControl(
              segments: const [
                CaptureSegment(
                  CaptureMode.region,
                  'Region',
                  icon: CaptureIcon.segmentRegion(),
                ),
                CaptureSegment(
                  CaptureMode.window,
                  'Window',
                  icon: CaptureIcon.segmentWindow(),
                ),
                CaptureSegment(
                  CaptureMode.color,
                  'Color',
                  icon: CaptureIcon.segmentColor(),
                ),
              ],
              value: mode,
              onChanged: onChanged,
            ),
            const CaptureDivider(),
            if (mode == .color) ...const [
              _Hint('LMB', 'Pick'),
              _Hint('Shift+LMB', 'Pick & keep'),
              _Hint('Scroll', 'Zoom'),
              _Hint('F', 'Format'),
            ] else ...[
              _Hint(mode == .region ? 'LMB' : 'Click', 'Copy'),
              _Hint(mode == .region ? 'RMB' : 'Right click', 'Edit'),
            ],
            _Hint('C', mode == .color ? 'Back to capture' : 'Pick color'),
            const _Hint('Tab', 'Switch'),
            const _Hint('Esc', 'Cancel'),
          ],
        ),
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.keyLabel, this.label);

  final String keyLabel;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: .min,
    spacing: 4,
    children: [
      CaptureKeycap(keyLabel),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _WindowLabel extends StatelessWidget {
  const _WindowLabel({
    required this.window,
    required this.rect,
    required this.viewport,
    required this.pixelSize,
  });

  final CaptureWindow window;
  final Rect rect;
  final Size viewport;
  final Size pixelSize;

  @override
  Widget build(BuildContext context) {
    final left = (rect.left + 16)
        .clamp(8.0, math.max(8.0, viewport.width - 220))
        .toDouble();
    return Positioned(
      top: (rect.top + 14).clamp(82.0, math.max(82.0, viewport.height - 70)),
      left: left,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(450, viewport.width - left),
          ),
          child: CaptureSurface(
            child: Row(
              mainAxisSize: .min,
              spacing: 8,
              children: [
                const CaptureIcon(.window),
                Flexible(child: Text(window.windowClass, overflow: .ellipsis)),
                Flexible(child: Text(window.title, overflow: .ellipsis)),
                CaptureSizeBadge(pixelSize),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionTools extends StatelessWidget {
  const _SelectionTools({
    required this.selection,
    required this.pixelSize,
    required this.edit,
    required this.busy,
    required this.onCancel,
    required this.onScroll,
    required this.onCapture,
  });

  final Rect selection;
  final Size pixelSize;
  final bool edit;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onScroll;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return CustomMultiChildLayout(
      delegate: _SelectionToolsLayout(selection),
      children: [
        LayoutId(
          id: _SelectionPart.badge,
          child: IgnorePointer(child: CaptureSizeBadge(pixelSize)),
        ),
        LayoutId(
          id: _SelectionPart.actions,
          child: Column(
            crossAxisAlignment: .end,
            mainAxisSize: .min,
            spacing: 10,
            children: [
              CaptureSurface(
                child: Wrap(
                  alignment: .end,
                  crossAxisAlignment: .center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    CaptureToggleChip(
                      label: 'Scrolling',
                      selected: false,
                      icon: const CaptureIcon(.scrollCapture),
                      onChanged: busy ? null : (_) => onScroll(),
                    ),
                    const CaptureDivider(),
                    CaptureButton(
                      label: 'Cancel',
                      variant: .text,
                      icon: const CaptureIcon(.close),
                      onPressed: busy ? null : onCancel,
                    ),
                    CaptureButton(
                      label: edit ? 'Edit' : 'Copy',
                      icon: CaptureIcon(edit ? .edit : .copy),
                      onPressed: busy ? null : onCapture,
                    ),
                  ],
                ),
              ),
              const IgnorePointer(
                child: CaptureSurface(
                  child: Wrap(
                    alignment: .end,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _Hint('Enter', 'Confirm'),
                      _Hint('Esc', 'Cancel'),
                      _Hint('Shift', 'Keep ratio'),
                      _Hint('←↑→↓', 'Nudge'),
                      _Hint('C', 'Pick color'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _SelectionPart { badge, actions }

class _SelectionToolsLayout extends MultiChildLayoutDelegate {
  _SelectionToolsLayout(this.selection);

  final Rect selection;

  @override
  void performLayout(Size size) {
    final margin = math.min(8.0, size.shortestSide / 2);
    final available = Size(size.width - 2 * margin, size.height - 2 * margin);
    final badge = layoutChild(
      _SelectionPart.badge,
      BoxConstraints.loose(available),
    );
    final badgeLeft = selection.left.clamp(
      margin,
      size.width - badge.width - margin,
    );
    final badgeAbove = selection.top - badge.height - 12;
    var badgeTop = math.max(badgeAbove, margin);

    final actions = layoutChild(
      _SelectionPart.actions,
      BoxConstraints(
        maxWidth: math.min(450, available.width),
        maxHeight: available.height,
      ),
    );
    final below = math.max(
      selection.bottom + 16,
      badgeTop + badge.height + margin,
    );
    final above = badgeTop - actions.height - margin;
    final latest = size.height - actions.height - margin;
    if (badgeTop + badge.height + margin > latest && above < margin) {
      badgeTop = margin;
    }
    positionChild(_SelectionPart.badge, Offset(badgeLeft, badgeTop));
    final top = below <= latest
        ? below
        : above >= margin
        ? above
        : math.min(latest, badgeTop + badge.height + margin);
    final left = (selection.right - actions.width).clamp(
      margin,
      size.width - actions.width - margin,
    );
    positionChild(_SelectionPart.actions, Offset(left, top));
  }

  @override
  bool shouldRelayout(_SelectionToolsLayout oldDelegate) =>
      oldDelegate.selection != selection;
}

class _Loupe extends StatelessWidget {
  const _Loupe({
    required this.output,
    required this.pointer,
    required this.viewport,
  });

  final FrozenOutput output;
  final Offset pointer;
  final Size viewport;

  @override
  Widget build(BuildContext context) {
    const extent = 144.0;
    const gap = 24.0;
    final x = pointer.dx + gap + extent <= viewport.width
        ? pointer.dx + gap
        : math.max(0.0, pointer.dx - gap - extent);
    final y = pointer.dy + gap + extent + 32 <= viewport.height
        ? pointer.dy + gap
        : math.max(0.0, pointer.dy - gap - extent - 32);
    final pixel = output.pixelAt(pointer, viewport);
    final colors = Theme.of(context).colorScheme;
    final color = output.colorAt(pixel).toARGB32() & 0xffffff;
    final hex = color.toRadixString(16).padLeft(6, '0').toUpperCase();
    return Positioned(
      left: x,
      top: y,
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: .start,
          spacing: 8,
          children: [
            ClipRRect(
              borderRadius: .circular(32),
              child: CustomPaint(
                painter: _LoupePaint(output, pixel, colors.primary),
                size: const Size.square(extent),
              ),
            ),
            CaptureTooltipLabel(
              '${pixel.dx.toInt()}, ${pixel.dy.toInt()} · #$hex',
            ),
          ],
        ),
      ),
    );
  }
}

class _LoupePaint extends CustomPainter {
  const _LoupePaint(this.output, this.pixel, this.color);

  final FrozenOutput output;
  final Offset pixel;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final focus = pixel + const Offset(.5, .5);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(8);
    canvas.drawImage(output.image, -focus, Paint()..filterQuality = .none);
    canvas.restore();
    final outline = Paint()
      ..color = color
      ..style = .stroke;
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 8, height: 8),
      outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(1),
        const Radius.circular(31),
      ),
      outline..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_LoupePaint old) =>
      old.pixel != pixel || old.output != output || old.color != color;
}

class _OverlayPaint extends CustomPainter {
  const _OverlayPaint({
    required this.hole,
    required this.pointer,
    required this.outline,
    required this.window,
    required this.scrolling,
  });

  final Rect? hole;
  final Offset? pointer;
  final Color outline;
  final bool window;
  final bool scrolling;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..fillType = .evenOdd;
    final rect = hole;
    if (rect != null) scrim.addRect(scrolling ? rect.inflate(1) : rect);
    canvas.drawPath(scrim, Paint()..color = const Color(0x8c000000));
    if (rect != null && window && !scrolling) {
      canvas.drawRect(
        rect,
        Paint()
          ..color = outline
          ..style = .stroke
          ..strokeWidth = 3,
      );
    }
    if (rect != null && scrolling) {
      final path = Path()..addRect(rect.inflate(1.5));
      final paint = Paint()
        ..color = outline
        ..style = .stroke
        ..strokeWidth = 1;
      for (final metric in path.computeMetrics()) {
        for (var start = 0.0; start < metric.length; start += 12) {
          canvas.drawPath(
            metric.extractPath(start, math.min(start + 6, metric.length)),
            paint,
          );
        }
      }
    }
    final at = pointer;
    if (at != null) {
      final paint = Paint()
        ..color = outline.withValues(alpha: .55)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, at.dy), Offset(size.width, at.dy), paint);
      canvas.drawLine(Offset(at.dx, 0), Offset(at.dx, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_OverlayPaint old) =>
      old.hole != hole ||
      old.pointer != pointer ||
      old.outline != outline ||
      old.window != window ||
      old.scrolling != scrolling;
}

class _ScrollingPanel extends StatelessWidget {
  const _ScrollingPanel({
    required this.scroll,
    required this.onBack,
    required this.onDone,
    required this.busy,
  });

  final ScrollPreview scroll;
  final VoidCallback onBack;
  final VoidCallback onDone;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final png = scroll.png;
    return CaptureSurface(
      child: Padding(
        padding: const .all(8),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 8,
          children: [
            Row(
              spacing: 8,
              children: [
                const CaptureIcon(.scrollCapture),
                Flexible(
                  child: Text(
                    'Scrolling capture',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            Text(scroll.message, style: theme.textTheme.bodySmall),
            Wrap(
              spacing: 8,
              children: [
                CaptureKeycap('${scroll.frames} frames'),
                CaptureSizeBadge(
                  Size(scroll.width.toDouble(), scroll.height.toDouble()),
                ),
              ],
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: .circular(12),
                child: ColoredBox(
                  color: theme.colorScheme.surface,
                  child: png == null
                      ? const SizedBox.expand()
                      : Image.memory(
                          png,
                          fit: .contain,
                          alignment: .bottomCenter,
                          gaplessPlayback: true,
                        ),
                ),
              ),
            ),
            LinearProgressIndicator(value: scroll.ready ? 1 : null),
            Wrap(
              alignment: .end,
              spacing: 4,
              children: [
                CaptureButton(
                  label: 'Cancel',
                  variant: .text,
                  onPressed: busy ? null : onBack,
                ),
                CaptureButton(
                  label: 'Done',
                  icon: const CaptureIcon(.check),
                  onPressed: busy || scroll.frames == 0 ? null : onDone,
                ),
              ],
            ),
            const Wrap(
              spacing: 8,
              children: [_Hint('Enter', 'Done'), _Hint('Esc', 'Back')],
            ),
          ],
        ),
      ),
    );
  }
}
