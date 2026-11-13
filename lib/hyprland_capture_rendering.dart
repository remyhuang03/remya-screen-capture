import 'dart:io';

class HyprlandCaptureRendering {
  HyprlandCaptureRendering._(this._hex, this._noHardwareCursors);

  String _hex;

  /// The `cursor.no_hardware_cursors` value replaced while capturing.
  int? _noHardwareCursors;

  /// Turns off the screen shader and, with [hardwareCursor], switches the
  /// cursor to the hardware plane. A software cursor is drawn into the
  /// screen image, so screencopy and KMS capture cannot leave it out.
  static Future<HyprlandCaptureRendering> suspend({
    bool hardwareCursor = false,
  }) async {
    final result = await _hyprctl([
      'repl',
      '''
local shader = hl.get_config('decoration.screen_shader')
if type(shader) ~= 'string' then return 'unknown shader' end
local nohw = hl.get_config('cursor.no_hardware_cursors')
local force = ${hardwareCursor ? 'true' : 'false'} and type(nohw) == 'number' and nohw ~= 0
if shader ~= '' then
  hl.config({decoration = {screen_shader = '[[EMPTY]]'}})
end
if force then
  hl.config({cursor = {no_hardware_cursors = 0}})
  -- The cursor backend is only re-evaluated when the pointer moves.
  local p = hl.get_cursor_pos()
  hl.dispatch(hl.dsp.cursor.move({x = p.x, y = p.y}))
end
return 'shader:' .. (shader:gsub('.', function(c) return string.format('%02x', c:byte()) end)) .. ':' .. (force and tostring(math.floor(nohw)) or '-')
''',
    ]);
    final response = RegExp(r'^shader:((?:[a-f0-9]{2})*):(-|\d+)$')
        .firstMatch(result.trim());
    if (response == null) {
      throw StateError('Could not read the current screen shader.');
    }
    final suspended = HyprlandCaptureRendering._(
      response[1]!,
      int.tryParse(response[2]!),
    );
    if (suspended._noHardwareCursors != null) {
      // Let the next frame render without the software cursor.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return suspended;
  }

  Future<void> restore() async {
    final noHardwareCursors = _noHardwareCursors;
    if (_hex.isEmpty && noHardwareCursors == null) return;
    await _hyprctl([
      'eval',
      '''
if '$_hex' ~= '' and hl.get_config('decoration.screen_shader') == '' then
  local shader = ('$_hex'):gsub('..', function(pair) return string.char(tonumber(pair, 16)) end)
  hl.config({decoration = {screen_shader = shader}})
end
if ${noHardwareCursors ?? 'nil'} and hl.get_config('cursor.no_hardware_cursors') == 0 then
  hl.config({cursor = {no_hardware_cursors = ${noHardwareCursors ?? 0}}})
  local p = hl.get_cursor_pos()
  hl.dispatch(hl.dsp.cursor.move({x = p.x, y = p.y}))
end
''',
    ]);
    _hex = '';
    _noHardwareCursors = null;
  }
}

Future<String> _hyprctl(List<String> arguments) async {
  final result = await Process.run(
    'hyprctl',
    arguments,
  ).timeout(const Duration(seconds: 5));
  if (result.exitCode != 0) {
    throw StateError(
      'hyprctl exited with ${result.exitCode}. ${result.stderr}',
    );
  }
  return result.stdout as String;
}
