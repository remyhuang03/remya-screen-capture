import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';

import '../../app.dart';
import '../color_picker/color_data.dart';
import '../recording/recording_backend.dart';
import 'preference_controller.dart';
import 'settings_pages.dart';

/// Pages from linux/packaging/remya-screen-capture.json.
const settingsPages = [
  (id: 'recording', title: 'Recording', icon: Icons.videocam_rounded),
  (id: 'color-picker', title: 'Color picker', icon: Icons.colorize_rounded),
];

class ScreenCaptureSettingsApp extends StatelessWidget {
  const ScreenCaptureSettingsApp({super.key, this.page});

  final String? page;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: themeController,
    builder: (context, _) => MaterialApp(
      title: 'Remya Screen Capture Settings',
      debugShowCheckedModeBanner: false,
      theme: remyaCaptureTheme(.light),
      darkTheme: remyaCaptureTheme(.dark),
      themeMode: themeController.theme.mode,
      home: SettingsWindow(initialPage: page),
    ),
  );
}

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({
    super.key,
    this.initialPage,
    this.preferences,
    this.colorStore,
  });

  final String? initialPage;

  /// Injected by tests; the window otherwise owns its remyad connection.
  final AppPreferences? preferences;
  final ColorPickerStore? colorStore;

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  late final SettingsClient? _client = widget.preferences == null
      ? SettingsClient()
      : null;
  late final AppPreferences _preferences =
      widget.preferences ??
      AppPreferences('remya-screen-capture', client: _client);
  late final _recording = PreferenceController<RecordingOptions>(
    preferences: _preferences,
    key: 'recording',
    parse: RecordingOptions.fromValue,
    save: (value) => value.save(preferences: _preferences),
  )..start();
  late final _colorPicker = PreferenceController<ColorPickerPreferences>(
    preferences: _preferences,
    key: 'color-picker',
    parse: ColorPickerPreferences.fromJson,
    save: (widget.colorStore ?? ColorPickerStore(preferences: _preferences))
        .writePreferences,
  )..start();
  StreamSubscription<bool>? _service;
  late String _page = widget.initialPage ?? settingsPages.first.id;

  @override
  void initState() {
    super.initState();
    // Resume watching once remyad (re)appears on the session bus.
    _service = _client?.serviceAvailableChanges.listen((available) {
      if (!available) return;
      _recording.start();
      _colorPicker.start();
    });
  }

  @override
  void dispose() {
    _service?.cancel();
    _recording.dispose();
    _colorPicker.dispose();
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final page = settingsPages.firstWhere((page) => page.id == _page);
    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: .stretch,
          children: [
            _Navigation(
              compact: compact,
              selected: _page,
              onSelected: (id) => setState(() => _page = id),
            ),
            Expanded(
              child: ListView(
                key: PageStorageKey(_page),
                padding: .fromLTRB(
                  compact ? 16 : 32,
                  24,
                  compact ? 16 : 32,
                  32,
                ),
                children: [
                  Text(
                    page.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  switch (_page) {
                    'recording' => RecordingSettingsPage(_recording),
                    _ => ColorPickerSettingsPage(_colorPicker),
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.compact,
    required this.selected,
    required this.onSelected,
  });

  final bool compact;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: compact ? 72 : 240,
      child: ListView(
        padding: const .fromLTRB(12, 24, 12, 12),
        children: [
          for (final page in settingsPages)
            Padding(
              padding: const .symmetric(vertical: 2),
              child: compact
                  ? IconButton.filledTonal(
                      tooltip: page.title,
                      isSelected: page.id == selected,
                      style: IconButton.styleFrom(
                        backgroundColor: page.id == selected
                            ? colors.secondaryContainer
                            : Colors.transparent,
                        foregroundColor: page.id == selected
                            ? colors.onSecondaryContainer
                            : colors.onSurfaceVariant,
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => onSelected(page.id),
                      icon: Icon(page.icon),
                    )
                  : ListTile(
                      selected: page.id == selected,
                      selectedTileColor: colors.secondaryContainer,
                      selectedColor: colors.onSecondaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: .circular(18),
                      ),
                      leading: Icon(page.icon),
                      title: Text(page.title),
                      minTileHeight: 48,
                      onTap: () => onSelected(page.id),
                    ),
            ),
        ],
      ),
    );
  }
}
