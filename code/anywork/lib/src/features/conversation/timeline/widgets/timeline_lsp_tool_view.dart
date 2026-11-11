import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/studio_l10n.dart';
import '../state/lsp_presentation.dart';
import '../state/tool_presentation.dart';
import 'timeline_markdown.dart';
import 'timeline_tool_blocks.dart';

typedef TimelineLspMarkdownBuilder = Widget Function(String id, String text);

/// 内联路径（`declaredContents == null`）下的 LSP 工具语义卡片入口。
Widget? timelineLspInlineBody(
  TimelineToolPresentation tool, {
  TimelineLspMarkdownBuilder? markdownBuilder,
}) {
  final presentation = parseTimelineLspPresentation(tool);
  if (presentation == null) return null;
  // 无参数工具（capabilities / status）在尚无输出时不渲染空壳卡片，保留错误或运行态。
  switch (presentation) {
    case TimelineLspCapabilitiesPresentation(hasOutput: false):
    case TimelineLspStatusPresentation(hasOutput: false):
      return null;
    case _:
      return TimelineLspToolView(
        itemId: tool.id,
        presentation: presentation,
        markdownBuilder: markdownBuilder,
      );
  }
}

/// 声明内容窗口路径（`TimelineBodyReadIntent`）下的 LSP 工具语义卡片入口。
Widget timelineLspWindowBody(
  TimelineToolPresentation tool,
  String windowText, {
  TimelineLspMarkdownBuilder? markdownBuilder,
}) {
  final presentation = parseTimelineLspPresentation(
    tool,
    outputOverride: windowText,
  );
  if (presentation == null) {
    return Text(windowText, softWrap: true);
  }
  return TimelineLspToolView(
    itemId: tool.id,
    presentation: presentation,
    markdownBuilder: markdownBuilder,
  );
}

/// 操作枚举的本地化短名称。
String timelineLspOperationLabel(
  AppLocalizations l10n,
  TimelineLspOperation operation, {
  String? raw,
}) => switch (operation) {
  TimelineLspOperation.goToDefinition => l10n.timelineLspOpDefinition,
  TimelineLspOperation.goToImplementation => l10n.timelineLspOpImplementation,
  TimelineLspOperation.findReferences => l10n.timelineLspOpReferences,
  TimelineLspOperation.hover => l10n.timelineLspOpHover,
  TimelineLspOperation.documentSymbol => l10n.timelineLspOpDocumentSymbol,
  TimelineLspOperation.workspaceSymbol => l10n.timelineLspOpWorkspaceSymbol,
  TimelineLspOperation.prepareCallHierarchy =>
    l10n.timelineLspOpPrepareCallHierarchy,
  TimelineLspOperation.incomingCalls => l10n.timelineLspOpIncomingCalls,
  TimelineLspOperation.outgoingCalls => l10n.timelineLspOpOutgoingCalls,
  TimelineLspOperation.diagnostics => l10n.timelineLspOpDiagnostics,
  TimelineLspOperation.unknown =>
    (raw != null && raw.trim().isNotEmpty)
        ? raw.trim()
        : l10n.timelineLspQueryTitle,
};

IconData _lspOpIcon(TimelineLspOperation operation) => switch (operation) {
  TimelineLspOperation.goToDefinition => Icons.my_location_outlined,
  TimelineLspOperation.goToImplementation => Icons.layers_outlined,
  TimelineLspOperation.findReferences => Icons.hub_outlined,
  TimelineLspOperation.hover => Icons.chat_bubble_outline,
  TimelineLspOperation.documentSymbol => Icons.account_tree_outlined,
  TimelineLspOperation.workspaceSymbol => Icons.manage_search,
  TimelineLspOperation.prepareCallHierarchy => Icons.adjust,
  TimelineLspOperation.incomingCalls => Icons.call_received,
  TimelineLspOperation.outgoingCalls => Icons.call_made,
  TimelineLspOperation.diagnostics => Icons.rule_outlined,
  TimelineLspOperation.unknown => Icons.code,
};

/// 时间线 LSP 系列工具展开区的统一语义卡片组件。
class TimelineLspToolView extends StatelessWidget {
  const TimelineLspToolView({
    super.key,
    required this.itemId,
    required this.presentation,
    this.markdownBuilder,
  });

