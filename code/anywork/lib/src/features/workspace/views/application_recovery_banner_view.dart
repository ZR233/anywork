import 'package:anywork_client/recovery.dart';
import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';

class ApplicationRecoveryBannerView extends StatelessWidget {
  const ApplicationRecoveryBannerView({
    required this.issues,
    required this.dismissedIds,
    required this.hasMore,
    required this.onMore,
    required this.onDismiss,
    super.key,
  });
  final List<RecoveryIssue> issues;
  final Set<String> dismissedIds;
  final bool hasMore;
  final VoidCallback onMore;
  final ValueChanged<String> onDismiss;

  @override
  Widget build(BuildContext context) {
    final visible = issues
        .where((issue) => !dismissedIds.contains(issue.id))
        .toList();
    if (visible.isEmpty) {
      // An incomplete collection is not "no application issues". Keep an
      // explicit bounded-read entry even if this page held only Thread issues.
      return hasMore
          ? Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onMore,
                child: Text(context.l10n.sidebarEarlier),
              ),
            )
          : const SizedBox.shrink();
    }
    final archived = visible.where(
      (issue) => issue.id == 'fresh-start-archive',
    );
    final other = visible.where((issue) => issue.id != 'fresh-start-archive');
    return Tooltip(
      richMessage: TextSpan(
        text: visible.map((issue) => issue.message).join('\n'),
      ),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final issue in archived) ...[
                      Text(context.l10n.recoveryArchiveNotice),
                      SelectableText(issue.message),
                    ],
                    if (other.isNotEmpty)
                      Text(context.l10n.recoveryGlobalWarning(other.length)),
                  ],
                ),
              ),
              if (hasMore)
                TextButton(
                  onPressed: onMore,
                  child: Text(context.l10n.sidebarEarlier),
                ),
              for (final issue in archived)
                IconButton(
                  key: const ValueKey('recovery-archive-dismiss'),
                  tooltip: context.l10n.recoveryArchiveDismiss,
                  onPressed: () => onDismiss(issue.id),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
