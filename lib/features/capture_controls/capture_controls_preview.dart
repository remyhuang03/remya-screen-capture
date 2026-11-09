import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'capture_buttons.dart';
import 'capture_color_picker.dart';
import 'capture_icon.dart';
import 'capture_labels.dart';
import 'capture_selection.dart';
import 'capture_slider.dart';
import 'capture_swatch.dart';

class CaptureControlsPreview extends StatefulWidget {
  const CaptureControlsPreview({super.key});

  @override
  State<CaptureControlsPreview> createState() => _CaptureControlsPreviewState();
}

enum _Mode { region, window, scroll }

class _CaptureControlsPreviewState extends State<CaptureControlsPreview> {
  static const _presets = {
    'Red': Color(0xfff44336),
    'Blue': Color(0xff2196f3),
    'Yellow': Color(0xffffeb3b),
    'Green': Color(0xff4caf50),
    'Purple': Color(0xff9c27b0),
  };

  bool _pen = false;
  bool _audio = true;
  _Mode _mode = .region;
  Color _color = _presets['Red']!;
  bool _customColor = false;
  List<Color> _recentColors = _presets.values.toList();
  double _strokeWidth = 4;
  String _font = 'Inter';
  Rect _selection = const Rect.fromLTWH(32, 32, 320, 200);

  Future<void> _pickColor() async {
    final color = await showCaptureColorPicker(
      context,
      color: _color,
      recentColors: _recentColors,
    );
    if (color == null || !mounted) return;
    setState(() {
      _color = color;
      _customColor = true;
      _recentColors = [
        color,
        ..._recentColors.where((recent) => recent != color),
      ].take(5).toList();
    });
  }

  void _togglePen() => setState(() => _pen = !_pen);

  void _showButtonPress(CaptureButtonStyle variant) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Copy · ${variant.name} button preview')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, includeRepeats: false):
            _togglePen,
      },
      child: Scaffold(
        body: Focus(
          autofocus: true,
          skipTraversal: true,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1019),
              child: ListView(
                padding: const .all(40),
                children: [
                  Text(
                    'Components · Remya Screen Capture',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontSize: 20, fontWeight: .w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Interactive control preview',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  _Section(
                    title: 'Icon button',
                    description:
                        'Tool selection with hover, press and focus states.',
                    children: [
                      CaptureIconButton(
                        icon: .pen,
                        label: 'Pen',
                        shortcut: 'P',
                        selected: _pen,
                        onPressed: _togglePen,
                      ),
                      CaptureIconButton(
                        icon: .pen,
                        label: 'Pen alternate',
                        selected: !_pen,
                        onPressed: _togglePen,
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Toggle chip',
                    description: 'A labelled binary option.',
                    children: [
                      CaptureToggleChip(
                        label: 'System audio',
                        icon: const CaptureIcon(.volumeUp),
                        selected: _audio,
                        onChanged: (value) => setState(() => _audio = value),
                      ),
                      CaptureToggleChip(
                        label: 'System audio',
                        icon: const CaptureIcon(.volumeUp),
                        selected: !_audio,
                        onChanged: (value) => setState(() => _audio = !value),
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Button',
                    description: 'Filled, tonal, text and error variants.',
                    children: [
                      for (final variant in CaptureButtonStyle.values)
                        CaptureButton(
                          label: 'Copy',
                          icon: const CaptureIcon(.copy),
                          variant: variant,
                          onPressed: () => _showButtonPress(variant),
                        ),
                    ],
                  ),
                  _Section(
                    title: 'Segment',
                    description: 'Connected single-selection buttons.',
                    children: [
                      SingleChildScrollView(
                        scrollDirection: .horizontal,
                        child: CaptureSegmentedControl<_Mode>(
                          segments: const [
                            CaptureSegment(
                              .region,
                              'Region',
                              icon: CaptureIcon.segmentRegion(),
                            ),
                            CaptureSegment(
                              .window,
                              'Window',
                              icon: CaptureIcon(.window),
                            ),
                            CaptureSegment(
                              .scroll,
                              'Scroll',
                              icon: CaptureIcon(.scrollCapture),
                            ),
                          ],
                          value: _mode,
                          onChanged: (value) => setState(() => _mode = value),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Swatch',
                    description:
                        'Choose a preset or open the custom color picker.',
                    children: [
                      for (final preset in _presets.entries)
                        CaptureSwatch(
                          color: preset.value,
                          label: preset.key,
                          selected: !_customColor && _color == preset.value,
                          onPressed: () => setState(() {
                            _color = preset.value;
                            _customColor = false;
                          }),
                        ),
                      CaptureSwatch.custom(
                        selected: _customColor,
                        onPressed: _pickColor,
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Slider',
                    description:
                        'A compact Material 3 Expressive stroke-width slider.',
                    children: [
                      SizedBox(
                        width: 160,
                        child: CaptureSlider(
                          label: 'Stroke width',
                          value: _strokeWidth,
                          min: 1,
                          max: 9,
                          formatValue: (value) => '${value.round()} pixels',
                          onChanged: (value) =>
                              setState(() => _strokeWidth = value),
                        ),
                      ),
                      Text(
                        '${_strokeWidth.round()} px',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Key · Size badge · Tooltip · Divider · Counter',
                    description:
                        'Labels and marks used in toolbars and on the canvas.',
                    spacing: 24,
                    children: [
                      const CaptureKeycap('Enter'),
                      CaptureSizeBadge(_selection.size),
                      const CaptureTooltipLabel('Pen', shortcut: 'P'),
                      const CaptureDivider(),
                      CaptureCounter(1, color: _color),
                    ],
                  ),
                  _Section(
                    title: 'Dropdown',
                    description: 'Choose a value from a Material menu.',
                    children: [
                      CaptureDropdown(
                        label: 'Font',
                        options: const {
                          'Inter': 'Inter',
                          'Roboto': 'Roboto',
                          'Monospace': 'Monospace',
                        },
                        value: _font,
                        onChanged: (value) => setState(() => _font = value),
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Selection',
                    description: 'Drag to move or resize. Hold Shift to keep the ratio. Use the arrow keys to nudge.',
                    padding: 0,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: .horizontal,
                        child: SizedBox(
                          width: 384,
                          height: 264,
                          child: CaptureSelection(
                            rect: _selection,
                            onChanged: (rect) =>
                                setState(() => _selection = rect),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Icons',
                    description: 'Material Symbols Rounded · 20 px',
                    spacing: 0,
                    children: [
                      for (final symbol in CaptureSymbol.values)
                        SizedBox.square(
                          dimension: 44,
                          child: CaptureTooltip(
                            label: symbol.asset.replaceAll('-', ' '),
                            child: Center(child: CaptureIcon(symbol)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.children,
    this.spacing = 16,
    this.padding = 16,
  });

  final String title;
  final String description;
  final List<Widget> children;
  final double spacing;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const .only(bottom: 40),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 12,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: .w700)),
          Text(
            description,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          Material(
            color: colors.surfaceContainer,
            borderRadius: .circular(20),
            clipBehavior: .antiAlias,
            child: Padding(
              padding: .all(padding),
              child: IconTheme.merge(
                data: IconThemeData(color: colors.onSurfaceVariant),
                child: Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  crossAxisAlignment: .center,
                  children: children,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
