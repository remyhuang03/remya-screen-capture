import 'package:material_ui/material_ui.dart';

import 'capture_icon.dart';
import 'capture_labels.dart';

class CaptureSwatch extends StatelessWidget {
  const CaptureSwatch({
    super.key,
    required Color this.color,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  const CaptureSwatch.custom({
    super.key,
    this.label = 'Custom color',
    required this.selected,
    required this.onPressed,
  }) : color = null;

  final Color? color;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CaptureTooltip(
      label: label,
      child: Semantics(
        selected: selected,
        child: OutlinedButton(
          onPressed: onPressed,
          style:
              OutlinedButton.styleFrom(
                foregroundColor: colors.onSurface,
                fixedSize: const Size.square(28),
                minimumSize: Size.zero,
                padding: .zero,
                tapTargetSize: .shrinkWrap,
                visualDensity: .standard,
                shape: RoundedRectangleBorder(
                  borderRadius: .circular(selected ? 10 : 14),
                ),
              ).copyWith(
                side: .resolveWith((states) {
                  if (states.contains(WidgetState.focused)) {
                    return BorderSide(color: colors.primary, width: 2);
                  }
                  return selected
                      ? BorderSide(color: colors.onSurface, width: 2)
                      : BorderSide.none;
                }),
              ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: selected ? 16 : 22,
            height: selected ? 16 : 22,
            alignment: .center,
            decoration: BoxDecoration(
              color: color ?? colors.surfaceContainerHighest,
              borderRadius: .circular(selected ? 5 : 11),
            ),
            child: color == null ? const CaptureIcon.swatchAdd() : null,
          ),
        ),
      ),
    );
  }
}
