import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../capture_controls/capture_buttons.dart';
import '../capture_controls/capture_icon.dart';
import '../capture_controls/capture_labels.dart';
import 'color_adjustment.dart';
import 'color_data.dart';
import 'color_picker_preferences_dialog.dart';

const _mono = TextStyle(
  fontFamily: 'JetBrains Mono',
  fontFamilyFallback: ['JetBrainsMono Nerd Font Mono', 'monospace'],
);
const _feedbackDuration = Duration(milliseconds: 1200);
const _shadeSteps = [20, 10, 0, -10, -20];

class ColorResultPanel extends StatefulWidget {
  const ColorResultPanel({
    super.key,
    required this.picked,
    required this.history,
    required this.preferences,
    required this.copied,
    this.error,
    required this.onCopy,
    required this.onRemember,
    required this.onDelete,
    required this.onPreferences,
    required this.onPickAgain,
    required this.onClose,
    required this.onHeightChanged,
  });

  static double preferredHeight(ColorPickerPreferences preferences) =>
      179 + _bodyHeight(preferences.formats.length);

  static double _bodyHeight(int formats) => math.max(408, 194 + 46.0 * formats);

  final PickedColor picked;
  final List<PickedColor> history;
  final ColorPickerPreferences preferences;
  final ColorFormat? copied;
  final String? error;
  final Future<void> Function(String) onCopy;
  final Future<List<PickedColor>> Function(PickedColor) onRemember;
  final Future<List<PickedColor>> Function(PickedColor) onDelete;
  final Future<void> Function(ColorPickerPreferences) onPreferences;
  final VoidCallback onPickAgain;
  final VoidCallback onClose;
  final ValueChanged<double> onHeightChanged;

  @override
  State<ColorResultPanel> createState() => _ColorResultPanelState();
}

class _ColorResultPanelState extends State<ColorResultPanel> {
  final _focus = FocusNode(debugLabel: 'Color result');
  late var _picked = widget.picked;
  late var _history = widget.history;
  late var _preferences = widget.preferences;
  late var _selected = _preferences.defaultFormat;
  late ColorFormat? _copied = widget.copied;
  late ColorFormat? _copiedRow = widget.copied;
  late Color? _clipboardColor = widget.copied == null ? null : _picked.color;
  late String? _error = widget.error;
  HSLColor? _draft;
  Timer? _copyFeedback;
  bool _busy = false;

  bool get _adjusting => _draft != null;
  Color get _color => _draft?.toColor() ?? _picked.color;

  @override
  void dispose() {
    _copyFeedback?.cancel();
    _focus.dispose();
    super.dispose();
  }

  String _value(ColorFormat format, Color color) =>
      format.format(color, uppercase: _preferences.uppercase);

