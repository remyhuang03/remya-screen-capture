import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:remya_client/remya_client.dart';

/// Uses the shipped registration defaults without touching the session bus.
class FakeAppPreferences implements AppPreferences {
  FakeAppPreferences() {
    final registration = jsonDecode(
      File('linux/packaging/remya-screen-capture.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    values = {
      for (final entry in (registration['settings'] as Map).entries)
        entry.key as String: entry.value['default'],
    };
  }

  late final Map<String, dynamic> values;
  bool unavailable = false;
  final writes = <String>[];
  final _changes = StreamController<String>.broadcast();

  /// Simulates a write from another client.
  void external(String key, Object? value) {
    values[key] = value;
    _changes.add(key);
  }

  @override
  String get id => 'remya-screen-capture';

  @override
  Future<Map<String, dynamic>> get(String key) async {
    if (unavailable) throw StateError('Core unavailable');
    return {'id': '$id.$key', 'value': values[key], 'revision': 'test'};
  }

  @override
  Future<Map<String, dynamic>> set(String key, Object? value) async {
    if (unavailable) throw StateError('Core unavailable');
    writes.add(key);
    values[key] = value;
    _changes.add(key);
    return get(key);
  }

  @override
  Stream<Map<String, dynamic>> watch(String key) async* {
    final pending = _changes.stream.where((changed) => changed == key);
    yield await get(key);
    await for (final _ in pending) {
      yield await get(key);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
