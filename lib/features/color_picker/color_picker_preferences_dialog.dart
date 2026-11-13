import 'package:material_ui/material_ui.dart';

import '../capture_controls/capture_buttons.dart';
import 'color_data.dart';

Future<ColorPickerPreferences?> showColorPickerPreferences(
  BuildContext context,
  ColorPickerPreferences preferences,
) => showDialog<ColorPickerPreferences>(
  context: context,
  builder: (_) => _PreferencesDialog(preferences),
);

class _PreferencesDialog extends StatefulWidget {
  const _PreferencesDialog(this.preferences);

  final ColorPickerPreferences preferences;

  @override
  State<_PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<_PreferencesDialog> {
  late var _action = widget.preferences.action;
  late var _format = widget.preferences.defaultFormat;
  late var _uppercase = widget.preferences.uppercase;
  late var _historySize = widget.preferences.historySize;
  late final _enabled = widget.preferences.formats.toSet();
  late final _order = [
    ...widget.preferences.formats,
    ...ColorFormat.values.where((format) => !_enabled.contains(format)),
  ];

  void _toggle(ColorFormat format, bool enabled) {
    setState(() {
      if (enabled) {
        _enabled.add(format);
      } else {
        _enabled.remove(format);
        if (format == _format) _format = _order.firstWhere(_enabled.contains);
      }
    });
  }

  void _move(int from, int to) {
    if (to >= 0 && to < _order.length && from != to) {
      setState(() => _order.insert(to, _order.removeAt(from)));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Color picker settings'),
    content: SizedBox(
      width: 390,
      height: 458,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          _Setting(
            label: 'After picking',
            child: CaptureDropdown(
              label: 'After picking',
              options: const {
                ColorPickAction.copyAndOpen: 'Copy + open panel',
                ColorPickAction.copyOnly: 'Copy only',
                ColorPickAction.openOnly: 'Open panel without copying',
              },
              value: _action,
              onChanged: (value) => setState(() => _action = value),
            ),
          ),
          _Setting(
            label: 'Default copy format',
            child: CaptureDropdown(
              label: 'Default copy format',
              options: {
                for (final format in _order.where(_enabled.contains))
                  format: format.label,
              },
              value: _format,
              onChanged: (value) => setState(() => _format = value),
            ),
          ),
          _Setting(
            label: 'HEX case',
            child: CaptureDropdown(
              label: 'HEX case',
              options: const {true: 'Upper', false: 'Lower'},
              value: _uppercase,
              onChanged: (value) => setState(() => _uppercase = value),
            ),
          ),
          _Setting(
            label: 'History size',
            trailing: Text('$_historySize'),
            child: Semantics(
              label: 'History size',
              child: Slider(
                value: _historySize.toDouble(),
                max: 128,
                divisions: 128,
                label: '$_historySize',
                onChanged: (value) =>
                    setState(() => _historySize = value.round()),
              ),
            ),
          ),
          const Divider(),
          Tooltip(
            message: 'Drag or press Alt + ↑/↓ to reorder',
            child: Text(
              'Visible formats',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: _order.length,
              onReorderItem: _move,
              itemBuilder: (context, index) {
                final format = _order[index];
                final enabled = _enabled.contains(format);
                return CallbackShortcuts(
                  key: ValueKey(format),
                  bindings: {
                    const SingleActivator(.arrowUp, alt: true): () =>
                        _move(index, index - 1),
                    const SingleActivator(.arrowDown, alt: true): () =>
                        _move(index, index + 1),
                  },
                  child: CheckboxListTile(
                    title: Text(format.label),
                    controlAffinity: .leading,
                    contentPadding: const .only(right: 36),
                    dense: true,
                    value: enabled,
                    onChanged: enabled && _enabled.length == 1
                        ? null
                        : (value) => _toggle(format, value!),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      CaptureButton(
        label: 'Cancel',
        variant: .text,
        onPressed: () => Navigator.pop(context),
      ),
      CaptureButton(
        label: 'Save',
        onPressed: () => Navigator.pop(
          context,
          ColorPickerPreferences(
            action: _action,
            defaultFormat: _format,
            uppercase: _uppercase,
            formats: _order.where(_enabled.contains).toList(),
            historySize: _historySize,
          ),
        ),
      ),
    ],
  );
}

class _Setting extends StatelessWidget {
  const _Setting({required this.label, required this.child, this.trailing});

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Row(
      spacing: 8,
      children: [
        SizedBox(width: 145, child: Text(label)),
        Expanded(child: child),
        ?trailing,
      ],
    ),
  );
}