  void _selectColor(PickedColor entry) {
    setState(() {
      _picked = entry;
      _copiedRow = null;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _writeClipboard(ColorFormat format, Color color) async {
    await widget.onCopy(_value(format, color));
    if (!mounted) return;
    _copyFeedback?.cancel();
    setState(() {
      _clipboardColor = color;
      _copied = format;
      _copiedRow = format;
      _error = null;
    });
    _copyFeedback = Timer(_feedbackDuration, () {
      if (mounted) setState(() => _copiedRow = null);
    });
  }

  void _copy(ColorFormat format, {bool close = false}) {
    if (_busy) return;
    final color = _color;
    if (!_adjusting) setState(() => _selected = format);
    unawaited(
      _run(() async {
        await _writeClipboard(format, color);
        if (mounted && close) widget.onClose();
      }),
    );
  }

  void _delete(PickedColor entry) => unawaited(
    _run(() async {
      final history = await widget.onDelete(entry);
      if (!mounted) return;
      setState(() {
        _history = history;
        if (_picked == entry && history.isNotEmpty) _picked = history.first;
      });
    }),
  );

  void _toggleAdjust(bool adjust) {
    setState(() => _draft = adjust ? HSLColor.fromColor(_picked.color) : null);
    widget.onHeightChanged(
      adjust ? 587 : ColorResultPanel.preferredHeight(_preferences),
    );
    if (!adjust) _focus.requestFocus();
  }

  void _apply() {
    final draft = _draft;
    if (draft == null) return;
    final entry = _picked.withColor(draft.toColor());
    unawaited(
      _run(() async {
        final history = await widget.onRemember(entry);
        if (!mounted) return;
        setState(() {
          _history = history;
          _picked = entry;
        });
        _toggleAdjust(false);
        await _writeClipboard(_preferences.defaultFormat, entry.color);
      }),
    );
  }

  Future<void> _settings() async {
    final preferences = await showColorPickerPreferences(context, _preferences);
    if (preferences == null || !mounted) return;
    await _run(() async {
      await widget.onPreferences(preferences);
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _selected = preferences.defaultFormat;
        _history = _history.take(preferences.historySize).toList();
        _error = null;
      });
      if (!_adjusting) {
        widget.onHeightChanged(ColorResultPanel.preferredHeight(preferences));
      }
      _focus.requestFocus();
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return .ignored;
    final key = event.logicalKey;
    if (key == .escape) {
      if (!_busy) {
        if (_adjusting) {
          _toggleAdjust(false);
        } else {
          widget.onClose();
        }
      }
      return .handled;
    }
    if (_busy) return .ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed) {
      return .ignored;
    }
    if (_adjusting) {
      if (key != .enter && key != .numpadEnter) return .ignored;
      if (event is! KeyRepeatEvent) _apply();
      return .handled;
    }
    if (key == .keyA && !keyboard.isShiftPressed) {
      if (event is! KeyRepeatEvent) _toggleAdjust(true);
      return .handled;
    }
    final formats = _preferences.formats;
    final row = int.tryParse(event.character ?? '');
    if (row != null && row > 0 && row <= formats.length) {
      if (event is! KeyRepeatEvent) _copy(formats[row - 1]);
      return .handled;
    }
    if (!node.hasPrimaryFocus) return .ignored;
    if (key == .space) {
      if (event is! KeyRepeatEvent) widget.onPickAgain();
    } else if (key == .enter || key == .numpadEnter) {
      if (event is! KeyRepeatEvent) _copy(_selected, close: true);
    } else if (key == .arrowUp || key == .arrowDown) {
      final step = key == .arrowUp ? -1 : 1;
      final index = (formats.indexOf(_selected) + step).clamp(
        0,
        formats.length - 1,
      );
      setState(() => _selected = formats[index]);
    } else {
      return .ignored;
    }
    return .handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final formats = _preferences.formats;
    final hsl = HSLColor.fromColor(_picked.color);
    final draft = _draft;
    final history = _history.take(_preferences.historySize).toList();
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: Material(
        color: colors.surfaceContainer,
        elevation: 14,
        shadowColor: Colors.black87,
        shape: RoundedRectangleBorder(
          borderRadius: .circular(32),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
        ),
        clipBehavior: .antiAlias,
        child: SingleChildScrollView(
          padding: const .all(17),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 16,
            children: [
              _Header(
                title: draft == null ? 'Picked color' : 'Adjust color',
                subtitle: draft == null
                    ? '${_coordinates(_picked)}  ·  ${_picked.output}  ·  '
                          '${TimeOfDay.fromDateTime(_picked.time).format(context)}'
                    : 'Adjusting · HSL · live preview',
                onClose: _busy ? null : widget.onClose,
                onSettings: _busy || draft != null ? null : _settings,
              ),
              SizedBox(
                height: draft == null
                    ? ColorResultPanel._bodyHeight(formats.length)
                    : 408,
                child: Row(
                  crossAxisAlignment: .stretch,
                  spacing: 16,
                  children: [
                    if (history.isNotEmpty)
                      _HistoryRail(
                        entries: history,
                        current: _picked,
                        uppercase: _preferences.uppercase,
                        onSelected: _busy || draft != null
                            ? null
                            : _selectColor,
                        onDelete: _busy || draft != null ? null : _delete,
                      ),
                    Expanded(
                      child: Column(
                        spacing: 12,
                        children: [
                          _Hero(
                            color: _color,
                            value: _value(_preferences.defaultFormat, _color),
                            original: draft == null ? null : _picked.color,
                            badge: draft != null
                                ? 'was ${_value(.hex, _picked.color)}'
                                : _clipboardColor == _color && _copied != null
                                ? '${_copied!.label} copied'
                                : null,
                          ),
                          if (draft != null)
                            ColorAdjustment(
                              value: draft,
                              enabled: !_busy,
                              onChanged: (value) =>
                                  setState(() => _draft = value),
                              onApply: _apply,
                            )
                          else
                            _Shades(
                              color: hsl,
                              onChanged: _busy
                                  ? null
                                  : (color) =>
                                        _selectColor(_picked.withColor(color)),
                            ),
                          Column(
                            spacing: 2,
                            children: [
                              for (final (index, format)
                                  in (draft == null
                                          ? formats
                                          : const [ColorFormat.hex])
                                      .indexed)
                                _FormatRow(
                                  index: index + 1,
                                  format: format,
                                  value: _value(format, _color),
                                  selected:
                                      draft != null || format == _selected,
                                  copied:
                                      _clipboardColor == _color &&
                                      format == _copiedRow,
                                  onCopy: _busy
                                      ? null
                                      : () {
                                          if (draft == null) {
                                            _focus.requestFocus();
                                          }
                                          _copy(format);
                                        },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                spacing: 8,
                children: [
                  CaptureButton(
                    label: draft == null ? 'Adjust' : 'Reset',
                    variant: .text,
                    icon: CaptureIcon(draft == null ? .tune : .undo),
                    onPressed: _busy
                        ? null
                        : draft == null
                        ? () => _toggleAdjust(true)
                        : () => setState(() => _draft = hsl),
                  ),
                  const Spacer(),
                  CaptureButton(
                    label: draft == null ? 'Pick again' : 'Cancel',
                    variant: draft == null ? .tonal : .text,
                    icon: CaptureIcon(draft == null ? .colorize : .close),
                    onPressed: _busy
                        ? null
                        : draft == null
                        ? widget.onPickAgain
                        : () => _toggleAdjust(false),
                  ),
                  CaptureButton(
                    label: draft == null ? 'Done' : 'Apply',
                    icon: const CaptureIcon(.check),
                    onPressed: _busy
                        ? null
                        : draft == null
                        ? widget.onClose
                        : _apply,
                  ),
                ],
              ),
              if (_error case final error?)
                Semantics(
                  liveRegion: true,
                  child: Tooltip(
                    message: error,
                    child: Text(
                      error,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ),
                )
              else
                _Hints(
                  draft == null
                      ? [
                          ('1–${formats.length}', 'Copy'),
                          ('↑↓', 'Select'),
                          ('Enter', 'Copy & close'),
                          ('Space', 'Pick again'),
                          ('A', 'Adjust'),
                          ('Esc', 'Close'),
                        ]
                      : const [
                          ('Tab', 'Next slider'),
                          ('←→', '±1'),
                          ('Shift ←→', '±10'),
                          ('0–9', 'Type value'),
                          ('Enter', 'Apply & copy'),
                          ('Esc', 'Back'),
                        ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _coordinates(PickedColor entry) =>
    '${entry.position.dx.floor()}, ${entry.position.dy.floor()}';

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onClose,
    this.onSettings,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onClose;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      spacing: 12,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: .circular(14),
          ),
          alignment: .center,
          child: IconTheme(
            data: IconThemeData(color: colors.onPrimaryContainer),
            child: const CaptureIcon(.colorize),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: .ellipsis,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (onSettings != null)
          CaptureIconButton(
            icon: .settings,
            label: 'Color picker settings',
            onPressed: onSettings,
          ),
        CaptureIconButton(
          icon: .close,
          label: 'Close color picker',
          onPressed: onClose,
        ),
      ],
    );
  }
}

class _HistoryRail extends StatefulWidget {
  const _HistoryRail({
    required this.entries,
    required this.current,
    required this.uppercase,
    this.onSelected,
    this.onDelete,
  });

  final List<PickedColor> entries;
  final PickedColor current;
  final bool uppercase;
  final ValueChanged<PickedColor>? onSelected;
  final ValueChanged<PickedColor>? onDelete;

  @override
  State<_HistoryRail> createState() => _HistoryRailState();
}

class _HistoryRailState extends State<_HistoryRail> {
  final _focus = FocusNode(debugLabel: 'Color history');
  final _scroll = ScrollController();
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final entries = widget.entries;
    if (event is KeyUpEvent || entries.isEmpty) return .ignored;
    final key = event.logicalKey;
    final index = entries.indexOf(widget.current);
    if (key == .delete && widget.onDelete != null) {
      if (index >= 0 && event is! KeyRepeatEvent) {
        widget.onDelete!(entries[index]);
      }
      return .handled;
    }
    final select = widget.onSelected;
    if (select == null || (key != .arrowUp && key != .arrowDown)) {
      return .ignored;
    }
    final next = (index + (key == .arrowUp ? -1 : 1)).clamp(
      0,
      entries.length - 1,
    );
    select(entries[next]);
    if (_scroll.hasClients) {
      final position = _scroll.position;
      final top = next * 44.0;
      final bottom = top + 44.0 - position.viewportDimension;
      _scroll.jumpTo(
        position.pixels
            .clamp(math.min(top, bottom), top)
            .clamp(0.0, position.maxScrollExtent)
            .toDouble(),
      );
    }
    return .handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final current = widget.current;
    final entries = widget.entries;
    return Focus(
      focusNode: _focus,
      canRequestFocus: widget.onSelected != null,
      onFocusChange: (focused) => setState(() => _focused = focused),
      onKeyEvent: _key,
      child: Semantics(
        label: 'Color history',
        child: Container(
          width: 52,
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            borderRadius: .circular(26),
            border: _focused ? Border.all(color: colors.primary) : null,
          ),
          padding: const .symmetric(vertical: 8),
          child: Column(
            children: [
              const Padding(padding: .all(4), child: CaptureIcon(.history)),
              Container(
                width: 4,
                height: 4,
                margin: const .symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: colors.outlineVariant,
                  shape: .circle,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: entries.length,
                  itemExtent: 44,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final selected = current == entry;
                    final label = ColorFormat.hex.format(
                      entry.color,
                      uppercase: widget.uppercase,
                    );
                    return Center(
                      child: Tooltip(
                        message: label,
                        child: Semantics(
                          button: true,
                          selected: selected,
                          child: Material(
                            color: entry.color,
                            shape: RoundedRectangleBorder(
                              borderRadius: .circular(selected ? 20 : 10),
                              side: BorderSide(
                                width: selected ? 2 : 1,
                                color: selected
                                    ? colors.onSurface
                                    : colors.outlineVariant,
                              ),
                            ),
                            clipBehavior: .antiAlias,
                            child: InkWell(
                              canRequestFocus: false,
                              onTap: widget.onSelected == null
                                  ? null
                                  : () {
                                      _focus.requestFocus();
                                      widget.onSelected!(entry);
                                    },
                              child: SizedBox.square(
                                dimension: selected ? 40 : 36,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _foreground(Color background) =>
    background.computeLuminance() < .179 ? Colors.white : Colors.black;

class _Hero extends StatelessWidget {
  const _Hero({
    required this.color,
    required this.value,
    this.original,
    this.badge,
  });

  final Color color;
  final Color? original;
  final String value;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final previous = original;
    final foreground = _foreground(previous ?? color);
    final tagForeground = _foreground(color);
    final badge = this.badge;
    return Container(
      height: 132,
      padding: const .fromLTRB(20, 20, 16, 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: .circular(28),
        gradient: previous == null
            ? null
            : LinearGradient(
                colors: [previous, previous, color, color],
                stops: const [0, .3, .3, 1],
              ),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisAlignment: .spaceBetween,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FittedBox(
                    fit: .scaleDown,
                    alignment: .centerLeft,
                    child: Text(
                      value,
                      style: _mono.copyWith(
                        fontSize: 32,
                        fontWeight: .w500,
                        color: foreground,
                        shadows: previous == null || foreground == tagForeground
                            ? null
                            : [Shadow(color: tagForeground, blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  decoration: BoxDecoration(
                    color: tagForeground.withValues(alpha: .18),
                    borderRadius: .circular(14),
                  ),
                  padding: .symmetric(
                    horizontal: 12,
                    vertical: previous == null ? 6 : 5,
                  ),
                  child: Row(
                    mainAxisSize: .min,
                    spacing: 6,
                    children: [
                      if (previous == null)
                        IconTheme(
                          data: IconThemeData(color: tagForeground),
                          child: const CaptureIcon(.check),
                        ),
                      Text(
                        badge,
                        style: TextStyle(
                          color: tagForeground,
                          fontSize: 12,
                          fontWeight: .w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          FittedBox(
            fit: .scaleDown,
            alignment: .centerLeft,
            child: Row(
              spacing: 8,
              children: [
                Text(
                  'Contrast',
                  style: TextStyle(fontSize: 12, color: foreground),
                ),
                _ContrastTag(color: color, background: Colors.white),
                _ContrastTag(color: color, background: Colors.black),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContrastTag extends StatelessWidget {
  const _ContrastTag({required this.color, required this.background});

  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final luminance = color.computeLuminance() + .05;
    final white = background == Colors.white;
    final ratio = white ? 1.05 / luminance : luminance / .05;
    final rating = ratio >= 7
        ? 'AAA'
        : ratio >= 4.5
        ? 'AA'
        : 'Fail';
    final value = '${ratio.toStringAsFixed(2)} : 1  $rating';
    return Semantics(
      label: 'Contrast against ${white ? 'white' : 'black'}, $value',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: .circular(8),
        ),
        padding: const .symmetric(horizontal: 8, vertical: 3),
        child: Text(
          'Aa  $value',
          style: TextStyle(
            fontSize: 10,
            height: 1.3,
            color: ratio >= 4.5 ? color : _foreground(background),
          ),
        ),
      ),
    );
  }
}

class _Shades extends StatelessWidget {
  const _Shades({required this.color, this.onChanged});

  final HSLColor color;
  final ValueChanged<Color>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 2,
    children: [
      for (final step in _shadeSteps)
        Expanded(
          child: _Shade(
            step: step,
            color: color
                .withLightness((color.lightness + step / 100).clamp(0.0, 1.0))
                .toColor(),
            onChanged: onChanged,
          ),
        ),
    ],
  );
}

class _Shade extends StatelessWidget {
  const _Shade({required this.step, required this.color, this.onChanged});

  final int step;
  final Color color;
  final ValueChanged<Color>? onChanged;

  @override
  Widget build(BuildContext context) {
    final foreground = _foreground(color);
    final selected = step == 0;
    final label = selected
        ? 'Current lightness'
        : 'Lightness ${step > 0 ? '+' : '−'}${step.abs()}';
    return Semantics(
      label: label,
      selected: selected,
      child: FilledButton(
        style:
            FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: foreground,
              disabledBackgroundColor: color,
              disabledForegroundColor: foreground,
              minimumSize: const Size(0, 40),
              tapTargetSize: .shrinkWrap,
              padding: .zero,
              shape: RoundedRectangleBorder(
                borderRadius: .horizontal(
                  left: Radius.circular(step == 20 || selected ? 20 : 6),
                  right: Radius.circular(step == -20 || selected ? 20 : 6),
                ),
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => selected || states.contains(WidgetState.focused)
                    ? BorderSide(color: foreground, width: 2)
                    : null,
              ),
            ),
        onPressed: selected || onChanged == null
            ? null
            : () => onChanged!(color),
        child: ExcludeSemantics(
          child: Text(
            selected ? '●' : 'L ${step > 0 ? '+' : '−'}${step.abs()}',
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ),
    );
  }
}

class _FormatRow extends StatelessWidget {
  const _FormatRow({
    required this.index,
    required this.format,
    required this.value,
    required this.selected,
    required this.copied,
    required this.onCopy,
  });

  final int index;
  final ColorFormat format;
  final String value;
  final bool selected;
  final bool copied;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: 'Copy ${format.label}, $value',
      child: Material(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        borderRadius: .circular(22),
        clipBehavior: .antiAlias,
        child: InkWell(
          canRequestFocus: false,
          onTap: onCopy,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const .symmetric(horizontal: 12),
              child: Row(
                spacing: 12,
                children: [
                  ExcludeSemantics(child: CaptureKeycap('$index')),
                  SizedBox(
                    width: 52,
                    child: Text(
                      format.label,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      overflow: .ellipsis,
                      maxLines: 1,
                      style: _mono.copyWith(fontSize: 14),
                    ),
                  ),
                  Tooltip(
                    message: copied
                        ? '${format.label} copied'
                        : 'Copy ${format.label}',
                    child: CaptureIcon(copied ? .check : .copy),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hints extends StatelessWidget {
  const _Hints(this.hints);

  final List<(String, String)> hints;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 4,
    children: [
      for (final (key, label) in hints)
        Row(
          mainAxisSize: .min,
          spacing: 6,
          children: [
            CaptureKeycap(key),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
    ],
  );
}

class ColorCopyToast extends StatelessWidget {
  const ColorCopyToast({
    super.key,
    required this.picked,
    required this.preferences,
    required this.onDetails,
    required this.onClose,
  });

  final PickedColor picked;
  final ColorPickerPreferences preferences;
  final VoidCallback onDetails;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = preferences.defaultFormat;
    final value = format.format(picked.color, uppercase: preferences.uppercase);
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return .ignored;
        if (event.logicalKey == .escape) {
          onClose();
        } else if (const SingleActivator(.keyH)
            .accepts(event, HardwareKeyboard.instance)) {
          onDetails();
        } else {
          return .ignored;
        }
        return .handled;
      },
      child: CaptureSurface(
        child: Row(
          spacing: 8,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: picked.color,
                borderRadius: .circular(16),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const .only(left: 8),
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      'Copied $value',
                      style: theme.textTheme.labelLarge,
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                    Text(
                      '${format.label} · ${_coordinates(picked)}'
                      '${preferences.historySize > 0 ? ' · added to history' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            CaptureButton(
              label: 'Details',
              variant: .text,
              icon: const CaptureIcon(.tune),
              onPressed: onDetails,
            ),
            CaptureIconButton(
              icon: .close,
              label: 'Dismiss',
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
