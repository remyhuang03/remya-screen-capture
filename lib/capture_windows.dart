import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';

const captureWindows = MethodChannel('top.remya.screen_capture/windows');

Future<int> openCaptureWindow(String role, {String? output}) async =>
    (await captureWindows.invokeMethod<int>('open', {
      'role': role,
      'output': ?output,
    }))!;

Future<void> changeCaptureWindow(String action, int id) async {
  try {
    await captureWindows.invokeMethod<void>(action, {'id': id});
  } on PlatformException catch (error) {
    if (error.code != 'window-closed' || action == 'show') rethrow;
  }
}

Future<void> setCaptureInput(int id, List<Rect>? rects, String keyboard) =>
    captureWindows.invokeMethod<void>('input', {
      'id': id,
      'keyboard': keyboard,
      'rects': rects
          ?.map(
            (rect) => {
              'x': rect.left.floor(),
              'y': rect.top.floor(),
              'width': rect.right.ceil() - rect.left.floor(),
              'height': rect.bottom.ceil() - rect.top.floor(),
            },
          )
          .toList(),
    });

String captureRuntimeDirectory() {
  final runtime = Platform.environment['XDG_RUNTIME_DIR'];
  if (runtime == null || !runtime.startsWith('/')) {
    throw StateError('A Wayland runtime directory is required.');
  }
  return runtime;
}

Future<RandomAccessFile?> tryCaptureLock() async {
  final runtime = captureRuntimeDirectory();
  final lock = await File('$runtime/top.remya.screen_capture.lock')
      .open(mode: .append);
  try {
    await lock.lock();
    return lock;
  } on FileSystemException catch (error) {
    await lock.close();
    // Linux fcntl reports a contended lock as EAGAIN or EACCES.
    if (error.osError?.errorCode case 11 || 13) return null;
    rethrow;
  }
}

class CaptureViews extends StatelessWidget {
  const CaptureViews(this.widgets, {super.key});

  final Map<int, Widget> widgets;

  @override
  Widget build(BuildContext context) => ViewCollection(
    views: [
      for (final view in WidgetsBinding.instance.platformDispatcher.views)
        if (widgets[view.viewId] case final home?)
          View(
            key: ValueKey(view.viewId),
            view: view,
            child: RemyaScreenCaptureApp(home: home),
          ),
    ],
  );
}
