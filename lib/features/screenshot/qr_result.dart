import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../capture_controls/capture_buttons.dart';
import '../capture_controls/capture_icon.dart';

/// Result bar shown after Scan QR copied the decoded text.
class QrResult extends StatefulWidget {
  const QrResult({
    super.key,
    required this.texts,
    required this.copyError,
    required this.onOpen,
    required this.onClose,
  });

  final List<String> texts;
  final String? copyError;
  final ValueChanged<Uri> onOpen;
  final VoidCallback onClose;

  @override
  State<QrResult> createState() => _QrResultState();
}

class _QrResultState extends State<QrResult> {
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    // Keep a failed copy on screen so the text can still be read.
    if (widget.copyError == null) {
      _expiry = Timer(const Duration(seconds: 6), widget.onClose);
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = widget.texts;
    final link = texts.length == 1 ? webLink(texts.single) : null;
    final codes = texts.length == 1 ? 'QR code' : '${texts.length} QR codes';
    final copyError = widget.copyError;
    final title = Text(
      copyError == null ? '$codes copied' : '$codes found · Copy failed',
      style: theme.textTheme.labelLarge,
      overflow: .ellipsis,
    );
    final content = texts.join('\n');
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              widget.onClose();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: CaptureSurface(
            child: Row(
              spacing: 8,
              children: [
                SizedBox.square(
                  dimension: 46,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: .circular(12),
                    ),
                    child: IconTheme.merge(
                      data: IconThemeData(color: colors.onSecondaryContainer),
                      child: const Center(child: CaptureIcon(.qrScanner)),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: .min,
                    mainAxisAlignment: .center,
                    crossAxisAlignment: .start,
                    spacing: 2,
                    children: [
                      if (copyError == null)
                        title
                      else
                        Tooltip(message: copyError, child: title),
                      Tooltip(
                        message: content,
                        child: Text(
                          content,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                if (link != null)
                  CaptureButton(
                    label: 'Open',
                    variant: .text,
                    icon: const CaptureIcon(.openInNew),
                    onPressed: () {
                      _expiry?.cancel();
                      widget.onOpen(link);
                    },
                  ),
                CaptureIconButton(
                  icon: .close,
                  label: 'Dismiss',
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [text] as a link only when it is a single http(s) URL with a host.
Uri? webLink(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null || uri.host.isEmpty) return null;
  return uri.isScheme('http') || uri.isScheme('https') ? uri : null;
}