  final String itemId;
  final TimelineLspPresentation presentation;
  final TimelineLspMarkdownBuilder? markdownBuilder;

  @override
  Widget build(BuildContext context) {
    final content = switch (presentation) {
      final TimelineLspQueryPresentation query => _LspQueryCard(
        itemId: itemId,
        query: query,
        markdownBuilder: markdownBuilder ?? _defaultSafeMarkdown,
      ),
      final TimelineLspCapabilitiesPresentation capabilities =>
        _LspCapabilitiesCard(capabilities: capabilities),
      final TimelineLspStatusPresentation status => _LspStatusCard(
        status: status,
      ),
    };
    return SelectionContainer.maybeOf(context) == null
        ? SelectionArea(child: content)
        : content;
  }

  static Widget _defaultSafeMarkdown(String id, String text) =>
      TimelineMarkdown(
        id: id,
        text: text,
        onLink: (_) {},
        isSafeLink: (_) => false,
        imageBuilder: (_, _) => const SizedBox.shrink(),
      );
}

class _LspSurfaceCard extends StatelessWidget {
  const _LspSurfaceCard({required this.header, this.body, this.omittedBytes});

  final Widget header;
  final Widget? body;
  final int? omittedBytes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasFooter = omittedBytes != null;
    final hasLowerSection = body != null || hasFooter;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(StudioRadii.sm)),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: colors.surfaceContainer.withValues(alpha: 0.6),
              border: hasLowerSection
                  ? Border(bottom: BorderSide(color: colors.outlineVariant))
                  : null,
            ),
            child: header,
          ),
          ?body,
          if (omittedBytes case final bytes?)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: StudioTone.warning
                    .background(context)
                    .withValues(alpha: 0.65),
                border: body != null
                    ? Border(top: BorderSide(color: colors.outlineVariant))
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.content_cut_outlined,
                    size: 13,
                    color: StudioTone.warning.foreground(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.l10n.timelineLspPreviewTruncated(
                        timelineFormatBytes(bytes),
                      ),
                      style: context.text.labelSmall?.copyWith(
                        color: StudioTone.warning.foreground(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LspBadge extends StatelessWidget {
  const _LspBadge({
    required this.label,
    this.icon,
    this.tone = StudioTone.neutral,
    this.monospace = false,
    this.outlined = false,
  });

  final String label;
  final IconData? icon;
  final StudioTone tone;
  final bool monospace;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final fg = tone.foreground(context);
    final bg = outlined
        ? context.colors.surfaceContainerLowest
        : tone.background(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(Radius.circular(StudioRadii.xs)),
        border: outlined
            ? Border.all(
                color: context.colors.outlineVariant.withValues(alpha: 0.85),
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: context.text.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
                fontFamily: monospace ? studioCodeFontFamily : null,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LspSymbolKindPill extends StatelessWidget {
  const _LspSymbolKindPill({required this.kind});

  final int kind;

  @override
  Widget build(BuildContext context) {
    final spec = timelineLspSymbolKindSpec(kind);
    final (fg, bg) = switch (spec.tone) {
      TimelineLspSymbolBadgeTone.typeLike => (
        StudioTone.brand.foreground(context),
        StudioTone.brand.background(context),
      ),
      TimelineLspSymbolBadgeTone.callable => (
        context.statusColors.activeIndicator,
        context.statusColors.activeIndicator.withValues(alpha: 0.13),
      ),
      TimelineLspSymbolBadgeTone.container => (
        StudioTone.warning.foreground(context),
        StudioTone.warning.background(context),
      ),
      TimelineLspSymbolBadgeTone.member => (
        context.colors.onSurfaceVariant,
        context.colors.surfaceContainerLowest,
      ),
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 42),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        border: spec.tone == TimelineLspSymbolBadgeTone.member
            ? Border.all(
                color: context.colors.outlineVariant.withValues(alpha: 0.7),
              )
            : null,
      ),
      child: Text(
        spec.badge,
        style: context.text.labelSmall?.copyWith(
          color: fg,
          fontFamily: studioCodeFontFamily,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}

class _LspQueryCard extends StatelessWidget {
  const _LspQueryCard({
    required this.itemId,
    required this.query,
    required this.markdownBuilder,
  });

  final String itemId;
  final TimelineLspQueryPresentation query;
  final TimelineLspMarkdownBuilder markdownBuilder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final opLabel = timelineLspOperationLabel(
      l10n,
      query.operation,
      raw: query.rawOperation,
    );
    final countSummary = _countSummaryLabel(l10n);
    final hasTargetRow =
        query.filePath != null ||
        query.query != null ||
        query.maxResults != null;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _LspBadge(
              icon: _lspOpIcon(query.operation),
              label: opLabel,
              tone: StudioTone.brand,
            ),
            if (query.languageId case final lang?)
              _LspBadge(label: lang, monospace: true, outlined: true),
            if (query.serverId case final server?)
              _LspBadge(
                icon: Icons.dns_outlined,
                label: server,
                monospace: true,
                outlined: true,
              ),
            if (countSummary != null)
              _LspBadge(
                label: countSummary,
                tone: StudioTone.neutral,
                outlined: true,
              ),
          ],
        ),
        if (hasTargetRow) ...[
          const SizedBox(height: 6),
          _LspQueryTargetRow(query: query),
        ],
      ],
    );

    final body = switch (query.body) {
      TimelineLspNoOutputBody() => null,
      TimelineLspEmptyQueryBody() => _LspEmptyQueryView(
        operation: query.operation,
      ),
      TimelineLspLocationsBody(:final groups) => _LspLocationsView(
        groups: groups,
      ),
      TimelineLspHoverBody(:final markdown) => _LspHoverView(
        itemId: itemId,
        markdown: markdown,
        markdownBuilder: markdownBuilder,
      ),
      TimelineLspDocumentSymbolsBody(:final items) => _LspDocumentSymbolsView(
        items: items,
      ),
      TimelineLspWorkspaceSymbolsBody(:final items, :final omittedCount) =>
        _LspWorkspaceSymbolsView(items: items, omittedCount: omittedCount),
      TimelineLspCallHierarchyBody(:final items) => _LspCallHierarchyView(
        operation: query.operation,
        items: items,
      ),
      TimelineLspDiagnosticsBody(:final items, :final omittedCount) =>
        _LspDiagnosticsView(items: items, omittedCount: omittedCount),
      TimelineLspRawTextBody(:final text) => _LspPlainFallbackView(text: text),
    };

    return _LspSurfaceCard(
      header: header,
      body: body,
      omittedBytes: query.previewOmittedBytes,
    );
  }

  String? _countSummaryLabel(AppLocalizations l10n) {
    final count = query.resultCount;
    if (count == null || count <= 0) return null;
    if (query.operation == TimelineLspOperation.hover) return null;
    final files = query.fileCount;
    if (files != null && files > 0) {
      return l10n.timelineLspResultCountFiles(count, files);
    }
    return l10n.timelineLspResultCountOnly(count);
  }
}

class _LspQueryTargetRow extends StatelessWidget {
  const _LspQueryTargetRow({required this.query});

  final TimelineLspQueryPresentation query;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final coordinate = _coordinateLabel(query.line, query.character);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (query.filePath case final path?)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.description_outlined,
                size: 13.5,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  path,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.onSurface,
                    fontFamily: studioCodeFontFamily,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (coordinate != null) ...[
                const SizedBox(width: 5),
                _CoordinateChip(label: coordinate),
              ],
            ],
          ),
        if (query.query case final keyword?)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 13.5, color: colors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '${context.l10n.timelineLspQueryKeywordLabel}:',
                style: context.text.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(StudioRadii.xs),
                    ),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Text(
                    keyword,
                    style: context.text.labelSmall?.copyWith(
                      color: colors.onSurface,
                      fontFamily: studioCodeFontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        if (query.maxResults case final limit?)
          Text(
            context.l10n.timelineLspMaxResultsLimit(limit),
            style: context.text.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  static String? _coordinateLabel(int? line, int? character) {
    if (line == null || line <= 0) return null;
    if (character == null || character <= 0) return 'L$line';
    return 'L$line:$character';
  }
}

class _CoordinateChip extends StatelessWidget {
  const _CoordinateChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.9)),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: colors.primary,
          fontFamily: studioCodeFontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 11,
          height: 1.2,
        ),
      ),
    );
  }
}

