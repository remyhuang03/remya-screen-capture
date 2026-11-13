import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_screen_capture/features/color_picker/color_data.dart';

void main() {
  test('formats colors from the same sRGB bytes', () {
    const red = Color(0xffff0000);
    const purple = Color(0xff4f378b);
    expect(ColorFormat.hex.format(purple), '#4F378B');
    expect(ColorFormat.hex.format(purple, uppercase: false), '#4f378b');
    expect(ColorFormat.rgb.format(purple), 'rgb(79, 55, 139)');
    expect(ColorFormat.hsl.format(purple), 'hsl(257, 43%, 38%)');
    expect(ColorFormat.hsv.format(purple), 'hsv(257, 60%, 55%)');
    expect(ColorFormat.hypr.format(purple), 'rgb(4f378b)');
    expect(ColorFormat.float.format(purple), 'vec3(0.310, 0.216, 0.545)');
    expect(ColorFormat.oklch.format(red), 'oklch(62.8% 0.258 29.2)');
    expect(ColorFormat.lab.format(red), 'lab(54.29% 80.80 69.89)');
    expect(ColorFormat.cmyk.format(red), 'cmyk(0%, 100%, 100%, 0%)');
  });

  test('handles neutral colors without undefined hue or black ink ratios', () {
    const black = Color(0xff000000);
    const white = Color(0xffffffff);
    expect(ColorFormat.oklch.format(black), 'oklch(0.0% 0.000 0.0)');
    expect(ColorFormat.oklch.format(white), 'oklch(100.0% 0.000 0.0)');
    expect(ColorFormat.lab.format(black), 'lab(0.00% 0.00 0.00)');
    expect(ColorFormat.lab.format(white), 'lab(100.00% 0.00 0.00)');
    expect(ColorFormat.cmyk.format(black), 'cmyk(0%, 0%, 0%, 100%)');
  });

  late Directory directory;
  late ColorPickerStore store;

  ColorPickerStore openStore() =>
      ColorPickerStore(stateDirectory: directory, configDirectory: directory);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('remya-color-test-');
    store = openStore();
  });
  tearDown(() => directory.delete(recursive: true));

  PickedColor pick(int rgb, {int x = 0}) => PickedColor(
    color: .new(0xff000000 | rgb),
    position: Offset(x.toDouble(), 12),
    output: 'DP-1',
    time: DateTime(2026, 11, 13, 14, 32, x),
  );

  test(
    'concurrent picks persist, update metadata, and enforce history size',
    () async {
      final first = pick(0x112233);
      final second = pick(0x445566);
      final third = pick(0xaabbcc);
      await Future.wait([store.add(first, 2), openStore().add(second, 2)]);
      expect(await openStore().readHistory(), [second, first]);

      final moved = pick(0x112233, x: 8);
      expect(await store.add(moved, 2), [moved, second]);
      expect(await store.add(third, 2), [third, moved]);
      expect(await openStore().readHistory(limit: 1), [third]);
      expect(await store.remove(moved, 2), [third]);
      expect(await store.add(moved, 0), isEmpty);
      expect(await openStore().readHistory(), isEmpty);
    },
  );

  test(
    'preferences persist order and fall back to a valid default format',
    () async {
      final defaults = await store.readPreferences();
      expect(defaults.formats, ColorPickerPreferences.defaultFormats);
      expect(defaults.action, ColorPickAction.copyAndOpen);
      expect(defaults.defaultFormat, ColorFormat.hex);
      expect(defaults.uppercase, isTrue);
      expect(defaults.historySize, 32);

      final saved = ColorPickerPreferences(
        formats: [.lab, .hsl, .lab],
        uppercase: false,
        action: .copyOnly,
        historySize: 400,
      );
      await store.writePreferences(saved);

      final loaded = await openStore().readPreferences();
      expect(loaded.formats, [ColorFormat.lab, ColorFormat.hsl]);
      expect(loaded.defaultFormat, ColorFormat.lab);
      expect(loaded.uppercase, isFalse);
      expect(loaded.action, ColorPickAction.copyOnly);
      expect(loaded.historySize, 128);
    },
  );

  test(
    'a reduced history limit also constrains a stale picker session',
    () async {
      final first = pick(0xff0000);
      final second = pick(0x0000ff);
      await store.add(first, 32);
      await store.writePreferences(ColorPickerPreferences(historySize: 1));
      expect(await openStore().add(second, 32), [second]);
      expect(await store.readHistory(), [second]);
    },
  );

  test('skips invalid history entries and tolerates malformed JSON', () async {
    final sample = pick(0xff0000);
    final history = File('${directory.path}/colors.json');
    await history.writeAsString('{"invalid');
    expect(await store.readHistory(), isEmpty);
    await store.add(sample, 32);
    final saved = jsonDecode(await history.readAsString()) as List;
    await history.writeAsString(jsonEncode([false, {}, ...saved]));
    expect(await openStore().readHistory(), [sample]);
  });
}
