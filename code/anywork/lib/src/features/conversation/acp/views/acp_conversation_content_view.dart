import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../timeline/widgets/timeline_activity_row.dart';
import '../../timeline/widgets/timeline_reasoning_view.dart';
import '../../widgets/latest_scroll.dart';
import '../state/acp_view_state.dart';
import '../widgets/acp_content_block_view.dart';
import '../widgets/acp_tool_card.dart';

/// Pure conversation reading stream for ACP sessions.
class AcpConversationContentView extends StatefulWidget {
  const AcpConversationContentView({
    super.key,
    required this.threadId,
    required this.header,
    required this.itemBuilder,
    this.planCard,
  });

  final String threadId;
  final AcpTimelineHeaderViewState header;
  final IndexedWidgetBuilder itemBuilder;
  final Widget? planCard;

  @override
  State<AcpConversationContentView> createState() =>
      _AcpConversationContentViewState();
}

class _AcpConversationContentViewState
    extends State<AcpConversationContentView> {
  final _scrollController = ScrollController(keepScrollOffset: false);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<Widget> _buildNotices(BuildContext context) {
    final l10n = context.l10n;
    final header = widget.header;
    final notices = <Widget>[];

    if (header.errorMessage case final err?) {
      notices.add(
        StudioNotice(
          icon: Icons.error_outline_rounded,
          title: l10n.acpNoticeErrorTitle,
          message: err,
          tone: StudioNoticeTone.danger,
        ),
      );
    }
    if (header.disconnected) {
      notices.add(
        StudioNotice(
          icon: Icons.link_off_rounded,
          message: l10n.acpNoticeDisconnected,
          tone: StudioNoticeTone.warning,
        ),
      );
    } else if (header.observationEnded) {
      notices.add(
        StudioNotice(
          icon: Icons.info_outline_rounded,
          message: l10n.acpNoticeObservationEnded,
          tone: StudioNoticeTone.neutral,
        ),
      );
    }
    if (header.gapKind case final gap?) {
      notices.add(
        StudioNotice(
          icon: Icons.warning_amber_rounded,
          message: switch (gap) {
            AcpGapKind.windowExceeded => l10n.acpNoticeGapWindowExceeded,
            AcpGapKind.disconnected => l10n.acpNoticeGapDisconnected,
            AcpGapKind.encoding => l10n.acpNoticeGapEncoding,
          },
          tone: StudioNoticeTone.warning,
        ),
      );
    }
    switch (header.historyKind) {
      case AcpHistoryOriginKind.resumedWithoutHistory:
        notices.add(
          StudioNotice(
            icon: Icons.history_toggle_off_rounded,
            message: l10n.acpNoticeResumedWithoutHistory,
            tone: StudioNoticeTone.info,
          ),
        );
      case AcpHistoryOriginKind.residentWithoutObservation:
        notices.add(
          StudioNotice(
            icon: Icons.history_toggle_off_rounded,
            message: l10n.acpNoticeResidentWithoutObservation,
            tone: StudioNoticeTone.info,
          ),
        );
      case AcpHistoryOriginKind.incomplete:
        notices.add(
          StudioNotice(
            icon: Icons.warning_amber_rounded,
            message: l10n.acpNoticeIncompleteHistory,
            tone: StudioNoticeTone.warning,
          ),
        );
      case AcpHistoryOriginKind.loadReplay:
      case AcpHistoryOriginKind.newSession:
      case null:
        break;
    }
    return notices;
  }

  @override
  Widget build(BuildContext context) {
    final header = widget.header;
    final notices = _buildNotices(context);
    final hasLeadingSlot = notices.isNotEmpty || widget.planCard != null;
    final showEmptyCenter =
        header.itemCount == 0 && widget.planCard == null && notices.isEmpty;

    if (showEmptyCenter) {
      return LiveStatusMotionHost(
        child: SelectionArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _EmptySessionState(header: header),
            ),
          ),
        ),
      );
    }

    final leadingCount = hasLeadingSlot ? 1 : 0;
    final showTrailingWelcome =
        header.itemCount > 0 &&
        !header.hasConversationalContent &&
        widget.planCard == null &&
        notices.isEmpty;
    final trailingCount = showTrailingWelcome ? 1 : 0;
    final totalCount = leadingCount + header.itemCount + trailingCount;

    return LiveStatusMotionHost(
      child: LatestScrollScope(
        key: ValueKey(widget.threadId),
        child: Column(
          children: [
            Expanded(
              child: LatestScrollViewport(
                controller: _scrollController,
                child: SelectionArea(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: totalCount,
                    itemBuilder: (context, rawIndex) {
                      if (hasLeadingSlot && rawIndex == 0) {
                        return _CenteredReadingConstraint(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < notices.length; i++) ...[
                                if (i > 0) const SizedBox(height: 8),
                                notices[i],
                              ],
                              if (widget.planCard case final plan?) ...[
                                if (notices.isNotEmpty)
                                  const SizedBox(height: 12),
                                plan,
                              ],
                              if (header.itemCount > 0)
                                const SizedBox(height: 16),
                            ],
                          ),
                        );
                      }
                      if (showTrailingWelcome && rawIndex == totalCount - 1) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 56, bottom: 24),
                          child: Center(
                            child: _EmptySessionState(header: header),
                          ),
                        );
                      }
                      final itemIndex = rawIndex - leadingCount;
                      return _CenteredReadingConstraint(
                        key: ValueKey(
                          AcpViewKeyValues.timelineItem(
                            widget.threadId,
                            itemIndex,
                          ),
                        ),
                        child: widget.itemBuilder(context, itemIndex),
                      );
                    },
                  ),
                ),
              ),
            ),
            const ReturnToLatestButton(),
          ],
        ),
      ),
    );
  }
}

