import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/settings_ui.dart';

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

const _appName = "Remy'a Screen Capture";

/// Moves and closes the undecorated settings window (linux/runner).
const _window = MethodChannel('top.remya.screen_capture/settings');

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
      home: Column(
        children: [
          RemyaTitleBar(
            icon: Image.asset('assets/icons/app_icon.png'),
            title: '$_appName Settings',
            onClose: () => unawaited(_window.invokeMethod('close')),
            dragArea: (child) => Listener(
              behavior: .opaque,
              onPointerDown: (event) {
                if (event.buttons == kPrimaryButton) {
                  unawaited(_window.invokeMethod('beginMove'));
                }
              },
              child: child,
            ),
          ),
          Expanded(child: SettingsWindow(initialPage: page)),
        ],
      ),
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
  final _version = remyaAppVersion();
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

  PreferenceController<Object>? get _controller => switch (_page) {
    'recording' => _recording,
    'color-picker' => _colorPicker,
    _ => null,
  };

  void _select(String id) => setState(() => _page = id);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_recording, _colorPicker]),
    builder: (context, _) {
      final controller = _controller;
      return RemyaSettingsScaffold(
        selected: _page,
        onSelected: _select,
        loading:
            controller != null &&
            controller.value == null &&
            controller.error == null,
        pages: [
          for (final page in settingsPages)
            RemyaSettingsPage(
              id: page.id,
              title: page.title,
              icon: page.icon,
              builder: (_) => switch (page.id) {
                'recording' => RecordingSettingsPage(_recording),
                _ => ColorPickerSettingsPage(_colorPicker),
              },
            ),
        ],
        footerPages: [
          RemyaSettingsPage(
            id: 'about',
            title: 'About',
            icon: Icons.info_outline_rounded,
            tabs: false,
            children: [
              RemyaSettingsPage(
                id: 'about',
                title: 'About',
                icon: Icons.info_outline_rounded,
                builder: (_) => _About(
                  version: _version,
                  onLicenses: () => _select('licenses'),
                ),
              ),
              RemyaSettingsPage(
                id: 'licenses',
                title: 'Third-party licenses',
                icon: Icons.description_outlined,
                fill: true,
                builder: (_) => const RemyaLicensesView(),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class _About extends StatelessWidget {
  const _About({required this.version, required this.onLicenses});

  final Future<String?> version;
  final VoidCallback onLicenses;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      FutureBuilder(
        future: version,
        builder: (context, snapshot) => RemyaAboutHeader(
          icon: Image.asset(
            'assets/icons/app_icon.png',
            semanticLabel: '$_appName icon',
          ),
          name: _appName,
          version: snapshot.data,
        ),
      ),
      RemyaAboutLinks(
        repository: 'https://github.com/remyhuang03/remya-screen-capture',
        onLicenses: onLicenses,
      ),
    ],
  );
}
