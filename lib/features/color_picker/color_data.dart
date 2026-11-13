import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Color, Offset;

import 'package:flutter/painting.dart' show HSLColor, HSVColor;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:remya_client/remya_client.dart';

enum ColorFormat {
  hex,
  rgb,
  hsl,
  hsv,
  oklch,
  hypr,
  float,
  cmyk,
  lab;

  String get label => name.toUpperCase();

  String format(Color color, {bool uppercase = true}) {
    final rgb = _rgb(color);
    final red = rgb >> 16;
    final green = (rgb >> 8) & 255;
    final blue = rgb & 255;
    final hex = rgb.toRadixString(16).padLeft(6, '0');
    final sample = Color(0xff000000 | rgb);
    switch (this) {
      case .hex:
        return '#${uppercase ? hex.toUpperCase() : hex}';
      case .rgb:
        return 'rgb($red, $green, $blue)';
      case .hsl:
        final hsl = HSLColor.fromColor(sample);
        return 'hsl(${hsl.hue.round() % 360}, ${_percent(hsl.saturation)}, '
            '${_percent(hsl.lightness)})';
      case .hsv:
        final hsv = HSVColor.fromColor(sample);
        return 'hsv(${hsv.hue.round() % 360}, ${_percent(hsv.saturation)}, '
            '${_percent(hsv.value)})';
      case .oklch:
        return _oklch(sample);
      case .hypr:
        return 'rgb($hex)';
      case .float:
        return 'vec3(${sample.r.toStringAsFixed(3)}, '
            '${sample.g.toStringAsFixed(3)}, ${sample.b.toStringAsFixed(3)})';
      case .cmyk:
        final hsv = HSVColor.fromColor(sample);
        final value = hsv.value;
        double ink(double channel) => value == 0 ? 0 : 1 - channel / value;
        return 'cmyk(${_percent(ink(sample.r))}, ${_percent(ink(sample.g))}, '
            '${_percent(ink(sample.b))}, ${_percent(1 - value)})';
      case .lab:
        return _lab(sample);
    }
  }
}

int _rgb(Color color) => color.toARGB32() & 0xffffff;

String _percent(double value) => '${(value * 100).round()}%';

double _linear(double value) => value <= .04045
    ? value / 12.92
    : math.pow((value + .055) / 1.055, 2.4).toDouble();

String _oklch(Color color) {
  final r = _linear(color.r);
  final g = _linear(color.g);
  final b = _linear(color.b);
  // Björn Ottosson's linear sRGB to Oklab matrices.
  final l = math.pow(
    .4122214708 * r + .5363325363 * g + .0514459929 * b,
    1 / 3,
  );
  final m = math.pow(
    .2119034982 * r + .6806995451 * g + .1073969566 * b,
    1 / 3,
  );
  final s = math.pow(
    .0883024619 * r + .2817188376 * g + .6299787005 * b,
    1 / 3,
  );
  final lightness = .2104542553 * l + .7936177850 * m - .0040720468 * s;
  final a = 1.9779984951 * l - 2.4285922050 * m + .4505937099 * s;
  final labB = .0259040371 * l + .7827717662 * m - .8086757660 * s;
  final chroma = math.sqrt(a * a + labB * labB);
  final angle = chroma < .0005
      ? 0.0
      : (math.atan2(labB, a) * 180 / math.pi) % 360;
  final hue = (angle * 10).round() % 3600 / 10;
  return 'oklch(${(lightness * 100).toStringAsFixed(1)}% '
      '${chroma.toStringAsFixed(3)} ${hue.toStringAsFixed(1)})';
}

String _lab(Color color) {
  final r = _linear(color.r);
  final g = _linear(color.g);
  final b = _linear(color.b);
  double curve(double value) => value > 216 / 24389
      ? math.pow(value, 1 / 3).toDouble()
      : ((24389 / 27) * value + 16) / 116;
  // Linear sRGB to XYZ with Bradford D50 adaptation and white normalization.
  final x = curve(.452211658242 * r + .399412253943 * g + .148376087815 * b);
  final y = curve(.222493177111 * r + .716887013094 * g + .060619809795 * b);
  final z = curve(.016875340921 * r + .117659414256 * g + .865465244822 * b);
  return 'lab(${_decimal(116 * y - 16)}% '
      '${_decimal(500 * (x - y))} ${_decimal(200 * (y - z))})';
}

String _decimal(double value) =>
    (value.abs() < .005 ? 0.0 : value).toStringAsFixed(2);

enum ColorPickAction { copyAndOpen, copyOnly, openOnly }