class _CenteredReadingConstraint extends StatelessWidget {
  const _CenteredReadingConstraint({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: StudioLayout.conversationWidth,
        ),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

class _EmptySessionState extends StatelessWidget {
  const _EmptySessionState({required this.header});

  final AcpTimelineHeaderViewState header;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (header.loading && !header.ready) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.acpSessionConnectingTitle,
              style: context.text.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return StudioEmptyState(
      icon: Icons.hub_outlined,
      title: l10n.acpSessionReadyEmptyTitle,
      maxWidth: 420,
    );
  }
}

/// Pure presentation widget for a single ACP timeline entry (user bubble,
/// assistant document prose, collapsible thought track, tool card, or session
/// update row).
class AcpTimelineEntryView extends StatelessWidget {
  const AcpTimelineEntryView({
    super.key,
    required this.item,
    this.isSafeLink,
    this.onOpenLink,
    this.imageBuilder,
    this.padding = const EdgeInsets.only(bottom: 14),
  });

  final AcpTimelineItemPresentation item;
  final bool Function(String url)? isSafeLink;
  final ValueChanged<String>? onOpenLink;
  final AcpImageWidgetBuilder? imageBuilder;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (item case AcpTimelineSessionUpdateItem(
      update: AcpSupersededUpdatePresentation(),
    )) {
      return const SizedBox.shrink();
    }
    final child = switch (item) {
      final AcpTimelineUserMessage user => _UserMessageBubble(
        item: user,
        isSafeLink: isSafeLink,
        onOpenLink: onOpenLink,
        imageBuilder: imageBuilder,
      ),
      final AcpTimelineAssistantMessage assistant => _AssistantProseBlock(
        item: assistant,
        isSafeLink: isSafeLink,
        onOpenLink: onOpenLink,
        imageBuilder: imageBuilder,
      ),
      final AcpTimelineThoughtItem thought => _buildThoughtView(
        context,
        thought,
      ),
      final AcpTimelineToolCallItem tool => AcpToolCard(
        item: tool,
        isSafeLink: isSafeLink,
        onOpenLink: onOpenLink,
        imageBuilder: imageBuilder,
      ),
      final AcpTimelineSessionUpdateItem update => _SessionUpdateBlock(
        item: update,
      ),
    };
    return Padding(padding: padding, child: child);
  }

  Widget _buildThoughtView(BuildContext context, AcpTimelineThoughtItem item) {
    final summary = item.summary.trim().isNotEmpty ? item.summary : null;
    final textStyle = context.text.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
      height: 1.55,
    );
    final body = item.blocks.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < item.blocks.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                AcpContentBlockView(
                  id: '${item.id}:$i',
                  block: item.blocks[i],
                  isSafeLink: isSafeLink ?? _defaultSafeLink,
                  onOpenLink: onOpenLink,
                  imageBuilder: imageBuilder,
                  textStyle: textStyle,
                ),
              ],
            ],
          );
    return TimelineReasoningView(
      summary: summary,
      running: item.active,
      body: body,
    );
  }
}

