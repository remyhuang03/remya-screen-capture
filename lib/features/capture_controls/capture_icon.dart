import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

/// Material Symbols Rounded artwork from the capture design.
enum CaptureSymbol {
  region('region'),
  window('window'),
  scrollCapture('scroll-capture'),
  check('check'),
  close('close'),
  copy('copy'),
  edit('edit'),
  mic('mic'),
  micOff('mic-off'),
  volumeUp('volume-up'),
  volumeOff('volume-off'),
  cursor('cursor'),
  record('record'),
  stop('stop'),
  pause('pause'),
  play('play'),
  laserPointer('laser-pointer'),
  highlighter('highlighter'),
  delete('delete'),
  timer('timer'),
  videocam('videocam'),
  pen('pen'),
  rectangle('rectangle'),
  ellipse('ellipse'),
  line('line'),
  arrow('arrow'),
  mosaic('mosaic'),
  counter('counter'),
  text('text'),
  crop('crop'),
  undo('undo'),
  redo('redo'),
  zoomIn('zoom-in'),
  zoomOut('zoom-out'),
  fitScreen('fit-screen'),
  save('save'),
  palette('palette'),
  colorize('colorize'),
  history('history'),
  tune('tune'),
  bold('bold'),
  italic('italic'),
  underline('underline'),
  strokeWidth('stroke-width'),
  keyboard('keyboard'),
  more('more'),
  dropdown('dropdown'),
  settings('settings'),
  trim('trim'),
  speed('speed'),
  movie('movie'),
  folder('folder'),
  replay5('replay-5'),
  forward5('forward-5'),
  move('move'),
  add('add');

  const CaptureSymbol(this.asset);

  final String asset;
}

class CaptureIcon extends StatelessWidget {
  const CaptureIcon(CaptureSymbol symbol, {super.key})
    : _symbol = symbol,
      _size = 20;

  const CaptureIcon.segmentRegion({super.key}) : _symbol = .region, _size = 18;

  const CaptureIcon.segmentWindow({super.key}) : _symbol = .window, _size = 18;

  const CaptureIcon.segmentColor({super.key}) : _symbol = .colorize, _size = 18;

  const CaptureIcon.swatchAdd({super.key}) : _symbol = .add, _size = 16;

  final CaptureSymbol _symbol;
  final double _size;

  @override
  Widget build(BuildContext context) {
    final asset = _size == 20 ? _symbol.asset : '${_symbol.asset}-small';
    final color =
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SvgPicture.asset(
      'assets/icons/capture/$asset.svg',
      width: _size,
      height: _size,
      colorFilter: ColorFilter.mode(color, .srcIn),
      excludeFromSemantics: true,
    );
  }
}

class CaptureAppIcon extends StatelessWidget {
  const CaptureAppIcon({super.key});

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/icons/app_icon.png',
    width: 40,
    height: 40,
    excludeFromSemantics: true,
  );
}
