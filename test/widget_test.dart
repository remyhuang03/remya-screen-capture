import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_screen_capture/app.dart';
import 'package:remya_screen_capture/features/capture_controls/capture_buttons.dart';
import 'package:remya_screen_capture/features/capture_controls/capture_color_picker.dart';
import 'package:remya_screen_capture/features/capture_controls/capture_controls_preview.dart';
import 'package:remya_screen_capture/features/capture_controls/capture_icon.dart';
import 'package:remya_screen_capture/features/capture_controls/capture_selection.dart';
import 'package:remya_screen_capture/main.dart';

void main() {
  const preview = RemyaScreenCaptureApp(home: CaptureControlsPreview());

  testWidgets('Preview opens and loads every design icon', (tester) async {
    tester.view.physicalSize = const Size(1019, 2300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview);
    await tester.pumpAndSettle();

    expect(find.text('Components · Remya Screen Capture'), findsOneWidget);
    for (final symbol in CaptureSymbol.values) {
      final icon = await rootBundle.load(
        'assets/icons/capture/${symbol.asset}.svg',
      );
      expect(icon.lengthInBytes, greaterThan(0), reason: symbol.asset);
    }
    expect(find.text('Icons'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Preview fits a narrow window', (tester) async {
    tester.view.physicalSize = const Size(320, 2300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview);
    await tester.pumpAndSettle();

    expect(find.text('Window'), findsOneWidget);
    expect(find.byType(CaptureSelection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A full-width dropdown puts its arrow at the trailing edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              child: CaptureDropdown(
                label: 'Resolution',
                options: const {0: 'Original · 2560 × 1600'},
                value: 0,
                onChanged: (_) {},
                fillWidth: true,
              ),
            ),
          ),
        ),
      ),
    );
    final button = tester.getRect(find.byType(FilledButton));
    final label = tester.getRect(find.text('Original · 2560 × 1600'));
    final arrow = tester.getRect(find.byType(CaptureIcon));
    expect(label.left - button.left, 12);
    expect(button.right - arrow.right, 8);
  });

  testWidgets('Preview updates toggle, segment and dropdown selections', (
    tester,
  ) async {
    await tester.pumpWidget(preview);

    final pen = find.byWidgetPredicate(
      (widget) => widget is CaptureIconButton && widget.label == 'Pen',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(tester.widget<CaptureIconButton>(pen).selected, isTrue);
    await tester.tap(pen);
    await tester.pumpAndSettle();
    expect(tester.widget<CaptureIconButton>(pen).selected, isFalse);

    final audio = find.byType(CaptureToggleChip).first;
    await tester.tap(audio);
    await tester.pumpAndSettle();
    expect(tester.widget<CaptureToggleChip>(audio).selected, isFalse);

    final previewScroll = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Window'),
      250,
      scrollable: previewScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Window'));
    await tester.pumpAndSettle();
    final selected = find.ancestor(
      of: find.text('Window'),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.selected == true,
      ),
    );
    expect(selected, findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Inter'),
      250,
      scrollable: previewScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inter'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Roboto'), findsOneWidget);
    expect(find.text('Inter'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Color picker validates hex and returns only confirmed colors', (
    tester,
  ) async {
    final result = <Color?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => CaptureButton(
              label: 'Open picker',
              onPressed: () async => result.add(
                await showCaptureColorPicker(
                  context,
                  color: const Color(0xfff44336),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final open = find.text('Open picker');
    await tester.tap(open);
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    await tester.enterText(field, '123');
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result, isEmpty);

    await tester.enterText(field, '1A2B3C');
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result, [const Color(0xff1a2b3c)]);

    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'AABBCC');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, [const Color(0xff1a2b3c), null]);
  });

  testWidgets('Selection moves, nudges and locks its ratio at the bounds', (
    tester,
  ) async {
    var rect = const Rect.fromLTWH(40, 40, 120, 80);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: .topLeft,
            child: SizedBox(
              width: 320,
              height: 240,
              child: StatefulBuilder(
                builder: (context, setState) => CaptureSelection(
                  rect: rect,
                  onChanged: (value) => setState(() => rect = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.dragFrom(rect.center, const Offset(20, 10));
    await tester.pumpAndSettle();
    expect(rect, const Rect.fromLTWH(60, 50, 120, 80));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(rect.topLeft, const Offset(61, 60));

    await tester.dragFrom(rect.centerRight, const Offset(500, 0));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(rect.right, closeTo(320, .0001));
    expect(rect.center.dy, closeTo(100, .0001));
    expect(rect.width / rect.height, closeTo(1.5, .0001));

    await tester.dragFrom(
      rect.centerRight - const Offset(1, 0),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(rect.width, CaptureSelection.minimumExtent);
    expect(rect.left, 61);

    await tester.dragFrom(
      rect.bottomCenter - const Offset(0, 1),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(rect.height, CaptureSelection.minimumExtent);
    final small = rect;
    await tester.dragFrom(rect.center, const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(rect, small.shift(const Offset(20, 20)));
    expect(tester.takeException(), isNull);
  });

  test(
    'parseEntrypoint recognizes screenshot, record and color picker flags',
    () {
      expect(parseEntrypoint(const []), CaptureEntrypoint.screenshot);
      expect(parseEntrypoint(const ['--record']), CaptureEntrypoint.recording);
      expect(
        parseEntrypoint(const ['--color-picker']),
        CaptureEntrypoint.colorPicker,
      );
    },
  );
}
