import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../widgets/interaction_widgets.dart';
import '../state/interaction_payload.dart';

class ChildInteractionNoticeView extends StatelessWidget {
  const ChildInteractionNoticeView({required this.notice, super.key});

  final ChildDecisionNotice notice;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      switch (notice.kind) {
        InteractionKind.userInput => context.l10n.childInteractionAnswerSaved,
        InteractionKind.toolApproval =>
          context.l10n.childInteractionApprovalResolved,
      },
      key: ValueKey('child-interaction-notice-${notice.interactionId}'),
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class ChildInteractionCardView extends StatelessWidget {
  const ChildInteractionCardView({
    required this.interactionId,
    required this.revision,
    required this.source,
    required this.pending,
    required this.accepted,
    required this.blocked,
    required this.child,
    this.failure,
    super.key,
  });

  final String interactionId;
  final int revision;
  final String source;
  final bool pending;
  final bool accepted;
  final bool blocked;
  final String? failure;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final secondaryStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return KeyedSubtree(
      key: StudioDriverKeys.childInteractionCard(interactionId),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InfoChip(
                icon: Icons.account_tree_outlined,
                label: context.l10n.childInteractionFrom(source),
              ),
              Text(
                context.l10n.childInteractionRevision(revision),
                key: ValueKey('child-interaction-revision-$interactionId'),
                style: secondaryStyle,
              ),
              if (pending || accepted)
                SizedBox.square(
                  key: ValueKey('child-interaction-awaiting-$interactionId'),
                  dimension: 14,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (accepted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.l10n.childInteractionDecisionAccepted,
                key: ValueKey('child-interaction-accepted-$interactionId'),
                style: secondaryStyle,
              ),
            ),
          const SizedBox(height: 6),
          child,
          if (failure case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.l10n.childInteractionDecideFailed(message),
                key: ValueKey('child-interaction-failure-$interactionId'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
