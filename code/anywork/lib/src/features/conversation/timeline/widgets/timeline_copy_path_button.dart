import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';

/// Copies a displayed path and owns its short-lived copied feedback.
class TimelineCopyPathButton extends StatefulWidget {
  const TimelineCopyPathButton({
    required this.path,
    this.padding = 3,
    super.key,
  });

  final String path;
  final double padding;

  @override
  State<TimelineCopyPathButton> createState() => _TimelineCopyPathButtonState();
}

class _TimelineCopyPathButtonState extends State<TimelineCopyPathButton> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.path)));
    _timer?.cancel();
    setState(() => _copied = true);
    _timer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Tooltip(
      message: _copied
          ? l10n.timelineOutcomeCopied
          : l10n.timelinePatchCopyPath,
      child: InkWell(
        onTap: _copy,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        child: Padding(
          padding: EdgeInsets.all(widget.padding),
          child: Icon(
            _copied ? Icons.check_rounded : Icons.content_copy_rounded,
            size: 13,
            color: _copied
                ? context.colors.primary
                : context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
