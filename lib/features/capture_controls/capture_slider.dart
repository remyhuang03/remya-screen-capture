import 'package:material_ui/material_ui.dart';

class CaptureSlider extends StatelessWidget {
  const CaptureSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.formatValue,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final String Function(double)? formatValue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: SizedBox(
        height: 32,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            year2023: false,
            trackHeight: 16,
            trackGap: 6,
            inactiveTrackColor: colors.secondaryContainer,
            thumbSize: .resolveWith(
              (states) =>
                  Size(states.contains(WidgetState.pressed) ? 2 : 4, 32),
            ),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            padding: const .symmetric(horizontal: 2),
            onChanged: onChanged,
            semanticFormatterCallback: formatValue,
          ),
        ),
      ),
    );
  }
}
