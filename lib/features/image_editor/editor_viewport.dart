part of 'image_editor.dart';

const _scrollbarExtent = 16.0;

class _BrushCursor extends CustomPainter {
  _BrushCursor(
    this.cursor,
    this.view,
    this.renderer,
    this.tool,
    this.style,
    this.outline,
  ) : super(repaint: cursor);

  final ValueNotifier<Offset?> cursor;
  final _View view;
  final _EditorRenderer renderer;
  final _Tool tool;
  final _Style style;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final position = cursor.value;
    final visibleImage = view.visibleImage;
    if (position == null || !visibleImage.contains(position)) return;
    final radius = style.size * view.scale / 2;
    canvas.save();
    canvas.clipRect(visibleImage);
    if (tool == .mosaic) {
      canvas.save();
      canvas.translate(view.origin.dx, view.origin.dy);
      canvas.scale(view.scale);
      renderer._mosaic(
        canvas,
        _Annotation(.mosaic, [
          view.toImage(position),
        ], style.copyWith(brush: true)),
      );
      canvas.restore();
      canvas.drawCircle(
        position,
        radius,
        Paint()
          ..color = outline
          ..strokeWidth = 1
          ..style = .stroke,
      );
    } else {
      final color = tool == .highlighter
          ? style.color.withValues(alpha: _highlighterOpacity)
          : style.color;
      canvas.drawCircle(position, radius, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrushCursor oldDelegate) =>
      view.origin != oldDelegate.view.origin ||
      view.scale != oldDelegate.view.scale ||
      view.crop != oldDelegate.view.crop ||
      tool != oldDelegate.tool ||
      style != oldDelegate.style ||
      outline != oldDelegate.outline;
}

class _CanvasScrollbar extends StatefulWidget {
  const _CanvasScrollbar({
    required this.axis,
    required this.viewport,
    required this.overflow,
    required this.offset,
    required this.onScroll,
  });

  final Axis axis;
  final double viewport;
  final double overflow;
  final double offset;
  final ValueChanged<double> onScroll;

  @override
  State<_CanvasScrollbar> createState() => _CanvasScrollbarState();
}

class _CanvasScrollbarState extends State<_CanvasScrollbar> {
  double _grabOffset = 0;

  void _scrollTo(double offset) =>
      widget.onScroll(offset.clamp(0, widget.overflow));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final horizontal = widget.axis == .horizontal;
    return LayoutBuilder(
      builder: (context, constraints) {
        final track = horizontal ? constraints.maxWidth : constraints.maxHeight;
        if (track <= 24) return const SizedBox.shrink();
        final thumb =
            (track * widget.viewport / (widget.viewport + widget.overflow))
                .clamp(24.0, track);
        final travel = track - thumb;
        if (travel <= 0) return const SizedBox.shrink();
        final start = widget.offset / widget.overflow * travel;
        final step = widget.viewport / 4;
        String percentage(double offset) =>
            '${(100 * offset.clamp(0, widget.overflow) / widget.overflow).round()}%';
        double along(Offset point) => horizontal ? point.dx : point.dy;
        void jump(double position) =>
            _scrollTo((position - _grabOffset) / travel * widget.overflow);

        return Semantics(
          label: horizontal
              ? 'Horizontal image scroll'
              : 'Vertical image scroll',
          value: percentage(widget.offset),
          increasedValue: percentage(widget.offset + step),
          decreasedValue: percentage(widget.offset - step),
          onIncrease: () => _scrollTo(widget.offset + step),
          onDecrease: () => _scrollTo(widget.offset - step),
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: .opaque,
              excludeFromSemantics: true,
              dragStartBehavior: .down,
              onPanDown: (details) {
                final position = along(details.localPosition);
                final onThumb = position >= start && position <= start + thumb;
                _grabOffset = onThumb ? position - start : thumb / 2;
                if (!onThumb) jump(position);
              },
              onPanUpdate: (details) => jump(along(details.localPosition)),
              child: Stack(
                children: [
                  Positioned.fill(
                    top: horizontal ? 4 : 0,
                    bottom: horizontal ? 4 : 0,
                    left: horizontal ? 0 : 4,
                    right: horizontal ? 0 : 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: .circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    top: horizontal ? 4 : start,
                    left: horizontal ? start : 4,
                    width: horizontal ? thumb : 8,
                    height: horizontal ? 8 : thumb,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.outline,
                        borderRadius: .circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
