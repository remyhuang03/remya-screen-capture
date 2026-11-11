import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Edits a rectangle in the local logical pixels of a bounded capture area.
/// Keep [rect] inside that area and at least [minimumExtent] on both axes.
class CaptureSelection extends StatefulWidget {
  const CaptureSelection({
    super.key,
    required this.rect,
    required this.onChanged,
    this.nudgeUnit = const Offset(1, 1),
  });

  static const minimumExtent = 24.0;

  final Rect rect;
  final ValueChanged<Rect>? onChanged;
  final Offset nudgeUnit;

  @override
  State<CaptureSelection> createState() => _CaptureSelectionState();
}

class _CaptureSelectionState extends State<CaptureSelection> {
  final _focusNode = FocusNode(debugLabel: 'Capture region');
  ({Rect rect, Offset origin, _Handle? handle})? _drag;
  bool _showFocus = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = widget.onChanged != null;
    final rect = widget.rect;
    final handleTarget = math.min(24.0, rect.size.shortestSide / 2);
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = constraints.biggest;
        return FocusableActionDetector(
          enabled: enabled,
          focusNode: _focusNode,
          onShowFocusHighlight: (value) => setState(() => _showFocus = value),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowLeft): _Nudge(
              Offset(-1, 0),
            ),
            SingleActivator(LogicalKeyboardKey.arrowRight): _Nudge(
              Offset(1, 0),
            ),
            SingleActivator(LogicalKeyboardKey.arrowUp): _Nudge(Offset(0, -1)),
            SingleActivator(LogicalKeyboardKey.arrowDown): _Nudge(Offset(0, 1)),
            SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): _Nudge(
              Offset(-10, 0),
            ),
            SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): _Nudge(
              Offset(10, 0),
            ),
            SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): _Nudge(
              Offset(0, -10),
            ),
            SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): _Nudge(
              Offset(0, 10),
            ),
          },
          actions: {
            _Nudge: CallbackAction<_Nudge>(
              onInvoke: (intent) {
                final unit = widget.nudgeUnit;
                final delta = Offset(
                  intent.delta.dx * unit.dx,
                  intent.delta.dy * unit.dy,
                );
                widget.onChanged?.call(_move(rect, bounds, delta));
                return null;
              },
            ),
          },
          child: Semantics(
            label: 'Capture region',
            value: '${rect.width.round()} by ${rect.height.round()}',
            hint: 'Use arrow keys to move the selection. Hold Shift to move ten pixels.',
            child: Stack(
              fit: .expand,
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: _dragTarget(
                    bounds: bounds,
                    cursor: SystemMouseCursors.move,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: .all(
                          color: colors.primary,
                          width: _showFocus ? 3 : 2,
                          strokeAlign: BorderSide.strokeAlignOutside,
                        ),
                      ),
                    ),
                  ),
                ),
                for (final handle in _Handle.values)
                  Positioned.fromRect(
                    rect: Rect.fromCenter(
                      center: handle.alignment.withinRect(rect),
                      width: handleTarget,
                      height: handleTarget,
                    ),
                    child: _dragTarget(
                      bounds: bounds,
                      cursor: handle.cursor,
                      handle: handle,
                      child: Center(
                        child: _HandleMark(handle: handle, colors: colors),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dragTarget({
    required Size bounds,
    required MouseCursor cursor,
    required Widget child,
    _Handle? handle,
  }) {
    if (widget.onChanged == null) return child;
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: .opaque,
        dragStartBehavior: .down,
        excludeFromSemantics: true,
        onTap: _focusNode.requestFocus,
        onPanStart: (details) {
          if (_drag != null) return;
          _focusNode.requestFocus();
          _drag = (
            rect: widget.rect,
            origin: (context.findRenderObject()! as RenderBox).globalToLocal(
              details.globalPosition,
            ),
            handle: handle,
          );
        },
        onPanUpdate: (details) {
          final drag = _drag;
          if (drag == null || drag.handle != handle) return;
          final position = (context.findRenderObject()! as RenderBox)
              .globalToLocal(details.globalPosition);
          final delta = position - drag.origin;
          final next = handle == null
              ? _move(drag.rect, bounds, delta)
              : _resize(
                  drag.rect,
                  bounds,
                  delta,
                  handle.alignment,
                  lockRatio: HardwareKeyboard.instance.isShiftPressed,
                );
          widget.onChanged?.call(next);
        },
        onPanEnd: (_) => _finishDrag(handle),
        onPanCancel: () => _finishDrag(handle),
        child: child,
      ),
    );
  }

  void _finishDrag(_Handle? handle) {
    if (_drag?.handle == handle) _drag = null;
  }
}

