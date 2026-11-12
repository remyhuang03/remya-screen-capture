import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_screen_capture/app.dart';
import 'package:remya_screen_capture/features/capture_controls/capture_selection.dart';
import 'package:remya_screen_capture/features/recording/recording_backend.dart';
import 'package:remya_screen_capture/features/recording/recording_setup.dart';
import 'package:remya_screen_capture/features/recording/recording_shortcut.dart';
import 'package:remya_screen_capture/features/screenshot/capture_geometry.dart';

void main() {
  test('the shortcut is forwarded to the active recording owner', () async {
    final directory = await Directory.systemTemp.createTemp('remya-key-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/record.sock';
    expect(await forwardRecordingShortcut(path), isFalse);

    final toggled = Completer<void>();
    final shortcut = await RecordingShortcut.listen(path, toggled.complete);
    try {
      expect(await forwardRecordingShortcut(path), isTrue);
      await toggled.future.timeout(const Duration(seconds: 2));
    } finally {
      await shortcut.close();
    }
    expect(await forwardRecordingShortcut(path), isFalse);
  });

  testWidgets(
    'select a display or region and start or cancel with the keyboard',
    (tester) async {
      final monitor = CaptureMonitor({
        'id': 1,
        'name': 'DP-1',
        'focused': true,
        'activeWorkspace': {'id': 1},
        'specialWorkspace': {},
        'width': 1200,
        'height': 900,
        'x': -800,
        'y': 0,
        'scale': 1.5,
        'transform': 0,
      });
      Rect? region;
      var wholeOutput = false;
      var cancelled = false;
      int? countdown;
      var options = const RecordingOptions();
      await tester.pumpWidget(
        RemyaScreenCaptureApp(
          home: StatefulBuilder(
            builder: (context, setState) => RecordingSetup(
              monitor: monitor,
              active: true,
              region: region,
              options: options,
              countdown: countdown,
              onFocus: () {},
              onSelect: (selection) => setState(() {
                region = selection;
                wholeOutput = selection == null;
              }),
              onOptions: (value) => setState(() => options = value),
              onStart: () => setState(() => countdown = 3),
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(120, 200));
      await tester.pump();
      expect(wholeOutput, isTrue);

      await tester.dragFrom(const Offset(120, 200), const Offset(160, 90));
      await tester.pump();
      expect(region, const Rect.fromLTWH(120, 200, 160, 90));
      expect(find.byType(CaptureSelection), findsOneWidget);
      expect(find.text('240 × 135'), findsOneWidget);

      await tester.tap(find.text('Microphone'));
      await tester.pump();
      expect(options.microphone, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(countdown, 3);
      expect(find.text('3'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(cancelled, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
