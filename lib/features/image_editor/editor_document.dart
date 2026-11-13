part of 'image_editor.dart';

enum _Tool {
  move(
    'Move / select',
    'V',
    .move,
    'Drag to pan, scroll to zoom, or select an object',
  ),
  pen('Pen', 'P', .pen, 'Drag to draw a stroke'),
  highlighter('Highlighter', 'H', .highlighter, 'Drag to highlight'),
  mosaic('Mosaic', 'M', .mosaic, 'Drag to obscure part of the image'),
  rectangle('Rectangle', 'R', .rectangle, 'Drag to draw a rectangle'),
  ellipse('Ellipse', 'O', .ellipse, 'Drag to draw an ellipse'),
  line('Line', 'L', .line, 'Drag to draw a line'),
  arrow('Arrow', 'A', .arrow, 'Drag to draw an arrow'),
  counter('Counter', 'N', .counter, 'Click to place the next marker'),
  text(
    'Text',
    'T',
    .text,
    'Click to place, double-click to edit, Ctrl+Enter to finish',
  ),
  crop('Crop', 'C', .crop, 'Drag the selection handles, then apply the crop');

  const _Tool(this.label, this.shortcut, this.icon, this.hint);

  final String label;
  final String shortcut;
  final CaptureSymbol icon;
  final String hint;

  bool get isLine => this == .line || this == .arrow;
  bool get isShape => this == .rectangle || this == .ellipse;
  bool get freehand => this == .pen || this == .highlighter;
  bool get hasBrushCursor => freehand || this == .mosaic;

  (double, double)? get sizes => switch (this) {
    .pen || .rectangle || .ellipse || .line || .arrow => (1, 12),
    .highlighter => (6, 40),
    .mosaic => (4, 32),
    .counter => (16, 56),
    .text => (10, 72),
    _ => null,
  };

  Map<String, Color> get palette => switch (this) {
    .move || .crop || .mosaic => const {},
    .highlighter => const {
      'Yellow': Color(0xffffeb3b),
      'Green': Color(0xff4caf50),
      'Blue': Color(0xff2196f3),
      'Orange': Color(0xffff9800),
      'Purple': Color(0xff9c27b0),
    },
    _ => const {
      'Red': Color(0xfff44336),
      'Orange': Color(0xffff9800),
      'Yellow': Color(0xffffeb3b),
      'Green': Color(0xff4caf50),
      'Blue': Color(0xff2196f3),
      'Purple': Color(0xff9c27b0),
      'Black': Color(0xff121212),
      'White': Colors.white,
    },
  };
}

enum _Mosaic { pixelate, blur }

enum _LineEnds { line, arrow, double }

const _highlighterOpacity = .38;

enum _CropRatio {
  free('Free', null),
  square('1:1', 1),
  standard('4:3', 4 / 3),
  wide('16:9', 16 / 9);

  const _CropRatio(this.label, this.value);
  final String label;
  final double? value;
}

class _Style {
  const _Style({
    required this.color,
    required this.size,
    this.number = 1,
    this.fill = false,
    this.brush = false,
    this.mosaic = .pixelate,
    this.ends = .line,
    this.font = 'Inter',
    this.bold = true,
    this.italic = false,
    this.underline = false,
  });

  factory _Style.forTool(_Tool tool) => _Style(
    color: tool.palette.values.firstOrNull ?? Colors.black,
    size: switch (tool) {
      .highlighter => 18,
      .mosaic => 12,
      .rectangle || .ellipse => 3,
      .counter => 28,
      .text => 22,
      _ => 4,
    },
    brush: tool == .mosaic,
    ends: tool == .arrow ? .arrow : .line,
  );

  final Color color;
  final double size;
  final int number;
  final bool fill;
  final bool brush;
  final _Mosaic mosaic;
  final _LineEnds ends;
  final String font;
  final bool bold;
  final bool italic;
  final bool underline;

  TextStyle get textStyle => TextStyle(
    inherit: false,
    color: color,
    fontFamily: font,
    fontSize: size,
    textBaseline: .alphabetic,
    fontWeight: bold ? .w700 : .w400,
    fontStyle: italic ? .italic : .normal,
    decoration: underline ? .underline : .none,
  );

