import 'package:material_ui/material_ui.dart';

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
      _Section(
        title: 'Recording',
        children: [
          _Switch(
            icon: Icons.volume_up_rounded,
            title: 'System audio',
            subtitle: 'Record the default output device',
            value: options.systemAudio,
            onChanged: write == null
                ? null
                : (value) => write(options.copyWith(systemAudio: value)),
          ),
          _Switch(
            icon: Icons.mic_rounded,
            title: 'Microphone',
            subtitle: 'Record the default input device',
            value: options.microphone,
            onChanged: write == null
                ? null
                : (value) => write(options.copyWith(microphone: value)),
          ),
          _Switch(
            icon: Icons.mouse_rounded,
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
        _Section(
          title: 'Picking',
          children: [
            _Row(
              icon: Icons.touch_app_rounded,
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
              icon: Icons.content_copy_rounded,
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
                icon: Icons.text_fields_rounded,
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
        _Section(
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
        _Section(
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
            _ErrorBanner(
              message: describePreferenceError(error),
              onRetry: controller.saving ? null : controller.start,
            ),
          if (value != null)
            ...builder(value, controller.saving ? null : controller.write)
          else if (error == null)
            const Padding(
              padding: .all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      );
    },
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const .only(top: 24),
      child: Material(
        color: colors.errorContainer,
        borderRadius: .circular(24),
        child: Padding(
          padding: const .fromLTRB(20, 12, 12, 12),
          child: Row(
            spacing: 16,
            children: [
              Icon(Icons.error_rounded, color: colors.onErrorContainer),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: colors.onErrorContainer,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      Padding(
        padding: const .only(top: 28, bottom: 12),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: .circular(24),
        clipBehavior: .antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i != 0) const Divider(height: 1, indent: 20, endIndent: 20),
              children[i],
            ],
          ],
        ),
      ),
    ],
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.trailing});

  final IconData icon;
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const .symmetric(horizontal: 20, vertical: 4),
    leading: Icon(icon),
    title: Text(title),
    trailing: trailing,
  );
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: const .symmetric(horizontal: 20, vertical: 4),
    secondary: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: onChanged,
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
    return ListTile(
      contentPadding: const .symmetric(horizontal: 20, vertical: 4),
      leading: const Icon(Icons.history_rounded),
      title: const Text('History size'),
      subtitle: Text(
        value == 0
            ? 'Picked colors are not kept'
            : 'Keep the last $value colors',
      ),
      trailing: SizedBox(
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
    return CheckboxListTile(
      contentPadding: const .only(left: 20, right: 12),
      controlAffinity: .leading,
      title: Text(format.label),
      subtitle: shown ? null : const Text('Hidden from the color panel'),
      value: shown,
      // At least one format must stay visible.
      onChanged: change == null || shown && enabled.length == 1
          ? null
          : (value) => change(
              value!
                  ? [...enabled, format]
                  : [...enabled.where((other) => other != format)],
            ),
      secondary: shown
          ? Row(
              mainAxisSize: .min,
              children: [
                IconButton(
                  tooltip: 'Move ${format.label} up',
                  onPressed: change == null || index == 0
                      ? null
                      : () => _move(-1),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
                IconButton(
                  tooltip: 'Move ${format.label} down',
                  onPressed: change == null || index == enabled.length - 1
                      ? null
                      : () => _move(1),
                  icon: const Icon(Icons.arrow_downward_rounded),
                ),
              ],
            )
          : null,
    );
  }
}
