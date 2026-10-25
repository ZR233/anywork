import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../state/conversation_view_state.dart';

/// The read-only child/interaction dock has no editable composer to lend Stop.
class ConversationStopControl extends StatelessWidget {
  const ConversationStopControl({
    required this.state,
    required this.onStop,
    required this.showButton,
    super.key,
  });
  final ConversationStopState? state;
  final VoidCallback? onStop;
  final bool showButton;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: ConversationStopStatus(state: state)),
      if (showButton)
        IconButton.filledTonal(
          key: StudioDriverKeys.composerStop,
          tooltip: context.l10n.composerStop,
          onPressed: onStop,
          icon: state?.pending == true
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
/// control's own enabled/disabled state. An Unknown outcome is new (accepted but
/// never observed by canonical), so its recovery hint is the single exception.
class ConversationStopStatus extends StatelessWidget {
  const ConversationStopStatus({required this.state, super.key});
  final ConversationStopState? state;

  @override
  Widget build(BuildContext context) {
    if (state?.unknown != true) return const SizedBox.shrink();
    return Text(context.l10n.conversationStopUnknown);
  }
}