class _LspEmptyQueryView extends StatelessWidget {
  const _LspEmptyQueryView({required this.operation});

  final TimelineLspOperation operation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (operation == TimelineLspOperation.diagnostics) {
      final fg = StudioTone.success.foreground(context);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 15, color: fg),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                l10n.timelineLspNoDiagnosticsClean,
                style: context.text.bodySmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final message = switch (operation) {
      TimelineLspOperation.goToDefinition => l10n.timelineLspNoDefinitions,
      TimelineLspOperation.goToImplementation =>
        l10n.timelineLspNoImplementations,
      TimelineLspOperation.findReferences => l10n.timelineLspNoReferences,
      TimelineLspOperation.hover => l10n.timelineLspNoHover,
      TimelineLspOperation.documentSymbol => l10n.timelineLspNoDocumentSymbols,
      TimelineLspOperation.workspaceSymbol =>
        l10n.timelineLspNoWorkspaceSymbols,
      TimelineLspOperation.prepareCallHierarchy ||
      TimelineLspOperation.incomingCalls ||
      TimelineLspOperation.outgoingCalls => l10n.timelineLspNoCallHierarchy,
      TimelineLspOperation.diagnostics => l10n.timelineLspNoDiagnosticsClean,
      TimelineLspOperation.unknown => l10n.timelineLspNoDefinitions,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.remove_circle_outline,
            size: 14,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LspLocationsView extends StatelessWidget {
  const _LspLocationsView({required this.groups});

  final List<TimelineLspFileLocations> groups;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: colors.outlineVariant.withValues(alpha: 0.65),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _buildGroup(context, groups[i]),
          ),
        ],
      ],
    );
  }

  Widget _buildGroup(BuildContext context, TimelineLspFileLocations group) {
    final colors = context.colors;
    final chips = [
      for (final pos in group.positions)
        _CoordinateChip(label: 'L${pos.line}:${pos.character}'),
    ];
    if (group.positions.length == 1) {
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  group.path,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.onSurface,
                    fontFamily: studioCodeFontFamily,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          chips.first,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 14,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                group.path,
                style: context.text.bodySmall?.copyWith(
                  color: colors.onSurface,
                  fontFamily: studioCodeFontFamily,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _LspBadge(
              label: '${group.positions.length}',
              monospace: true,
              outlined: true,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 20),
          child: Wrap(spacing: 6, runSpacing: 5, children: chips),
        ),
      ],
    );
  }
}

