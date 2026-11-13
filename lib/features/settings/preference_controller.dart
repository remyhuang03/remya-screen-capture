import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';

/// One app preference watched through remyad. Errors keep the last valid
/// value; a successful write or [start] resumes watching.
class PreferenceController<T> extends ChangeNotifier {
  PreferenceController({
    required this.preferences,
    required this.key,
    required this.parse,
    required this.save,
  });

  final AppPreferences preferences;
  final String key;
  final T Function(Object? value) parse;
  final Future<void> Function(T value) save;

  T? value;
  Object? error;
  bool saving = false;
  StreamSubscription<Map<String, dynamic>>? _watch;
  bool _disposed = false;

  void start() {
    _watch?.cancel();
    _watch = preferences
        .watch(key)
        .listen(
          (reply) {
            try {
              value = parse(reply['value']);
              error = null;
            } catch (failure) {
              error = failure;
            }
            _notify();
          },
          onError: (Object failure) {
            _watch = null;
            error = failure;
            _notify();
          },
          onDone: () => _watch = null,
          cancelOnError: true,
        );
  }

  Future<void> write(T next) async {
    if (saving) return;
    saving = true;
    _notify();
    try {
      await save(next);
      value = next;
      error = null;
      if (_watch == null && !_disposed) start();
    } catch (failure) {
      error = failure;
    } finally {
      saving = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _watch?.cancel();
    super.dispose();
  }
}

/// User-facing text for a remyad failure.
String describePreferenceError(Object error) {
  final text = '$error';
  // shortcut: matches the D-Bus error name in the text because package:dbus is
  // only a transitive dependency; switch to a typed check if remya_client
  // exports one.
  if (text.contains('org.freedesktop.DBus.Error.ServiceUnknown') ||
      text.contains('org.freedesktop.DBus.Error.NameHasNoOwner')) {
    return 'Remya Core is unavailable. Start remyad to load and change these '
        'settings.';
  }
  return text;
}
