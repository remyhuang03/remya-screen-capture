import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show OffsetLayer, RendererBinding;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_screen_capture/features/image_editor/image_editor.dart';

const _sourceOrigin = Offset(560, 354);

ui.Image _testImage({bool checkerboard = false}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (checkerboard) {
    canvas.drawColor(Colors.white, .src);
    final paint = Paint()..color = Colors.black;
    for (var y = 0; y < 120; y++) {
      for (var x = y % 2; x < 160; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), paint);
      }
    }
  } else {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 80, 120),
      Paint()..color = Colors.blue,
    );
    canvas.drawRect(
      const Rect.fromLTWH(80, 0, 80, 120),
      Paint()..color = Colors.green,
    );
  }
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(160, 120);
  } finally {
    picture.dispose();
  }
}

Future<void> _open(
  WidgetTester tester, {
  required ui.Image image,
  required Future<void> Function(Uint8List) onCopy,
  Future<String?> Function(Uint8List, {required bool saveAs})? onSave,
  VoidCallback? onClose,
  Listenable? closeRequests,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(image.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: ImageEditor(
        image: image,
        initialName: 'Example.png',
        onCopy: onCopy,
        onSave: onSave ?? (png, {required saveAs}) async => null,
        onClose: onClose ?? () {},
        closeRequests: closeRequests,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool ctrl = false,
}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

class _Copy {
  late Completer<Uint8List> _result;

  Future<void> receive(Uint8List bytes) async => _result.complete(bytes);

  Future<ui.Image> read(WidgetTester tester) async {
    final image = await tester.runAsync(() async {
      _result = Completer<Uint8List>();
      await tester.tap(find.text('Copy'));
      final png = await _result.future.timeout(const Duration(seconds: 5));
      final codec = await ui.instantiateImageCodec(png);
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    });
    expect(image, isNotNull);
    return image!;
  }
}

Future<ByteData> _pixels(WidgetTester tester, ui.Image image) async {
  final bytes = await tester.runAsync(() => image.toByteData());
  expect(bytes, isNotNull);
  return bytes!;
}

int _rgba(ByteData pixels, ui.Image image, int x, int y) =>
    pixels.getUint32((y * image.width + x) * 4);

Future<Set<(int, int)>> _annotationInk(WidgetTester tester) async {
  final view = RendererBinding.instance.renderViews.single;
  final snapshot = (view.debugLayer! as OffsetLayer).toImageSync(
    _sourceOrigin & const Size(160, 120),
  );
  try {
    final bytes = await _pixels(tester, snapshot);
    return {
      for (var y = 0; y < snapshot.height; y++)
        for (var x = 0; x < snapshot.width; x++)
          if (_rgba(bytes, snapshot, x, y) >> 24 > 180) (x, y),
    };
  } finally {
    snapshot.dispose();
  }
}

void main() {
  testWidgets('Crop and PNG export use original pixels independently of zoom', (
    tester,
  ) async {
    final copied = _Copy();
    await _open(tester, image: _testImage(), onCopy: copied.receive);
    await _press(tester, LogicalKeyboardKey.keyC);
    await tester.dragFrom(
      _sourceOrigin + const Offset(18, 18),
      const Offset(120, 84),
    );
    await tester.pump();
    expect(find.text('120 × 84'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(find.text('120 × 84 · Edited'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(find.text('160 × 120'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.keyY, ctrl: true);
    await _press(tester, LogicalKeyboardKey.equal, ctrl: true);
    expect(find.text('125%'), findsOneWidget);

    final image = await copied.read(tester);
    addTearDown(image.dispose);
    expect((image.width, image.height), (120, 84));
    final pixels = await _pixels(tester, image);
    expect(_rgba(pixels, image, 61, 0), 0x2196f3ff);
    expect(_rgba(pixels, image, 62, 0), 0x4caf50ff);
  });

  testWidgets('Pixelation flattens source pixels and clips to its annotation', (
    tester,
  ) async {
    final copied = _Copy();
    await _open(
      tester,
      image: _testImage(checkerboard: true),
      onCopy: copied.receive,
    );
    await _press(tester, LogicalKeyboardKey.keyM);
    await tester.tap(find.text('Area'));
    await tester.dragFrom(
      _sourceOrigin + const Offset(20, 20),
      const Offset(80, 70),
    );
    await tester.pump();
    expect(find.text('1 object'), findsOneWidget);

    final image = await copied.read(tester);
    addTearDown(image.dispose);
    final pixels = await _pixels(tester, image);
    expect(_rgba(pixels, image, 5, 5), 0x000000ff);
    expect(_rgba(pixels, image, 6, 5), 0xffffffff);
    expect(_rgba(pixels, image, 28, 28), _rgba(pixels, image, 29, 28));
  });

  testWidgets('Move, resize and preset shortcuts edit a selected shape', (
    tester,
  ) async {
    final copied = _Copy();
    await _open(tester, image: _testImage(), onCopy: copied.receive);
    await _press(tester, LogicalKeyboardKey.keyR);
    await tester.tap(find.text('Fill'));
    await tester.dragFrom(
      _sourceOrigin + const Offset(12, 12),
      const Offset(44, 42),
    );
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.keyV);
    await tester.dragFrom(
      _sourceOrigin + const Offset(35, 35),
      const Offset(48, 26),
    );
    await tester.pump();
    await tester.dragFrom(
      _sourceOrigin + const Offset(104, 59),
      const Offset(20, 0),
    );
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.digit8);
    expect(find.text('1 object'), findsOneWidget);

    final image = await copied.read(tester);
    addTearDown(image.dispose);
    final pixels = await _pixels(tester, image);
    expect(_rgba(pixels, image, 35, 35), 0x2196f3ff);
    expect(_rgba(pixels, image, 87, 60), 0xffffffff);
    expect(_rgba(pixels, image, 117, 60), 0xffffffff);
  });

  testWidgets('Mosaic brush does not affect pixels off the stroke', (
    tester,
  ) async {
    final copied = _Copy();
    await _open(
      tester,
      image: _testImage(checkerboard: true),
      onCopy: copied.receive,
    );
    await _press(tester, LogicalKeyboardKey.keyM);
    await tester.dragFrom(
      _sourceOrigin + const Offset(20, 40),
      const Offset(80, 40),
    );
    await tester.pump();

    final image = await copied.read(tester);
    addTearDown(image.dispose);
    final pixels = await _pixels(tester, image);
    expect(_rgba(pixels, image, 29, 70), 0xffffffff);
    expect(_rgba(pixels, image, 30, 70), 0x000000ff);
    expect(_rgba(pixels, image, 29, 40), _rgba(pixels, image, 30, 40));
  });

  testWidgets('Blur samples across a source edge inside its area', (
    tester,
  ) async {
    final copied = _Copy();
    await _open(tester, image: _testImage(), onCopy: copied.receive);
    await _press(tester, LogicalKeyboardKey.keyM);
    await tester.tap(find.text('Blur'));
    await tester.pump();
    await tester.tap(find.text('Area'));
    await tester.pump();
    await tester.dragFrom(
      _sourceOrigin + const Offset(40, 20),
      const Offset(80, 70),
    );
    await tester.pump();

    final image = await copied.read(tester);
    addTearDown(image.dispose);
    final pixels = await _pixels(tester, image);
    expect(_rgba(pixels, image, 79, 8), 0x2196f3ff);
    final mixed = _rgba(pixels, image, 79, 50);
    expect(mixed >> 24, inExclusiveRange(0x21, 0x4c));
    expect(mixed & 0xff, 0xff);
  });

  testWidgets('Move mode wheel, image drag and scrollbars share a viewport', (
    tester,
  ) async {
    await _open(tester, image: _testImage(), onCopy: (_) async {});
    const center = Offset(640, 414);
    final mouse = await tester.createGesture(kind: .mouse);
    await mouse.addPointer(location: center);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -120)),
    );
    await tester.pump();
    expect(find.text('133%'), findsOneWidget);
    expect(find.bySemanticsLabel('Horizontal image scroll'), findsNothing);

    final drag = await tester.startGesture(center, kind: .mouse);
    await drag.moveBy(const Offset(20, 30));
    await tester.pump();
    await drag.up();
    await mouse.moveTo(center);
    await tester.pump();
    expect(find.text('64, 37'), findsOneWidget);
    expect(find.text('0 objects'), findsOneWidget);

    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -1000)),
    );
    await tester.pump();
    final horizontal = find.bySemanticsLabel('Horizontal image scroll');
    final vertical = find.bySemanticsLabel('Vertical image scroll');
    expect(horizontal, findsOneWidget);
    expect(vertical, findsOneWidget);
    (int, int) coordinates() {
      final text = tester.widget<Text>(
        find.textContaining(RegExp(r'^\d+, \d+$')),
      );
      final parts = text.data!.split(', ').map(int.parse).toList();
      return (parts.first, parts.last);
    }

    final (x, y) = coordinates();
    await tester.dragFrom(tester.getCenter(horizontal), const Offset(220, 0));
    await mouse.moveTo(center);
    await tester.pump();
    final (nextX, nextY) = coordinates();
    expect(nextX, greaterThan(x));
    expect(nextY, y);
    await tester.dragFrom(tester.getCenter(vertical), const Offset(0, 140));
    await mouse.moveTo(center);
    await tester.pump();
    final (finalX, finalY) = coordinates();
    expect(finalX, nextX);
    expect(finalY, greaterThan(y));
    await _press(tester, LogicalKeyboardKey.digit0, ctrl: true);
    expect(horizontal, findsNothing);
    expect(vertical, findsNothing);
    await mouse.removePointer();
  });

  testWidgets(
    'Pen, highlighter and mosaic replace the pointer over the image',
    (tester) async {
      await _open(tester, image: _testImage(), onCopy: (_) async {});
      const device = 42;
      final mouse = TestGesture(
        dispatcher: tester.sendEventToBinding,
        kind: .mouse,
        device: device,
      );
      final onImage = _sourceOrigin + const Offset(50, 40);
      await mouse.addPointer(location: onImage);
      for (final key in [
        LogicalKeyboardKey.keyP,
        LogicalKeyboardKey.keyH,
        LogicalKeyboardKey.keyM,
      ]) {
        await _press(tester, key);
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(device),
          SystemMouseCursors.none,
        );
        await mouse.moveTo(const Offset(1000, 500));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(device),
          SystemMouseCursors.basic,
        );
        await mouse.moveTo(onImage);
        await tester.pump();
      }
      await mouse.removePointer();
    },
  );

  testWidgets('Editor controls fit narrow windows', (tester) async {
    await _open(tester, image: _testImage(), onCopy: (_) async {});
    for (final width in [1024.0, 960.0, 800.0, 540.0, 480.0, 400.0]) {
      tester.view.physicalSize = Size(width, 500);
      await _press(tester, LogicalKeyboardKey.keyT);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: "Window width $width");
      expect(find.text('Shortcuts'), findsOneWidget);
    }
  });

  testWidgets('Transparent text input and PNG use the same wrapped layout', (
    tester,
  ) async {
    final copied = _Copy();
    await _open(tester, image: _testImage(), onCopy: copied.receive);
    await _press(tester, LogicalKeyboardKey.keyT);
    final point = _sourceOrigin + const Offset(78, 24);
    await tester.tapAt(point);
    await tester.pump();

    final field = find.byType(TextField);
    final editable = find.byType(EditableText);
    expect(tester.widget<TextField>(field).decoration, isNull);
    expect(tester.getTopLeft(editable), point);
    await tester.enterText(field, 'ABC DE FG');
    await tester.pump(const Duration(milliseconds: 600));
    final inkBefore = await _annotationInk(tester);
    expect(inkBefore.length, greaterThan(200));
    expect(inkBefore.any((pixel) => pixel.$2 > 68), isTrue);

    await _press(tester, LogicalKeyboardKey.enter, ctrl: true);
    final exported = await copied.read(tester);
    addTearDown(exported.dispose);
    final bytes = await _pixels(tester, exported);
    final inkAfter = {
      for (var y = 0; y < exported.height; y++)
        for (var x = 0; x < exported.width; x++)
          if (_rgba(bytes, exported, x, y) >> 24 > 180) (x, y),
    };
    expect(inkAfter, inkBefore);
  });

  testWidgets(
    'Text supports finish, undo and dirty close through the native callback',
    (tester) async {
      final requests = ChangeNotifier();
      addTearDown(requests.dispose);
      var closed = false;
      await _open(
        tester,
        image: _testImage(),
        onCopy: (_) async {},
        onClose: () => closed = true,
        closeRequests: requests,
      );
      await _press(tester, LogicalKeyboardKey.keyT);
      await tester.tapAt(_sourceOrigin + const Offset(20, 36));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Example annotation');
      await _press(tester, LogicalKeyboardKey.enter, ctrl: true);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('1 object'), findsOneWidget);

      requests.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved edits?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(closed, isFalse);
      await _press(tester, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(find.text('0 objects'), findsOneWidget);
      requests.notifyListeners();
      expect(closed, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