class _UserMessageBubble extends StatelessWidget {
  const _UserMessageBubble({
    required this.item,
    this.isSafeLink,
    this.onOpenLink,
    this.imageBuilder,
  });

  final AcpTimelineUserMessage item;
  final bool Function(String url)? isSafeLink;
  final ValueChanged<String>? onOpenLink;
  final AcpImageWidgetBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: StudioLayout.conversationPromptWidth,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerHigh,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(6),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < item.blocks.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  AcpContentBlockView(
                    id: '${item.id}:$i',
                    block: item.blocks[i],
                    isSafeLink: isSafeLink ?? _defaultSafeLink,
                    onOpenLink: onOpenLink,
                    imageBuilder: imageBuilder,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantProseBlock extends StatelessWidget {
  const _AssistantProseBlock({
    required this.item,
    this.isSafeLink,
    this.onOpenLink,
    this.imageBuilder,
  });

  final AcpTimelineAssistantMessage item;
  final bool Function(String url)? isSafeLink;
  final ValueChanged<String>? onOpenLink;
  final AcpImageWidgetBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < item.blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          AcpContentBlockView(
            id: '${item.id}:$i',
            block: item.blocks[i],
            isSafeLink: isSafeLink ?? _defaultSafeLink,
            onOpenLink: onOpenLink,
            imageBuilder: imageBuilder,
          ),
        ],
      ],
    );
  }
}

class _SessionUpdateBlock extends StatelessWidget {
  const _SessionUpdateBlock({required this.item});

  final AcpTimelineSessionUpdateItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return switch (item.update) {
      AcpNoticeUpdatePresentation(:final title, :final description) =>
        StudioNotice(
          icon: Icons.info_outline_rounded,
          title: description == null ? null : title,
          message: description ?? title,
          tone: StudioNoticeTone.info,
        ),
      AcpUsageUpdatePresentation(
        :final usedFormatted,
        :final sizeFormatted,
        :final costLabel,
      ) =>
        TimelineActivityRow(
          icon: Icons.data_usage_rounded,
          label: l10n.acpUsageReadout(usedFormatted, sizeFormatted),
          meta: costLabel,
          expandable: false,
        ),
      AcpCompactionUpdatePresentation(
        :final statusLabel,
        :final errorMessage,
        :final inProgress,
      ) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TimelineActivityRow(
              icon: Icons.compress_rounded,
              indicatorStyle: TimelineActivityIndicatorStyle.compactingZip,
              active: inProgress && errorMessage == null,
              label: l10n.acpUpdateCompaction(statusLabel),
              isIssue: errorMessage != null,
              expandable: false,
            ),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(
                  left: TimelineActivityRow.contentIndent,
                  top: 4,
                ),
                child: Text(
                  errorMessage,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
          ],
        ),
      AcpCommandsUpdatePresentation(:final commands) =>
        _AvailableCommandsActivityBlock(commands: commands),
      AcpSessionInfoUpdatePresentation() => TimelineActivityRow(
        icon: Icons.info_outline_rounded,
        label: l10n.acpUpdateSessionInfo,
        expandable: false,
      ),
      AcpSupersededUpdatePresentation() => const SizedBox.shrink(),
      AcpGenericUpdatePresentation() => TimelineActivityRow(
        icon: Icons.sync_rounded,
        label: l10n.acpUpdateGeneric,
        expandable: false,
      ),
    };
  }
}

class _AvailableCommandsActivityBlock extends StatelessWidget {
  const _AvailableCommandsActivityBlock({required this.commands});

  final List<({String name, String description})> commands;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preview = commands.take(4).map((cmd) => '/${cmd.name}').join(' · ');
    final suffix = commands.length > 4 ? ' …' : '';
    final label =
        '${l10n.acpCommandsSummary(commands.length)} · $preview$suffix';

    return TimelineActivityDisclosure(
      childrenPadding: const EdgeInsetsDirectional.only(top: 4, bottom: 4),
      titleBuilder: (context, expanded) => TimelineActivityRow(
        icon: Icons.terminal_rounded,
        label: label,
        expanded: expanded,
        expandable: true,
        tooltip: l10n.acpCommandsSummary(commands.length),
      ),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final cmd in commands)
              Text(
                '/${cmd.name} — ${cmd.description}',
                style: context.text.bodySmall,
              ),
          ],
        ),
      ],
    );
  }
}

bool _defaultSafeLink(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}
