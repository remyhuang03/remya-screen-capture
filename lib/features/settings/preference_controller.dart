import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';

/// One app preference watched through remyad. Errors keep the last valid
/// value while the connection recovers.
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
  Timer? _retry;
  int _watchGeneration = 0;
  int _observed = 0;
  bool _disposed = false;

  void start() {
    if (_disposed) return;
    _retry?.cancel();
    _retry = null;
    final generation = ++_watchGeneration;
    _watch?.cancel().ignore();
    _watch = preferences
        .watch(key)
        .listen(
          (reply) {
            if (generation != _watchGeneration) return;
            try {
              value = parse(reply['value']);
              _observed++;
              error = null;
            } catch (failure) {
              error = failure;
            }
            _notify();
          },
          onError: (Object failure) {
            if (generation != _watchGeneration) return;
            error = failure;
            _watchEnded();
            _notify();
          },
          onDone: () {
            if (generation != _watchGeneration) return;
            _watchEnded();
          },
          cancelOnError: true,
        );
  }

  void _watchEnded() {
    _watch = null;
    _retry ??= Timer(const Duration(seconds: 2), start);
  }

  Future<void> write(T next) async {
    if (saving || _disposed) return;
    final observed = _observed;
    saving = true;
    _notify();
    try {
      await save(next);
      if (_disposed) return;
      if (observed == _observed) value = next;
      error = null;
      // Read from a fresh subscription after Set so an older response cannot
      // undo a value just observed from Core or arrive later.
      start();
    } catch (failure) {
      if (!_disposed) error = failure;
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
    _watchGeneration++;
    _retry?.cancel();
    _watch?.cancel().ignore();
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
    return 'Remy\'a Core is unavailable. Start remyad to load and change these '
        'settings.';
  }
  return text;
}
