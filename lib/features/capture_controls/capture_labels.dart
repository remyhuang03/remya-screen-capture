import 'package:material_ui/material_ui.dart';

class CaptureKeycap extends StatelessWidget {
  const CaptureKeycap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: .circular(6),
      ),
      padding: const .symmetric(horizontal: 6, vertical: 2),
      child: Text(
        label,
        textAlign: .center,
        style: TextStyle(
          color: colors.onSurfaceVariant,
          fontSize: 11,
          height: 13 / 11,
          fontWeight: .w500,
        ),
      ),
    );
  }
}

class CaptureSizeBadge extends StatelessWidget {
  const CaptureSizeBadge(this.size, {super.key});

  final Size size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.inverseSurface,
        borderRadius: .circular(8),
      ),
      padding: const .symmetric(horizontal: 8, vertical: 4),
      child: Text(
        '${size.width.round()} × ${size.height.round()}',
        style: TextStyle(
          color: colors.onInverseSurface,
          fontSize: 12,
          height: 1.25,
          fontWeight: .w500,
        ),
      ),
    );
  }
}

class CaptureTooltip extends StatelessWidget {
  const CaptureTooltip({
    super.key,
    required this.label,
    required this.child,
    this.shortcut,
  });

  final String label;
  final String? shortcut;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      richMessage: _tooltipLabel(colors, label, shortcut),
      decoration: _tooltipDecoration(colors),
      padding: const .fromLTRB(10, 4, 6, 4),
      textStyle: Theme.of(context).textTheme.bodySmall,
      child: child,
    );
  }
}

class CaptureTooltipLabel extends StatelessWidget {
  const CaptureTooltipLabel(this.label, {super.key, this.shortcut});

  final String label;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: _tooltipDecoration(colors),
      child: Padding(
        padding: const .fromLTRB(10, 4, 6, 4),
        child: Text.rich(_tooltipLabel(colors, label, shortcut)),
      ),
    );
  }
}

BoxDecoration _tooltipDecoration(ColorScheme colors) =>
    BoxDecoration(color: colors.inverseSurface, borderRadius: .circular(8));

TextSpan _tooltipLabel(ColorScheme colors, String label, String? shortcut) =>
    TextSpan(
      text: label,
      style: TextStyle(
        color: colors.onInverseSurface,
        fontSize: 12,
        height: 1.25,
        fontWeight: .w500,
      ),
      children: [
        if (shortcut != null)
          WidgetSpan(
            alignment: .middle,
            child: Padding(
              padding: const .only(left: 8),
              child: Container(
                decoration: BoxDecoration(
                  border: .all(color: colors.outline),
                  borderRadius: .circular(4),
                ),
                padding: const .symmetric(horizontal: 5, vertical: 1),
                child: Text(
                  shortcut,
                  style: TextStyle(
                    color: colors.onInverseSurface,
                    fontSize: 11,
                    height: 13 / 11,
                    fontWeight: .w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

class CaptureDivider extends StatelessWidget {
  const CaptureDivider({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 24,
    child: VerticalDivider(
      width: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    ),
  );
}

class CaptureCounter extends StatelessWidget {
  const CaptureCounter(this.number, {super.key, required this.color});

  final int number;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final white = color.computeLuminance() < .179;
    return Container(
      width: 28,
      height: 28,
      alignment: .center,
      decoration: BoxDecoration(
        color: color,
        shape: .circle,
        border: .all(color: Colors.white, width: 2),
      ),
      padding: const .all(2),
      child: FittedBox(
        fit: .scaleDown,
        child: Text(
          '$number',
          style: TextStyle(
            color: white ? Colors.white : Colors.black,
            fontSize: 14,
            fontWeight: .w700,
          ),
        ),
      ),
    );
  }
}
