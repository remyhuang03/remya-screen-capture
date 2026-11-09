import 'package:material_ui/material_ui.dart';

import 'capture_icon.dart';
import 'capture_labels.dart';

class CaptureIconButton extends StatelessWidget {
  const CaptureIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected,
    this.shortcut,
  });

  final CaptureSymbol icon;
  final String label;
  final VoidCallback? onPressed;
  final bool? selected;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = selected == true;
    return CaptureTooltip(
      label: label,
      shortcut: shortcut,
      child: IconButton(
        isSelected: selected,
        onPressed: onPressed,
        style: _style(
          colors,
          background: active ? colors.primary : Colors.transparent,
          foreground: active ? colors.onPrimary : colors.onSurfaceVariant,
          height: 40,
          padding: .zero,
          radius: .circular(active ? 14 : 20),
          pressedRadius: .circular(active ? 10 : 14),
        ).copyWith(fixedSize: const WidgetStatePropertyAll(Size.square(40))),
        icon: CaptureIcon(icon),
      ),
    );
  }
}

enum CaptureButtonStyle { filled, tonal, text, error }

class CaptureButton extends StatelessWidget {
  const CaptureButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = .filled,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final CaptureButtonStyle variant;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (variant) {
      .filled => (colors.primary, colors.onPrimary),
      .tonal => (colors.secondaryContainer, colors.onSecondaryContainer),
      .text => (Colors.transparent, colors.primary),
      .error => (colors.errorContainer, colors.onErrorContainer),
    };
    return FilledButton(
      onPressed: onPressed,
      style: _style(
        colors,
        background: background,
        foreground: foreground,
        height: 40,
        padding: const .fromLTRB(16, 0, 20, 0),
        radius: .circular(20),
      ),
      child: _ButtonLabel(label, icon: icon),
    );
  }
}

class CaptureToggleChip extends StatelessWidget {
  const CaptureToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.icon,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onChanged;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      toggled: selected,
      child: FilledButton(
        onPressed: onChanged == null ? null : () => onChanged!(!selected),
        style: _style(
          colors,
          background: selected
              ? colors.primary
              : colors.surfaceContainerHighest,
          foreground: selected ? colors.onPrimary : colors.onSurfaceVariant,
          height: 40,
          padding: const .fromLTRB(12, 0, 16, 0),
          radius: .circular(selected ? 12 : 20),
        ),
        child: _ButtonLabel(label, icon: icon),
      ),
    );
  }
}

class CaptureSegment<T> {
  const CaptureSegment(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final Widget? icon;
}

class CaptureSegmentedControl<T> extends StatelessWidget {
  const CaptureSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<CaptureSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      spacing: 2,
      children: [
        for (final (index, segment) in segments.indexed)
          _SegmentButton(
            label: segment.label,
            icon: segment.icon,
            first: index == 0,
            last: index == segments.length - 1,
            selected: segment.value == value,
            onPressed: onChanged == null
                ? null
                : () {
                    if (segment.value != value) onChanged!(segment.value);
                  },
          ),
      ],
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.first,
    required this.last,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final Widget? icon;
  final bool first;
  final bool last;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: FilledButton(
        onPressed: onPressed,
        style: _style(
          colors,
          background: selected
              ? colors.primary
              : colors.surfaceContainerHighest,
          foreground: selected ? colors.onPrimary : colors.onSurfaceVariant,
          height: 36,
          padding: const .symmetric(horizontal: 14),
          radius: BorderRadiusDirectional.horizontal(
            start: Radius.circular(selected || first ? 18 : 6),
            end: Radius.circular(selected || last ? 18 : 6),
          ),
          fontSize: 13,
        ),
        child: _ButtonLabel(label, icon: icon, spacing: 6),
      ),
    );
  }
}

class CaptureDropdown<T extends Object> extends StatefulWidget {
  const CaptureDropdown({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final Map<T, String> options;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  State<CaptureDropdown<T>> createState() => _CaptureDropdownState<T>();
}

class _CaptureDropdownState<T extends Object>
    extends State<CaptureDropdown<T>> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final options = widget.options;
    return MenuAnchor(
      childFocusNode: _focus,
      menuChildren: [
        for (final option in options.entries)
          MenuItemButton(
            autofocus: option.key == widget.value,
            onPressed: () => widget.onChanged?.call(option.key),
            child: Semantics(
              selected: option.key == widget.value,
              child: Text(option.value),
            ),
          ),
      ],
      builder: (context, controller, child) => Semantics(
        label: widget.label,
        expanded: controller.isOpen,
        child: FilledButton(
          focusNode: _focus,
          onPressed: widget.onChanged == null || options.isEmpty
              ? null
              : () =>
                    controller.isOpen ? controller.close() : controller.open(),
          style: _style(
            colors,
            background: colors.surfaceContainerHighest,
            foreground: colors.onSurface,
            height: 36,
            padding: const .fromLTRB(12, 0, 8, 0),
            radius: .circular(12),
            fontSize: 13,
          ),
          child: Row(
            mainAxisSize: .min,
            spacing: 4,
            children: [
              Flexible(
                child: Text(
                  options[widget.value] ?? widget.label,
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
              ),
              const CaptureIcon(.dropdown),
            ],
          ),
        ),
      ),
    );
  }
}

class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel(this.label, {required this.icon, this.spacing = 8});

  final String label;
  final Widget? icon;
  final double spacing;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: .min,
    spacing: spacing,
    children: [
      ?icon,
      Flexible(child: Text(label, maxLines: 1, overflow: .ellipsis)),
    ],
  );
}

ButtonStyle _style(
  ColorScheme colors, {
  required Color background,
  required Color foreground,
  required double height,
  required EdgeInsetsGeometry padding,
  required BorderRadiusGeometry radius,
  BorderRadiusGeometry? pressedRadius,
  double fontSize = 14,
}) => ButtonStyle(
  backgroundColor: .resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? (background == Colors.transparent
              ? Colors.transparent
              : colors.onSurface.withValues(alpha: .12))
        : background,
  ),
  foregroundColor: .resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? colors.onSurface.withValues(alpha: .38)
        : foreground,
  ),
  overlayColor: .resolveWith((states) {
    if (states.contains(WidgetState.pressed) ||
        states.contains(WidgetState.focused)) {
      return foreground.withValues(alpha: .12);
    }
    return states.contains(WidgetState.hovered)
        ? foreground.withValues(alpha: .08)
        : null;
  }),
  side: .resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? BorderSide(color: foreground)
        : null,
  ),
  shape: .resolveWith(
    (states) => RoundedRectangleBorder(
      borderRadius: states.contains(WidgetState.pressed)
          ? pressedRadius ?? radius
          : radius,
    ),
  ),
  padding: .all(padding),
  minimumSize: .all(Size(0, height)),
  tapTargetSize: .shrinkWrap,
  visualDensity: .standard,
  splashFactory: NoSplash.splashFactory,
  textStyle: .all(
    TextStyle(fontSize: fontSize, fontWeight: .w500, letterSpacing: 0),
  ),
);