class _Nudge extends Intent {
  const _Nudge(this.delta);

  final Offset delta;
}

enum _Handle {
  topLeft(Alignment.topLeft, SystemMouseCursors.resizeUpLeftDownRight),
  topRight(Alignment.topRight, SystemMouseCursors.resizeUpRightDownLeft),
  bottomLeft(Alignment.bottomLeft, SystemMouseCursors.resizeUpRightDownLeft),
  bottomRight(Alignment.bottomRight, SystemMouseCursors.resizeUpLeftDownRight),
  top(Alignment.topCenter, SystemMouseCursors.resizeUpDown),
  bottom(Alignment.bottomCenter, SystemMouseCursors.resizeUpDown),
  left(Alignment.centerLeft, SystemMouseCursors.resizeLeftRight),
  right(Alignment.centerRight, SystemMouseCursors.resizeLeftRight);

  const _Handle(this.alignment, this.cursor);

  final Alignment alignment;
  final MouseCursor cursor;
}

class _HandleMark extends StatelessWidget {
  const _HandleMark({required this.handle, required this.colors});

  final _Handle handle;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final size = switch ((handle.alignment.x, handle.alignment.y)) {
      (0, _) => const Size(24, 6),
      (_, 0) => const Size(6, 24),
      _ => const Size.square(12),
    };
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: colors.primary,
        border: .all(color: colors.surfaceContainerLowest, width: 2),
        borderRadius: .circular(size.shortestSide / 2),
      ),
    );
  }
}

Rect _move(Rect start, Size bounds, Offset delta) => start
    .translate(
      delta.dx.clamp(-start.left, bounds.width - start.right),
      delta.dy.clamp(-start.top, bounds.height - start.bottom),
    )
    .intersect(Offset.zero & bounds);

Rect _resize(
  Rect start,
  Size bounds,
  Offset delta,
  Alignment edge, {
  required bool lockRatio,
}) {
  final minWidth = math.min(CaptureSelection.minimumExtent, start.width);
  final minHeight = math.min(CaptureSelection.minimumExtent, start.height);
  if (!lockRatio) {
    return Rect.fromLTRB(
      edge.x < 0
          ? (start.left + delta.dx).clamp(0, start.right - minWidth)
          : start.left,
      edge.y < 0
          ? (start.top + delta.dy).clamp(0, start.bottom - minHeight)
          : start.top,
      edge.x > 0
          ? (start.right + delta.dx).clamp(start.left + minWidth, bounds.width)
          : start.right,
      edge.y > 0
          ? (start.bottom + delta.dy).clamp(
              start.top + minHeight,
              bounds.height,
            )
          : start.bottom,
    );
  }

  final anchor = Alignment(-edge.x, -edge.y).withinRect(start);
  final horizontal = edge.x * delta.dx / start.width;
  final vertical = edge.y * delta.dy / start.height;
  final change = horizontal.abs() > vertical.abs() ? horizontal : vertical;
  final maxWidth = _availableExtent(anchor.dx, bounds.width, edge.x);
  final maxHeight = _availableExtent(anchor.dy, bounds.height, edge.y);
  final scale = (1 + change).clamp(
    math.max(minWidth / start.width, minHeight / start.height),
    math.max(1, math.min(maxWidth / start.width, maxHeight / start.height)),
  );
  final width = start.width * scale;
  final height = start.height * scale;
  // Clamp rounding error at the area boundary before the next drag.
  return Rect.fromLTWH(
    anchor.dx - width * (1 - edge.x) / 2,
    anchor.dy - height * (1 - edge.y) / 2,
    width,
    height,
  ).intersect(Offset.zero & bounds);
}

double _availableExtent(double anchor, double limit, double edge) =>
    switch (edge) {
      < 0 => anchor,
      > 0 => limit - anchor,
      _ => 2 * math.min(anchor, limit - anchor),
    };
