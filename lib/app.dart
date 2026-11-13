import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/remya_ui.dart';

/// Shared Remya theme from Core; it keeps the last valid theme on errors.
final themeController = SettingsThemeController.service();

/// The shared theme for [brightness], keeping the app's Inter font.
ThemeData remyaCaptureTheme(Brightness brightness) {
  final theme = themeController.theme.theme(brightness);
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Inter'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Inter'),
  );
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
