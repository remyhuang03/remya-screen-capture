import 'dart:io';

class HyprlandCaptureRendering {
  HyprlandCaptureRendering._(this._hex, this._restoreCursor);

  String _hex;
  bool _restoreCursor;

  static Future<HyprlandCaptureRendering> suspend({
    bool hideCursor = false,
  }) async {
    final result = await _hyprctl([
      'repl',
      '''
local shader = hl.get_config('decoration.screen_shader')
if type(shader) ~= 'string' then return 'unknown shader' end
local hide = ${hideCursor ? 'true' : 'false'} and not hl.get_config('cursor.invisible')
if shader ~= '' then
  hl.config({decoration = {screen_shader = '[[EMPTY]]'}})
end
if hide then hl.config({cursor = {invisible = true}}) end
return 'shader:' .. (shader:gsub('.', function(c) return string.format('%02x', c:byte()) end)) .. ':' .. (hide and '1' or '0')
''',
    ]);
    final response = RegExp(r'^shader:((?:[a-f0-9]{2})*):([01])$')
        .firstMatch(result.trim());
    if (response == null) {
      throw StateError('Could not read the current screen shader.');
    }
    final suspended = HyprlandCaptureRendering._(
      response[1]!,
      response[2] == '1',
    );
    if (suspended._restoreCursor) {
      // Hyprland applies cursor visibility on a 500 ms timer.
      await Future<void>.delayed(const Duration(milliseconds: 550));
    }
    return suspended;
  }

  Future<void> restore() async {
    if (_hex.isEmpty && !_restoreCursor) return;
    await _hyprctl([
      'eval',
      '''
if '$_hex' ~= '' and hl.get_config('decoration.screen_shader') == '' then
  local shader = ('$_hex'):gsub('..', function(pair) return string.char(tonumber(pair, 16)) end)
  hl.config({decoration = {screen_shader = shader}})
end
if ${_restoreCursor ? 'true' : 'false'} then
  hl.config({cursor = {invisible = false}})
end
''',
    ]);
    _hex = '';
    _restoreCursor = false;
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