class ColorPickerPreferences {
  factory ColorPickerPreferences({
    ColorPickAction action = .copyAndOpen,
    ColorFormat defaultFormat = .hex,
    bool uppercase = true,
    List<ColorFormat> formats = defaultFormats,
    int historySize = 32,
  }) {
    final enabled = formats.isEmpty ? defaultFormats : formats.toSet().toList();
    return ColorPickerPreferences._(
      action,
      enabled.contains(defaultFormat) ? defaultFormat : enabled.first,
      uppercase,
      List.unmodifiable(enabled),
      historySize.clamp(0, 128),
    );
  }

  const ColorPickerPreferences._(
    this.action,
    this.defaultFormat,
    this.uppercase,
    this.formats,
    this.historySize,
  );

  static const defaultFormats = [
    ColorFormat.hex,
    ColorFormat.rgb,
    ColorFormat.hsl,
    ColorFormat.hsv,
    ColorFormat.oklch,
    ColorFormat.hypr,
    ColorFormat.float,
  ];

  final ColorPickAction action;
  final ColorFormat defaultFormat;
  final bool uppercase;
  final List<ColorFormat> formats;
  final int historySize;

  static ColorPickerPreferences fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        _enumValue(ColorPickAction.values, json['action']) == null ||
        _enumValue(ColorFormat.values, json['defaultFormat']) == null ||
        json['uppercase'] is! bool ||
        json['historySize'] is! int ||
        (json['historySize'] as int) < 0 ||
        (json['historySize'] as int) > 128 ||
        json['formats'] is! List) {
      throw const FormatException(
        'Invalid color picker preferences from Remya Core.',
      );
    }
    final saved = json['formats'] as List;
    final formats = saved
        .map((value) => _enumValue(ColorFormat.values, value))
        .toList();
    if (formats.isEmpty ||
        formats.contains(null) ||
        formats.toSet().length != formats.length ||
        !formats.contains(
          _enumValue(ColorFormat.values, json['defaultFormat']),
        )) {
      throw const FormatException(
        'Invalid color picker formats from Remya Core.',
      );
    }
    final history = json['historySize'] as int;
    return ColorPickerPreferences(
      action:
          _enumValue(ColorPickAction.values, json['action']) ?? .copyAndOpen,
      defaultFormat:
          _enumValue(ColorFormat.values, json['defaultFormat']) ?? .hex,
      uppercase: json['uppercase'] != false,
      formats: formats.cast<ColorFormat>(),
      historySize: history,
    );
  }

  Map<String, Object> _toJson() => {
    'action': action.name,
    'defaultFormat': defaultFormat.name,
    'uppercase': uppercase,
    'formats': [for (final format in formats) format.name],
    'historySize': historySize,
  };
}

T? _enumValue<T extends Enum>(List<T> values, Object? name) =>
    values.where((value) => value.name == name).firstOrNull;

class PickedColor {
  const PickedColor({
    required this.color,
    required this.output,
    required this.position,
    required this.time,
  });

  final Color color;
  final String output;
  final Offset position;
  final DateTime time;

  PickedColor withColor(Color value) =>
      PickedColor(color: value, output: output, position: position, time: time);

  @override
  bool operator ==(Object other) =>
      other is PickedColor &&
      _rgb(other.color) == _rgb(color) &&
      other.output == output &&
      other.position == position &&
      other.time.isAtSameMomentAs(time);

  @override
  int get hashCode =>
      Object.hash(_rgb(color), output, position, time.microsecondsSinceEpoch);

  static PickedColor? _fromJson(Object? json) {
    if (json
        case {
          'rgb': final int rgb,
          'output': final String output,
          'x': final num x,
          'y': final num y,
          'time': final String time,
        }
        when rgb >= 0 && rgb <= 0xffffff && x.isFinite && y.isFinite) {
      final date = DateTime.tryParse(time);
      if (date == null) return null;
      return PickedColor(
        color: .new(0xff000000 | rgb),
        output: output,
        position: .new(x.toDouble(), y.toDouble()),
        time: date.toLocal(),
      );
    }
    return null;
  }

  Map<String, Object> _toJson() => {
    'rgb': _rgb(color),
    'output': output,
    'x': position.dx,
    'y': position.dy,
    'time': time.toUtc().toIso8601String(),
  };
}

class ColorPickerStore {
  ColorPickerStore({Directory? stateDirectory, this.preferences})
    : _history = stateDirectory == null
          ? _xdgFile(
              'XDG_STATE_HOME',
              '.local/state',
              'remya-capture/colors.json',
            )
          : File('${stateDirectory.path}/colors.json');

  final File? _history;
  final AppPreferences? preferences;
  ColorPickerPreferences _current = ColorPickerPreferences();