  _Style copyWith({
    Color? color,
    double? size,
    int? number,
    bool? fill,
    bool? brush,
    _Mosaic? mosaic,
    _LineEnds? ends,
    String? font,
    bool? bold,
    bool? italic,
    bool? underline,
  }) => _Style(
    color: color ?? this.color,
    size: size ?? this.size,
    number: number ?? this.number,
    fill: fill ?? this.fill,
    brush: brush ?? this.brush,
    mosaic: mosaic ?? this.mosaic,
    ends: ends ?? this.ends,
    font: font ?? this.font,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
  );
}

class _Annotation {
  _Annotation(
    this.tool,
    List<Offset> points,
    this.style, {
    this.text = '',
    this.textWidth = double.infinity,
  }) : points = List.unmodifiable(points);

  final _Tool tool;
  final List<Offset> points;
  final _Style style;
  final String text;
  final double textWidth;

  _Annotation copyWith({_Style? style, List<Offset>? points}) => _Annotation(
    tool,
    points ?? this.points,
    style ?? this.style,
    text: text,
    textWidth: textWidth,
  );

  TextPainter _layoutText() =>
      _textPainter(text, style.textStyle, maxWidth: textWidth);

  _Annotation transform(Offset Function(Offset) apply) =>
      copyWith(points: points.map(apply).toList());

  _Annotation resize(Alignment handle, Offset delta, bool constrain) {
    final frame = bounds;
    final opposite = Alignment(-handle.x, -handle.y);
    final sx = frame.width > 0
        ? (1 + delta.dx * handle.x / frame.width).clamp(.05, 50.0)
        : 1.0;
    final sy = frame.height > 0
        ? (1 + delta.dy * handle.y / frame.height).clamp(.05, 50.0)
        : 1.0;
    final scale = switch ((handle.x, handle.y)) {
      (0, _) => sy,
      (_, 0) => sx,
      _ => math.min(sx, sy),
    };
    if (tool == .text || tool == .counter) {
      final (min, max) = tool.sizes!;
      final factor = (sx - 1).abs() >= (sy - 1).abs() ? sx : sy;
      final adjusted = copyWith(
        style: style.copyWith(size: (style.size * factor).clamp(min, max)),
      );
      final shift =
          opposite.withinRect(frame) - opposite.withinRect(adjusted.bounds);
      return adjusted.transform((point) => point + shift);
    }
    final anchor = opposite.withinRect(frame);
    return transform(
      (point) => Offset(
        anchor.dx + (point.dx - anchor.dx) * (constrain ? scale : sx),
        anchor.dy + (point.dy - anchor.dy) * (constrain ? scale : sy),
      ),
    );
  }

  Rect get bounds {
    final first = points.first;
    if (tool == .text) {
      final painter = _layoutText();
      final rect = first & painter.size;
      painter.dispose();
      return rect;
    }
    if (tool == .counter) {
      return Rect.fromCenter(
        center: first,
        width: style.size,
        height: style.size,
      );
    }
    var left = first.dx;
    var top = first.dy;
    var right = first.dx;
    var bottom = first.dy;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      top = math.min(top, point.dy);
      right = math.max(right, point.dx);
      bottom = math.max(bottom, point.dy);
    }
    final padding =
        tool.freehand || tool.isLine || (tool == .mosaic && style.brush)
        ? style.size / 2
        : 0.0;
    return Rect.fromLTRB(left, top, right, bottom).inflate(padding);
  }

  bool get isDrawable => switch (tool) {
    .rectangle || .ellipse || .mosaic when tool != .mosaic || !style.brush =>
      (points.first.dx - points.last.dx).abs() >= 1 &&
          (points.first.dy - points.last.dy).abs() >= 1,
    .line || .arrow => (points.first - points.last).distance >= 1,
    _ => true,
  };

  bool hits(Offset point, double tolerance) {
    if (!bounds.inflate(tolerance).contains(point)) return false;
    if (tool.freehand || tool.isLine || (tool == .mosaic && style.brush)) {
      for (var i = 1; i < points.length; i++) {
        final start = points[i - 1];
        final segment = points[i] - start;
        final distance = segment.distanceSquared;
        final difference = point - start;
        final t = distance == 0
            ? 0.0
            : ((difference.dx * segment.dx + difference.dy * segment.dy) /
                      distance)
                  .clamp(0.0, 1.0);
        if ((difference - segment * t).distance <= tolerance + style.size / 2) {
          return true;
        }
      }
      return false;
    }
    return true;
  }
}

