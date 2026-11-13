import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_screen_capture/app.dart';
import 'package:remya_screen_capture/features/color_picker/color_data.dart';
import 'package:remya_screen_capture/features/color_picker/color_result_panel.dart';

void main() {
  testWidgets('result supports keyboard copy, history, and HSL adjustment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final picked = PickedColor(
      color: const Color(0xff4f378b),
      output: 'DP-1',
      position: const Offset(812, 236),
      time: DateTime(2026, 11, 13, 14, 32),
    );
    final earlier = picked.withColor(Colors.white);
    final history = [picked, earlier];
    final clipboard = <String>[];
    final heights = <double>[];
    var closed = false;
    await tester.pumpWidget(
      RemyaScreenCaptureApp(
        home: Center(
          child: SizedBox(
            width: 640,
            child: ColorResultPanel(
              picked: picked,
              history: history,
              preferences: ColorPickerPreferences(),
              copied: .hex,
              onCopy: (value) async => clipboard.add(value),
              onRemember: (entry) async {
                history.insert(0, entry);
                return List.of(history);
              },
              onDelete: (entry) async {
                history.remove(entry);
                return List.of(history);
              },
              onPreferences: (_) async {},
              onPickAgain: () {},
              onClose: () => closed = true,
              onHeightChanged: heights.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('HEX copied'), findsOneWidget);
    await tester.sendKeyEvent(.digit2);
    await tester.pump();
    expect(clipboard, ['rgb(79, 55, 139)']);
    expect(find.text('RGB copied'), findsOneWidget);
    await tester.tap(find.byTooltip('#FFFFFF'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(.delete);
    await tester.pumpAndSettle();
    expect(history, [picked]);
    expect(find.byTooltip('#FFFFFF'), findsNothing);
    await tester.sendKeyEvent(.keyA);
    await tester.pumpAndSettle();
    expect(heights, [587]);
    expect(find.text('Adjust color'), findsOneWidget);
    final hue = find.byType(TextField).first;
    final start = int.parse(tester.widget<TextField>(hue).controller!.text);
    await tester.sendKeyDownEvent(.shiftLeft);
    await tester.sendKeyEvent(.arrowRight);
    await tester.sendKeyUpEvent(.shiftLeft);
    await tester.pump();
    expect(tester.widget<TextField>(hue).controller!.text, '${start + 10}');
    await tester.sendKeyEvent(.digit1);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(hue).focusNode!.hasFocus, isTrue);
    await tester.enterText(hue, '90');
    await tester.pump();
    await tester.sendKeyEvent(.tab);
    await tester.pump();
    expect(
      tester.widget<Slider>(find.byType(Slider).at(1)).focusNode!.hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(.enter);
    await tester.pumpAndSettle();
    expect(heights, [587, 695]);
    expect(history.first.color, isNot(picked.color));
    expect(clipboard.last, ColorFormat.hex.format(history.first.color));
    await tester.sendKeyEvent(.arrowDown);
    await tester.sendKeyEvent(.enter);
    await tester.pumpAndSettle();
    expect(clipboard.last, ColorFormat.hsl.format(history.first.color));
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
