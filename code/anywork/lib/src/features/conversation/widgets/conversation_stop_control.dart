import 'package:anywork_client/conversation.dart' show studioFailureReason;
import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../state/composer_primary_action.dart';
import '../state/conversation_view_state.dart';

/// A root interaction dock borrows the same canonical matrix as the composer.
/// Child details never mount this control.
class ConversationStopControl extends StatelessWidget {
  const ConversationStopControl({
    required this.state,
    required this.onStop,
    required this.primaryAction,
    super.key,
  });
  final ConversationStopState? state;
  final VoidCallback? onStop;
  final ComposerPrimaryAction primaryAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConversationStopStatus(state: state),
            if (state?.failure case final failure?)
              Text(
                context.composerFailureReasonLabel(
                  studioFailureReason(failure),
                ),
                key: const ValueKey('composer-stop-failure'),
              ),
          ],
        ),
      ),
      if (primaryAction.kind == ComposerPrimaryActionKind.stopping) ...[
        Text(
          context.l10n.composerStopping,
          key: StudioDriverKeys.composerStopping,
        ),
        const SizedBox(width: 8),
      ],
      if (primaryAction.kind == ComposerPrimaryActionKind.stop ||
          primaryAction.kind == ComposerPrimaryActionKind.stopping)
        IconButton.filledTonal(
          key: primaryAction.kind == ComposerPrimaryActionKind.stopping
              ? const ValueKey('composer-stopping-disabled')
              : StudioDriverKeys.composerStop,
          tooltip: primaryAction.kind == ComposerPrimaryActionKind.stopping
              ? context.l10n.composerStopping
              : context.l10n.composerStop,
          onPressed: primaryAction.enabled ? onStop : null,
          icon: primaryAction.kind == ComposerPrimaryActionKind.stopping
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.stop),
        ),
    ],
  );
}

/// Only the Unknown outcome keeps a visible line.
///
/// The pre-refactor composer showed no stop phase text at all: requesting,
/// awaiting-observation, observed and effective were all expressed by the
/// control's own enabled/disabled state. An Unknown outcome does not establish
/// acceptance, so its uncertainty hint is the single exception.
class ConversationStopStatus extends StatelessWidget {
  const ConversationStopStatus({required this.state, super.key});
  final ConversationStopState? state;

  @override
  Widget build(BuildContext context) {
    if (state?.unknown != true) return const SizedBox.shrink();
    return Text(context.l10n.conversationStopUnknown);
  }
}
