import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../capture_controls/capture_buttons.dart';
import '../capture_controls/capture_color_picker.dart';
import '../capture_controls/capture_icon.dart';
import '../capture_controls/capture_labels.dart';
import '../capture_controls/capture_slider.dart';
import '../capture_controls/capture_swatch.dart';

part 'editor_document.dart';
part 'editor_fonts.dart';
part 'editor_toolbar.dart';
part 'editor_viewport.dart';

/// Edits a borrowed image and exports flattened PNG bytes at source resolution.
class ImageEditor extends StatefulWidget {
  const ImageEditor({
    super.key,
    required this.image,
    required this.initialName,
    required this.onCopy,
    required this.onSave,
    required this.onClose,
    this.closeRequests,
    this.onMoveWindow,
  });

  final ui.Image image;
  final String initialName;
  final Future<void> Function(Uint8List png) onCopy;
  final Future<String?> Function(Uint8List png, {required bool saveAs}) onSave;
  final VoidCallback onClose;
  final Listenable? closeRequests;
  final VoidCallback? onMoveWindow;

  @override
  State<ImageEditor> createState() => _ImageEditorState();
}

class _ImageEditorState extends State<ImageEditor> {
  final _focus = FocusNode(debugLabel: 'Screenshot editor');
  final _textFocus = FocusNode(debugLabel: 'Annotation text');
  final _text = TextEditingController();
  late final _renderer = _EditorRenderer(widget.image);
  late final _sourceBounds = Rect.fromLTWH(
    0,
    0,
    widget.image.width.toDouble(),
    widget.image.height.toDouble(),
  );
  late final _history = [_Document(_sourceBounds)];
  late _Document _saved = _history.first;
  late String _name = widget.initialName;
  final _styles = {for (final tool in _Tool.values) tool: _Style.forTool(tool)};
  final _recent = <Color>[];
  int _revision = 0;
  int? _selected;
  int? _editingText;
  int? _styleGestureRevision;
  _Tool _tool = .move;
  Rect? _crop;
  _CropRatio _cropRatio = .free;
  Offset? _textOrigin;
  double? _textWidth;
  final _cursor = ValueNotifier<Offset?>(null);
  _Drag? _drag;
  _Annotation? _draft;
  DateTime? _lastTextClick;
  int? _lastTextHit;
  bool _busy = false;
  bool _askingToClose = false;
  double? _zoom;
  _View? _pinchView;
  Offset _pan = Offset.zero;

  _Document get _document => _history[_revision];
  _Annotation? get _selection {
    final index = _selected;
    return index == null || index >= _document.objects.length
        ? null
        : _document.objects[index];
  }

  _Tool get _optionsTool => _selection?.tool ?? _tool;
  _Style get _style => _selection?.style ?? _styles[_optionsTool]!;
  bool get _dirty => !identical(_document, _saved);
  bool get _canUndo => _revision > 0;
  bool get _canRedo => _revision < _history.length - 1;
  bool get _typing => _textOrigin != null;

  @override
  void initState() {
    super.initState();
    widget.closeRequests?.addListener(_close);
  }

