import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_screen_capture/features/color_picker/color_data.dart';
import 'package:remya_screen_capture/features/settings/settings_window.dart';

import 'fake_app_preferences.dart';

void main() {
  late FakeAppPreferences preferences;
  late Directory state;

  setUp(() {
    preferences = FakeAppPreferences();
    state = Directory.systemTemp.createTempSync('capture-settings-');
  });
  tearDown(() => state.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester, String page) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsWindow(
          initialPage: page,
          preferences: preferences,
          colorStore: ColorPickerStore(
            stateDirectory: state,
            preferences: preferences,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The color store checks the history file with real I/O.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  bool switchValue(WidgetTester tester, String title) => tester
      .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title))
      .value;

  testWidgets('recording keeps the last valid value on errors and follows '
      'external changes', (tester) async {
    preferences.unavailable = true;
    await pump(tester, 'recording');
    expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);

    preferences.unavailable = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_rounded), findsNothing);

    await tester.tap(find.text('Microphone'));
    await tester.pumpAndSettle();
    expect(preferences.values['recording']['microphone'], isTrue);
    expect(switchValue(tester, 'Microphone'), isTrue);

    preferences.unavailable = true;
    await tester.tap(find.text('Cursor'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Core unavailable'), findsOneWidget);
    expect(switchValue(tester, 'Cursor'), isTrue);

    preferences.unavailable = false;
    preferences.external('recording', {
      'systemAudio': false,
      'microphone': true,
      'cursor': true,
    });
    await tester.pumpAndSettle();
    expect(switchValue(tester, 'System audio'), isFalse);
  });

  testWidgets('color picker hides HEX case without HEX and reassigns the '
      'default format', (tester) async {
    await pump(tester, 'color-picker');
    expect(find.text('HEX case'), findsOneWidget);

    final hex = find.widgetWithText(CheckboxListTile, 'HEX');
    await tester.scrollUntilVisible(
      hex,
      200,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('color-picker')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(hex);
    await tester.pumpAndSettle();
    await tester.tap(hex);
    await settle(tester);
    final saved = preferences.values['color-picker'] as Map;
    expect(saved['formats'], isNot(contains('hex')));
    expect(saved['defaultFormat'], 'rgb');
    expect(find.text('HEX case'), findsNothing);

    await tester.ensureVisible(find.byTooltip('Move RGB down'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move RGB down'));
    await settle(tester);
    expect(
      ((preferences.values['color-picker'] as Map)['formats'] as List).take(2),
      ['hsl', 'rgb'],
    );
  });
}
