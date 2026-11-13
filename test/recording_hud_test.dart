import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_screen_capture/features/capture_controls/capture_labels.dart';
import 'package:remya_screen_capture/features/recording/recording_hud.dart';
import 'package:remya_screen_capture/features/screenshot/capture_geometry.dart';

CaptureMonitor _monitor(int id, {int x = 0, double scale = 1}) =>
    CaptureMonitor({
      'id': id,
      'name': 'DP-$id',
      'focused': id == 1,
      'x': x,
      'y': 0,
      'width': (800 * scale).round(),
      'height': (720 * scale).round(),
      'scale': scale,
      'transform': 0,
      'activeWorkspace': {'id': 1},
      'specialWorkspace': <String, Object>{},
    });

RecordingHudController _controller({
  required List<CaptureMonitor> monitors,
  Rect? region,
  Future<void> Function()? onPause,
  Future<void> Function()? onStop,
  bool Function()? paused,
  Future<Offset?> Function()? cursorPosition,
}) => RecordingHudController(
  monitors: monitors,
  target: monitors.first,
  region: region,
  systemAudio: true,
  microphone: false,
  cursor: true,
  elapsed: () => const Duration(seconds: 42),
  paused: paused ?? () => false,
  onPause: onPause ?? () async {},
  onStop: onStop ?? () async {},
  cursorPosition: cursorPosition ?? () async => null,
);

typedef _HudInput = ({List<Rect> rectangles, bool keyboard});

Future<void> _showHuds(
  WidgetTester tester,
  List<CaptureMonitor> monitors,
  RecordingHudController controller,
  Map<int, _HudInput> inputs,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(800.0 * monitors.length, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: Row(
        children: [
          for (final monitor in monitors)
            SizedBox.fromSize(
              size: monitor.bounds.size,
              child: RecordingHud(
                controller: controller,
                monitor: monitor,
                onInputChanged: (rectangles, keyboard) => inputs[monitor.id] = (
                  rectangles: rectangles,
                  keyboard: keyboard,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

Future<void> _closeHuds(
  WidgetTester tester,
  RecordingHudController controller,
) async {
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
}

void main() {
  testWidgets('moves between scaled outputs and reveals a docked toolbar', (
    tester,
  ) async {
    final monitors = [_monitor(1, x: -800), _monitor(2, scale: 1.5)];
    final inputs = <int, _HudInput>{};
    Offset? cursor;
    final controller = _controller(
      monitors: monitors,
      cursorPosition: () async => cursor,
    );
    await _showHuds(tester, monitors, controller, inputs);
    expect(inputs[1]!.rectangles.single.size, const Size(464, 58));
    expect(inputs[2]!.rectangles, isEmpty);
    expect(inputs[2]!.keyboard, isFalse);

    final mouse = await tester.startGesture(
      tester.getCenter(find.text('00:42')),
      kind: .mouse,
    );
    await mouse.moveTo(const Offset(900, 6));
    await tester.pump();
    await mouse.up();
    await tester.pump();

    expect(inputs[1]!.rectangles, isEmpty);
    expect(inputs[1]!.keyboard, isFalse);
    final docked = inputs[2]!.rectangles.single;
    expect(docked.top, 0);

    // A fast cross-screen release can miss the destination's enter/exit events.
    cursor = const Offset(720, 400);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 400));
    expect(inputs[2]!.rectangles.single.height, 4);
    expect(inputs[2]!.keyboard, isFalse);
    expect(find.text('00:42'), findsNothing);
    expect(
      find.byType(CustomPaint).at(1),
      paintsExactlyCountTimes(#drawColor, 1),
    );

    cursor = Offset(docked.center.dx, 2);
    await mouse.moveTo(Offset(800 + docked.center.dx, 2));
    await tester.pump();
    expect(inputs[2]!.rectangles.single, docked);
    expect(find.text('00:42'), findsOneWidget);
    controller.dispose();
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('activates only the drawing area and clears marker and laser', (
    tester,
  ) async {
    const area = Rect.fromLTRB(30, 220, 700, 660);
    final monitors = [_monitor(1)];
    final inputs = <int, _HudInput>{};
    final controller = _controller(monitors: monitors, region: area);
    await _showHuds(tester, monitors, controller, inputs);
    expect(inputs[1]!.rectangles, isNot(contains(area)));
    await tester.tap(find.byTooltip('Marker'));
    await tester.pump();
    expect(inputs[1]!.rectangles, contains(area));
    expect(find.text('6 px'), findsOneWidget);
    await tester.tapAt(const Offset(350, 350));
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    expect(find.text('7 px'), findsOneWidget);

    final ink = find.byType(CustomPaint).first;
    const yellow = Color(0xffffdd33);
    expect(ink, paints..circle(color: yellow));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(ink, isNot(paints..circle(color: yellow)));

    await tester.tap(find.byTooltip('Laser pointer'));
    await tester.pump();
    expect(find.text('7 px'), findsNothing);
    final laser = await tester.startGesture(
      const Offset(350, 350),
      kind: PointerDeviceKind.mouse,
    );
    await laser.moveBy(const Offset(60, 0));
    await tester.pump();
    const laserRed = Color(0xfff44336);
    final laserPath = paints
      ..something(
        (method, arguments) =>
            method == #drawPath &&
            (arguments[1] as Paint).color.toARGB32() == laserRed.toARGB32(),
      );
    expect(ink, laserPath);
    await laser.up();
    await tester.pump();
    // The trail fades out after release instead of vanishing.
    expect(ink, laserPath);

    await tester.tap(find.byTooltip('Laser pointer'));
    await tester.pump();
    expect(ink, isNot(laserPath));
    expect(inputs[1]!.rectangles, isNot(contains(area)));
    await _closeHuds(tester, controller);
  });

  testWidgets('shows IPC pause errors and recovers on the next request', (
    tester,
  ) async {
    final monitors = [_monitor(1)];
    var paused = false;
    var fail = true;
    var stops = 0;
    final controller = _controller(
      monitors: monitors,
      paused: () => paused,
      onPause: () async {
        if (fail) throw StateError('Recorder IPC unavailable');
        paused = !paused;
      },
      onStop: () async => stops++,
    );
    await _showHuds(tester, monitors, controller, {});
    await tester.tap(find.byTooltip('Pause recording'));
    await tester.pump();
    expect(find.text('Pause failed'), findsOneWidget);
    expect(tester.takeException(), isNull);

    fail = false;
    await tester.tap(find.byTooltip('Pause recording'));
    await tester.pump();
    expect(find.text('Pause failed'), findsNothing);
    expect(find.byTooltip('Resume recording'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CaptureTooltip && widget.label == 'Stop recording',
      ),
    );
    await tester.pump();
    expect(stops, 1);
    await _closeHuds(tester, controller);
  });
}
