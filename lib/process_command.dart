import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Runs a short command with a deadline for its exit and output.
Future<ProcessResult> runCommand(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  Future<Process> Function(String, List<String>) launch = Process.start,
}) async {
  final process = await launch(executable, arguments);
  process.stdin.close().ignore();
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  const decoder = Utf8Decoder(allowMalformed: true);
  final output = process.stdout.transform(decoder).listen(stdout.write);
  final errors = process.stderr.transform(decoder).listen(stderr.write);
  var exited = false;
  final exit = process.exitCode.then((status) {
    exited = true;
    return status;
  });
  try {
    final (status, _, _) = await (
      exit,
      output.asFuture<void>(),
      errors.asFuture<void>(),
    ).wait.timeout(timeout);
    return ProcessResult(
      process.pid,
      status,
      stdout.toString(),
      stderr.toString(),
    );
  } finally {
    if (!exited) process.kill(.sigkill);
    // A descendant may keep a pipe open even after the command exited.
    await output.cancel();
    await errors.cancel();
  }
}