  @override
  void didUpdateWidget(ImageEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.closeRequests != widget.closeRequests) {
      oldWidget.closeRequests?.removeListener(_close);
      widget.closeRequests?.addListener(_close);
    }
  }

  @override
  void dispose() {
    widget.closeRequests?.removeListener(_close);
    _focus.dispose();
    _textFocus.dispose();
    _text.dispose();
    _cursor.dispose();
    _renderer.dispose();
    super.dispose();
  }

  void _commit(_Document document, {bool coalesce = false}) {
    if (coalesce) {
      _history[_revision] = document;
      return;
    }
    _history.removeRange(_revision + 1, _history.length);
    _history.add(document);
    _revision++;
  }

  void _step(int delta) {
    final next = _revision + delta;
    if (next < 0 || next >= _history.length) return;
    setState(() {
      _revision = next;
      _selected = null;
      if (_crop != null) _crop = _document.crop;
    });
  }

  void _selectTool(_Tool tool) {
    if (_typing) _finishText();
    setState(() {
      _tool = tool;
      _selected = null;
      _draft = null;
      _drag = null;
      _crop = tool == .crop ? _document.crop : null;
      if (tool == .crop) _cropRatio = .free;
    });
    _focus.requestFocus();
  }

  void _changeStyle(_Style style) {
    setState(() {
      _styles[_optionsTool] = style;
      final selected = _selection;
      final baseline = _styleGestureRevision;
      if (selected != null) {
        _replace(
          _selected!,
          selected.copyWith(style: style),
          coalesce: baseline != null && _revision > baseline,
        );
      }
    });
  }

  void _add(_Annotation annotation, {_Style? nextStyle}) {
    final objects = [..._document.objects, annotation];
    _commit(_Document(_document.crop, objects));
    if (nextStyle != null) _styles[annotation.tool] = nextStyle;
  }

  void _replace(int index, _Annotation annotation, {bool coalesce = false}) {
    final objects = _document.objects.toList();
    objects[index] = annotation;
    _commit(_Document(_document.crop, objects), coalesce: coalesce);
  }

  void _remove() {
    if (_selection == null) return;
    setState(() {
      final objects = _document.objects.toList()..removeAt(_selected!);
      _commit(_Document(_document.crop, objects));
      _selected = null;
    });
  }

  void _duplicate() {
    final selection = _selection;
    if (selection == null) return;
    setState(() {
      _add(selection.transform((point) => point + const Offset(12, 12)));
      _selected = _document.objects.length - 1;
    });
  }

  void _resetCounter() {
    setState(() {
      _styles[_Tool.counter] = _styles[_Tool.counter]!.copyWith(number: 1);
    });
  }

  void _changeCropRatio(_CropRatio ratio) {
    setState(() {
      _cropRatio = ratio;
      final crop = _crop!;
      if (ratio.value case final double value) {
        final width = math.min(crop.width, crop.height * value);
        _crop = Rect.fromCenter(
          center: crop.center,
          width: width,
          height: width / value,
        );
      }
    });
  }

  void _applyCrop() {
    final proposed = _crop;
    if (proposed == null) return;
    final crop = Rect.fromLTRB(
      proposed.left.roundToDouble(),
      proposed.top.roundToDouble(),
      proposed.right.roundToDouble(),
      proposed.bottom.roundToDouble(),
    ).intersect(_document.crop);
    if (crop.width < 1 || crop.height < 1) return;
    setState(() {
      if (crop != _document.crop) {
        _commit(_Document(crop, _document.objects));
      }
      _crop = null;
      _tool = .move;
      _zoom = null;
      _pan = Offset.zero;
    });
    _focus.requestFocus();
  }

  Future<void> _chooseColor() async {
    final color = await showCaptureColorPicker(
      context,
      color: _style.color,
      recentColors: _recent,
    );
    if (!mounted || color == null) return;
    _recent.remove(color);
    _recent.insert(0, color);
    if (_recent.length > 5) _recent.removeLast();
    _changeStyle(_style.copyWith(color: color));
  }

  Future<void> _export({required bool copy, bool saveAs = false}) async {
    if (_busy) return;
    if (_typing) _finishText();
    final snapshot = _document;
    setState(() => _busy = true);
    try {
      final png = await _renderer.export(snapshot);
      if (!mounted) return;
      if (copy) {
        await widget.onCopy(png);
        if (mounted) _notify('Screenshot copied to the clipboard');
      } else {
        final savedName = await widget.onSave(png, saveAs: saveAs);
        if (mounted && savedName != null) {
          setState(() {
            _name = savedName.split('/').last;
            _saved = snapshot;
          });
          _notify('Saved $_name');
        }
      }
    } catch (error) {
      if (mounted) _notify('${copy ? 'Copy' : 'Save'} failed. $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _close() async {
    if (_busy || _askingToClose) return;
    if (_typing) _finishText();
    if (!_dirty) {
      widget.onClose();
      return;
    }
    _askingToClose = true;
    try {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved edits?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard == true && mounted) widget.onClose();
    } finally {
      _askingToClose = false;
    }
  }

  void _startText(Offset origin, {int? index}) {
    setState(() {
      _editingText = index;
      _selected = index;
      _textOrigin = origin;
      _textWidth = index == null
          ? math.max(1, _document.crop.right - origin.dx)
          : _document.objects[index].textWidth;
      _text.text = index == null ? '' : _document.objects[index].text;
    });
    _textFocus.requestFocus();
  }

  void _finishText({bool cancel = false}) {
    if (!_typing) return;
    setState(() {
      final text = _text.text;
      if (!cancel && text.trim().isNotEmpty) {
        final annotation = _Annotation(
          .text,
          [_textOrigin!],
          _style,
          text: text,
          textWidth: _textWidth!,
        );
        final editing = _editingText;
        if (editing == null) {
          _add(annotation);
          _selected = _document.objects.length - 1;
        } else if (_document.objects[editing].text != text) {
          _replace(editing, annotation);
        }
      }
      _textOrigin = null;
      _textWidth = null;
      _editingText = null;
      _text.clear();
    });
    _focus.requestFocus();
  }

  void _setZoom(
    _View view,
    double zoom,
    Offset anchor, {
    Offset delta = Offset.zero,
  }) {
    final scale = zoom.clamp(.001, 16.0);
    final imagePoint = view.toImage(anchor);
    final next = _View(
      view.crop,
      view.workspace,
      scale,
      Offset.zero,
      view.devicePixelRatio,
    );
    setState(() {
      _zoom = scale;
      _pan = next.limitPan(anchor + delta - next.toScreen(imagePoint));
    });
  }

  void _fit() => setState(() {
    _zoom = null;
    _pan = Offset.zero;
  });

  void _actualSize(double devicePixelRatio) => setState(() {
    _zoom = 1 / devicePixelRatio;
    _pan = Offset.zero;
  });

  KeyEventResult _onKey(FocusNode node, KeyEvent event, _View view) {
    if (event is KeyUpEvent) return .ignored;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final ctrl = keyboard.isControlPressed;
    final shift = keyboard.isShiftPressed;
    if (_typing) {
      if (key == LogicalKeyboardKey.escape) {
        _finishText(cancel: true);
      } else if (ctrl && key == LogicalKeyboardKey.enter) {
        _finishText();
      } else {
        return .ignored;
      }
      return .handled;
    }
    if (_styleGestureRevision != null) return .ignored;
    if (_drag != null) {
      if (key != LogicalKeyboardKey.escape) return .ignored;
      setState(() {
        final drag = _drag!;
        if (drag.pan != null) _pan = drag.pan!;
        if (drag.rect != null) _crop = drag.rect;
        _drag = null;
        _draft = null;
      });
      return .handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_crop != null) {
        _selectTool(.move);
      } else {
        _close();
      }
    } else if (ctrl) {
      final center = view.size.center(Offset.zero);
      switch (key) {
        case LogicalKeyboardKey.keyZ when !shift:
          _step(-1);
        case LogicalKeyboardKey.keyY when !shift:
          _step(1);
        case LogicalKeyboardKey.keyD:
          _duplicate();
        case LogicalKeyboardKey.keyC:
          _export(copy: true);
        case LogicalKeyboardKey.keyS:
          _export(copy: false, saveAs: shift);
        case LogicalKeyboardKey.equal ||
            LogicalKeyboardKey.add ||
            LogicalKeyboardKey.numpadAdd:
          _setZoom(view, view.scale * 1.25, center);
        case LogicalKeyboardKey.minus || LogicalKeyboardKey.numpadSubtract:
          _setZoom(view, view.scale / 1.25, center);
        case LogicalKeyboardKey.digit0 || LogicalKeyboardKey.numpad0:
          _fit();
        case LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1:
          _actualSize(View.of(context).devicePixelRatio);
        default:
          return .ignored;
      }
    } else if (key == LogicalKeyboardKey.delete) {
      _remove();
    } else if (key == LogicalKeyboardKey.enter && _crop != null) {
      _applyCrop();
    } else if (_crop != null && _cropNudges.containsKey(key)) {
      setState(() {
        _crop = _moveRect(
          _crop!,
          _document.crop,
          _cropNudges[key]! * (shift ? 10 : 1),
        );
      });
    } else if (key == LogicalKeyboardKey.bracketLeft ||
        key == LogicalKeyboardKey.bracketRight) {
      if (_optionsTool.sizes case (final double min, final double max)) {
        final delta = key == LogicalKeyboardKey.bracketLeft ? -1 : 1;
        final size = (_style.size + delta).clamp(min, max);
        if (size != _style.size) _changeStyle(_style.copyWith(size: size));
      }
    } else {
      final preset = _optionsTool.palette;
      final number = int.tryParse(key.keyLabel) ?? 0;
      if (number > 0 && number <= preset.length) {
        _changeStyle(
          _style.copyWith(color: preset.values.elementAt(number - 1)),
        );
      } else {
        final tools = _Tool.values.where(
          (tool) => tool.shortcut == key.keyLabel,
        );
        if (tools.isEmpty || keyboard.isAltPressed || keyboard.isMetaPressed) {
          return .ignored;
        }
        _selectTool(tools.first);
      }
    }
    return .handled;
  }

  int? _hit(Offset point, double tolerance, {_Tool? tool}) {
    final objects = _document.objects;
    for (var i = objects.length - 1; i >= 0; i--) {
      if ((tool == null || objects[i].tool == tool) &&
          objects[i].hits(point, tolerance)) {
        return i;
      }
    }
    return null;
  }

  void _pointerDown(PointerDownEvent event, _View view) {
    if (_drag != null) return;
    final screen = event.localPosition;
    final point = view.toImage(screen);
    if (event.buttons == kMiddleMouseButton ||
        (event.buttons == kPrimaryButton &&
            HardwareKeyboard.instance.isLogicalKeyPressed(
              LogicalKeyboardKey.space,
            ))) {
      _drag = _Drag(event.pointer, screen, pan: view.pan);
      return;
    }
    if (event.buttons != kPrimaryButton) return;
    if (_typing) _finishText();
    _focus.requestFocus();
    final tolerance = 9 / view.scale;
    if (_tool == .crop) {
      if (!_document.crop.inflate(tolerance).contains(point)) return;
      final crop = _crop!;
      final handle = _nearestHandle(crop, point, tolerance);
      final start = _clampPoint(point, _document.crop);
      _drag = _Drag(
        event.pointer,
        start,
        rect: crop,
        handle: handle,
        createCrop:
            handle == null && (crop == _document.crop || !crop.contains(point)),
      );
      return;
    }
    if (!_document.crop.contains(point)) return;
    setState(() {
      final selection = _selection;
      final handle = selection == null
          ? null
          : _nearestHandle(selection.bounds, point, tolerance);
      if (handle != null) {
        _drag = _Drag(event.pointer, point, object: selection, handle: handle);
        return;
      }
      switch (_tool) {
        case .move:
          _selected = _hit(point, tolerance);
          if (_selection case final _Annotation selected) {
            _drag = _Drag(event.pointer, point, object: selected);
          } else {
            _drag = _Drag(event.pointer, screen, pan: view.pan);
          }
        case .text:
          final hit = _hit(point, tolerance, tool: .text);
          final now = DateTime.now();
          if (hit == null) {
            _startText(point);
          } else if (hit == _lastTextHit &&
              _lastTextClick != null &&
              now.difference(_lastTextClick!) <
                  const Duration(milliseconds: 400)) {
            _startText(_document.objects[hit].points.first, index: hit);
            _lastTextHit = null;
            _lastTextClick = null;
          } else {
            _selected = hit;
            _lastTextHit = hit;
            _lastTextClick = now;
          }
        case .counter:
          _selected = null;
          final style = _style;
          _add(
            _Annotation(.counter, [point], style),
            nextStyle: style.copyWith(number: style.number + 1),
          );
        default:
          _selected = null;
          final points = [point, point];
          _drag = _Drag(event.pointer, point, points: points);
          _draft = _Annotation(_tool, points, _style);
      }
    });
  }

  void _pointerMove(PointerMoveEvent event, _View view) {
    final screen = event.localPosition;
    _cursor.value = screen;
    final drag = _drag;
    if (drag == null || drag.pointer != event.pointer) return;
    if (drag.pan case final Offset pan) {
      setState(() => _pan = view.limitPan(pan + screen - drag.origin));
      return;
    }
    final point = _clampPoint(view.toImage(screen), _document.crop);
    final delta = point - drag.origin;
    final constrain = HardwareKeyboard.instance.isShiftPressed;
    setState(() {
      if (drag.rect case final Rect crop) {
        final ratio =
            _cropRatio.value ?? (constrain ? crop.width / crop.height : null);
        final bounds = _document.crop;
        if (drag.createCrop) {
          final next = _resizeFrom(drag.origin, point, bounds, ratio: ratio);
          if (next.width >= 1 && next.height >= 1) _crop = next;
        } else if (drag.handle case final Alignment handle) {
          _crop = _resizeCrop(crop, bounds, delta, handle, ratio: ratio);
        } else {
          _crop = _moveRect(crop, bounds, delta);
        }
      } else if (drag.object case final _Annotation object) {
        _draft = drag.handle == null
            ? object.transform((point) => point + delta)
            : object.resize(drag.handle!, delta, constrain);
      } else {
        final points = drag.points!;
        if (_tool.freehand || (_tool == .mosaic && _style.brush)) {
          if ((point - points.last).distance >= .5) points.add(point);
        } else {
          points[1] = constrain
              ? _constrainEnd(drag.origin, point, line: _tool.isLine)
              : point;
        }
        _draft = _Annotation(_tool, points, _style);
      }
    });
  }

  void _pointerEnd(PointerEvent event, {bool cancel = false}) {
    final drag = _drag;
    if (drag == null || drag.pointer != event.pointer) return;
    setState(() {
      final draft = _draft;
      _drag = null;
      _draft = null;
      if (cancel) {
        if (drag.pan != null) _pan = drag.pan!;
        if (drag.rect != null) _crop = drag.rect;
        return;
      }
      if (draft == null || !draft.isDrawable) return;
      if (drag.object != null && _selected != null) {
        _replace(_selected!, draft);
      } else {
        _add(draft);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth,
          math.max(1, constraints.maxHeight - 100),
        );
        final view = _View(
          _document.crop,
          size,
          _zoom,
          _pan,
          View.of(context).devicePixelRatio,
        );
        return Focus(
          autofocus: true,
          focusNode: _focus,
          onKeyEvent: (node, event) => _onKey(node, event, view),
          child: Column(
            children: [
              _EditorAppBar(editor: this, view: view),
              Expanded(child: _buildWorkspace(view)),
              _EditorStatus(editor: this, view: view),
            ],
          ),
        );
      },
    ),
  );

  Widget _buildWorkspace(_View view) {
    final colors = Theme.of(context).colorScheme;
    final brush = _tool.hasBrushCursor;
    final visibleImage = view.visibleImage;
    final overflow = view.overflow;
    return Stack(
      fit: .expand,
      children: [
        Positioned.fromRect(
          rect: Offset.zero & view.size,
          child: _canvas(view, colors, brush, visibleImage),
        ),
        if (_textOrigin case final Offset origin when !visibleImage.isEmpty)
          _textField(view, origin),
        Positioned(
          top: 12,
          bottom: 12 + (overflow.dx > 0 ? _scrollbarExtent : 0),
          left: 16,
          child: Center(child: _ToolRail(editor: this)),
        ),
        if (_optionsTool != .move)
          Positioned(
            top: 16,
            left: 84,
            right: view.size.width >= 950 ? 84 : 12,
            child: Align(
              child: TextFieldTapRegion(child: _ToolOptions(editor: this)),
            ),
          ),
        if (overflow.dx > 0)
          Positioned(
            left: 4,
            width: math.max(0, view.size.width - 8),
            bottom: 0,
            height: _scrollbarExtent,
            child: _CanvasScrollbar(
              axis: .horizontal,
              viewport: view.size.width,
              overflow: overflow.dx,
              offset: overflow.dx / 2 - view.pan.dx,
              onScroll: (offset) => setState(() {
                _pan = Offset(overflow.dx / 2 - offset, view.pan.dy);
              }),
            ),
          ),
        if (overflow.dy > 0)
          Positioned(
            top: 4,
            height: math.max(0, view.size.height - 8),
            right: 0,
            width: _scrollbarExtent,
            child: _CanvasScrollbar(
              axis: .vertical,
              viewport: view.size.height,
              overflow: overflow.dy,
              offset: overflow.dy / 2 - view.pan.dy,
              onScroll: (offset) => setState(() {
                _pan = Offset(view.pan.dx, overflow.dy / 2 - offset);
              }),
            ),
          ),
      ],
    );
  }

  Widget _canvas(
    _View view,
    ColorScheme colors,
    bool brush,
    Rect visibleImage,
  ) => MouseRegion(
    cursor: switch (_tool) {
      .move => SystemMouseCursors.basic,
      .text => SystemMouseCursors.text,
      _ when brush => SystemMouseCursors.basic,
      _ => SystemMouseCursors.precise,
    },
    onEnter: (event) => _cursor.value = event.localPosition,
    onHover: (event) => _cursor.value = event.localPosition,
    onExit: (_) => _cursor.value = null,
    child: Listener(
      behavior: .opaque,
      onPointerDown: (event) => _pointerDown(event, view),
      onPointerMove: (event) => _pointerMove(event, view),
      onPointerUp: _pointerEnd,
      onPointerCancel: (event) => _pointerEnd(event, cancel: true),
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            event.scrollDelta.dy != 0 &&
            (_tool == .move || HardwareKeyboard.instance.isControlPressed)) {
          GestureBinding.instance.pointerSignalResolver.register(event, (_) {
            _setZoom(
              view,
              view.scale * math.exp(-event.scrollDelta.dy / 420),
              event.localPosition,
            );
          });
        }
      },
      onPointerPanZoomStart: (_) => _pinchView = view,
      onPointerPanZoomUpdate: (event) {
        final start = _pinchView;
        if (start != null) {
          _setZoom(
            start,
            start.scale * event.scale,
            event.localPosition,
            delta: event.pan,
          );
        }
      },
      onPointerPanZoomEnd: (_) => _pinchView = null,
      child: Stack(
        fit: .expand,
        children: [
          CustomPaint(
            painter: _EditorPainter(
              renderer: _renderer,
              view: view,
              document: _document,
              colors: colors,
              draft: _draft,
              replacing: _drag?.object != null ? _selected : _editingText,
              selection: _typing
                  ? null
                  : (_drag?.object != null ? _draft : _selection),
              crop: _crop,
            ),
          ),
          if (brush && !visibleImage.isEmpty)
            Positioned.fromRect(
              rect: visibleImage,
              child: const MouseRegion(cursor: SystemMouseCursors.none),
            ),
          if (brush && (_draft == null || (_tool == .mosaic && !_style.brush)))
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _BrushCursor(
                      _cursor,
                      view,
                      _renderer,
                      _tool,
                      _styles[_tool]!,
                      colors.onSurface,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _textField(_View view, Offset origin) {
    final visible = view.visibleImage;
    final start = view.toScreen(origin) - visible.topLeft;
    const cursorWidth = 2.0;
    return Positioned.fromRect(
      rect: visible,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: start.dx,
              top: start.dy,
              // RenderEditable reserves the cursor width and a one-pixel gap.
              width: _textWidth! + cursorWidth + 1,
              child: Transform.scale(
                alignment: .topLeft,
                scale: view.scale,
                child: MediaQuery.withNoTextScaling(
                  child: Semantics(
                    label: 'Annotation text',
                    child: CallbackShortcuts(
                      bindings: {
                        const SingleActivator(.enter, control: true):
                            _finishText,
                        const SingleActivator(.escape): () =>
                            _finishText(cancel: true),
                      },
                      child: TextField(
                        focusNode: _textFocus,
                        autofocus: true,
                        controller: _text,
                        style: _style.textStyle,
                        strutStyle: .disabled,
                        textDirection: .ltr,
                        minLines: 1,
                        maxLines: null,
                        cursorWidth: cursorWidth,
                        keyboardType: .multiline,
                        decoration: null,
                        onTapOutside: (_) => _finishText(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