class _LspHoverView extends StatelessWidget {
  const _LspHoverView({
    required this.itemId,
    required this.markdown,
    required this.markdownBuilder,
  });

  final String itemId;
  final String markdown;
  final TimelineLspMarkdownBuilder markdownBuilder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: markdownBuilder('$itemId:lsp-hover', markdown),
    );
  }
}

class _LspDocumentSymbolsView extends StatelessWidget {
  const _LspDocumentSymbolsView({required this.items});

  final List<TimelineLspDocumentSymbolItem> items;

  @override
  Widget build(BuildContext context) {
    final guideColor = context.colors.outlineVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
              child: _symbolRow(context, items[i], guideColor),
            ),
        ],
      ),
    );
  }

  Widget _symbolRow(
    BuildContext context,
    TimelineLspDocumentSymbolItem item,
    Color guideColor,
  ) {
    final clampedDepth = item.depth.clamp(0, 6);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var level = 0; level < clampedDepth; level++)
            Container(
              width: 14,
              alignment: AlignmentDirectional.centerStart,
              margin: const EdgeInsetsDirectional.only(start: 4),
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(color: guideColor, width: 1),
                ),
              ),
            ),
          _LspSymbolKindPill(kind: item.kind),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              item.name,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurface,
                fontFamily: studioCodeFontFamily,
                fontWeight: item.depth == 0 ? FontWeight.w600 : FontWeight.w400,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LspWorkspaceSymbolsView extends StatelessWidget {
  const _LspWorkspaceSymbolsView({required this.items, this.omittedCount});

  final List<TimelineLspWorkspaceSymbolItem> items;
  final int? omittedCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: colors.outlineVariant.withValues(alpha: 0.55),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LspSymbolKindPill(kind: items[i].kind),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        items[i].name,
                        style: context.text.bodySmall?.copyWith(
                          color: colors.onSurface,
                          fontFamily: studioCodeFontFamily,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (items[i].path.isNotEmpty)
                  Text(
                    items[i].path,
                    style: context.text.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFamily: studioCodeFontFamily,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (omittedCount case final omitted? when omitted > 0)
          _OmittedItemsFooter(count: omitted),
      ],
    );
  }
}

