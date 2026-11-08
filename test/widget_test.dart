import 'package:flutter_test/flutter_test.dart';
import 'package:remya_screen_capture/app.dart';

void main() {
  testWidgets('Application skeleton starts', (tester) async {
    await tester.pumpWidget(const RemyaScreenCaptureApp());

    expect(find.byType(RemyaScreenCaptureApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
