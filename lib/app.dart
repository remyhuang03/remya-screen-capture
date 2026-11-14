import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/remya_ui.dart';

/// Shared Remya theme from Core; it keeps the last valid theme on errors.
final themeController = SettingsThemeController.service();
RemyaTheme? _themeSource;
final _themes = <Brightness, ThemeData>{};

/// The shared theme for [brightness], keeping the app's Inter font.
ThemeData remyaCaptureTheme(Brightness brightness) {
  final source = themeController.theme;
  if (_themeSource != source) {
    _themeSource = source;
    _themes.clear();
  }
  return _themes.putIfAbsent(brightness, () {
    final theme = source.theme(brightness);
    return theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'Inter'),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Inter'),
    );
  });
}

class RemyaScreenCaptureApp extends StatelessWidget {
  const RemyaScreenCaptureApp({super.key, required this.home});

  final Widget home;

  // Capture surfaces float over arbitrary screen content and were designed
  // dark, so they always use the dark scheme of the shared seed.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: themeController,
    builder: (context, _) => MaterialApp(
      title: "Remy'a Screen Capture",
      debugShowCheckedModeBanner: false,
      theme: remyaCaptureTheme(.dark),
      home: home,
    ),
  );
}