class _LspCallHierarchyView extends StatelessWidget {
  const _LspCallHierarchyView({required this.operation, required this.items});

  final TimelineLspOperation operation;
  final List<TimelineLspCallItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final icon = switch (operation) {
      TimelineLspOperation.incomingCalls => Icons.call_received,
      TimelineLspOperation.outgoingCalls => Icons.call_made,
      _ => Icons.adjust,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: colors.outlineVariant.withValues(alpha: 0.55),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 14,
                      color: context.statusColors.activeIndicator,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        items[i].name,
                        style: context.text.bodySmall?.copyWith(
                          color: colors.onSurface,
                          fontFamily: studioCodeFontFamily,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (items[i].path.isNotEmpty)
                  Text(
                    items[i].path,
                    style: context.text.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFamily: studioCodeFontFamily,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LspDiagnosticsView extends StatelessWidget {
  const _LspDiagnosticsView({required this.items, this.omittedCount});

  final List<TimelineLspDiagnosticItem> items;
  final int? omittedCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = StudioTone.warning.foreground(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: colors.outlineVariant.withValues(alpha: 0.65),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 14, color: accent),
                    Text(
                      items[i].path,
                      style: context.text.labelSmall?.copyWith(
                        color: colors.onSurface,
                        fontFamily: studioCodeFontFamily,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _CoordinateChip(
                      label: 'L${items[i].line}:${items[i].character}',
                    ),
                    if (items[i].code case final code? when code.isNotEmpty)
                      _LspBadge(label: code, monospace: true, outlined: true),
                    if (items[i].source case final source?
                        when source.isNotEmpty)
                      Text(
                        source,
                        style: context.text.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 20),
                  child: Text(
                    items[i].message,
                    style: context.text.bodySmall?.copyWith(
                      color: colors.onSurface,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (omittedCount case final omitted? when omitted > 0)
          _OmittedItemsFooter(count: omitted),
      ],
    );
  }
}

class _OmittedItemsFooter extends StatelessWidget {
  const _OmittedItemsFooter({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.65)),
        ),
      ),
      child: Text(
        context.l10n.timelineLspOmittedItems(count),
        style: context.text.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LspPlainFallbackView extends StatelessWidget {
  const _LspPlainFallbackView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurface,
          fontFamily: studioCodeFontFamily,
          height: 1.5,
        ),
      ),
    );
  }
}

class _LspCapabilitiesCard extends StatelessWidget {
  const _LspCapabilitiesCard({required this.capabilities});

  final TimelineLspCapabilitiesPresentation capabilities;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final header = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _LspBadge(
          icon: Icons.extension_outlined,
          label: l10n.timelineLspCapabilitiesTitle,
          tone: StudioTone.brand,
        ),
        if (capabilities.fallbackText == null)
          _LspBadge(
            label: l10n.timelineLspCapabilitiesSummary(
              capabilities.servers.length,
            ),
            outlined: true,
          ),
      ],
    );

    final Widget body;
    if (capabilities.fallbackText case final fallback?) {
      body = _LspPlainFallbackView(text: fallback);
    } else if (capabilities.servers.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          l10n.timelineLspCapabilitiesEmpty,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < capabilities.servers.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: context.colors.outlineVariant.withValues(alpha: 0.65),
              ),
            _CapabilityServerSection(server: capabilities.servers[i]),
          ],
        ],
      );
    }

    return _LspSurfaceCard(
      header: header,
      body: body,
      omittedBytes: capabilities.previewOmittedBytes,
    );
  }
}

class _CapabilityServerSection extends StatelessWidget {
  const _CapabilityServerSection({required this.server});

