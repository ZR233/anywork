import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';

/// One row frame of the timeline: alignment, spacing, labels and the avatar of
/// a prompt row.
///
/// It owns no payload semantics: [prompt] rows are right-aligned with their
/// avatar, activity rows keep the tighter rhythm of a group member.
class TimelineRowFrame extends StatelessWidget {
  const TimelineRowFrame({
    required this.id,
    required this.child,
    this.prompt = false,
    this.parentAgent = false,
    this.accepted = false,
    this.rolledBack = false,
    this.compact = false,
    this.inGroup = false,
    super.key,
  });
  final String id;
  final Widget child;
  final bool prompt;
  final bool parentAgent;
  final bool accepted;
  final bool rolledBack;
  final bool compact;
  final bool inGroup;

  @override
  Widget build(BuildContext context) => Padding(
    key: StudioDriverKeys.timelineRow(id),
    padding: EdgeInsets.only(
      bottom: prompt
          ? 14
          : inGroup
          ? 2
          : compact
          ? 6
          : 12,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: prompt
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Flexible(
          child: ConstrainedBox(
            // Reply bodies use the reading column's available width; user and
            // parent-agent messages keep the narrower right-aligned bubble.
            constraints: BoxConstraints(
              maxWidth: prompt
                  ? StudioLayout.conversationPromptWidth
                  : double.infinity,
            ),
            child: Column(
              crossAxisAlignment: prompt
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (accepted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      context.l10n.promptAccepted,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                if (parentAgent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      context.l10n.timelineParentAgent,
                      key: StudioDriverKeys.parentAgentLabel(id),
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ),
                Opacity(opacity: rolledBack ? 0.52 : 1, child: child),
                if (rolledBack)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: DecoratedBox(
                      key: StudioDriverKeys.timelineRolledBack(id),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceContainer,
                        border: Border.all(
                          color: context.colors.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: Text(
                          context.l10n.timelineRolledBack,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (prompt)
          _PromptAvatar(
            icon: parentAgent
                ? Icons.account_tree_outlined
                : Icons.person_outline,
          ),
      ],
    ),
  );
}

class _PromptAvatar extends StatelessWidget {
  const _PromptAvatar({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outlineVariant),
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: 27,
          child: Icon(icon, size: 15, color: colors.onSurfaceVariant),
        ),
      ),
    );
  }
}