  Future<Map<String, dynamic>> _call(
    Future<Map<String, dynamic>> Function(AppPreferences) operation,
  ) async {
    final store = preferences ?? AppPreferences('remya-screen-capture');
    try {
      return await operation(store);
    } finally {
      if (preferences == null) await store.close();
    }
  }

  // POSIX file locks serialize separate processes, so queue writes in this isolate too.
  static Future<void> _pendingHistory = Future.value();

  Future<ColorPickerPreferences> readPreferences() async {
    final reply = await _call((store) => store.get('color-picker'));
    return _current = ColorPickerPreferences.fromJson(reply['value']);
  }

  Future<void> writePreferences(ColorPickerPreferences preferences) async {
    final reply = await _call(
      (store) => store.set('color-picker', preferences._toJson()),
    );
    _current = ColorPickerPreferences.fromJson(reply['value']);
    if (_history != null && await _history.exists()) {
      await _updateHistory(preferences.historySize, (entries) => entries);
    }
  }

  Future<List<PickedColor>> readHistory({int limit = 128}) async {
    final saved = await _readJson(_history);
    if (saved is! List) return [];
    return saved
        .map(PickedColor._fromJson)
        .nonNulls
        .take(limit.clamp(0, 128))
        .toList();
  }

  Future<List<PickedColor>> add(PickedColor pick, int limit) => _updateHistory(
    limit,
    (entries) => [
      pick,
      ...entries.where((entry) => _rgb(entry.color) != _rgb(pick.color)),
    ],
  );

  Future<List<PickedColor>> remove(PickedColor pick, int limit) =>
      _updateHistory(
        limit,
        (entries) => entries.where((entry) => entry != pick),
      );

  Future<List<PickedColor>> _updateHistory(
    int limit,
    Iterable<PickedColor> Function(List<PickedColor>) update,
  ) {
    final pending = _pendingHistory.then((_) async {
      final file = _history;
      if (file == null) {
        if (limit <= 0) return <PickedColor>[];
        throw StateError('Could not locate the color picker state directory.');
      }
      if (limit <= 0 && !await file.exists()) return <PickedColor>[];
      await file.parent.create(recursive: true);
      final lock = await File('${file.path}.lock').open(mode: .append);
      try {
        await lock.lock(.blockingExclusive);
        try {
          await readPreferences();
        } catch (error) {
          debugPrint('Could not read color picker settings. $error');
        }
        final capacity = math.min(limit, _current.historySize);
        final next = update(await readHistory())
            .take(capacity.clamp(0, 128))
            .toList();
        await _writeJson(file, [for (final pick in next) pick._toJson()]);
        return next;
      } finally {
        await lock.close();
      }
    });
    _pendingHistory = pending.then<void>((_) {}, onError: (Object _) {});
    return pending;
  }

  Future<void> copy(String text) async {
    final Process process;
    try {
      process = await Process.start('wl-copy', [
        '--type',
        'text/plain;charset=utf-8',
      ]);
    } on ProcessException {
      throw StateError(
        'Could not start wl-copy. Install wl-clipboard to copy colors.',
      );
    }
    final stdout = process.stdout.listen((_) {});
    final errors = StringBuffer();
    final stderr = process.stderr.transform(utf8.decoder).listen(errors.write);
    try {
      process.stdin.write(text);
      await process.stdin.close();
      final status = await process.exitCode.timeout(const Duration(seconds: 3));
      if (status != 0) {
        throw StateError(
          'Could not copy the color (wl-copy exited with $status). ${errors.toString().trim()}',
        );
      }
    } on TimeoutException {
      process.kill();
      throw StateError('Timed out copying the color to the Wayland clipboard.');
    } finally {
      await stdout.cancel();
      // The background clipboard owner can keep stderr open after its parent exits.
      await stderr.cancel();
    }
  }
}

File? _xdgFile(String variable, String fallback, String relative) {
  final configured = Platform.environment[variable];
  final home = Platform.environment['HOME'];
  if (configured != null && configured.startsWith('/')) {
    return File('$configured/$relative');
  }
  if (home != null && home.startsWith('/')) {
    return File('$home/$fallback/$relative');
  }
  return null;
}

Future<Object?> _readJson(File? file) async {
  if (file == null) return null;
  try {
    return jsonDecode(await file.readAsString());
  } on FileSystemException catch (error) {
    if (error.osError?.errorCode != 2) rethrow;
    return null;
  } on FormatException {
    return null;
  }
}

Future<void> _writeJson(File destination, Object json) async {
  final parent = await destination.parent.create(recursive: true);
  final staging = await parent.createTemp('.color-picker-');
  try {
    final file = await File('${staging.path}/data.json')
        .writeAsString(jsonEncode(json), flush: true);
    await file.rename(destination.path);
  } finally {
    await staging.delete(recursive: true);
  }
}
