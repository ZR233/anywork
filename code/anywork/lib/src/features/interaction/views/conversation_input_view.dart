import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';

/// Child/interaction Stop is independent of text/send/platform pending state.
/// The editor itself remains outside this slot in ConversationView.interactions.
class ConversationInputView extends StatelessWidget {
  const ConversationInputView({
    required this.retired,
    required this.runtimeDriven,
    required this.interactionVisible,
    required this.interactionReopenable,
    required this.interactionPending,
    required this.onReopen,
    required this.stopControl,
    required this.composer,
    super.key,
  });
  final bool retired;
  final bool runtimeDriven;
  final bool interactionVisible;
  final bool interactionReopenable;
  final bool interactionPending;
  final VoidCallback onReopen;
  final Widget stopControl;
  final Widget composer;

  @override
  Widget build(BuildContext context) {
    if (retired) {
      return Text(
        context.l10n.agentRoleRetired,
        key: const ValueKey('retired-planner-input-notice'),
      );
    }
    if (interactionVisible) return stopControl;
    if (runtimeDriven) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [Text(context.l10n.composerAgentRuntimeDriven), stopControl],
      );
    }
    if (interactionReopenable) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: onReopen,
            child: Text(context.l10n.timelineUserInputAwaiting),
          ),
          stopControl,
        ],
      );
    }
    if (interactionPending) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [Text(context.l10n.timelineUserInputAwaiting), stopControl],
      );
    }
    return composer;
  }
}