  final TimelineLspCapabilityServer server;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                server.displayName,
                style: context.text.bodySmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (server.id.isNotEmpty && server.id != server.displayName)
                Text(
                  server.id,
                  style: context.text.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFamily: studioCodeFontFamily,
                  ),
                ),
              _LspBadge(
                icon: server.ready ? Icons.check_circle_outline : null,
                label: server.ready
                    ? l10n.settingsLspPhaseReady
                    : _availabilityLabel(l10n, server.availability),
                tone: server.ready ? StudioTone.success : StudioTone.neutral,
              ),
              for (final lang in server.languageIds)
                _LspBadge(label: lang, monospace: true, outlined: true),
            ],
          ),
          if (server.operations.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final op in server.operations)
                  _LspBadge(
                    icon: _lspOpIcon(op.operation),
                    label: timelineLspOperationLabel(
                      l10n,
                      op.operation,
                      raw: op.raw,
                    ),
                    outlined: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LspStatusCard extends StatelessWidget {
  const _LspStatusCard({required this.status});

  final TimelineLspStatusPresentation status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final readyCount = status.servers
        .where(
          (server) =>
              server.phase == 'ready' && server.availability == 'available',
        )
        .length;
    final configDir = _relativeWorkspacePath(
      status.configurationDirectory,
      status.workspaceRoot,
    );

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _LspBadge(
              icon: Icons.dns_outlined,
              label: l10n.timelineLspStatusTitle,
              tone: StudioTone.brand,
            ),
            if (status.fallbackText == null && status.servers.isNotEmpty)
              _LspBadge(
                label: l10n.timelineLspStatusSummary(
                  readyCount,
                  status.servers.length,
                ),
                tone: readyCount == status.servers.length
                    ? StudioTone.success
                    : StudioTone.neutral,
                outlined: readyCount != status.servers.length,
              ),
            if (configDir != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_open_outlined,
                    size: 13,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      configDir,
                      style: context.text.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFamily: studioCodeFontFamily,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );

    final Widget body;
    if (status.fallbackText case final fallback?) {
      body = _LspPlainFallbackView(text: fallback);
    } else if (status.servers.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          l10n.timelineLspStatusEmpty,
          style: context.text.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < status.servers.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.65),
              ),
            _StatusServerSection(
              server: status.servers[i],
              workspaceRoot: status.workspaceRoot,
            ),
          ],
        ],
      );
    }

    return _LspSurfaceCard(
      header: header,
      body: body,
      omittedBytes: status.previewOmittedBytes,
    );
  }
}

class _StatusServerSection extends StatelessWidget {
  const _StatusServerSection({
    required this.server,
    required this.workspaceRoot,
  });

