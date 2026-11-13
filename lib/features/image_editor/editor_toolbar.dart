part of 'image_editor.dart';

class _EditorAppBar extends StatelessWidget {
  const _EditorAppBar({required this.editor, required this.view});

  final _ImageEditorState editor;
  final _View view;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final zoom = (view.scale * View.of(context).devicePixelRatio * 100).round();
    return Material(
      color: colors.surfaceContainer,
      child: SizedBox(
        height: 64,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1024;
            final tiny = constraints.maxWidth < 540;
            final title = _WindowDrag(
              onMove: editor.widget.onMoveWindow,
              child: tiny
                  ? const CaptureAppIcon()
                  : _EditorTitle(
                      name: editor._name,
                      size: editor._document.crop.size,
                      edited: editor._dirty,
                    ),
            );
            return Padding(
              padding: const .symmetric(horizontal: 12),
              child: Row(
                spacing: compact ? 2 : 8,
                children: [
                  if (tiny)
                    title
                  else if (compact)
                    Expanded(child: title)
                  else
                    SizedBox(width: 298, child: title),
                  if (!compact)
                    Expanded(
                      child: _WindowDrag(onMove: editor.widget.onMoveWindow),
                    ),
                  if (!tiny)
                    Material(
                      color: colors.surfaceContainerHighest,
                      borderRadius: .circular(20),
                      child: Row(
                        children: [
                          CaptureIconButton(
                            icon: .zoomOut,
                            label: 'Zoom out',
                            shortcut: 'Ctrl+-',
                            onPressed: () => editor._setZoom(
                              view,
                              view.scale / 1.25,
                              view.size.center(Offset.zero),
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              '$zoom%',
                              textAlign: .center,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          CaptureIconButton(
                            icon: .zoomIn,
                            label: 'Zoom in',
                            shortcut: 'Ctrl++',
                            onPressed: () => editor._setZoom(
                              view,
                              view.scale * 1.25,
                              view.size.center(Offset.zero),
                            ),
                          ),
                          CaptureIconButton(
                            icon: .fitScreen,
                            label: 'Fit to window',
                            shortcut: 'Ctrl+0',
                            onPressed: editor._fit,
                          ),
                        ],
                      ),
                    ),
                  if (!compact)
                    Expanded(
                      child: _WindowDrag(onMove: editor.widget.onMoveWindow),
                    ),
                  CaptureIconButton(
                    icon: .undo,
                    label: 'Undo',
                    shortcut: 'Ctrl+Z',
                    onPressed: editor._canUndo ? () => editor._step(-1) : null,
                  ),
                  CaptureIconButton(
                    icon: .redo,
                    label: 'Redo',
                    shortcut: 'Ctrl+Y',
                    onPressed: editor._canRedo ? () => editor._step(1) : null,
                  ),
                  if (!tiny) const CaptureDivider(),
                  if (compact) ...[
                    CaptureIconButton(
                      icon: .copy,
                      label: 'Copy',
                      shortcut: 'Ctrl+C',
                      onPressed: editor._busy
                          ? null
                          : () => editor._export(copy: true),
                    ),
                    CaptureIconButton(
                      icon: .save,
                      label: 'Save',
                      shortcut: 'Ctrl+S',
                      onPressed: editor._busy
                          ? null
                          : () => editor._export(copy: false),
                    ),
                  ] else ...[
                    CaptureButton(
                      label: 'Copy',
                      icon: const CaptureIcon(.copy),
                      variant: .tonal,
                      onPressed: editor._busy
                          ? null
                          : () => editor._export(copy: true),
                    ),
                    CaptureButton(
                      label: 'Save',
                      icon: const CaptureIcon(.save),
                      onPressed: editor._busy
                          ? null
                          : () => editor._export(copy: false),
                    ),
                  ],
                  _EditorMenu(editor: editor),
                  if (tiny) const Spacer(),
                  CaptureIconButton(
                    icon: .close,
                    label: 'Close',
                    shortcut: 'Esc',
                    onPressed: editor._busy ? null : editor._close,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WindowDrag extends StatelessWidget {
  const _WindowDrag({required this.onMove, this.child});

  final VoidCallback? onMove;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: .opaque,
    onPointerDown: (event) {
      if (event.buttons == kPrimaryButton) onMove?.call();
    },
    child: SizedBox(height: double.infinity, child: child),
  );
}

class _EditorTitle extends StatelessWidget {
  const _EditorTitle({
    required this.name,
    required this.size,
    required this.edited,
  });

  final String name;
  final Size size;
  final bool edited;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      spacing: 8,
      children: [
        const CaptureAppIcon(),
        Expanded(
          child: Column(
            mainAxisAlignment: .center,
            crossAxisAlignment: .start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: .ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                '${size.width.round()} × ${size.height.round()}${edited ? ' · Edited' : ''}',
                maxLines: 1,
                overflow: .ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditorMenu extends StatelessWidget {
  const _EditorMenu({required this.editor});

  final _ImageEditorState editor;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      MenuItemButton(
        onPressed: editor._busy
            ? null
            : () => editor._export(copy: false, saveAs: true),
        child: const Text('Save as…'),
      ),
      MenuItemButton(
        onPressed: editor._fit,
        child: const Text('Fit to window'),
      ),
      MenuItemButton(
        onPressed: () => editor._actualSize(View.of(context).devicePixelRatio),
        child: const Text('Actual size'),
      ),
      MenuItemButton(
        onPressed: editor._selection == null ? null : editor._duplicate,
        child: const Text('Duplicate selected object'),
      ),
      MenuItemButton(
        onPressed: editor._selection == null ? null : editor._remove,
        child: const Text('Delete selected object'),
      ),
      MenuItemButton(
        onPressed: () => _showShortcuts(context),
        child: const Text('Keyboard shortcuts'),
      ),
    ],
    builder: (context, menu, child) => CaptureIconButton(
      icon: .more,
      label: 'More actions',
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
    ),
  );
}

class _ToolRail extends StatelessWidget {
  const _ToolRail({required this.editor});

  final _ImageEditorState editor;

  @override
  Widget build(BuildContext context) {
    return _FloatingTools(
      radius: 30,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: .min,
          spacing: 4,
          children: [
            for (final tool in _Tool.values) ...[
              if (tool == .crop)
                const Divider(height: 1, thickness: 1, indent: 8, endIndent: 8),
              CaptureIconButton(
                icon: tool.icon,
                label: tool.label,
                shortcut: tool.shortcut,
                selected: tool == editor._tool,
                onPressed: () => editor._selectTool(tool),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FloatingTools extends StatelessWidget {
  const _FloatingTools({required this.child, required this.radius});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      elevation: 5,
      shadowColor: Colors.black45,
      clipBehavior: .antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: .circular(radius),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
      child: Padding(padding: const .all(9), child: child),
    );
  }
}

class _ToolOptions extends StatelessWidget {
  const _ToolOptions({required this.editor});

  final _ImageEditorState editor;

  @override
  Widget build(BuildContext context) {
    final tool = editor._optionsTool;
    final style = editor._style;
    final canChangeMask = editor._selection == null;
    final colors = Theme.of(context).colorScheme;
    return _FloatingTools(
      radius: 30,
      child: SingleChildScrollView(
        scrollDirection: .horizontal,
        child: Row(
          mainAxisSize: .min,
          spacing: 4,
          children: [
            if (tool.palette.isNotEmpty) ...[
              for (final entry in tool.palette.entries)
                CaptureSwatch(
                  color: entry.value,
                  label: entry.key,
                  selected: style.color == entry.value,
                  onPressed: () =>
                      editor._changeStyle(style.copyWith(color: entry.value)),
                ),
              CaptureSwatch.custom(
                selected: !tool.palette.containsValue(style.color),
                onPressed: editor._chooseColor,
              ),
              const CaptureDivider(),
            ],
            if (tool == .mosaic) ...[
              CaptureSegmentedControl<_Mosaic>(
                segments: const [
                  CaptureSegment(.pixelate, 'Pixelate'),
                  CaptureSegment(.blur, 'Blur'),
                ],
                value: style.mosaic,
                onChanged: (value) =>
                    editor._changeStyle(style.copyWith(mosaic: value)),
              ),
              const CaptureDivider(),
              CaptureSegmentedControl<bool>(
                segments: const [
                  CaptureSegment(true, 'Brush'),
                  CaptureSegment(false, 'Area'),
                ],
                value: style.brush,
                onChanged: canChangeMask
                    ? (value) =>
                          editor._changeStyle(style.copyWith(brush: value))
                    : null,
              ),
              const CaptureDivider(),
            ],
            if (tool.sizes case (final double min, final double max)
                when tool != .text)
              _StrokeSize(
                editor: editor,
                style: style,
                tool: tool,
                min: min,
                max: max,
              ),
            if (tool.isShape || tool.isLine || tool == .counter)
              const CaptureDivider(),
            if (tool.isShape)
              CaptureSegmentedControl<bool>(
                segments: const [
                  CaptureSegment(false, 'Border'),
                  CaptureSegment(true, 'Fill'),
                ],
                value: style.fill,
                onChanged: (value) =>
                    editor._changeStyle(style.copyWith(fill: value)),
              ),
            if (tool.isLine)
              CaptureSegmentedControl<_LineEnds>(
                segments: const [
                  CaptureSegment(.line, 'Line'),
                  CaptureSegment(.arrow, 'Arrow'),
                  CaptureSegment(.double, 'Double'),
                ],
                value: style.ends,
                onChanged: (value) =>
                    editor._changeStyle(style.copyWith(ends: value)),
              ),
            if (tool == .counter) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: .circular(18),
                ),
                child: Padding(
                  padding: const .symmetric(horizontal: 12, vertical: 8),
                  child: Text('Next  ${editor._styles[_Tool.counter]!.number}'),
                ),
              ),
              CaptureButton(
                label: 'Reset',
                icon: const CaptureIcon(.undo),
                variant: .text,
                onPressed: editor._resetCounter,
              ),
            ],
            if (tool == .text) _TextOptions(editor: editor, style: style),
            if (tool == .crop) ...[
              CaptureSegmentedControl<_CropRatio>(
                segments: [
                  for (final ratio in _CropRatio.values)
                    CaptureSegment(ratio, ratio.label),
                ],
                value: editor._cropRatio,
                onChanged: editor._changeCropRatio,
              ),
              CaptureSizeBadge(editor._crop!.size),
              const CaptureDivider(),
              CaptureButton(
                label: 'Cancel',
                icon: const CaptureIcon(.close),
                variant: .text,
                onPressed: () => editor._selectTool(.move),
              ),
              CaptureButton(
                label: 'Apply',
                icon: const CaptureIcon(.check),
                onPressed: editor._applyCrop,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StrokeSize extends StatelessWidget {
  const _StrokeSize({
    required this.editor,
    required this.style,
    required this.tool,
    required this.min,
    required this.max,
  });

  final _ImageEditorState editor;
  final _Style style;
  final _Tool tool;
  final double min;
  final double max;

  String _format(double value) {
    final prefix = tool != .mosaic
        ? ''
        : (style.mosaic == .blur ? 'Radius ' : 'Block ');
    return '$prefix${value.round()} px';
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: .min,
    spacing: 8,
    children: [
      SizedBox(
        width: 160,
        child: Listener(
          onPointerDown: (_) => editor._styleGestureRevision = editor._revision,
          onPointerUp: (_) => editor._styleGestureRevision = null,
          onPointerCancel: (_) => editor._styleGestureRevision = null,
          child: CaptureSlider(
            label: 'Size',
            value: style.size,
            min: min,
            max: max,
            onChanged: (value) {
              final size = value.roundToDouble();
              if (size != style.size) {
                editor._changeStyle(style.copyWith(size: size));
              }
            },
            formatValue: _format,
          ),
        ),
      ),
      Text(_format(style.size), style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _TextOptions extends StatelessWidget {
  const _TextOptions({required this.editor, required this.style});

  final _ImageEditorState editor;
  final _Style style;

  Future<void> _chooseFont(BuildContext context) async {
    final family = await showDialog<String>(
      context: context,
      builder: (_) => _FontPicker(selected: style.font),
    );
    if (!editor.mounted) return;
    if (family != null && family != editor._style.font) {
      editor._changeStyle(editor._style.copyWith(font: family));
    }
    if (editor._typing) editor._textFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: .min,
    spacing: 4,
    children: [
      Semantics(
        label: 'Font',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: CaptureButton(
            label: _FontPicker.label(style.font),
            icon: const CaptureIcon(.dropdown),
            variant: .tonal,
            onPressed: () => _chooseFont(context),
          ),
        ),
      ),
      CaptureDropdown<double>(
        label: 'Font size',
        options: {
          for (final size in <double>{
            10,
            12,
            14,
            16,
            18,
            20,
            22,
            24,
            28,
            32,
            36,
            48,
            72,
            style.size,
          })
            size: '${size.round()}',
        },
        value: style.size,
        onChanged: (value) => editor._changeStyle(style.copyWith(size: value)),
      ),
      const CaptureDivider(),
      CaptureIconButton(
        icon: .bold,
        label: 'Bold',
        selected: style.bold,
        onPressed: () => editor._changeStyle(style.copyWith(bold: !style.bold)),
      ),
      CaptureIconButton(
        icon: .italic,
        label: 'Italic',
        selected: style.italic,
        onPressed: () =>
            editor._changeStyle(style.copyWith(italic: !style.italic)),
      ),
      CaptureIconButton(
        icon: .underline,
        label: 'Underline',
        selected: style.underline,
        onPressed: () =>
            editor._changeStyle(style.copyWith(underline: !style.underline)),
      ),
    ],
  );
}

class _EditorStatus extends StatelessWidget {
  const _EditorStatus({required this.editor, required this.view});

  final _ImageEditorState editor;
  final _View view;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: colors.onSurfaceVariant);
    final count = editor._document.objects.length;
    return Material(
      color: colors.surfaceContainer,
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const .symmetric(horizontal: 16),
          child: Row(
            spacing: 16,
            children: [
              Expanded(
                child: Text(
                  '${editor._tool.label} — ${editor._tool.hint}',
                  overflow: .ellipsis,
                  style: style,
                ),
              ),
              ValueListenableBuilder(
                valueListenable: editor._cursor,
                builder: (context, cursor, child) {
                  if (cursor == null || !view.visibleImage.contains(cursor)) {
                    return const SizedBox.shrink();
                  }
                  final crop = view.crop;
                  final point = view.toImage(cursor);
                  return Text(
                    '${(point.dx - crop.left).floor()}, ${(point.dy - crop.top).floor()}',
                    style: style,
                  );
                },
              ),
              Text('$count ${count == 1 ? 'object' : 'objects'}', style: style),
              TextButton.icon(
                onPressed: () => _showShortcuts(context),
                icon: const CaptureIcon(.keyboard),
                label: const Text('Shortcuts'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  tapTargetSize: .shrinkWrap,
                  padding: const .symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showShortcuts(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Keyboard shortcuts'),
    content: SizedBox(
      width: 552,
      child: SingleChildScrollView(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 465;
            final sections = [
              _ShortcutColumn('Tools', [
                for (final tool in _Tool.values) (tool.label, [tool.shortcut]),
                ('Stroke size', ['[', ']']),
                ('Preset color', ['1', '…', '8']),
              ]),
              const _ShortcutColumn('Edit & view', [
                ('Undo', ['Ctrl', 'Z']),
                ('Redo', ['Ctrl', 'Y']),
                ('Delete object', ['Del']),
                ('Duplicate', ['Ctrl', 'D']),
                ('Copy image', ['Ctrl', 'C']),
                ('Save', ['Ctrl', 'S']),
                ('Save as…', ['Ctrl', 'Shift', 'S']),
                ('Zoom in / out', ['Ctrl', '+', '−']),
                ('Fit to window', ['Ctrl', '0']),
                ('Actual size', ['Ctrl', '1']),
                ('Pan', ['Space', 'Drag']),
                ('Constrain angle / ratio', ['Shift']),
                ('Close', ['Esc']),
              ]),
            ];
            return compact
                ? Column(spacing: 20, children: sections)
                : Row(
                    crossAxisAlignment: .start,
                    spacing: 32,
                    children: [
                      for (final section in sections) Expanded(child: section),
                    ],
                  );
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);

class _ShortcutColumn extends StatelessWidget {
  const _ShortcutColumn(this.title, this.entries);

  final String title;
  final List<(String, List<String>)> entries;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    spacing: 8,
    children: [
      Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
      for (final (label, keys) in entries)
        Row(
          spacing: 4,
          children: [
            Expanded(child: Text(label)),
            for (final key in keys) CaptureKeycap(key),
          ],
        ),
    ],
  );
}
