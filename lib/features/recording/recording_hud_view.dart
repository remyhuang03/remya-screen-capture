part of 'recording_hud.dart';

class RecordingHud extends StatefulWidget {
  const RecordingHud({
    super.key,
    required this.controller,
    required this.monitor,
    required this.onInputChanged,
  });

  final RecordingHudController controller;
  final CaptureMonitor monitor;
  final void Function(List<Rect> regions, bool keyboard) onInputChanged;

  @override
  State<RecordingHud> createState() => _RecordingHudState();
}

class _RecordingHudState extends State<RecordingHud> {
  final _focus = FocusNode(skipTraversal: true);
  List<Rect>? _lastRegions;
  bool? _lastKeyboard;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _publishInput(List<Rect> regions, bool keyboard) {
    if (listEquals(_lastRegions, regions) && _lastKeyboard == keyboard) return;
    _lastRegions = regions;
    _lastKeyboard = keyboard;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_lastRegions, regions)) {
        widget.onInputChanged(regions, keyboard);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final monitor = widget.monitor;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final dragging = controller._dragPointer != null;
        final placement = dragging
            ? null
            : controller._settledPlacement(monitor);
        final onTarget = monitor == controller.target;
        final drawing = onTarget && controller._annotation != .none;
        final visible = placement != null && !controller._hidden;
        final trigger = visible ? null : placement?.trigger;
        final ownsToolbar = monitor == controller._toolbarMonitor;
        final picker = ownsToolbar && controller._pickingColor;
        final viewport = Offset.zero & monitor.bounds.size;
        // Wayland's implicit grab keeps motion and release on the press surface.
        if (!dragging) {
          _publishInput([
            if (picker)
              viewport
            else ...[
              if (drawing) controller._drawingBounds,
              if (visible) placement.toolbar.intersect(viewport),
              ?placement?.options,
              ?trigger,
            ],
          ], visible || drawing || picker);
        }

        Offset global(PointerEvent event) =>
            event.localPosition + monitor.bounds.topLeft;

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.backspace, control: true):
                controller._clear,
            const SingleActivator(LogicalKeyboardKey.bracketLeft): () =>
                controller._setWidth(controller._markerWidth - 1),
            const SingleActivator(LogicalKeyboardKey.bracketRight): () =>
                controller._setWidth(controller._markerWidth + 1),
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (controller._annotation != .none) {
                controller._toggleTool(controller._annotation);
              }
            },
          },
          child: Focus(
            autofocus: true,
            focusNode: _focus,
            child: Listener(
              onPointerMove: (event) =>
                  controller._moveDrag(event.pointer, global(event)),
              onPointerUp: (event) =>
                  controller._endDrag(event.pointer, global(event)),
              onPointerCancel: (event) => controller._endDrag(
                event.pointer,
                global(event),
                cancelled: true,
              ),
              child: Stack(
                fit: .expand,
                children: [
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _RecordingInk(controller, drawsInk: onTarget),
                      ),
                    ),
                  ),
                  if (drawing)
                    Positioned.fromRect(
                      rect: controller._drawingBounds,
                      child: _drawingInput(controller),
                    ),
                  _positionedToolbar(
                    controller,
                    monitor,
                    visible ? placement.toolbar : null,
                    dragging: dragging,
                  ),
                  if (placement?.options case final rect?)
                    Positioned.fromRect(
                      rect: rect,
                      child: MouseRegion(
                        onEnter: (_) => controller._holdOpen(),
                        onExit: (_) => controller._leave(),
                        child: FittedBox(
                          child: SizedBox.fromSize(
                            size: _optionsSize,
                            child: _MarkerOptions(controller),
                          ),
                        ),
                      ),
                    ),
                  if (trigger != null)
                    Positioned.fromRect(
                      rect: trigger,
                      child: MouseRegion(
                        onEnter: (_) => controller._holdOpen(),
                        child: Center(
                          child: SizedBox.square(
                            dimension: 40,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: .circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _positionedToolbar(
    RecordingHudController controller,
    CaptureMonitor monitor,
    Rect? settledBounds, {
    required bool dragging,
  }) {
    final dragBounds = controller._dragBounds[monitor]!;
    return ValueListenableBuilder(
      valueListenable: dragBounds,
      child: MouseRegion(
        onEnter: (_) => controller._holdOpen(),
        onExit: (_) => controller._leave(),
        child: FittedBox(
          child: SizedBox.fromSize(
            size: _toolbarSize,
            child: RepaintBoundary(
              child: _RecordingToolbar(
                controller: controller,
                onDragStart: (event) => controller._beginDrag(
                  event.pointer,
                  event.position + monitor.bounds.topLeft,
                ),
              ),
            ),
          ),
        ),
      ),
      builder: (context, bounds, toolbar) {
        final rect = dragging ? bounds : settledBounds;
        return rect == null
            ? const SizedBox.shrink()
            : Positioned.fromRect(rect: rect, child: toolbar!);
      },
    );
  }

  Widget _drawingInput(RecordingHudController controller) => MouseRegion(
    cursor: SystemMouseCursors.precise,
    child: Listener(
      behavior: .opaque,
      onPointerDown: (event) {
        if (event.buttons != kPrimaryMouseButton) return;
        _focus.requestFocus();
        controller._beginDrawing(
          event.pointer,
          event.localPosition + controller._drawingBounds.topLeft,
        );
      },
      onPointerMove: (event) => controller._moveDrawing(
        event.pointer,
        event.localPosition + controller._drawingBounds.topLeft,
      ),
      onPointerUp: (event) => controller._endDrawing(event.pointer),
      onPointerCancel: (event) => controller._endDrawing(event.pointer),
    ),
  );
}

class _RecordingToolbar extends StatelessWidget {
  const _RecordingToolbar({
    required this.controller,
    required this.onDragStart,
  });

  final RecordingHudController controller;
  final ValueChanged<PointerDownEvent> onDragStart;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final paused = controller._wasPaused;
    return CaptureSurface(
      child: Row(
        spacing: 4,
        children: [
          Expanded(
            child: CaptureTooltip(
              label:
                  controller._error?.detail ??
                  'Drag to move recording controls',
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Listener(
                  behavior: .opaque,
                  onPointerDown: (event) {
                    if (event.buttons == kPrimaryMouseButton) {
                      onDragStart(event);
                    }
                  },
                  child: _RecordingStatus(controller),
                ),
              ),
            ),
          ),
          CaptureIconButton(
            icon: paused ? .play : .pause,
            label: paused ? 'Resume recording' : 'Pause recording',
            onPressed: controller._busy
                ? null
                : () => controller._invoke(
                    controller.onPause,
                    paused ? 'Resume failed' : 'Pause failed',
                  ),
          ),
          CaptureTooltip(
            label: 'Stop recording',
            shortcut: 'Super+R',
            child: IconButton.filled(
              onPressed: controller._busy
                  ? null
                  : () => controller._invoke(controller.onStop, 'Stop failed'),
              style: IconButton.styleFrom(
                fixedSize: const Size.square(40),
                minimumSize: Size.zero,
                padding: .zero,
                tapTargetSize: .shrinkWrap,
                backgroundColor: colors.errorContainer,
                foregroundColor: colors.onErrorContainer,
                shape: RoundedRectangleBorder(borderRadius: .circular(14)),
              ),
              icon: const CaptureIcon(.stop),
            ),
          ),
          const CaptureDivider(),
          CaptureIconButton(
            icon: .laserPointer,
            label: 'Laser pointer',
            selected: controller._annotation == .laser,
            onPressed: () => controller._toggleTool(.laser),
          ),
          CaptureIconButton(
            icon: .highlighter,
            label: 'Marker',
            selected: controller._annotation == .marker,
            onPressed: () => controller._toggleTool(.marker),
          ),
          CaptureIconButton(
            icon: .delete,
            label: 'Clear drawings',
            shortcut: 'Ctrl+Backspace',
            onPressed: controller._clear,
          ),
          const CaptureDivider(),
          _AudioToggle(
            label: 'System audio',
            state: controller.systemAudio(),
            onIcon: .volumeUp,
            offIcon: .volumeOff,
            controller: controller,
            onToggle: controller.onSystemAudio,
          ),
          _AudioToggle(
            label: 'Microphone',
            state: controller.microphone(),
            onIcon: .mic,
            offIcon: .micOff,
            controller: controller,
            onToggle: controller.onMicrophone,
          ),
          _InputStatus(
            label:
                'Cursor capture · ${controller.cursor ? 'enabled' : 'disabled'}',
            icon: .cursor,
            dimmed: !controller.cursor,
          ),
        ],
      ),
    );
  }
}

class _RecordingStatus extends StatelessWidget {
  const _RecordingStatus(this.controller);

  final RecordingHudController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final paused = controller._wasPaused;
    if (controller._error case final error?) {
      return Semantics(
        liveRegion: true,
        label: error.detail,
        child: Container(
          height: 34,
          alignment: .center,
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: .circular(20),
          ),
          child: Text(
            error.label,
            style: TextStyle(color: colors.onErrorContainer, fontSize: 11),
          ),
        ),
      );
    }
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: paused ? colors.secondaryContainer : colors.errorContainer,
        borderRadius: .circular(20),
      ),
      padding: const .symmetric(horizontal: 8),
      child: Row(
        spacing: 8,
        mainAxisAlignment: .center,
        children: [
          Opacity(
            opacity: paused ? .55 : 1,
            child: const Icon(
              Symbols.circle_rounded,
              size: 10,
              color: Color(0xfff2b8b5),
              fill: 1,
              weight: captureIconWeight,
            ),
          ),
          Flexible(
            child: ValueListenableBuilder(
              valueListenable: controller._seconds,
              builder: (context, seconds, _) {
                String twoDigits(int value) => value.toString().padLeft(2, '0');
                final elapsed =
                    '${twoDigits(seconds ~/ 60)}:${twoDigits(seconds % 60)}';
                return FittedBox(
                  fit: .scaleDown,
                  child: Text(
                    elapsed,
                    semanticsLabel:
                        '${paused ? 'Paused' : 'Recording'}, $elapsed elapsed',
                    style: TextStyle(
                      color: paused
                          ? colors.onSecondaryContainer
                          : colors.onErrorContainer,
                      fontFamily: 'JetBrains Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontSize: 14,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioToggle extends StatelessWidget {
  const _AudioToggle({
    required this.label,
    required this.state,
    required this.onIcon,
    required this.offIcon,
    required this.controller,
    required this.onToggle,
  });

  final String label;
  final ({bool enabled, bool available}) state;
  final CaptureSymbol onIcon;
  final CaptureSymbol offIcon;
  final RecordingHudController controller;
  final Future<void> Function(bool)? onToggle;

  @override
  Widget build(BuildContext context) {
    final icon = state.enabled ? onIcon : offIcon;
    final status = '$label · ${state.enabled ? 'on' : 'off'}';
    final toggle = onToggle;
    if (!state.available || toggle == null) {
      return _InputStatus(label: status, icon: icon, dimmed: !state.enabled);
    }
    return CaptureIconButton(
      icon: icon,
      label: status,
      selected: state.enabled,
      onPressed: controller._busy
          ? null
          : () => controller._invoke(
              () => toggle(!state.enabled),
              'Could not change ${label.toLowerCase()}',
            ),
    );
  }
}

class _InputStatus extends StatelessWidget {
  const _InputStatus({
    required this.label,
    required this.icon,
    this.dimmed = false,
  });

  final String label;
  final CaptureSymbol icon;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      label: label,
      child: CaptureTooltip(
        label: label,
        child: SizedBox.square(
          dimension: 40,
          child: Center(
            child: IconTheme(
              data: IconThemeData(
                color: dimmed ? color.withValues(alpha: .5) : color,
              ),
              child: CaptureIcon(icon),
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkerOptions extends StatelessWidget {
  const _MarkerOptions(this.controller);

  final RecordingHudController controller;

  @override
  Widget build(BuildContext context) => CaptureSurface(
    child: Row(
      spacing: 4,
      children: [
        for (final (label, color) in _markerPresets.entries.map(
          (entry) => (entry.key, entry.value),
        ))
          CaptureSwatch(
            color: color,
            label: label,
            selected:
                !controller._customColor && color == controller._markerColor,
            onPressed: () => controller._setColor(color),
          ),
        CaptureSwatch.custom(
          selected: controller._customColor,
          onPressed: () => controller._pickColor(context),
        ),
        const CaptureDivider(),
        Expanded(
          child: CaptureSlider(
            label: 'Marker width',
            value: controller._markerWidth,
            min: 1,
            max: 16,
            formatValue: (value) => '${value.round()} pixels',
            onChanged: controller._setWidth,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${controller._markerWidth.round()} px',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}
