import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../timeline/widgets/timeline_activity_row.dart';
import '../../timeline/widgets/timeline_patch_diff_view.dart';
import '../state/acp_view_state.dart';
import 'acp_content_block_view.dart';

IconData _iconForToolKind(String? kindLabel) => switch (kindLabel) {
  'read' => Icons.article_outlined,
  'edit' => Icons.edit_note_rounded,
  'delete' => Icons.delete_outline_rounded,
  'move' => Icons.drive_file_move_outline,
  'search' => Icons.travel_explore_rounded,
  'execute' => Icons.terminal_rounded,
  'think' => Icons.psychology_outlined,
  'fetch' => Icons.public_rounded,
  'switchMode' => Icons.swap_horiz_rounded,
  _ => Icons.handyman_outlined,
};

/// Pure presentation widget for an ACP tool call item, aligned with the native
/// [TimelineActivityRow] process track (`20px` icon column + `28px` content
/// indent + unified patch diff view).
class AcpToolCard extends StatefulWidget {
  const AcpToolCard({
    super.key,
    required this.item,
    this.initiallyExpanded = false,
    this.fullDetails = false,
    this.isSafeLink,
    this.onOpenLink,
    this.imageBuilder,
  });

  final AcpTimelineToolCallItem item;
  final bool initiallyExpanded;
  final bool fullDetails;
  final bool Function(String url)? isSafeLink;
  final ValueChanged<String>? onOpenLink;
  final AcpImageWidgetBuilder? imageBuilder;

  @override
  State<AcpToolCard> createState() => _AcpToolCardState();
}

class _AcpToolCardState extends State<AcpToolCard> {
  late bool _expanded =
      widget.initiallyExpanded ||
      widget.item.diffs.isNotEmpty ||
      widget.item.status == AcpToolStatusKind.failed;

  bool get _hasExpandableDetails {
    final item = widget.item;
    return item.locations.isNotEmpty ||
        item.terminals.isNotEmpty ||
        item.diffs.isNotEmpty ||
        item.contentBlocks.isNotEmpty ||
        item.tool.arguments.trim().isNotEmpty ||
        item.tool.output.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final active =
        item.status == AcpToolStatusKind.pending ||
        item.status == AcpToolStatusKind.inProgress;
    final isIssue = item.status == AcpToolStatusKind.failed;
    final expandable = _hasExpandableDetails;
    final locationSummary = item.locations.isEmpty
        ? null
        : item.locations.first;

    final row = TimelineActivityRow(
      key: ValueKey(AcpViewKeyValues.toolCard(item.toolCallId)),
      icon: _iconForToolKind(item.kindLabel),
      label: item.tool.name,
      meta: item.kindLabel,
      active: active,
      isIssue: isIssue,
      expanded: expandable && (_expanded || widget.fullDetails),
      expandable: expandable && !widget.fullDetails,
      tooltip: [item.tool.name, ?locationSummary].join('\n'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (expandable && !widget.fullDetails)
          InkWell(
            borderRadius: BorderRadius.circular(StudioRadii.xs),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: row,
            ),
          )
        else
          Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: row),
        if (expandable && (_expanded || widget.fullDetails))
          Padding(
            padding: const EdgeInsets.only(
              left: TimelineActivityRow.contentIndent,
              top: 6,
              bottom: 6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.locations.isNotEmpty || item.terminals.isNotEmpty) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final location in item.locations)
                        Text(location, style: context.text.bodySmall),
                      for (final terminal in item.terminals)
                        Text(
                          context.l10n.acpToolTerminalPrefix(terminal),
                          style: context.text.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                for (var i = 0; i < item.diffs.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(StudioRadii.sm),
                      border: Border.all(color: context.colors.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TimelinePatchDiffView(
                        document: item.diffs[i],
                        softWrap: widget.fullDetails,
                      ),
                    ),
                  ),
                ],
                for (var i = 0; i < item.contentBlocks.length; i++) ...[
                  if (i > 0 || item.diffs.isNotEmpty) const SizedBox(height: 8),
                  AcpContentBlockView(
                    id: '${item.id}:content:$i',
                    block: item.contentBlocks[i],
                    isSafeLink: widget.isSafeLink ?? _fallbackSafeLink,
                    onOpenLink: widget.onOpenLink,
                    imageBuilder: widget.imageBuilder,
                    fullDetails: widget.fullDetails,
                  ),
                ],
                if (item.tool.arguments.trim().isNotEmpty) ...[
                  if (item.contentBlocks.isNotEmpty) const SizedBox(height: 8),
                  StudioCodeBlock(
                    text: item.tool.arguments,
                    language: context.l10n.timelineToolArguments,
                    horizontalScroll: false,
                  ),
                ],
                if (item.tool.output.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  StudioCodeBlock(
                    text: item.tool.output,
                    language: context.l10n.timelineToolOutput,
                    horizontalScroll: false,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

bool _fallbackSafeLink(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}
