import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_screen_capture/features/screenshot/qr_result.dart';

void main() {
  test('only single http(s) URLs become links', () {
    expect(
      webLink(' https://example.com/a '),
      Uri.parse('https://example.com/a'),
    );
    expect(webLink('http://example.com'), isNotNull);
    expect(webLink('ftp://example.com'), isNull);
    expect(webLink('javascript:alert(1)'), isNull);
    expect(webLink('https://'), isNull);
    expect(webLink('plain text'), isNull);
  });

  testWidgets('QR result offers Open only for one link', (tester) async {
    final opened = <Uri>[];
    var closed = 0;
    Future<void> show(List<String> texts, {String? copyError}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QrResult(
                key: ValueKey((texts.join('\n'), copyError)),
                texts: texts,
                copyError: copyError,
                onOpen: opened.add,
                onClose: () => closed++,
              ),
            ),
          ),
        );

    await show(['https://example.com/a']);
    expect(find.text('QR code copied'), findsOneWidget);
    await tester.tap(find.text('Open'));
    expect(opened, [Uri.parse('https://example.com/a')]);

    await show(['first', 'https://example.com/b']);
    expect(find.text('2 QR codes copied'), findsOneWidget);
    expect(find.text('Open'), findsNothing);

    await show(['text'], copyError: 'wl-copy missing');
    expect(find.text('QR code found · Copy failed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    expect(closed, 0);

    await show(['text']);
    await tester.pump(const Duration(seconds: 7));
    expect(closed, 1);
  });
}
