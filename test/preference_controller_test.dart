import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_screen_capture/features/settings/preference_controller.dart';

import 'fake_app_preferences.dart';

class _DelayedPreferences extends FakeAppPreferences {
  final watches = <StreamController<Map<String, dynamic>>>[];

  @override
  Stream<Map<String, dynamic>> watch(String key) {
    final watch = StreamController<Map<String, dynamic>>();
    watches.add(watch);
    return watch.stream;
  }

  void update(int value) => watches.last.add({'value': value});
}

void main() {
  testWidgets('a newer watch value survives an older write completion', (
    tester,
  ) async {
    final preferences = _DelayedPreferences();
    final response = Completer<void>();
    final controller = PreferenceController<int>(
      preferences: preferences,
      key: 'recording',
      parse: (value) => value as int,
      save: (_) => response.future,
    )..start();
    addTearDown(controller.dispose);

    preferences.update(1);
    await tester.pump();
    final writing = controller.write(2);
    preferences.update(3);
    await tester.pump();
    response.complete();
    await writing;

    expect(controller.value, 3);
    expect(preferences.watches, hasLength(2));
    preferences.watches.first.add({'value': 1});
    preferences.update(4);
    await tester.pump();
    expect(controller.value, 4);
  });

  testWidgets('a failed watch reconnects and keeps its last valid value', (
    tester,
  ) async {
    final preferences = _DelayedPreferences();
    final controller = PreferenceController<int>(
      preferences: preferences,
      key: 'recording',
      parse: (value) => value as int,
      save: (_) async {},
    )..start();
    try {
      preferences.update(1);
      await tester.pump();
      preferences.watches.single.addError(StateError('Core unavailable'));
      await tester.pump();
      expect(controller.error, isA<StateError>());
      expect(controller.value, 1);

      await tester.pump(const Duration(seconds: 2));
      expect(preferences.watches, hasLength(2));
      preferences.update(2);
      await tester.pump();
      expect(controller.value, 2);
      expect(controller.error, isNull);
    } finally {
      controller.dispose();
    }
  });
}
