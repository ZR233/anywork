import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../timeline/widgets/timeline_activity_row.dart';
import '../state/acp_view_state.dart';
import '../widgets/acp_content_block_view.dart';
import '../widgets/acp_tool_card.dart';

/// Pure conversation reading stream for ACP sessions.
///
/// Enforces the `1040px` centered reading column, `680px` warm user message
/// bubbles, `StudioNotice` banners, handshake/ready empty state with capability
/// pills, and a floating "Jump to latest" pill when scrolled away from bottom.
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
  final ScrollController _scrollController = ScrollController();
  bool _showJumpToLatest = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant AcpConversationContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.header.itemCount > oldWidget.header.itemCount &&
        !_showJumpToLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final position = _scrollController.position;
        if (position.maxScrollExtent > position.pixels) {
          _scrollController.jumpTo(position.maxScrollExtent);
        }
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final extentAfter = _scrollController.position.extentAfter;
    final away = extentAfter > 160;
    if (away != _showJumpToLatest) {
      setState(() => _showJumpToLatest = away);
    }
  }

  void _jumpToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
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
      return SelectionArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _EmptySessionState(header: header),
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

    return Stack(
      children: [
        SelectionArea(
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
                        if (notices.isNotEmpty) const SizedBox(height: 12),
                        plan,
                      ],
                      if (header.itemCount > 0) const SizedBox(height: 16),
                    ],
                  ),
                );
              }
              if (showTrailingWelcome && rawIndex == totalCount - 1) {
                return Padding(
                  padding: const EdgeInsets.only(top: 56, bottom: 24),
                  child: Center(child: _EmptySessionState(header: header)),
                );
              }
              final itemIndex = rawIndex - leadingCount;
              return _CenteredReadingConstraint(
                key: ValueKey(
                  AcpViewKeyValues.timelineItem(widget.threadId, itemIndex),
                ),
                child: widget.itemBuilder(context, itemIndex),
              );
            },
          ),
        ),
        if (_showJumpToLatest)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: _jumpToLatest,
                icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                label: Text(context.l10n.timelineJumpToLatest),
              ),
            ),
          ),
      ],
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
            const SizedBox(height: 6),
            Text(
              l10n.acpSessionConnectingSubtitle,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StudioEmptyState(
            icon: Icons.hub_outlined,
            title: l10n.acpSessionReadyEmptyTitle,
            message: l10n.acpSessionReadyEmptySubtitle,
            maxWidth: 420,
          ),
          if (header.capabilities.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final cap in header.capabilities)
                  StudioPill(
                    icon: _capabilityIcon(cap),
                    label: _capabilityLabel(context, cap),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  IconData _capabilityIcon(AcpCapabilityKind cap) => switch (cap) {
    AcpCapabilityKind.image => Icons.image_outlined,
    AcpCapabilityKind.audio => Icons.graphic_eq_rounded,
    AcpCapabilityKind.embeddedContext => Icons.attach_file_rounded,
    AcpCapabilityKind.loadSession => Icons.history_rounded,
    AcpCapabilityKind.resumeSession => Icons.play_circle_outline_rounded,
    AcpCapabilityKind.listSessions => Icons.storage_rounded,
  };

  String _capabilityLabel(BuildContext context, AcpCapabilityKind cap) {
    final l10n = context.l10n;
    return switch (cap) {
      AcpCapabilityKind.image => l10n.acpCapabilityImage,
      AcpCapabilityKind.audio => l10n.acpCapabilityAudio,
      AcpCapabilityKind.embeddedContext => l10n.acpCapabilityEmbeddedContext,
      AcpCapabilityKind.loadSession => l10n.acpCapabilityLoadSession,
      AcpCapabilityKind.resumeSession => l10n.acpCapabilityResumeSession,
      AcpCapabilityKind.listSessions => l10n.acpCapabilityListSessions,
    };
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
  });

  final AcpTimelineItemPresentation item;
  final bool Function(String url)? isSafeLink;
  final ValueChanged<String>? onOpenLink;
  final AcpImageWidgetBuilder? imageBuilder;

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
      final AcpTimelineThoughtItem thought => _ThoughtActivityBlock(
        item: thought,
        isSafeLink: isSafeLink,
        onOpenLink: onOpenLink,
        imageBuilder: imageBuilder,
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
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: child);
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

class _ThoughtActivityBlock extends StatefulWidget {
  const _ThoughtActivityBlock({
    required this.item,
    this.isSafeLink,
    this.onOpenLink,
    this.imageBuilder,
  });

  final AcpTimelineThoughtItem item;
  final bool Function(String url)? isSafeLink;
  final ValueChanged<String>? onOpenLink;
  final AcpImageWidgetBuilder? imageBuilder;

  @override
  State<_ThoughtActivityBlock> createState() => _ThoughtActivityBlockState();
}

class _ThoughtActivityBlockState extends State<_ThoughtActivityBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final summary = widget.item.summary.trim();
    final label = summary.isEmpty
        ? l10n.acpContentThoughtLabel
        : '${l10n.acpContentThoughtLabel} · $summary';
    final expandable = widget.item.blocks.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(StudioRadii.xs),
          onTap: expandable
              ? () => setState(() => _expanded = !_expanded)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: TimelineActivityRow(
              icon: Icons.psychology_outlined,
              label: label,
              active: widget.item.active,
              expanded: expandable && _expanded,
              expandable: expandable,
              tooltip: summary.isEmpty ? l10n.acpContentThoughtLabel : summary,
            ),
          ),
        ),
        if (expandable && _expanded)
          Padding(
            padding: const EdgeInsets.only(
              left: TimelineActivityRow.contentIndent,
              top: 6,
              bottom: 6,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: context.colors.outlineVariant,
                    width: 2,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < widget.item.blocks.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      AcpContentBlockView(
                        id: '${widget.item.id}:$i',
                        block: widget.item.blocks[i],
                        isSafeLink: widget.isSafeLink ?? _defaultSafeLink,
                        onOpenLink: widget.onOpenLink,
                        imageBuilder: widget.imageBuilder,
                        textStyle: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
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
      ) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TimelineActivityRow(
              icon: Icons.compress_rounded,
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

class _AvailableCommandsActivityBlock extends StatefulWidget {
  const _AvailableCommandsActivityBlock({required this.commands});

  final List<({String name, String description})> commands;

  @override
  State<_AvailableCommandsActivityBlock> createState() =>
      _AvailableCommandsActivityBlockState();
}

class _AvailableCommandsActivityBlockState
    extends State<_AvailableCommandsActivityBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final commands = widget.commands;
    final preview = commands.take(4).map((cmd) => '/${cmd.name}').join(' · ');
    final suffix = commands.length > 4 ? ' …' : '';
    final label =
        '${l10n.acpCommandsSummary(commands.length)} · $preview$suffix';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(StudioRadii.xs),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: TimelineActivityRow(
              icon: Icons.terminal_rounded,
              label: label,
              expanded: _expanded,
              expandable: true,
              tooltip: l10n.acpCommandsSummary(commands.length),
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(
              left: TimelineActivityRow.contentIndent,
              top: 6,
              bottom: 4,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: context.colors.outlineVariant,
                    width: 2,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final cmd in commands)
                      StudioCompactChip(
                        icon: Icons.terminal_rounded,
                        label: '/${cmd.name}',
                        tooltip: cmd.description,
                      ),
                  ],
                ),
              ),
            ),
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