TextPainter _textPainter(
  String text,
  TextStyle style, {
  double maxWidth = double.infinity,
}) => TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: .ltr,
)..layout(maxWidth: maxWidth);

class _Document {
  const _Document(this.crop, [this.objects = const []]);

  final Rect crop;
  final List<_Annotation> objects;
}

class _View {
  _View(
    this.crop,
    this.workspace,
    double? zoom,
    this.requestedPan,
    this.devicePixelRatio,
  ) : scale =
          zoom ??
          math
              .min(
                math.max(1, workspace.width - 156) / crop.width,
                math.max(1, workspace.height - 144) / crop.height,
              )
              .clamp(.001, 1 / devicePixelRatio) {
    final image = crop.size * scale;
    final needsHorizontal = image.width > workspace.width;
    final needsVertical = image.height > workspace.height;
    final horizontal =
        needsHorizontal ||
        (needsVertical && image.width > workspace.width - _scrollbarExtent);
    final vertical =
        needsVertical ||
        (needsHorizontal && image.height > workspace.height - _scrollbarExtent);
    size = Size(
      math.max(1, workspace.width - (vertical ? _scrollbarExtent : 0)),
      math.max(1, workspace.height - (horizontal ? _scrollbarExtent : 0)),
    );
  }

  final Rect crop;
  late final Size size;
  final double scale;
  final Size workspace;
  final Offset requestedPan;
  final double devicePixelRatio;
  Offset get overflow => Offset(
    crop.width * scale - size.width,
    crop.height * scale - size.height,
  );

  Offset limitPan(Offset requested) {
    final limit = Offset(overflow.dx.abs(), overflow.dy.abs()) / 2;
    return _clampPoint(requested, Rect.fromPoints(-limit, limit));
  }

  Offset get pan => limitPan(requestedPan);
  Offset get origin => size.center(Offset.zero) + pan - crop.center * scale;
  Rect get visibleImage => (toScreen(crop.topLeft) & (crop.size * scale))
      .intersect(Offset.zero & size);
  Offset toImage(Offset point) => (point - origin) / scale;
  Offset toScreen(Offset point) => point * scale + origin;
}

class _Drag {
  const _Drag(
    this.pointer,
    this.origin, {
    this.pan,
    this.rect,
    this.handle,
    this.createCrop = false,
    this.object,
    this.points,
  });

  final int pointer;
  final Offset origin;
  final Offset? pan;
  final Rect? rect;
  final Alignment? handle;
  final bool createCrop;
  final _Annotation? object;
  final List<Offset>? points;
}

final _cropNudges = {
  LogicalKeyboardKey.arrowLeft: Offset(-1, 0),
  LogicalKeyboardKey.arrowRight: Offset(1, 0),
  LogicalKeyboardKey.arrowUp: Offset(0, -1),
  LogicalKeyboardKey.arrowDown: Offset(0, 1),
};

const _handles = [
  Alignment.topLeft,
  Alignment.topRight,
  Alignment.bottomLeft,
  Alignment.bottomRight,
  Alignment.topCenter,
  Alignment.centerLeft,
  Alignment.centerRight,
  Alignment.bottomCenter,
];

Alignment? _nearestHandle(Rect rect, Offset point, double tolerance) {
  Alignment? result;
  var nearest = tolerance;
  for (final handle in _handles) {
    final distance = (handle.withinRect(rect) - point).distance;
    if (distance < nearest) {
      nearest = distance;
      result = handle;
    }
  }
  return result;
}

Offset _clampPoint(Offset point, Rect bounds) => Offset(
  point.dx.clamp(bounds.left, bounds.right),
  point.dy.clamp(bounds.top, bounds.bottom),
);

