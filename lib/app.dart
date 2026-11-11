import 'package:material_ui/material_ui.dart';

class RemyaScreenCaptureApp extends StatelessWidget {
  const RemyaScreenCaptureApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Remy'a Screen Capture",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xffd0bcff),
          onPrimary: Color(0xff381e72),
          primaryContainer: Color(0xff4f378b),
          onPrimaryContainer: Color(0xffeaddff),
          secondaryContainer: Color(0xff4a4458),
          onSecondaryContainer: Color(0xffe8def8),
          errorContainer: Color(0xff8c1d18),
          onErrorContainer: Color(0xfff9dedc),
          surface: Color(0xff141218),
          onSurface: Color(0xffe6e0e9),
          onSurfaceVariant: Color(0xffcac4d0),
          surfaceContainerLowest: Color(0xff0f0d13),
          surfaceContainer: Color(0xff211f26),
          surfaceContainerHigh: Color(0xff2b2930),
          surfaceContainerHighest: Color(0xff36343b),
          outline: Color(0xff938f99),
          outlineVariant: Color(0xff49454f),
          inverseSurface: Color(0xffe6e0e9),
          onInverseSurface: Color(0xff322f35),
        ),
      ),
      home: home,
    );
  }
}
