import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../capture_windows.dart';

String recordingShortcutPath() =>
    '${captureRuntimeDirectory()}/top.remya.screen_capture.record.sock';

Future<bool> forwardRecordingShortcut(String path) async {
  final Socket socket;
  try {
    socket = await Socket.connect(
      InternetAddress(path, type: .unix),
      0,
      timeout: const Duration(milliseconds: 350),
    );
  } on SocketException {
    return false;
  }
  try {
    socket.writeln('toggle');
    final reply = await socket
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 1));
    return reply == 'ok';
  } on IOException {
    return false;
  } on StateError {
    return false;
  } on TimeoutException {
    return false;
  } finally {
    socket.destroy();
  }
}

class RecordingShortcut {
  RecordingShortcut._(this._server, this._path);

  final ServerSocket _server;
  final String _path;

  // Only bind or unlink the socket while holding the shared capture lock.
  static Future<RecordingShortcut> listen(
    String path,
    void Function() onToggle,
  ) async {
    await _unlink(path);
    final server = await ServerSocket.bind(
      InternetAddress(path, type: .unix),
      0,
    );
    server.listen((socket) => unawaited(_reply(socket, onToggle)));
    return RecordingShortcut._(server, path);
  }

  static Future<void> _reply(Socket socket, void Function() onToggle) async {
    try {
      final request = await socket
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 1));
      if (request != 'toggle') return;
      socket.writeln('ok');
      await socket.flush();
      onToggle();
    } on IOException {
      // A shortcut invocation can exit before the reply.
    } on StateError {
      // A client that disconnects before sending a line has no request.
    } on TimeoutException {
      // Stale connections do not affect the current recording.
    } finally {
      socket.destroy();
    }
  }

  Future<void> close() async {
    await _server.close();
    await _unlink(_path);
  }

  static Future<void> _unlink(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode != 2) rethrow;
    }
  }
}
