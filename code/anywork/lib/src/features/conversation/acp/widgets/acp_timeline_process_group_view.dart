import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../timeline/widgets/timeline_activity_row.dart';
import '../state/acp_timeline_row.dart';
import '../views/acp_conversation_content_view.dart';
import 'acp_content_block_view.dart';

/// One disclosure for a contiguous process interval between visible messages.
class AcpTimelineProcessGroupView extends StatelessWidget {
  const AcpTimelineProcessGroupView({
    super.key,
    required this.row,
    this.initiallyExpanded = false,
    this.isSafeLink,
    this.onOpenLink,
    this.imageBuilder,
  });

  final AcpTimelineProcessRow row;
  final bool initiallyExpanded;
  final bool Function(String url)? isSafeLink;
  final ValueChanged<String>? onOpenLink;
  final AcpImageWidgetBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final summary = l10n.acpProcessGroupSummary(
      row.items.length,
      row.toolCount,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ListTileTheme(
        data: Theme.of(context).listTileTheme.copyWith(
          tileColor: colors.surface,
          selectedTileColor: colors.surface,
        ),
        child: ExpansionTile(
          key: PageStorageKey<String>(row.id),
          initiallyExpanded: initiallyExpanded,
          backgroundColor: colors.surface,
          collapsedBackgroundColor: colors.surface,
          textColor: colors.onSurfaceVariant,
          collapsedTextColor: colors.onSurfaceVariant,
          iconColor: colors.onSurfaceVariant,
          collapsedIconColor: colors.onSurfaceVariant,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TimelineActivityRow(
                icon: Icons.account_tree_outlined,
                label: summary,
                labelWidget: Text(
                  summary,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                active: row.active,
                isIssue: row.failedCount > 0,
                expandable: false,
                tooltip: summary,
              ),
              if (row.active || row.failedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(
                    left: TimelineActivityRow.contentIndent,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (row.active) Text(l10n.acpProcessGroupRunning),
                      if (row.failedCount > 0)
                        Text(
                          l10n.acpProcessGroupFailed(row.failedCount),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          children: [
            Builder(
              builder: (context) {
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in row.items)
                      AcpTimelineEntryView(
                        key: ValueKey(item.id),
                        item: item,
                        fullDetails: true,
                        isSafeLink: isSafeLink,
                        onOpenLink: onOpenLink,
                        imageBuilder: imageBuilder,
                      ),
                  ],
                );
                return SelectionContainer.maybeOf(context) == null
                    ? SelectionArea(child: details)
                    : details;
              },
            ),
          ],
        ),
      ),
    );
  }
}
