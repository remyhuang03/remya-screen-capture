import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'capture_buttons.dart';
import 'capture_swatch.dart';

Future<Color?> showCaptureColorPicker(
  BuildContext context, {
  required Color color,
  List<Color> recentColors = const [],
}) => showDialog<Color>(
  context: context,
  builder: (_) => _ColorPicker(color: color, recentColors: recentColors),
);

String _hex(Color color) => (color.toARGB32() & 0xffffff)
    .toRadixString(16)
    .padLeft(6, '0')
    .toUpperCase();

class _ColorPicker extends StatefulWidget {
  const _ColorPicker({required this.color, required this.recentColors});

  final Color color;
  final List<Color> recentColors;

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late HSVColor _color = HSVColor.fromColor(widget.color.withAlpha(255));
  late final _hexField = TextEditingController(text: _hex(widget.color));
  bool _validHex = true;

  @override
  void dispose() {
    _hexField.dispose();
    super.dispose();
  }

  void _setColor(HSVColor color) {
    final hex = _hex(color.toColor());
    _hexField.value = TextEditingValue(
      text: hex,
      selection: TextSelection.collapsed(offset: hex.length),
    );
    setState(() {
      _color = color;
      _validHex = true;
    });
  }

  void _editHex(String text) {
    final rgb = text.length == 6 ? int.tryParse(text, radix: 16) : null;
    setState(() {
      _validHex = rgb != null;
      if (rgb != null) _color = HSVColor.fromColor(Color(0xff000000 | rgb));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 300),
      insetPadding: const .all(16),
      shape: RoundedRectangleBorder(
        borderRadius: .circular(28),
        side: BorderSide(color: colors.surfaceContainerHighest),
      ),
      child: Semantics(
        label: 'Custom color picker',
        child: SingleChildScrollView(
          padding: const .all(17),
          child: Column(
            mainAxisSize: .min,
            spacing: 14,
            children: [
              _SaturationValue(color: _color, onChanged: _setColor),
              _HueSlider(
                value: _color.hue,
                onChanged: (value) => _setColor(_color.withHue(value)),
              ),
              Row(
                spacing: 10,
                children: [
                  SizedBox.square(
                    dimension: 36,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _color.toColor(),
                        shape: .circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Semantics(
                      label: 'Six-digit hexadecimal color',
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _hexField,
                          onChanged: _editHex,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp('[0-9a-fA-F]'),
                            ),
                            LengthLimitingTextInputFormatter(6),
                          ],
                          style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            prefixText: '#  ',
                            prefixStyle: TextStyle(
                              color: colors.onSurfaceVariant,
                            ),
                            filled: true,
                            fillColor: colors.surfaceContainerHighest,
                            isDense: true,
                            contentPadding: const .symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderSide: .none,
                              borderRadius: .circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: colors.primary),
                              borderRadius: .circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.recentColors.isNotEmpty)
                Align(
                  alignment: .centerLeft,
                  child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: .center,
                    children: [
                      Text(
                        'Recent',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      for (final color in widget.recentColors)
                        CaptureSwatch(
                          color: color,
                          label: '#${_hex(color)}',
                          selected: false,
                          onPressed: () => _setColor(
                            HSVColor.fromColor(color.withAlpha(255)),
                          ),
                        ),
                    ],
                  ),
                ),
              Row(
                mainAxisAlignment: .end,
                spacing: 8,
                children: [
                  CaptureButton(
                    label: 'Cancel',
                    variant: .text,
                    onPressed: () => Navigator.pop(context),
                  ),
                  CaptureButton(
                    label: 'Done',
                    onPressed: _validHex
                        ? () => Navigator.pop(context, _color.toColor())
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaturationValue extends StatelessWidget {
  const _SaturationValue({required this.color, required this.onChanged});

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 170,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        void select(Offset position) {
          onChanged(
            color
                .withSaturation((position.dx / size.width).clamp(0, 1))
                .withValue(1 - (position.dy / size.height).clamp(0, 1)),
          );
        }

        return GestureDetector(
          excludeFromSemantics: true,
          onPanDown: (details) => select(details.localPosition),
          onPanUpdate: (details) => select(details.localPosition),
          child: ClipRRect(
            borderRadius: .circular(16),
            child: Stack(
              fit: .expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white,
                        color.withSaturation(1).withValue(1).toColor(),
                      ],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: .topCenter,
                      end: .bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                ),
                Positioned(
                  left: size.width * color.saturation - 10,
                  top: size.height * (1 - color.value) - 10,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: color.toColor(),
                      shape: .circle,
                      border: .all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Hue',
    child: SizedBox(
      height: 16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: .circular(8),
          gradient: const LinearGradient(
            colors: [
              Color(0xffff0000),
              Color(0xffffff00),
              Color(0xff00ff00),
              Color(0xff00ffff),
              Color(0xff0000ff),
              Color(0xffff00ff),
              Color(0xffff0000),
            ],
          ),
        ),
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            year2023: false,
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
            thumbColor: Theme.of(context).colorScheme.onSurface,
            thumbSize: const WidgetStatePropertyAll(Size(4, 28)),
          ),
          child: Slider(
            value: value,
            max: 360,
            onChanged: onChanged,
            padding: const .symmetric(horizontal: 2),
            semanticFormatterCallback: (value) => '${value.round()}°',
          ),
        ),
      ),
    ),
  );
}
