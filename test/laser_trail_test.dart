import 'package:flutter_test/flutter_test.dart';
import 'package:remya_screen_capture/features/recording/laser_trail.dart';

void main() {
  const ms = Duration(milliseconds: 1);

  test('densifies fast moves', () {
    final trail = LaserTrail()
      ..add(Offset.zero, Duration.zero)
      ..add(const Offset(60, 0), ms * 16);
    expect(trail.length, greaterThanOrEqualTo(10));
  });

  test('outlines a horizontal stroke as a thin tapered shape', () {
    final trail = LaserTrail();
    for (var i = 0; i <= 10; i++) {
      trail.add(Offset(i * 20.0, 0), ms * (i * 16));
    }
    final bounds = trail.outline(ms * 160, 10, keepHead: true).getBounds();
    expect(bounds.isEmpty, isFalse);
    expect(bounds.height, lessThanOrEqualTo(10 + .01));
    expect(bounds.width, greaterThan(100));
  });

  test('prunes expired samples', () {
    final trail = LaserTrail()
      ..add(Offset.zero, Duration.zero)
      ..add(const Offset(60, 0), ms * 16);
    trail.prune(trail.lifetime + ms * 100);
    expect(trail.isEmpty, isTrue);
  });

  test('keeps a held single sample as a full circle', () {
    final trail = LaserTrail()..add(const Offset(50, 50), Duration.zero);
    final bounds = trail
        .outline(const Duration(seconds: 5), 10, keepHead: true)
        .getBounds();
    expect(bounds.width, closeTo(10, .01));
    expect(bounds.height, closeTo(10, .01));
  });
}
