import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

class CaptureMonitor {
  CaptureMonitor(Map<String, dynamic> data)
    : id = data['id'] as int,
      name = data['name'] as String,
      focused = data['focused'] as bool,
      workspace = (data['activeWorkspace'] as Map)['id'] as int,
      specialWorkspace = (data['specialWorkspace'] as Map)['id'] as int? ?? 0,
      bounds = _monitorBounds(data);

  final int id;
  final String name;
  final bool focused;
  final int workspace;
  final int specialWorkspace;
  final Rect bounds;

  static Rect _monitorBounds(Map<String, dynamic> data) {
    final scale = data['scale'] as num;
    final rotated = (data['transform'] as int).isOdd;
    final width = data[rotated ? 'height' : 'width'] as num;
    final height = data[rotated ? 'width' : 'height'] as num;
    return .fromLTWH(
      (data['x'] as num).toDouble(),
      (data['y'] as num).toDouble(),
      (width / scale).roundToDouble(),
      (height / scale).roundToDouble(),
    );
  }
}

class CaptureWindow {
  CaptureWindow(Map<String, dynamic> data)
    : id = data['stableId'] as String? ?? '',
      monitor = data['monitor'] as int,
      workspace = (data['workspace'] as Map)['id'] as int,
      mapped = data['mapped'] as bool,
      hidden = data['hidden'] as bool,
      pinned = data['pinned'] as bool,
      floating = data['floating'] as bool,
      fullscreen = (data['fullscreen'] as int) != 0,
      allowedOverFullscreen = data['allowedOverFullscreen'] as bool? ?? false,
      windowClass = data['class'] as String,
      title = data['title'] as String,
      bounds = _windowBounds(data);

  final String id;
  final int monitor;
  final int workspace;
  final bool mapped;
  final bool hidden;
  final bool pinned;
  final bool floating;
  final bool fullscreen;
  final bool allowedOverFullscreen;
  final String windowClass;
  final String title;
  final Rect bounds;

  static Rect _windowBounds(Map<String, dynamic> data) {
    final at = (data['at'] as List).cast<num>();
    final size = (data['size'] as List).cast<num>();
    return .fromLTWH(
      at[0].toDouble(),
      at[1].toDouble(),
      size[0].toDouble(),
      size[1].toDouble(),
    );
  }
}

Future<List<CaptureMonitor>> readMonitors() async {
  return (await _hyprlandList('monitors'))
      .where((data) => data['disabled'] != true && data['mirrorOf'] == 'none')
      .map(CaptureMonitor.new)
      .toList();
}

Future<List<CaptureWindow>> readWindows() async {
  return (await _hyprlandList('clients')).map(CaptureWindow.new).toList();
}

Future<Offset?> readCursor() async {
  try {
    final data = await _hyprlandJson('cursorpos') as Map;
    return Offset((data['x'] as num).toDouble(), (data['y'] as num).toDouble());
  } on Exception {
    return null;
  } on StateError {
    return null;
  }
}

Future<List<Map<String, dynamic>>> _hyprlandList(String subject) async =>
    (await _hyprlandJson(subject) as List).cast<Map<String, dynamic>>();

Future<Object?> _hyprlandJson(String subject) async {
  final result = await Process.run('hyprctl', [
    '-j',
    subject,
  ]).timeout(const Duration(seconds: 3));
  if (result.exitCode != 0) {
    throw StateError('Could not read Hyprland $subject: ${result.stderr}');
  }
  return jsonDecode(result.stdout as String);
}

CaptureWindow? windowAt(
  CaptureMonitor monitor,
  List<CaptureWindow> windows,
  Offset globalPosition,
) {
  final candidates = windows.reversed.where(
    (window) =>
        window.mapped &&
        !window.hidden &&
        window.id.isNotEmpty &&
        (window.monitor == monitor.id ||
            (!window.bounds.isEmpty &&
                window.floating &&
                window.bounds.overlaps(monitor.bounds))) &&
        (window.pinned ||
            window.workspace == monitor.workspace ||
            (monitor.specialWorkspace != 0 &&
                window.workspace == monitor.specialWorkspace)),
  );
  final workspaceFullscreen = candidates.any(
    (window) => window.fullscreen && window.workspace == monitor.workspace,
  );
  CaptureWindow? hit;
  var best = -1;
  for (final window in candidates) {
    if (!window.bounds.contains(globalPosition)) continue;
    final special =
        monitor.specialWorkspace != 0 &&
        window.workspace == monitor.specialWorkspace;
    final rank = switch (window) {
      _ when window.pinned => 6,
      _ when special => window.floating ? 5 : 4,
      _ when workspaceFullscreen && window.allowedOverFullscreen => 3,
      _ when window.fullscreen => 2,
      _ when workspaceFullscreen => -1,
      _ => window.floating ? 1 : 0,
    };
    if (rank > best) {
      hit = window;
      best = rank;
    }
  }
  return hit;
}

Rect scaleRect(Rect rect, Size source, Size target) => .fromLTRB(
  rect.left * target.width / source.width,
  rect.top * target.height / source.height,
  rect.right * target.width / source.width,
  rect.bottom * target.height / source.height,
);

Rect pixelRect(Rect rect, Size bounds) {
  final left = rect.left.round().clamp(0, bounds.width.toInt() - 1);
  final top = rect.top.round().clamp(0, bounds.height.toInt() - 1);
  final right = rect.right.round().clamp(left + 1, bounds.width.toInt());
  final bottom = rect.bottom.round().clamp(top + 1, bounds.height.toInt());
  return .fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right.toDouble(),
    bottom.toDouble(),
  );
}

typedef PanelPlacement = ({String output, Rect rect});

PanelPlacement? placeScrollPanel(
  CaptureMonitor target,
  Rect selection,
  Iterable<CaptureMonitor> monitors,
) {
  const margin = 16.0;
  final global = selection.shift(target.bounds.topLeft);
  final bounds = target.bounds;
  final spaces = [
    (
      target,
      Rect.fromLTRB(bounds.left, bounds.top, global.left, bounds.bottom),
    ),
    (
      target,
      Rect.fromLTRB(global.right, bounds.top, bounds.right, bounds.bottom),
    ),
    (
      target,
      Rect.fromLTRB(bounds.left, global.bottom, bounds.right, bounds.bottom),
    ),
    for (final monitor in monitors)
      if (monitor != target && !monitor.bounds.overlaps(bounds))
        (monitor, monitor.bounds),
  ];
  // Favor space on the current output. On that output use the largest slot.
  spaces.sort((a, b) {
    if (a.$1 == target && b.$1 != target) return -1;
    if (a.$1 != target && b.$1 == target) return 1;
    return (b.$2.width * b.$2.height).compareTo(a.$2.width * a.$2.height);
  });
  for (final (monitor, space) in spaces) {
    final available = space.deflate(margin);
    if (available.width < 240 || available.height < 264) continue;
    final width = math.min(340.0, available.width);
    final height = math.min(746.0, available.height);
    final left = global.left >= available.right
        ? available.right - width
        : global.left.clamp(available.left, available.right - width);
    final top = global.top.clamp(available.top, available.bottom - height);
    return (
      output: monitor.name,
      rect: Rect.fromLTWH(
        left,
        top,
        width,
        height,
      ).shift(-monitor.bounds.topLeft),
    );
  }
  return null;
}
