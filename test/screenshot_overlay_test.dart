import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_screen_capture/features/capture_controls/capture_buttons.dart';
import 'package:remya_screen_capture/features/capture_controls/capture_labels.dart';
import 'package:remya_screen_capture/features/screenshot/capture_geometry.dart';
import 'package:remya_screen_capture/features/screenshot/capture_overlay.dart';
import 'package:remya_screen_capture/features/screenshot/capture_session.dart';

CaptureMonitor monitor({
  int id = 1,
  String name = 'DP-1',
  int x = 0,
  int y = 0,
  int width = 1440,
  int height = 1050,
  double scale = 1.5,
  int transform = 0,
}) => CaptureMonitor({
  'id': id,
  'name': name,
  'focused': true,
  'x': x,
  'y': y,
  'width': width,
  'height': height,
  'scale': scale,
  'transform': transform,
  'activeWorkspace': {'id': 1},
  'specialWorkspace': {'address': '', 'type': '', 'name': ''},
});

CaptureWindow window(
  String id, {
  int workspace = 1,
  bool floating = false,
  bool pinned = false,
  bool hidden = false,
}) => CaptureWindow({
  'stableId': id,
  'monitor': 1,
  'workspace': {'id': workspace},
  'mapped': true,
  'hidden': hidden,
  'floating': floating,
  'pinned': pinned,
  'fullscreen': 0,
  'class': 'Browser',
  'title': 'Test window',
  'at': [10, 30],
  'size': [500, 400],
});

void main() {
  test('window hit testing respects workspace, layer and stacking order', () {
    final output = monitor();
    final tiled = window('a');
    final floating = window('b', floating: true);
    final top = window('c', floating: true);
    final hidden = window('d', floating: true, hidden: true);
    final otherWorkspace = window('e', workspace: 2, floating: true);
    final all = [floating, top, tiled, hidden, otherWorkspace];
    final cursor = const Offset(20, 40);
    expect(windowAt(output, all, cursor), top);
    final pinned = window('f', workspace: 2, pinned: true);
    expect(windowAt(output, [pinned, ...all], cursor), pinned);
    expect(windowAt(output, all, const Offset(1, 1)), isNull);
  });

  test(
    'monitor geometry and panel placement handle mixed and rotated outputs',
    () {
      final target = monitor(x: -960);
      final other = monitor(
        id: 2,
        name: 'eDP-1',
        x: 0,
        width: 1050,
        height: 1440,
        transform: 1,
      );
      expect(other.bounds.size, const Size(960, 700));
      final selection = const Rect.fromLTWH(16, 16, 900, 660);
      expect(placeScrollPanel(target, selection, [target]), isNull);
      final panel = placeScrollPanel(target, selection, [target, other]);
      expect(panel?.output, 'eDP-1');
      expect(panel?.rect.width, 340);
      final local = placeScrollPanel(
        target,
        const Rect.fromLTWH(350, 60, 600, 600),
        [target],
      );
      expect(local?.output, 'DP-1');
      expect(local!.rect.right, lessThan(350));
    },
  );

  testWidgets(
    'primary click captures the output and secondary drag edits a pixel crop',
    (tester) async {
      tester.view.physicalSize = const Size(960, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xff536789), .src);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(1440, 1050);
      picture.dispose();
      addTearDown(image.dispose);
      final output = FrozenOutput(
        monitor(),
        Uint8List(0),
        image,
        ByteData(1440 * 1050 * 4),
      );
      final session = CaptureSession([output], [window('a')], output);
      addTearDown(session.dispose);
      final requests = <CaptureRequest>[];
      var pickerRequests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CaptureOverlay(
            session: session,
            output: output,
            onCapture: requests.add,
            onPickColor: () => pickerRequests++,
            onScroll: () {},
            onBack: session.clearSelection,
            onDone: () {},
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      expect(pickerRequests, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(pickerRequests, 1);

      final toolbarHint = find.text('Switch');
      final before = tester.getCenter(toolbarHint);
      await tester.dragFrom(
        before,
        const Offset(60, 48),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(tester.getCenter(toolbarHint), before + const Offset(60, 48));
      expect(requests, isEmpty);

      await tester.tapAt(const Offset(510, 330));
      await tester.pump();
      expect(requests.single.rect, const Rect.fromLTWH(0, 0, 1440, 1050));
      expect(requests.single.edit, isFalse);

      final mouse = await tester.startGesture(
        const Offset(240, 200),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.moveTo(const Offset(440, 360));
      await tester.pump();
      expect(toolbarHint, findsNothing);
      await mouse.cancel();
      await tester.pump();
      expect(tester.getCenter(toolbarHint), before + const Offset(60, 48));

      final selection = await tester.startGesture(
        const Offset(240, 200),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await selection.moveTo(const Offset(440, 360));
      await selection.up();
      await tester.pump();
      expect(find.text('Edit'), findsOneWidget);
      expect(session.selection, const Rect.fromLTRB(360, 300, 660, 540));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(requests.last.rect, const Rect.fromLTRB(361, 300, 661, 540));
      expect(requests.last.edit, isTrue);

      final hintSurface = find.ancestor(
        of: find.text('Keep ratio'),
        matching: find.byType(CaptureSurface),
      );
      final badge = find.byType(CaptureSizeBadge);
      expect(
        tester.getRect(hintSurface).top,
        greaterThan(tester.getRect(badge).bottom),
      );

      session.setSelection(const Rect.fromLTRB(360, 720, 660, 1040));
      await tester.pump();
      expect(
        tester.getRect(hintSurface).bottom,
        lessThan(tester.getRect(badge).top),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
