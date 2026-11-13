import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

const _laserRed = Color(0xfff44336);
const _laserWidth = 10.0;
const _sampleSpacing = 4.0;

/// A fading laser stroke drawn as one tapered polygon.
///
/// The approach (streamlined samples, age- and position-based taper, round
/// head cap) follows Excalidraw's MIT-licensed laser pointer.
class LaserTrail {
  LaserTrail({this.lifetime = const Duration(milliseconds: 600)});

  final Duration lifetime;
  final _samples = <({Offset point, Duration time})>[];

  bool get isEmpty => _samples.isEmpty;

  @visibleForTesting
  int get length => _samples.length;

  void clear() => _samples.clear();

  void add(Offset point, Duration time) {
    if (_samples.isEmpty) {
      _samples.add((point: point, time: time));
      return;
    }
    final last = _samples.last;
    final target = Offset.lerp(last.point, point, .6)!;
    final distance = (target - last.point).distance;
    if (distance < 1) return;
    // Densify so fast flicks still taper smoothly instead of forming spikes.
    final steps = (distance / _sampleSpacing).ceil();
    for (var step = 1; step <= steps; step++) {
      final t = step / steps;
      _samples.add((
        point: Offset.lerp(last.point, target, t)!,
        time: last.time + (time - last.time) * t,
      ));
    }
  }

  void prune(Duration now, {bool keepHead = false}) {
    final candidates = keepHead ? _samples.length - 1 : _samples.length;
    var expired = 0;
    while (expired < candidates && now - _samples[expired].time >= lifetime) {
      expired++;
    }
    _samples.removeRange(0, expired);
  }

  Path outline(Duration now, double width, {required bool keepHead}) {
    final count = _samples.length;
    if (count == 0) return Path();
    final half = width / 2;

    double radius(int i) {
      if (keepHead && i == count - 1) return half;
      final age =
          (now - _samples[i].time).inMicroseconds / lifetime.inMicroseconds;
      final position = count == 1 ? 1.0 : i / (count - 1);
      final x = math.min(1 - age, position).clamp(0.0, 1.0);
      return half * (1 - math.pow(1 - x, 3));
    }

    if (count == 1) {
      return Path()..addOval(
        Rect.fromCircle(center: _samples.first.point, radius: radius(0)),
      );
    }

    final left = <Offset>[];
    final right = <Offset>[];
    var normal = Offset.zero;
    for (var i = 0; i < count; i++) {
      final direction =
          _samples[math.min(i + 1, count - 1)].point -
          _samples[math.max(i - 1, 0)].point;
      if (direction.distance > 0) {
        normal = Offset(-direction.dy, direction.dx) / direction.distance;
      }
      final offset = normal * radius(i);
      left.add(_samples[i].point + offset);
      right.add(_samples[i].point - offset);
    }

    // Round head cap: sweep the head normal through the direction of travel.
    final head = _samples.last.point;
    final headRadius = radius(count - 1);
    final start = math.atan2(normal.dy, normal.dx);
    final cap = [
      for (var k = 1; k <= 7; k++)
        head + Offset.fromDirection(start - math.pi * k / 8, headRadius),
    ];

    final points = [...left, ...cap, ...right.reversed];
    Offset mid(int i) =>
        (points[i % points.length] + points[(i + 1) % points.length]) / 2;
    final path = Path()..moveTo(mid(0).dx, mid(0).dy);
    for (var i = 1; i <= points.length; i++) {
      final control = points[i % points.length];
      final end = mid(i);
      path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    }
    return path..close();
  }
}

void paintLaser(
  Canvas canvas,
  LaserTrail trail,
  Duration now, {
  required bool keepHead,
}) {
  if (trail.isEmpty) return;
  final layers = [
    (
      2.4,
      Paint()
        ..color = _laserRed.withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(.normal, _laserWidth),
    ),
    (1.0, Paint()..color = _laserRed),
    (.4, Paint()..color = Colors.white),
  ];
  for (final (scale, paint) in layers) {
    canvas.drawPath(
      trail.outline(now, _laserWidth * scale, keepHead: keepHead),
      paint,
    );
  }
}