Rect _moveRect(Rect rect, Rect bounds, Offset delta) => rect.shift(
  Offset(
    delta.dx.clamp(bounds.left - rect.left, bounds.right - rect.right),
    delta.dy.clamp(bounds.top - rect.top, bounds.bottom - rect.bottom),
  ),
);

Offset _constrainEnd(Offset origin, Offset point, {required bool line}) {
  final delta = point - origin;
  if (line) {
    const step = math.pi / 4;
    final direction = (delta.direction / step).round() * step;
    return origin + Offset.fromDirection(direction, delta.distance);
  }
  final side = math.min(delta.dx.abs(), delta.dy.abs());
  return origin + Offset(side * delta.dx.sign, side * delta.dy.sign);
}

Rect _resizeFrom(Offset anchor, Offset point, Rect bounds, {double? ratio}) {
  final end = _clampPoint(point, bounds);
  final delta = end - anchor;
  if (ratio == null || delta.dx == 0 || delta.dy == 0) {
    return Rect.fromPoints(anchor, end);
  }
  final width = math.min(delta.dx.abs(), delta.dy.abs() * ratio);
  return Rect.fromPoints(
    anchor,
    anchor + Offset(width * delta.dx.sign, width / ratio * delta.dy.sign),
  );
}

Rect _resizeCrop(
  Rect crop,
  Rect bounds,
  Offset delta,
  Alignment handle, {
  double? ratio,
}) {
  if (ratio != null && handle.x != 0 && handle.y != 0) {
    final anchor = Alignment(-handle.x, -handle.y).withinRect(crop);
    final target = handle.withinRect(crop) + delta;
    final constrained = Offset(
      handle.x < 0
          ? math.min(target.dx, anchor.dx - 1)
          : math.max(target.dx, anchor.dx + 1),
      handle.y < 0
          ? math.min(target.dy, anchor.dy - 1)
          : math.max(target.dy, anchor.dy + 1),
    );
    return _resizeFrom(anchor, constrained, bounds, ratio: ratio);
  }
  final rect = Rect.fromLTRB(
    handle.x < 0
        ? (crop.left + delta.dx).clamp(bounds.left, crop.right - 1)
        : crop.left,
    handle.y < 0
        ? (crop.top + delta.dy).clamp(bounds.top, crop.bottom - 1)
        : crop.top,
    handle.x > 0
        ? (crop.right + delta.dx).clamp(crop.left + 1, bounds.right)
        : crop.right,
    handle.y > 0
        ? (crop.bottom + delta.dy).clamp(crop.top + 1, bounds.bottom)
        : crop.bottom,
  );
  if (ratio == null) return rect;
  if (handle.x != 0) {
    final heightLimit =
        2 *
        math.min(crop.center.dy - bounds.top, bounds.bottom - crop.center.dy);
    final width = math.min(rect.width, heightLimit * ratio);
    final center = Offset(
      handle.x < 0 ? crop.right - width / 2 : crop.left + width / 2,
      crop.center.dy,
    );
    return Rect.fromCenter(center: center, width: width, height: width / ratio);
  }
  final widthLimit =
      2 * math.min(crop.center.dx - bounds.left, bounds.right - crop.center.dx);
  final height = math.min(rect.height, widthLimit / ratio);
  final center = Offset(
    crop.center.dx,
    handle.y < 0 ? crop.bottom - height / 2 : crop.top + height / 2,
  );
  return Rect.fromCenter(center: center, width: height * ratio, height: height);
}

class _EditorRenderer {
  _EditorRenderer(this.image);

  final ui.Image image;
  final _pixelated = <int, ui.Image>{};
  Rect get _bounds =>
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  void dispose() {
    for (final image in _pixelated.values) {
      image.dispose();
    }
  }

