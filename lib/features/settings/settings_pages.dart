import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../capture_controls/capture_buttons.dart';
import '../color_picker/color_data.dart';
import '../recording/recording_backend.dart';
import 'preference_controller.dart';

class RecordingSettingsPage extends StatelessWidget {
  const RecordingSettingsPage(this.controller, {super.key});

  final PreferenceController<RecordingOptions> controller;

  @override
  Widget build(BuildContext context) => _PreferencePage(
    controller: controller,
    builder: (options, write) => [
      SettingsGroup(
        title: 'Recording',
        children: [
          _Switch(
            title: 'System audio',
            subtitle: 'Record the default output device',
            value: options.systemAudio,
            onChanged: write == null
                ? null
                : (value) => write(options.copyWith(systemAudio: value)),
          ),
          _Switch(
            title: 'Microphone',
            subtitle: 'Record the default input device',
            value: options.microphone,
            onChanged: write == null
                ? null
                : (value) => write(options.copyWith(microphone: value)),
          ),
          _Switch(
            title: 'Cursor',
            subtitle: 'Show the pointer in recordings',
            value: options.cursor,
            onChanged: write == null
                ? null
                : (value) => write(options.copyWith(cursor: value)),
          ),
        ],
      ),
    ],
  );
}

class ColorPickerSettingsPage extends StatelessWidget {
  const ColorPickerSettingsPage(this.controller, {super.key});

  final PreferenceController<ColorPickerPreferences> controller;

  @override
  Widget build(BuildContext context) => _PreferencePage(
    controller: controller,
    builder: (preferences, write) {
      ColorPickerPreferences change({
        ColorPickAction? action,
        ColorFormat? defaultFormat,
        bool? uppercase,
        List<ColorFormat>? formats,
        int? historySize,
      }) => ColorPickerPreferences(
        action: action ?? preferences.action,
        defaultFormat: defaultFormat ?? preferences.defaultFormat,
        uppercase: uppercase ?? preferences.uppercase,
        formats: formats ?? preferences.formats,
        historySize: historySize ?? preferences.historySize,
      );
      final enabled = preferences.formats;
      return [
        SettingsGroup(
          title: 'Picking',
          children: [
            _Row(
              title: 'After picking',
              trailing: CaptureDropdown<ColorPickAction>(
                label: 'After picking',
                options: const {
                  ColorPickAction.copyAndOpen: 'Copy and open panel',
                  ColorPickAction.copyOnly: 'Copy only',
                  ColorPickAction.openOnly: 'Open panel without copying',
                },
                value: preferences.action,
                onChanged: write == null
                    ? null
                    : (value) => write(change(action: value)),
              ),
            ),
            _Row(
              title: 'Default copy format',
              trailing: CaptureDropdown<ColorFormat>(
                label: 'Default copy format',
                options: {for (final format in enabled) format: format.label},
                value: preferences.defaultFormat,
                onChanged: write == null
                    ? null
                    : (value) => write(change(defaultFormat: value)),
              ),
            ),
            if (enabled.contains(ColorFormat.hex))
              _Row(
                title: 'HEX case',
                trailing: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Upper')),
                    ButtonSegment(value: false, label: Text('Lower')),
                  ],
                  selected: {preferences.uppercase},
                  onSelectionChanged: write == null
                      ? null
                      : (value) => write(change(uppercase: value.single)),
                ),
              ),
          ],
        ),
        SettingsGroup(
          title: 'History',
          children: [
            _HistorySize(
              value: preferences.historySize,
              onChanged: write == null
                  ? null
                  : (value) => write(change(historySize: value)),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Visible formats',
          children: [
            for (final format in [
              ...enabled,
              ...ColorFormat.values.where(
                (format) => !enabled.contains(format),
              ),
            ])
              _FormatRow(
                format: format,
                enabled: enabled,
                onChanged: write == null
                    ? null
                    : (formats) => write(change(formats: formats)),
              ),
          ],
        ),
      ];
    },
  );
}

/// Shows the watched value, its loading state and any remyad error.
class _PreferencePage<T> extends StatelessWidget {
  const _PreferencePage({required this.controller, required this.builder});

  final PreferenceController<T> controller;

  /// `write` is null while a save is in progress.
  final List<Widget> Function(T value, ValueChanged<T>? write) builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final value = controller.value;
      final error = controller.error;
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          if (error != null)
            SettingsErrorCard(
              message: describePreferenceError(error),
              onRetry: controller.saving ? null : controller.start,
            ),
          // The window shows the loading bar until the first value arrives.
          if (value != null)
            ...builder(value, controller.saving ? null : controller.write),
        ],
      );
    },
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.trailing});

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) =>
      SettingRow(id: title, label: SettingLabel(title), control: trailing);
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SettingRow(
    id: title,
    label: SettingLabel(title, description: subtitle),
    control: Switch(value: value, onChanged: onChanged),
  );
}

/// Keeps the dragged value locally and saves once the drag ends.
class _HistorySize extends StatefulWidget {
  const _HistorySize({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int>? onChanged;

  @override
  State<_HistorySize> createState() => _HistorySizeState();
}

class _HistorySizeState extends State<_HistorySize> {
  int? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = _dragging ?? widget.value;
    return SettingRow(
      id: 'history-size',
      label: SettingLabel(
        'History size',
        description: value == 0
            ? 'Picked colors are not kept'
            : 'Keep the last $value colors',
      ),
      control: SizedBox(
        width: 240,
        child: Slider(
          value: value.toDouble(),
          max: 128,
          divisions: 128,
          label: '$value',
          semanticFormatterCallback: (value) => '${value.round()} colors',
          onChanged: widget.onChanged == null
              ? null
              : (value) => setState(() => _dragging = value.round()),
          onChangeEnd: (value) {
            setState(() => _dragging = null);
            if (value.round() != widget.value) {
              widget.onChanged?.call(value.round());
            }
          },
        ),
      ),
    );
  }
}

class _FormatRow extends StatelessWidget {
  const _FormatRow({
    required this.format,
    required this.enabled,
    required this.onChanged,
  });

  final ColorFormat format;

  /// Enabled formats in their saved order.
  final List<ColorFormat> enabled;
  final ValueChanged<List<ColorFormat>>? onChanged;

  void _move(int offset) {
    final formats = [...enabled];
    final index = formats.indexOf(format);
    formats.insert(index + offset, formats.removeAt(index));
    onChanged?.call(formats);
  }

  @override
  Widget build(BuildContext context) {
    final index = enabled.indexOf(format);
    final shown = index >= 0;
    final change = onChanged;
    return SettingRow(
      id: 'format-${format.name}',
      label: SettingLabel(
        format.label,
        description: shown ? null : 'Hidden from the color panel',
      ),
      control: Row(
        mainAxisSize: .min,
        children: [
          if (shown) ...[
            IconButton(
              tooltip: 'Move ${format.label} up',
              onPressed: change == null || index == 0 ? null : () => _move(-1),
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
            IconButton(
              tooltip: 'Move ${format.label} down',
              onPressed: change == null || index == enabled.length - 1
                  ? null
                  : () => _move(1),
              icon: const Icon(Icons.arrow_downward_rounded),
            ),
            const SizedBox(width: 8),
          ],
          Switch(
            value: shown,
            // At least one format must stay visible.
            onChanged: change == null || shown && enabled.length == 1
                ? null
                : (value) => change(
                    value
                        ? [...enabled, format]
                        : [...enabled.where((other) => other != format)],
                  ),
          ),
        ],
      ),
    );
  }
}
