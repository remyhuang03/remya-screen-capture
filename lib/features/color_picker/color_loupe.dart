import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../screenshot/capture_session.dart';
import 'color_data.dart';

class ColorLoupe extends StatelessWidget {
  const ColorLoupe({
    super.key,
    required this.output,
    required this.pointer,
    required this.pixel,
    required this.position,
    required this.viewport,
    required this.zoom,
    required this.format,
    required this.uppercase,
  });

  final FrozenOutput output;
  final Offset pointer;
  final Offset pixel;
  final Offset position;
  final Size viewport;
  final int zoom;
  final ColorFormat format;
  final bool uppercase;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sample = output.colorAt(pixel);
    final value = format.format(sample, uppercase: uppercase);
    final coordinate = '${position.dx.toInt()}, ${position.dy.toInt()}';

    return Positioned.fill(
      child: IgnorePointer(
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodySmall!,
          child: Stack(
            children: [
              Positioned(
                left: pointer.dx - 12.5,
                top: pointer.dy - 12.5,
                child: CustomPaint(
                  painter: _Reticle(colors.onSurface),
                  size: const Size.square(25),
                ),
              ),
              CustomSingleChildLayout(
                delegate: _LoupePosition(pointer),
                child: Column(
                  mainAxisSize: .min,
                  spacing: 8,
                  children: [
                    Material(
                      color: colors.surfaceContainerLowest,
                      elevation: 8,
                      shadowColor: Colors.black54,
                      borderRadius: .circular(44),
                      clipBehavior: .antiAlias,
                      child: SizedBox.square(
                        dimension: math.min(
                          159,
                          math.max(0, viewport.shortestSide - 8),
                        ),
                        child: Stack(
                          fit: .expand,
                          children: [
                            CustomPaint(
                              painter: _ColorLens(output, pixel, sample, zoom),
                            ),
                            Positioned(
                              right: 10,
                              top: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHigh,
                                  borderRadius: .circular(8),
                                ),
                                child: Padding(
                                  padding: const .symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    '$zoom×',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: .circular(16),
                        border: .all(color: colors.surfaceContainerHighest),
                      ),
                      child: Padding(
                        padding: const .fromLTRB(6, 6, 12, 6),
                        child: Wrap(
                          alignment: .center,
                          crossAxisAlignment: .center,
                          spacing: 8,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: sample,
                                borderRadius: .circular(7),
                                border: .all(color: colors.outlineVariant),
                              ),
                            ),
                            Text(
                              value,
                              style: const TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontFamilyFallback: [
                                  'JetBrainsMono Nerd Font Mono',
                                  'monospace',
                                ],
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              coordinate,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoupePosition extends SingleChildLayoutDelegate {
  const _LoupePosition(this.pointer);

  final Offset pointer;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.deflate(const .all(4)).biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double place(double point, double limit, double extent) {
      const gap = 24.0;
      final after = point + gap;
      final before = point - gap - extent;
      return (after + extent + 4 <= limit ? after : before).clamp(
        4.0,
        math.max(4.0, limit - extent - 4),
      );
    }

    return Offset(
      place(pointer.dx, size.width, childSize.width),
      place(pointer.dy, size.height, childSize.height),
    );
  }

  @override
  bool shouldRelayout(_LoupePosition oldDelegate) =>
      pointer != oldDelegate.pointer;
}

class _Reticle extends CustomPainter {
  const _Reticle(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()..strokeCap = .round;
    for (final unit in const [
      Offset(-1, 0),
      Offset(1, 0),
      Offset(0, -1),
      Offset(0, 1),
    ]) {
      final start = center + unit * 5.5;
      final end = center + unit * 11;
      canvas.drawLine(
        start,
        end,
        paint
          ..color = Colors.black54
          ..strokeWidth = 3.5,
      );
      canvas.drawLine(
        start,
        end,
        paint
          ..color = color
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_Reticle oldDelegate) => color != oldDelegate.color;
}

class _ColorLens extends CustomPainter {
  const _ColorLens(this.output, this.pixel, this.color, this.zoom);

  final FrozenOutput output;
  final Offset pixel;
  final Color color;
  final int zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final cell = zoom + 2.0;
    final paint = Paint()..isAntiAlias = false;
    final cells = (size.width / cell / 2).ceil();
    for (var y = -cells; y <= cells; y++) {
      for (var x = -cells; x <= cells; x++) {
        final source = pixel + Offset(x.toDouble(), y.toDouble());
        final target = Rect.fromCenter(
          center: center + Offset(x * cell, y * cell),
          width: cell - 1,
          height: cell - 1,
        );
        if (source.dx >= 0 &&
            source.dy >= 0 &&
            source.dx < output.image.width &&
            source.dy < output.image.height) {
          canvas.drawRect(target, paint..color = output.colorAt(source));
        }
      }
    }
    final outline = Paint()
      ..style = .stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: cell + 2, height: cell + 2),
        const Radius.circular(3),
      ),
      outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(2),
        const Radius.circular(42),
      ),
      outline
        ..color = color
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(_ColorLens oldDelegate) =>
      output != oldDelegate.output ||
      pixel != oldDelegate.pixel ||
      zoom != oldDelegate.zoom;
}
