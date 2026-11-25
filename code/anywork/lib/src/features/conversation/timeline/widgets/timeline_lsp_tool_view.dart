import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/studio_l10n.dart';
import '../state/lsp_presentation.dart';
import '../tools/support/tool_detail_values.dart' show timelineFormatBytes;
import 'timeline_markdown.dart';

part 'timeline_lsp_query_view.dart';
part 'timeline_lsp_servers_view.dart';

typedef TimelineLspMarkdownBuilder = Widget Function(String id, String text);

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