  Future<Uint8List> export(_Document document) async {
    final crop = document.crop;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..translate(-crop.left, -crop.top);
    paint(canvas, document);
    final picture = recorder.endRecording();
    try {
      final exported = await picture.toImage(
        crop.width.round(),
        crop.height.round(),
      );
      try {
        final bytes = await exported.toByteData(format: .png);
        if (bytes == null) throw StateError('Could not encode PNG');
        return bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      } finally {
        exported.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  void paint(
    Canvas canvas,
    _Document document, {
    _Annotation? draft,
    int? replacing,
  }) {
    canvas.save();
    canvas.clipRect(document.crop, doAntiAlias: false);
    canvas.drawImage(image, Offset.zero, Paint());
    for (final (index, object) in document.objects.indexed) {
      if (index == replacing) {
        if (draft != null) _paintObject(canvas, draft);
      } else {
        _paintObject(canvas, object);
      }
    }
    if (draft != null && replacing == null) _paintObject(canvas, draft);
    canvas.restore();
  }

  void _paintObject(Canvas canvas, _Annotation object) {
    if (!object.isDrawable) return;
    final style = object.style;
    final paint = Paint()
      ..color = style.color
      ..strokeWidth = style.size
      ..style = style.fill ? .fill : .stroke
      ..strokeCap = .round
      ..strokeJoin = .round;
    final start = object.points.first;
    final end = object.points.last;
    switch (object.tool) {
      case .pen || .highlighter:
        if (object.tool == .highlighter) {
          paint.color = style.color.withValues(alpha: _highlighterOpacity);
        }
        _stroke(canvas, object.points, paint);
      case .rectangle:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromPoints(start, end),
            const Radius.circular(4),
          ),
          paint,
        );
      case .ellipse:
        canvas.drawOval(Rect.fromPoints(start, end), paint);
      case .line || .arrow:
        canvas.drawLine(start, end, paint);
        if (style.ends != .line) _arrowhead(canvas, start, end, paint);
        if (style.ends == .double) _arrowhead(canvas, end, start, paint);
      case .counter:
        final radius = style.size / 2;
        canvas.drawCircle(start, radius, Paint()..color = style.color);
        canvas.drawCircle(
          start,
          radius - 1,
          Paint()
            ..color = Colors.white
            ..style = .stroke
            ..strokeWidth = 2,
        );
        final text = _textPainter(
          '${style.number}',
          TextStyle(
            fontFamily: 'Inter',
            color: style.color.computeLuminance() < .25
                ? Colors.white
                : Colors.black,
            fontSize: style.size * (style.number >= 100 ? .37 : .5),
            fontWeight: .w700,
          ),
          maxWidth: style.size - 3,
        );
        text.paint(canvas, start - text.size.center(Offset.zero));
        text.dispose();
      case .text:
        final text = object._layoutText();
        text.paint(canvas, start);
        text.dispose();
      case .mosaic:
        _mosaic(canvas, object);
      case .move || .crop:
        break;
    }
  }

  void _mosaic(Canvas canvas, _Annotation object) {
    final style = object.style;
    final brush = style.brush;
    final mask = brush
        ? object.bounds
        : Rect.fromPoints(object.points.first, object.points.last);
    canvas.save();
    canvas.clipRect(mask, doAntiAlias: false);
    if (brush) canvas.clipPath(_brushMask(object.points, style.size));
    switch (style.mosaic) {
      case .pixelate:
        final block = style.size.round();
        final reduced = _pixelated.putIfAbsent(block, () {
          final width = (image.width / block).ceil();
          final height = (image.height / block).ceil();
          final recorder = ui.PictureRecorder();
          Canvas(recorder)
            ..clipRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()))
            ..drawImageRect(
              image,
              _bounds,
              Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
              Paint()..filterQuality = .none,
            );
          final picture = recorder.endRecording();
          try {
            return picture.toImageSync(width, height);
          } finally {
            picture.dispose();
          }
        });
        canvas.drawImageRect(
          reduced,
          Rect.fromLTWH(
            0,
            0,
            reduced.width.toDouble(),
            reduced.height.toDouble(),
          ),
          _bounds,
          Paint()..filterQuality = .none,
        );
      case .blur:
        canvas.drawImage(
          image,
          Offset.zero,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: style.size / 2,
              sigmaY: style.size / 2,
              tileMode: .clamp,
            ),
        );
    }
    canvas.restore();
  }

  Path _brushMask(List<Offset> points, double width) {
    final radius = width / 2;
    final path = Path()
      ..addOval(Rect.fromCircle(center: points.first, radius: radius));
    for (var i = 1; i < points.length; i++) {
      final from = points[i - 1];
      final to = points[i];
      final delta = to - from;
      if (delta == Offset.zero) continue;
      final normal = Offset(-delta.dy, delta.dx) * (radius / delta.distance);
      path
        ..addPolygon([
          from - normal,
          to - normal,
          to + normal,
          from + normal,
        ], true)
        ..addOval(Rect.fromCircle(center: to, radius: radius));
    }
    return path;
  }

  void _stroke(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length <= 2 && points.first == points.last) {
      paint.style = .fill;
      canvas.drawCircle(points.first, paint.strokeWidth / 2, paint);
      return;
    }
    canvas.drawPath(Path()..addPolygon(points, false), paint);
  }

  void _arrowhead(Canvas canvas, Offset from, Offset to, Paint paint) {
    final angle = (to - from).direction;
    final length = math.min(
      (to - from).distance * .45,
      math.max(10, paint.strokeWidth * 3),
    );
    final path = Path()
      ..moveTo(
        to.dx + math.cos(angle + math.pi * .8) * length,
        to.dy + math.sin(angle + math.pi * .8) * length,
      )
      ..lineTo(to.dx, to.dy)
      ..lineTo(
        to.dx + math.cos(angle - math.pi * .8) * length,
        to.dy + math.sin(angle - math.pi * .8) * length,
      );
    canvas.drawPath(path, paint);
  }
}

