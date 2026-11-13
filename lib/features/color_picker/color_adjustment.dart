import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class ColorAdjustment extends StatelessWidget {
  const ColorAdjustment({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onApply,
  });

  final HSLColor value;
  final bool enabled;
  final ValueChanged<HSLColor> onChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: .circular(24),
    ),
    padding: const .symmetric(horizontal: 16, vertical: 12),
    child: Column(
      spacing: 12,
      children: [
        _ChannelSlider(
          label: 'H',
          name: 'Hue',
          unit: '°',
          max: 360,
          autofocus: true,
          value: value.hue,
          gradient: [
            for (var hue = 0; hue <= 360; hue += 60)
              HSLColor.fromAHSL(1, hue.toDouble(), 1, .5).toColor(),
          ],
          onChanged: enabled ? (hue) => onChanged(value.withHue(hue)) : null,
          onApply: onApply,
        ),
        _ChannelSlider(
          label: 'S',
          name: 'Saturation',
          unit: '%',
          max: 100,
          value: value.saturation * 100,
          gradient: [
            value.withSaturation(0).toColor(),
            value.withSaturation(1).toColor(),
          ],
          onChanged: enabled
              ? (saturation) =>
                    onChanged(value.withSaturation(saturation / 100))
              : null,
          onApply: onApply,
        ),
        _ChannelSlider(
          label: 'L',
          name: 'Lightness',
          unit: '%',
          max: 100,
          value: value.lightness * 100,
          gradient: [
            Colors.black,
            value.withLightness(.5).toColor(),
            Colors.white,
          ],
          onChanged: enabled
              ? (lightness) => onChanged(value.withLightness(lightness / 100))
              : null,
          onApply: onApply,
        ),
      ],
    ),
  );
}

class _ChannelSlider extends StatefulWidget {
  const _ChannelSlider({
    required this.label,
    required this.name,
    required this.unit,
    required this.max,
    required this.value,
    required this.gradient,
    required this.onChanged,
    required this.onApply,
    this.autofocus = false,
  });

  final String label;
  final String name;
  final String unit;
  final int max;
  final double value;
  final List<Color> gradient;
  final ValueChanged<double>? onChanged;
  final VoidCallback onApply;
  final bool autofocus;

  @override
  State<_ChannelSlider> createState() => _ChannelSliderState();
}

class _ChannelSliderState extends State<_ChannelSlider> {
  late final _slider = FocusNode(onKeyEvent: (_, event) => _sliderKey(event));
  late final _field = FocusNode(skipTraversal: true, onKeyEvent: _fieldKey)
    ..addListener(_fieldFocusChanged);
  late final _text = TextEditingController(text: '${widget.value.round()}');

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _slider.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _slider.dispose();
    _field.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ChannelSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_field.hasFocus || oldWidget.value != widget.value) _syncText();
  }

  void _fieldFocusChanged() {
    if (!_field.hasFocus) _syncText();
  }

  void _syncText() {
    final text = '${widget.value.round()}';
    if (_text.text != text) _text.text = text;
  }

  void _type(String text) {
    final value = int.tryParse(text);
    if (value != null) {
      widget.onChanged?.call(value.clamp(0, widget.max).toDouble());
    }
  }

  KeyEventResult _fieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return .ignored;
    if (event.logicalKey == .tab) {
      final direction = HardwareKeyboard.instance.isShiftPressed;
      if (direction) {
        node.previousFocus();
      } else {
        node.nextFocus();
      }
      return .handled;
    }
    if (event.logicalKey == .enter || event.logicalKey == .numpadEnter) {
      widget.onApply();
      return .handled;
    }
    return .ignored;
  }

  KeyEventResult _sliderKey(KeyEvent event) {
    if (!_slider.hasPrimaryFocus ||
        event is KeyUpEvent ||
        widget.onChanged == null) {
      return .ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed) {
      return .ignored;
    }
    final key = event.logicalKey;
    if (key == .arrowLeft || key == .arrowRight) {
      final step =
          (keyboard.isShiftPressed ? 10 : 1) * (key == .arrowLeft ? -1 : 1);
      widget.onChanged!(
        (widget.value.round() + step).clamp(0, widget.max).toDouble(),
      );
      return .handled;
    }
    if (event is! KeyDownEvent) return .ignored;
    final digit = event.character;
    if (digit == null || int.tryParse(digit) == null) return .ignored;
    _field.requestFocus();
    _text.value = TextEditingValue(
      text: digit,
      selection: const TextSelection.collapsed(offset: 1),
    );
    _type(digit);
    return .handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      spacing: 12,
      children: [
        SizedBox(
          width: 16,
          child: Text(widget.label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Semantics(
            label: widget.name,
            child: SizedBox(
              height: 36,
              child: Stack(
                fit: .expand,
                children: [
                  Center(
                    child: Container(
                      height: 20,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: widget.gradient),
                        borderRadius: .circular(10),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      year2023: false,
                      trackHeight: 20,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      disabledActiveTrackColor: Colors.transparent,
                      disabledInactiveTrackColor: Colors.transparent,
                      thumbColor: colors.onSurface,
                      overlayColor: colors.primary.withValues(alpha: .24),
                      thumbSize: const WidgetStatePropertyAll(Size(5, 36)),
                    ),
                    child: Slider(
                      focusNode: _slider,
                      value: widget.value,
                      max: widget.max.toDouble(),
                      divisions: widget.max,
                      padding: const .symmetric(horizontal: 2),
                      onChanged: widget.onChanged,
                      semanticFormatterCallback: (value) =>
                          '${value.round()}${widget.unit}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          width: 64,
          height: 32,
          child: Semantics(
            label:
                '${widget.name} in ${widget.unit == '°' ? 'degrees' : 'percent'}',
            child: TextField(
              controller: _text,
              focusNode: _field,
              enabled: widget.onChanged != null,
              onTap: () => _text.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _text.text.length,
              ),
              onChanged: _type,
              onSubmitted: (_) => widget.onApply(),
              keyboardType: .number,
              textAlign: .right,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 13,
              ),
              decoration: InputDecoration(
                suffixText: widget.unit,
                suffixStyle: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 13,
                ),
                isDense: true,
                filled: true,
                fillColor: colors.surfaceContainerHighest,
                contentPadding: const .symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: .circular(12),
                  borderSide: .none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: .circular(12),
                  borderSide: BorderSide(color: colors.primary, width: 2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
