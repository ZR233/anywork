part of 'timeline_lsp_tool_view.dart';

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
