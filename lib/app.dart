import 'package:material_ui/material_ui.dart';

class RemyaScreenCaptureApp extends StatelessWidget {
  const RemyaScreenCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Remy'a Screen Capture",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const SizedBox.shrink(),
    );
  }
}
