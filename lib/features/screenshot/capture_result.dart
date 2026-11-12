import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../capture_controls/capture_buttons.dart';
import '../capture_controls/capture_icon.dart';

typedef CaptureReceipt = ({
  bool copied,
  String? path,
  String? copyError,
  String? saveError,
});

class CaptureResult extends StatefulWidget {
  const CaptureResult({
    super.key,
    required this.image,
    required this.receipt,
    required this.onRetry,
    required this.onEdit,
    required this.onClose,
  });

  final ui.Image image;
  final CaptureReceipt receipt;
  final Future<CaptureReceipt> Function(CaptureReceipt) onRetry;
  final VoidCallback onEdit;
  final VoidCallback onClose;

  @override
  State<CaptureResult> createState() => _CaptureResultState();
}

class _CaptureResultState extends State<CaptureResult> {
  late CaptureReceipt _receipt;
  Timer? _expiry;
  bool _busy = false;
  bool get _complete => _receipt.copied && _receipt.path != null;

  @override
  void initState() {
    super.initState();
    _receipt = widget.receipt;
    _scheduleExpiry();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  void _scheduleExpiry() {
    if (_complete) _expiry = Timer(const Duration(seconds: 4), widget.onClose);
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    final receipt = await widget.onRetry(_receipt);
    if (!mounted) return;
    setState(() {
      _receipt = receipt;
      _busy = false;
    });
    _scheduleExpiry();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = widget.image;
    final label = _receipt.copied
        ? (_receipt.path == null
              ? 'Copied · Save failed'
              : 'Copied to clipboard')
        : _receipt.path == null
        ? 'Could not copy or save'
        : 'Saved · Copy failed';
    final size = '${image.width} × ${image.height} · PNG';
    final path = _receipt.path;
    final details = path == null ? size : '$size · $path';
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
                ClipRRect(
                  borderRadius: .circular(8),
                  child: RawImage(
                    image: image,
                    fit: .cover,
                    width: 92,
                    height: 46,
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: .min,
                    mainAxisAlignment: .center,
                    crossAxisAlignment: .start,
                    spacing: 2,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.labelLarge,
                        overflow: .ellipsis,
                      ),
                      Tooltip(
                        message: details,
                        child: Text(
                          details,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (_receipt.copyError != null ||
                          _receipt.saveError != null)
                        Tooltip(
                          message: [
                            if (_receipt.copyError case final error?)
                              'Copy · $error',
                            if (_receipt.saveError case final error?)
                              'Save · $error',
                          ].join('\n'),
                          child: CaptureButton(
                            label: 'Retry',
                            variant: .text,
                            onPressed: _busy ? null : _retry,
                          ),
                        ),
                    ],
                  ),
                ),
                CaptureButton(
                  label: 'Edit',
                  icon: const CaptureIcon(.edit),
                  variant: .tonal,
                  onPressed: _busy
                      ? null
                      : () {
                          _expiry?.cancel();
                          widget.onEdit();
                        },
                ),
                CaptureIconButton(
                  icon: .close,
                  label: 'Dismiss',
                  onPressed: _busy ? null : widget.onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
