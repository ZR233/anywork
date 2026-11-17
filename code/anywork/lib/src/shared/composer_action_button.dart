import 'package:material_ui/material_ui.dart';

/// Presentation only: protocol-specific eligibility and actions stay with owners.
enum ComposerActionButtonState {
  send,
  sendAndContinue,
  stop,
  continueConversation,
  busy,
  readOnly,
}

/// The single, fixed-size primary action used by every conversation composer.
class ComposerActionButton extends StatelessWidget {
  const ComposerActionButton({
    required this.state,
    required this.tooltip,
    this.onPressed,
    this.buttonKey,
    this.progressKey,
    super.key,
  });

  static const double dimension = 34;

  final ComposerActionButtonState state;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Stable automation identity belongs to the actual interactive control.
  final Key? buttonKey;
  final Key? progressKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = state == ComposerActionButtonState.busy;
    final inactive = busy || state == ComposerActionButtonState.readOnly;
    final stop = state == ComposerActionButtonState.stop;
    return SizedBox.square(
      dimension: dimension,
      child: IconButton.filled(
        key: buttonKey,
        tooltip: tooltip,
        onPressed: inactive ? null : onPressed,
        iconSize: 20,
        padding: EdgeInsets.zero,
        alignment: Alignment.center,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(dimension),
          minimumSize: const Size.square(dimension),
          maximumSize: const Size.square(dimension),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const CircleBorder(),
          backgroundColor: stop
              ? colors.surfaceContainerHighest
              : colors.primary,
          foregroundColor: stop ? colors.onSurface : colors.onPrimary,
          disabledBackgroundColor: colors.surfaceContainerHighest,
          disabledForegroundColor: colors.onSurface.withValues(alpha: 0.38),
        ),
        icon: busy
            ? SizedBox.square(
                key: progressKey,
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onSurfaceVariant,
                ),
              )
            : Icon(switch (state) {
                ComposerActionButtonState.stop => Icons.stop_rounded,
                ComposerActionButtonState.continueConversation =>
                  Icons.play_arrow_rounded,
                _ => Icons.arrow_upward_rounded,
              }),
      ),
    );
  }
}