class _EditorPainter extends CustomPainter {
  const _EditorPainter({
    required this.renderer,
    required this.view,
    required this.document,
    required this.colors,
    this.draft,
    this.replacing,
    this.selection,
    this.crop,
  });

  final _EditorRenderer renderer;
  final _View view;
  final _Document document;
  final ColorScheme colors;
  final _Annotation? draft;
  final int? replacing;
  final _Annotation? selection;
  final Rect? crop;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(view.origin.dx, view.origin.dy);
    canvas.scale(view.scale);
    canvas.drawRect(
      document.crop.shift(Offset(0, 6 / view.scale)),
      Paint()
        ..color = Colors.black54
        ..maskFilter = MaskFilter.blur(.normal, 16 / view.scale),
    );
    renderer.paint(canvas, document, draft: draft, replacing: replacing);
    if (crop case final Rect region) {
      canvas.drawPath(
        Path()
          ..fillType = .evenOdd
          ..addRect(document.crop)
          ..addRect(region),
        Paint()..color = Colors.black54,
      );
      _outline(canvas, region);
    } else if (selection case final _Annotation object) {
      _outline(canvas, object.bounds);
    }
    canvas.restore();
  }

  void _outline(Canvas canvas, Rect rect) {
    final px = 1 / view.scale;
    canvas.drawRect(
      rect,
      Paint()
        ..color = colors.primary
        ..strokeWidth = 2 * px
        ..style = .stroke,
    );
    for (final handle in _handles) {
      final at = handle.withinRect(rect);
      final size = switch ((handle.x, handle.y)) {
        (0, _) => Size(22 * px, 6 * px),
        (_, 0) => Size(6 * px, 22 * px),
        _ => Size.square(11 * px),
      };
      final mark = RRect.fromRectAndRadius(
        Rect.fromCenter(center: at, width: size.width, height: size.height),
        Radius.circular(size.shortestSide / 2),
      );
      canvas.drawRRect(mark, Paint()..color = colors.primary);
      canvas.drawRRect(
        mark,
        Paint()
          ..color = colors.surfaceContainerLowest
          ..style = .stroke
          ..strokeWidth = 1.5 * px,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EditorPainter oldDelegate) =>
      document != oldDelegate.document ||
      view.origin != oldDelegate.view.origin ||
      view.scale != oldDelegate.view.scale ||
      draft != oldDelegate.draft ||
      replacing != oldDelegate.replacing ||
      selection != oldDelegate.selection ||
      crop != oldDelegate.crop ||
      colors != oldDelegate.colors;
}