  final TimelineLspServerStatusItem server;
  final String? workspaceRoot;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final (statusLabel, statusTone, statusIcon) = _serverStatusBadge(
      l10n,
      server,
    );
    final configPath = _relativeWorkspacePath(
      server.configurationPath,
      workspaceRoot,
    );
    final activeActivity = server.activity != 'idle';
    final activityDetail = [
      if (server.activityTitle case final title? when title.isNotEmpty) title,
      if (server.activityMessage case final msg? when msg.isNotEmpty) msg,
    ].join(' · ');
    final infoMessage =
        (server.message != null && server.message != server.lastError)
        ? server.message
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                server.displayName,
                style: context.text.bodySmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (server.id.isNotEmpty && server.id != server.displayName)
                Text(
                  server.id,
                  style: context.text.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFamily: studioCodeFontFamily,
                  ),
                ),
              _LspBadge(icon: statusIcon, label: statusLabel, tone: statusTone),
              for (final lang in server.languageIds)
                _LspBadge(label: lang, monospace: true, outlined: true),
            ],
          ),
          if (activeActivity) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLowest,
                borderRadius: const BorderRadius.all(
                  Radius.circular(StudioRadii.xs),
                ),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            server.activity == 'indexing'
                                ? Icons.manage_search_outlined
                                : Icons.sync,
                            size: 13.5,
                            color: context.statusColors.activeIndicator,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _activityLabel(l10n, server),
                            style: context.text.labelSmall?.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (activityDetail.isNotEmpty)
                        Text(
                          activityDetail,
                          style: context.text.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  if (server.activityPercentage case final pct?) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: const BorderRadius.all(
                        Radius.circular(StudioRadii.pill),
                      ),
                      child: LinearProgressIndicator(
                        value: (pct.clamp(0, 100)) / 100.0,
                        minHeight: 3,
                        color: context.statusColors.activeIndicator,
                        backgroundColor: colors.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.tune_outlined,
                size: 12.5,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  configPath ?? l10n.settingsLspConfigurationMissing,
                  style: context.text.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFamily: configPath != null
                        ? studioCodeFontFamily
                        : null,
                  ),
                ),
              ),
            ],
          ),
          if (infoMessage != null) ...[
            const SizedBox(height: 5),
            Text(
              infoMessage,
              style: context.text.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (server.lastError case final error? when error.isNotEmpty) ...[
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: StudioTone.error
                    .background(context)
                    .withValues(alpha: 0.65),
                borderRadius: const BorderRadius.all(
                  Radius.circular(StudioRadii.xs),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1.5),
                    child: Icon(
                      Icons.error_outline,
                      size: 14,
                      color: StudioTone.error.foreground(context),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error,
                      style: context.text.bodySmall?.copyWith(
                        color: StudioTone.error.foreground(context),
                        fontFamily: studioCodeFontFamily,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static (String, StudioTone, IconData) _serverStatusBadge(
    AppLocalizations l10n,
    TimelineLspServerStatusItem server,
  ) {
    if (server.availability == 'missingCommand') {
      return (
        l10n.timelineLspStateMissingCommand,
        StudioTone.error,
        Icons.error_outline,
      );
    }
    if (server.phase == 'failed' || server.availability == 'unavailable') {
      return (
        server.phase == 'failed'
            ? l10n.settingsLspPhaseFailed
            : l10n.settingsStateUnavailable,
        StudioTone.error,
        Icons.error_outline,
      );
    }
    if (server.phase == 'disabled' || server.availability == 'disabled') {
      return (
        l10n.settingsLspPhaseDisabled,
        StudioTone.neutral,
        Icons.block_outlined,
      );
    }
    if (server.phase == 'stopped') {
      return (
        l10n.settingsLspPhaseStopped,
        StudioTone.neutral,
        Icons.stop_circle_outlined,
      );
    }
    if (server.phase == 'ready' && server.availability == 'available') {
      return (
        l10n.settingsLspPhaseReady,
        StudioTone.success,
        Icons.check_circle_outline,
      );
    }
    final phaseLabel = switch (server.phase) {
      'loading' => l10n.settingsLspPhaseLoading,
      'probing' => l10n.settingsLspPhaseProbing,
      'starting' => l10n.settingsLspPhaseStarting,
      'initializing' => l10n.settingsLspPhaseInitializing,
      _ => _availabilityLabel(l10n, server.availability),
    };
    return (phaseLabel, StudioTone.active, Icons.sync);
  }

  static String _activityLabel(
    AppLocalizations l10n,
    TimelineLspServerStatusItem server,
  ) {
    final base = switch (server.activity) {
      'indexing' => l10n.settingsLspActivityIndexing,
      'busy' => l10n.settingsLspActivityBusy,
      _ => l10n.settingsLspActivityIdle,
    };
    final pct = server.activityPercentage;
    if (pct == null) return base;
    return '$base · ${l10n.statusLspActivityPercentage(pct)}';
  }
}

String _availabilityLabel(AppLocalizations l10n, String availability) =>
    switch (availability) {
      'checking' => l10n.settingsStateChecking,
      'available' => l10n.settingsStateAvailable,
      'unavailable' => l10n.settingsStateUnavailable,
      'missingCommand' => l10n.timelineLspStateMissingCommand,
      'disabled' => l10n.settingsStateDisabled,
      _ => availability,
    };

String? _relativeWorkspacePath(String? path, String? workspaceRoot) {
  if (path == null || path.trim().isEmpty) return null;
  final trimmedPath = path.trim();
  if (workspaceRoot == null || workspaceRoot.trim().isEmpty) return trimmedPath;
  final root = workspaceRoot.trim().replaceAll(RegExp(r'[/\\]+$'), '');
  if (root.isEmpty) return trimmedPath;
  if (trimmedPath.startsWith('$root/') || trimmedPath.startsWith('$root\\')) {
    final relative = trimmedPath.substring(root.length + 1);
    return relative.isEmpty ? trimmedPath : relative;
  }
  return trimmedPath;
}
