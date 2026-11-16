import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

/// Material Icons and retained SVG artwork used by capture controls.
enum CaptureSymbol {
  region.svg('region'),
  window.svg('window'),
  scrollCapture.material(Icons.swap_vert_rounded),
  check.material(Icons.check_rounded),
  close.material(Icons.close_rounded),
  copy.material(Icons.content_copy_rounded),
  edit.material(Icons.edit_rounded),
  mic.material(Icons.mic_rounded),
  micOff.material(Icons.mic_off_rounded),
  volumeUp.material(Icons.volume_up_rounded),
  volumeOff.material(Icons.volume_off_rounded),
  cursor.svg('cursor'),
  record.material(Icons.fiber_manual_record_rounded),
  stop.material(Icons.stop_rounded),
  pause.material(Icons.pause_rounded),
  play.material(Icons.play_arrow_rounded),
  laserPointer.svg('laser-pointer'),
  highlighter.svg('highlighter'),
  delete.material(Icons.delete_outline_rounded),
  timer.material(Icons.timer_rounded),
  videocam.material(Icons.videocam_rounded),
  pen.material(Icons.draw_rounded),
  rectangle.material(Icons.check_box_outline_blank_rounded),
  ellipse.material(Icons.panorama_fish_eye_rounded),
  line.material(Icons.horizontal_rule_rounded),
  arrow.material(Icons.arrow_outward_rounded),
  mosaic.svg('mosaic'),
  counter.svg('counter'),
  text.material(Icons.title_rounded),
  crop.material(Icons.crop_rounded),
  undo.material(Icons.undo_rounded),
  redo.material(Icons.redo_rounded),
  zoomIn.material(Icons.zoom_in_rounded),
  zoomOut.material(Icons.zoom_out_rounded),
  fitScreen.material(Icons.fit_screen_rounded),
  save.svg('save'),
  palette.material(Icons.palette_rounded),
  colorize.material(Icons.colorize_rounded),
  history.material(Icons.history_rounded),
  tune.material(Icons.tune_rounded),
  bold.material(Icons.format_bold_rounded),
  italic.material(Icons.format_italic_rounded),
  underline.material(Icons.format_underlined_rounded),
  strokeWidth.material(Icons.line_weight_rounded),
  keyboard.material(Icons.keyboard_rounded),
  more.material(Icons.more_horiz_rounded),
  dropdown.material(Icons.arrow_drop_down_rounded),
  settings.material(Icons.settings_rounded),
  trim.material(Icons.content_cut_rounded),
  speed.material(Icons.speed_rounded),
  movie.material(Icons.movie_rounded),
  folder.material(Icons.folder_open_rounded),
  replay5.material(Icons.replay_5_rounded),
  forward5.material(Icons.forward_5_rounded),
  move.material(Icons.open_with_rounded),
  add.material(Icons.add_rounded);

  const CaptureSymbol.material(IconData this.icon) : svgAsset = null;
  const CaptureSymbol.svg(String this.svgAsset) : icon = null;

  final IconData? icon;
  final String? svgAsset;
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
    final color =
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    if (_symbol.svgAsset case final asset?) {
      final filename = _size == 20 ? asset : '$asset-small';
      return SvgPicture.asset(
        'assets/icons/capture/$filename.svg',
        width: _size,
        height: _size,
        colorFilter: ColorFilter.mode(color, .srcIn),
        excludeFromSemantics: true,
      );
    }
    return Icon(_symbol.icon, size: _size, color: color);
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
