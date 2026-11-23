import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_screen_capture/features/capture_controls/capture_buttons.dart';
import 'package:remya_screen_capture/features/capture_controls/capture_labels.dart';
import 'package:remya_screen_capture/features/color_picker/color_data.dart';
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
  test(
    'launch metadata retains mixed scale and rotated monitor geometry',
    () async {
      final data = {
        'id': 1,
        'name': 'DP-1',
        'focused': true,
        'x': -960,
        'y': 30,
        'width': 1050,
        'height': 1440,
        'scale': 1.5,
        'transform': 1,
        'activeWorkspace': {'id': 1},
        'specialWorkspace': {},
        'mirrorOf': 'none',
      };
      final outputs = await readMonitors(
        snapshot: jsonEncode([
          data,
          {...data, 'name': 'disabled', 'disabled': true},
          {...data, 'name': 'mirror', 'mirrorOf': 'DP-1'},
        ]),
      );
      expect(outputs.single.name, 'DP-1');
      expect(outputs.single.bounds, const Rect.fromLTWH(-960, 30, 960, 700));
      expect(await readWindows(snapshot: '[]'), isEmpty);
      expect(
        await readCursor(snapshot: '{"x":-30,"y":40}'),
        const Offset(-30, 40),
      );
      expect(await readCursor(snapshot: 'invalid'), isNull);
    },
  );

  test(
    'launch metadata matches named and special workspaces by address',
    () async {
      const active = {'address': 'design', 'type': 'normal', 'name': 'design'};
      const special = {
        'address': 'special:tools',
        'type': 'special',
        'name': 'tools',
      };
      final client = {
        'monitor': 1,
        'mapped': true,
        'hidden': false,
        'pinned': false,
        'floating': false,
        'fullscreen': 0,
        'class': 'Browser',
        'title': 'Test window',
        'at': [10, 30],
        'size': [500, 400],
      };
      final (monitors, windows) = await (
        readMonitors(
          snapshot: jsonEncode([
            {
              'id': 1,
              'name': 'DP-1',
              'focused': true,
              'x': 0,
              'y': 0,
              'width': 1440,
              'height': 1050,
              'scale': 1.5,
              'transform': 0,
              'mirrorOf': 'none',
              'activeWorkspace': active,
              'specialWorkspace': special,
            },
          ]),
        ),
        readWindows(
          snapshot: jsonEncode([
            {...client, 'stableId': 'active', 'workspace': active},
            {...client, 'stableId': 'special', 'workspace': special},
            {
              ...client,
              'stableId': 'other',
              'workspace': {'address': 'other'},
            },
          ]),
        ),
      ).wait;
      const cursor = Offset(20, 40);
      expect(
        windowAt(monitors.single, [windows.first, windows.last], cursor)?.id,
        'active',
      );
      expect(windowAt(monitors.single, windows, cursor)?.id, 'special');
    },
  );

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
      await tester.pumpWidget(
        MaterialApp(
          home: CaptureOverlay(
            session: session,
            output: output,
            onCapture: requests.add,
            onPickColor: (_, {required keepPicking}) =>
                fail('Screenshot mode should never pick a color'),
            onColorHistory: () {},
            onScroll: () {},
            onBack: session.clearSelection,
            onDone: () {},
          ),
        ),
      );
      expect(find.text('Pick color'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      expect(session.mode, CaptureMode.region);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(session.mode, CaptureMode.window);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(session.mode, CaptureMode.region);
      await tester.pump();
      final toolbarHint = find.text('Switch');
      final before = tester.getCenter(toolbarHint);
      final frozenImage = tester.widget<RawImage>(find.byType(RawImage));
      await tester.dragFrom(
        before,
        const Offset(20, 48),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(tester.getCenter(toolbarHint), before + const Offset(20, 48));
      expect(tester.widget<RawImage>(find.byType(RawImage)), same(frozenImage));
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
      expect(session.confinedOutput, output);
      await mouse.moveTo(const Offset(440, 360));
      await tester.pump();
      expect(toolbarHint, findsNothing);
      await mouse.cancel();
      await tester.pump();
      expect(session.confinedOutput, isNull);
      expect(tester.getCenter(toolbarHint), before + const Offset(20, 48));

      final selection = await tester.startGesture(
        const Offset(240, 200),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await selection.moveTo(const Offset(440, 360));
      await selection.up();
      await tester.pump();
      expect(session.confinedOutput, isNull);
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
      session.setScroll((
        panel: (output: output.name, rect: const Rect.fromLTWH(8, 8, 300, 500)),
        frames: 0,
        width: 0,
        height: 0,
        png: null,
        message: 'Starting…',
        ready: false,
      ));
      session.setBusy(true);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(session.selection, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in [CaptureMode.region, CaptureMode.color]) {
    testWidgets('${mode.name} toolbar crosses outputs while held', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final left = _frozen(tester, monitor(x: -600, width: 900, height: 900));
      final right = _frozen(
        tester,
        monitor(id: 2, name: 'eDP-1', width: 1200, height: 1200, scale: 2),
      );
      final session = CaptureSession([left, right], [], left, mode: mode);
      addTearDown(session.dispose);
      final picks = <(PickedColor, bool)>[];
      var historyOpens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              for (final output in [left, right])
                Expanded(
                  child: CaptureOverlay(
                    session: session,
                    output: output,
                    nativeBackground: true,
                    onCapture: (_) => fail('Dragging the toolbar captured'),
                    onPickColor: (color, {required keepPicking}) =>
                        picks.add((color, keepPicking)),
                    onColorHistory: () => historyOpens++,
                    onScroll: () {},
                    onBack: session.clearSelection,
                    onDone: () {},
                  ),
                ),
            ],
          ),
        ),
      );
      expect(find.byType(RawImage), findsNothing);
      final hint = find.widgetWithText(CaptureKeycap, 'Esc');
      final origin = tester.getCenter(hint);
      final mouse = await tester.startGesture(origin, kind: .mouse);
      await mouse.moveTo(Offset(1000, 150));
      await tester.pump();
      expect(session.toolbarDragSource, left);
      expect(session.active, right);
      expect(tester.getCenter(hint.last).dx, greaterThan(600));
      await mouse.moveTo(Offset(1030, 180));
      await mouse.up();
      await tester.pump();
      expect(session.toolbarDragSource, isNull);
      expect(hint, findsOneWidget);
      expect(tester.getCenter(hint).dx, greaterThan(600));

      if (mode == .color) {
        expect(find.text('Region'), findsNothing);
        final surface = find.byType(CaptureSurface);
        final background = tester.getRect(surface);
        final toolbar = find.descendant(
          of: surface,
          matching: find.byType(Wrap),
        );
        final content = tester.getRect(toolbar);
        expect(
          tester.widget<Wrap>(toolbar).children.first,
          isA<CaptureButton>()
              .having((button) => button.label, 'label', 'History')
              .having(
                (button) => button.variant,
                'variant',
                CaptureButtonStyle.filled,
              ),
        );
        expect(content.left - background.left, 18);
        expect(background.right - content.right, 18);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        expect(session.mode, CaptureMode.color);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
        expect(historyOpens, 1);
        right.pixels
          ..setUint32((800 * 1200 + 201) * 4, 0x123456ff)
          ..setUint32((800 * 1200 + 204) * 4, 0x4f378bff);
        await tester.sendEventToBinding(
          const PointerHoverEvent(
            device: 50,
            kind: .mouse,
            position: Offset(700, 400),
          ),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(picks.single.$1.color, const Color(0xff123456));
        expect(picks.single.$1.output, right.name);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tapAt(const Offset(702, 400));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(picks.last.$1.color, const Color(0xff4f378b));
        expect(picks.last.$2, isTrue);
        await tester.pumpAndSettle();
        session.setUppercaseHex(false);
        await tester.pumpAndSettle();
        expect(find.text('#4f378b'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        expect(session.colorFormat, ColorFormat.rgb);
        await tester.tap(find.widgetWithText(CaptureButton, 'History'));
        expect(historyOpens, 2);
      } else {
        expect(find.text('History'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        expect(session.mode, CaptureMode.window);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a region drag stays on the display where it began', (
    tester,
  ) async {
    final left = _frozen(tester, monitor(x: -960));
    final right = _frozen(
      tester,
      monitor(
        id: 2,
        name: 'eDP-1',
        x: 24,
        y: 60,
        width: 1600,
        height: 1200,
        scale: 2,
      ),
    );
    final session = CaptureSession([left, right], [], left);
    addTearDown(session.dispose);
    final viewport = left.monitor.bounds.size;
    session.hover(right, const Offset(100, 200), right.monitor.bounds.size);
    expect(session.active, right);
    expect(session.confinedOutput, isNull);
    session.startDrag(
      left,
      const Offset(900, 100),
      viewport,
      true,
      confinePointer: true,
    );
    expect(session.confinedOutput, left);
    session.updateDrag(left, const Offset(945, 140), viewport);
    expect(session.draft, const Rect.fromLTRB(900, 100, 945, 140));
    session.updateDrag(left, const Offset(959, 199), viewport);
    expect(session.pointer, const Offset(959, 199));
    expect(session.draft, const Rect.fromLTRB(900, 100, 960, 199));
    session.hover(right, const Offset(52, 171), right.monitor.bounds.size);
    session.updateDrag(left, const Offset(1036, 231), viewport);
    expect(session.active, left);
    expect(session.pointer, const Offset(960, 231));
    expect(session.draft, const Rect.fromLTRB(900, 100, 960, 231));
    expect(session.endDrag(left, const Offset(1036, 231), viewport), isNull);
    expect(session.confinedOutput, isNull);
    expect(session.request.output, left);
    expect(session.selection, const Rect.fromLTRB(1350, 150, 1440, 347));
    expect(session.request.edit, isTrue);
    session.clearSelection();

    session.startDrag(left, const Offset(950, 140), viewport, false);
    expect(session.endDrag(left, const Offset(985, 140), viewport), isNull);
    expect(session.active, left);
    expect(session.selection, isNull);
    session.startDrag(
      left,
      const Offset(950, 140),
      viewport,
      false,
      confinePointer: true,
    );
    session.updateDrag(left, const Offset(970, 200), viewport);
    expect(session.draft, const Rect.fromLTRB(950, 140, 960, 200));
    session.cancelDrag();
    expect(session.confinedOutput, isNull);
    expect(session.draft, isNull);
    session.hover(right, const Offset(20, 20), right.monitor.bounds.size);
    expect(session.active, right);
  });
}

FrozenOutput _frozen(WidgetTester tester, CaptureMonitor output) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff536789), .src);
  final picture = recorder.endRecording();
  final width = output.pixelSize.width.toInt();
  final height = output.pixelSize.height.toInt();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  addTearDown(image.dispose);
  return FrozenOutput(
    output,
    Uint8List(0),
    image,
    ByteData(width * height * 4),
  );
}
