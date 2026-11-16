import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

const captureIconWeight = 400.0;

/// Material Symbols used by capture controls.
enum CaptureSymbol {
  region(Symbols.screenshot_region_rounded),
  window(Symbols.select_window_2_rounded),
  scrollCapture(Symbols.swap_vert_rounded),
  check(Symbols.check_rounded),
  close(Symbols.close_rounded),
  copy(Symbols.content_copy_rounded),
  edit(Symbols.edit_rounded),
  mic(Symbols.mic_rounded),
  micOff(Symbols.mic_off_rounded),
  volumeUp(Symbols.volume_up_rounded),
  volumeOff(Symbols.volume_off_rounded),
  cursor(Symbols.arrow_selector_tool_rounded),
  record(Symbols.fiber_manual_record_rounded, fill: 1),
  stop(Symbols.stop_rounded, fill: 1),
  pause(Symbols.pause_rounded, fill: 1),
  play(Symbols.play_arrow_rounded, fill: 1),
  laserPointer(Symbols.stylus_laser_pointer_rounded),
  highlighter(Symbols.ink_highlighter_rounded),
  delete(Symbols.delete_outline_rounded),
  timer(Symbols.timer_rounded),
  videocam(Symbols.videocam_rounded),
  pen(Symbols.draw_rounded),
  rectangle(Symbols.check_box_outline_blank_rounded),
  ellipse(Symbols.panorama_fish_eye_rounded),
  line(Symbols.horizontal_rule_rounded),
  arrow(Symbols.arrow_outward_rounded),
  mosaic(Symbols.blur_on_rounded),
  counter(Symbols.counter_1_rounded),
  text(Symbols.title_rounded),
  crop(Symbols.crop_rounded),
  undo(Symbols.undo_rounded),
  redo(Symbols.redo_rounded),
  zoomIn(Symbols.zoom_in_rounded),
  zoomOut(Symbols.zoom_out_rounded),
  fitScreen(Symbols.fit_screen_rounded),
  save(Symbols.download_rounded),
  palette(Symbols.palette_rounded),
  colorize(Symbols.colorize_rounded),
  history(Symbols.history_rounded),
  tune(Symbols.tune_rounded),
  bold(Symbols.format_bold_rounded),
  italic(Symbols.format_italic_rounded),
  underline(Symbols.format_underlined_rounded),
  strokeWidth(Symbols.line_weight_rounded),
  keyboard(Symbols.keyboard_rounded),
  more(Symbols.more_horiz_rounded),
  dropdown(Symbols.arrow_drop_down_rounded),
  settings(Symbols.settings_rounded),
  trim(Symbols.content_cut_rounded),
  speed(Symbols.speed_rounded),
  movie(Symbols.movie_rounded),
  folder(Symbols.folder_open_rounded),
  previousFrame(Symbols.skip_previous_rounded, fill: 1),
  nextFrame(Symbols.skip_next_rounded, fill: 1),
  move(Symbols.open_with_rounded),
  add(Symbols.add_rounded);

  const CaptureSymbol(this.icon, {this.fill});

  final IconData icon;
  final double? fill;
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
    return Icon(
      _symbol.icon,
      size: _size,
      color: color,
      fill: _symbol.fill,
      weight: captureIconWeight,
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
