import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../app/theme/studio_tokens.dart';
import '../../../../../../l10n/app_localizations.dart';
import '../../../../../../l10n/studio_l10n.dart';
import '../../../../../../shared/studio_chrome.dart';
import '../../../state/patch_presentation.dart';
import '../../../state/tool_presentation.dart';
import '../../../widgets/timeline_activity_row.dart';
import '../../../widgets/timeline_patch_diff_view.dart';
import '../../support/tool_detail_values.dart';
import '../../tool_item_adapter.dart';
import 'acp_tool_details_scope.dart';

/// Mapping from ACP protocol `ToolKind` strings to uniform icons and
/// localized category labels.
IconData acpToolKindIcon(String? kind) => switch (kind) {
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

String? acpToolKindLocalizedLabel(AppLocalizations l10n, String? kind) =>
    switch (kind) {
      'read' => l10n.acpToolKindRead,
      'edit' => l10n.acpToolKindEdit,
      'delete' => l10n.acpToolKindDelete,
      'move' => l10n.acpToolKindMove,
      'search' => l10n.acpToolKindSearch,
      'execute' => l10n.acpToolKindExecute,
      'think' => l10n.acpToolKindThink,
      'fetch' => l10n.acpToolKindFetch,
      'switchMode' => l10n.acpToolKindSwitchMode,
      'other' => l10n.acpToolKindOther,
      _ => null,
    };

/// Adapter for ACP protocol peer-reported tool calls (`acp.tool` / `acp.tool.*`).
///
/// Intentionally does NOT extend [StructuredTimelineToolAdapter]: ACP `rawInput`
/// and `rawOutput` are peer reports that may omit output, carry plain text,
/// or wrap structured fields without Native's strict JSON schema guarantees.
class AcpToolItem extends TimelineToolItemAdapter {
  const AcpToolItem();

  static const String contractPrefix = 'acp.tool';

  @override
  String get id => contractPrefix;

  @override
  TimelineToolMatcher get matcher =>
      const TimelineToolMatcher.contractPrefix(contractPrefix);

  @override
  TimelineToolBodyPolicy get bodyPolicy => const TimelineToolBodyPolicy(
    requiresJsonObjectArguments: false,
    readsStructuredOutput: false,
  );

  String? _resolveKind(
    AcpToolDetailsScope? scope,
    TimelineToolPresentation item,
  ) {
    final fromScope = scope?.kind?.trim();
    if (fromScope != null && fromScope.isNotEmpty) return fromScope;
    final contract = item.presentationContract;
    if (contract.startsWith('$contractPrefix.')) {
      final suffix = contract.substring(contractPrefix.length + 1).trim();
      if (suffix.isNotEmpty) return suffix;
    }
    return null;
  }

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) {
    final trimmed = item.name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final kind = _resolveKind(null, item);
    return acpToolKindLocalizedLabel(l10n, kind) ?? l10n.acpToolKindOther;
  }

  @override
  TimelineToolRowSummary buildRowSummary(TimelineToolItemContext context) {
    final l10n = context.l10n;
    final item = context.item;
    final scope = AcpToolDetailsScope.maybeOf(context.buildContext);
    final kind = _resolveKind(scope, item);
    final kindLabel = acpToolKindLocalizedLabel(l10n, kind);
    final label = item.name.trim().isNotEmpty
        ? item.name.trim()
        : (kindLabel ?? l10n.acpToolKindOther);

    final active =
        item.statusString == 'running' ||
        item.statusString == 'pending' ||
        item.statusString == 'inProgress';
    final isIssue = item.statusString == 'failed';

    final String? meta;
    if (isIssue) {
      meta = kindLabel == null
          ? l10n.toolStatusFailed
          : '$kindLabel · ${l10n.toolStatusFailed}';
    } else {
      meta = kindLabel;
    }

    final rawName = scope?.rawName?.trim();
    final locationSummary = scope == null || scope.locations.isEmpty
        ? null
        : scope.locations.first;
    final tooltip = {
      label,
      if (rawName != null && rawName.isNotEmpty && rawName != label) rawName,
      ?locationSummary,
      ?meta,
    }.join('\n');

    final cardKey =
        scope?.cardKey ??
        (item.toolCallId.trim().isNotEmpty
            ? ValueKey('acp-tool-${item.toolCallId}')
            : null);

    return TimelineToolRowSummary(
      icon: TimelineToolIcon.data(
        acpToolKindIcon(kind),
        activeIndicatorStyle: TimelineActivityIndicatorStyle.circularProgress,
        preserveWhenIssue: true,
      ),
      label: label,
      tooltip: tooltip,
      meta: meta,
      active: active,
      isIssue: isIssue,
      cardKey: cardKey,
      disclosureKey: ValueKey('timeline-tool-details:${item.id}'),
    );
  }

  @override
  List<Widget> buildExpandedChildren(
    TimelineToolItemContext context,
    TimelineToolExpandedSlots slots,
  ) => slots.standardPanel == null ? const [] : [slots.standardPanel!];

  @override
  Widget? buildInlineBody(
    TimelineToolItemContext context, {
    ToolAcceptanceProjection? acceptance,
  }) {
    final buildContext = context.buildContext;
    final l10n = context.l10n;
    final item = context.item;
    final scope = AcpToolDetailsScope.maybeOf(buildContext);
    final locations = scope?.locations ?? const <String>[];
    final terminals = scope?.terminals ?? const <String>[];
    final diffs = scope?.diffs ?? const <TimelinePatchDocument>[];
    final contentBlocks =
        scope?.contentBlocksBuilder?.call(buildContext) ?? const <Widget>[];
    final hasArguments = item.arguments.trim().isNotEmpty;
    final hasOutput = item.output.trim().isNotEmpty;

    if (locations.isEmpty &&
        terminals.isEmpty &&
        diffs.isEmpty &&
        contentBlocks.isEmpty &&
        !hasArguments &&
        !hasOutput) {
      return null;
    }

    final metaStyle = buildContext.text.bodySmall?.copyWith(
      color: buildContext.colors.onSurfaceVariant,
      fontFamily: studioCodeFontFamily,
    );
    final nestedCardColor = buildContext.colors.surfaceContainerLowest;
    final nestedBorder = Border.all(color: buildContext.colors.outlineVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (locations.isNotEmpty || terminals.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final location in locations)
                _AcpToolMetaRow(
                  icon: Icons.place_outlined,
                  text: location,
                  style: metaStyle,
                  copyText: location,
                ),
              for (final terminal in terminals)
                _AcpToolMetaRow(
                  icon: Icons.terminal_rounded,
                  text: l10n.acpToolTerminalPrefix(terminal),
                  style: metaStyle,
                ),
            ],
          ),
        for (var i = 0; i < diffs.length; i++) ...[
          if (i > 0 || locations.isNotEmpty || terminals.isNotEmpty)
            const SizedBox(height: 8),
          TimelinePatchDiffView(
            document: diffs[i],
            softWrap: true,
            margin: EdgeInsets.zero,
            backgroundColor: nestedCardColor,
            border: nestedBorder,
          ),
        ],
        for (var i = 0; i < contentBlocks.length; i++) ...[
          if (i > 0 ||
              locations.isNotEmpty ||
              terminals.isNotEmpty ||
              diffs.isNotEmpty)
            const SizedBox(height: 8),
          contentBlocks[i],
        ],
        if (hasArguments) ...[
          if (locations.isNotEmpty ||
              terminals.isNotEmpty ||
              diffs.isNotEmpty ||
              contentBlocks.isNotEmpty)
            const SizedBox(height: 8),
          StudioCodeBlock(
            text: item.arguments,
            language: l10n.timelineToolArguments,
            horizontalScroll: false,
            backgroundColor: nestedCardColor,
          ),
        ],
        if (hasOutput) ...[
          if (locations.isNotEmpty ||
              terminals.isNotEmpty ||
              diffs.isNotEmpty ||
              contentBlocks.isNotEmpty ||
              hasArguments)
            const SizedBox(height: 8),
          StudioCodeBlock(
            text: item.output,
            language: l10n.timelineToolOutput,
            horizontalScroll: false,
            backgroundColor: nestedCardColor,
          ),
        ],
      ],
    );
  }

  @override
  Widget buildWindowBody(
    TimelineToolItemContext context,
    String windowText, {
    required bool isInput,
    ToolAcceptanceProjection? acceptance,
  }) => StudioCodeBlock(
    text: windowText,
    language: isInput
        ? context.l10n.timelineToolArguments
        : context.l10n.timelineToolOutput,
    horizontalScroll: false,
    backgroundColor: context.buildContext.colors.surfaceContainerLowest,
  );
}

class _AcpToolMetaRow extends StatefulWidget {
  const _AcpToolMetaRow({
    required this.icon,
    required this.text,
    this.style,
    this.copyText,
  });

  final IconData icon;
  final String text;
  final TextStyle? style;
  final String? copyText;

  @override
  State<_AcpToolMetaRow> createState() => _AcpToolMetaRowState();
}

class _AcpToolMetaRowState extends State<_AcpToolMetaRow> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy(String value) {
    unawaited(Clipboard.setData(ClipboardData(text: value)));
    _timer?.cancel();
    setState(() => _copied = true);
    _timer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final copyValue = widget.copyText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              widget.icon,
              size: 13,
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(widget.text, style: widget.style, softWrap: true),
          ),
          if (copyValue != null && copyValue.trim().isNotEmpty)
            Tooltip(
              message: _copied
                  ? l10n.timelineOutcomeCopied
                  : l10n.timelinePatchCopyPath,
              child: InkWell(
                onTap: () => _copy(copyValue),
                borderRadius: const BorderRadius.all(Radius.circular(4)),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    _copied ? Icons.check_rounded : Icons.content_copy_rounded,
                    size: 13,
                    color: _copied
                        ? context.colors.primary
                        : context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
