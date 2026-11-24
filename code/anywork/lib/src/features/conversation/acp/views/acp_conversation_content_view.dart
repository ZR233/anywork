import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/latest_scroll.dart';
import '../../../../shared/studio_chrome.dart';
import '../../timeline/widgets/timeline_activity_row.dart';
import '../../timeline/widgets/timeline_reasoning_view.dart';
import '../state/acp_view_state.dart';
import '../widgets/acp_content_block_view.dart';
import '../widgets/acp_message_actions.dart';
import '../widgets/acp_tool_card.dart';

/// Pure conversation reading stream for ACP sessions.
class AcpConversationContentView extends StatefulWidget {
  const AcpConversationContentView({
    super.key,
    required this.threadId,
    required this.header,
    required this.itemBuilder,
    this.planCard,
    this.outputRevision,
    this.onInsertSlashCommand,
  });

  final String threadId;
  final AcpTimelineHeaderViewState header;
  final IndexedWidgetBuilder itemBuilder;
  final Widget? planCard;
  final Object? outputRevision;
  final ValueChanged<String>? onInsertSlashCommand;

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

  String _returnLabel(BuildContext context, bool hasNewOutput) {
    final l10n = context.l10n;
    final header = widget.header;
    if (header.pendingPermissionCount > 0) {
      return l10n.acpJumpToPendingPermission;
    }
    if (header.running) return l10n.acpJumpToRunning;
    return hasNewOutput ? l10n.acpJumpToNewOutput : l10n.timelineJumpToLatest;
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
    final planCard = widget.planCard;
    final reading = header.itemCount == 0 && notices.isEmpty
        ? SelectionArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _EmptySessionState(
                  header: header,
                  onInsertSlashCommand: widget.onInsertSlashCommand,
                ),
              ),
            ),
          )
        : _buildReadingList(header, notices);

    return LiveStatusMotionHost(
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (planCard != null)
              _buildPlanHeader(context, constraints, planCard),
            Expanded(key: const ValueKey('acp-reading-area'), child: reading),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanHeader(
    BuildContext context,
    BoxConstraints constraints,
    Widget planCard,
  ) {
    final boundedPlan = constraints.hasBoundedHeight
        ? ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight <= 84.0
                  ? constraints.maxHeight
                  : (constraints.maxHeight * 0.55).clamp(84.0, 320.0),
            ),
            child: planCard,
          )
        : planCard;
    return DecoratedBox(
      key: ValueKey('acp-sticky-plan:${widget.threadId}'),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          bottom: BorderSide(
            color: context.colors.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: _CenteredReadingConstraint(child: boundedPlan),
      ),
    );
  }

  Widget _buildReadingList(
    AcpTimelineHeaderViewState header,
    List<Widget> notices,
  ) {
    final leadingCount = notices.isEmpty ? 0 : 1;
    final showTrailingWelcome =
        header.itemCount > 0 &&
        !header.hasConversationalContent &&
        notices.isEmpty;
    final totalCount =
        leadingCount + header.itemCount + (showTrailingWelcome ? 1 : 0);
    return LatestScrollScope(
      key: ValueKey(widget.threadId),
      child: Column(
        children: [
          Expanded(
            child: LatestScrollViewport(
              controller: _scrollController,
              outputRevision: (header.itemCount, widget.outputRevision),
              child: SelectionArea(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: totalCount,
                  itemBuilder: (context, rawIndex) {
                    if (leadingCount != 0 && rawIndex == 0) {
                      return _CenteredReadingConstraint(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < notices.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              notices[i],
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
                          child: _EmptySessionState(
                            header: header,
                            onInsertSlashCommand: widget.onInsertSlashCommand,
                          ),
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
          ReturnToLatestButton(labelBuilder: _returnLabel),
        ],
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
  const _EmptySessionState({required this.header, this.onInsertSlashCommand});

  final AcpTimelineHeaderViewState header;
  final ValueChanged<String>? onInsertSlashCommand;

  (IconData, String) _capabilityMeta(
    AppLocalizations l10n,
    AcpCapabilityKind capability,
  ) => switch (capability) {
    AcpCapabilityKind.image => (Icons.image_outlined, l10n.acpCapabilityImage),
    AcpCapabilityKind.audio => (
      Icons.graphic_eq_rounded,
      l10n.acpCapabilityAudio,
    ),
    AcpCapabilityKind.embeddedContext => (
      Icons.attach_file_rounded,
      l10n.acpCapabilityEmbeddedContext,
    ),
    AcpCapabilityKind.loadSession => (
      Icons.history_rounded,
      l10n.acpCapabilityLoadSession,
    ),
    AcpCapabilityKind.resumeSession => (
      Icons.play_circle_outline_rounded,
      l10n.acpCapabilityResumeSession,
    ),
    AcpCapabilityKind.listSessions => (
      Icons.list_alt_rounded,
      l10n.acpCapabilityListSessions,
    ),
  };

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

    final commands = header.availableCommands.take(6).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StudioEmptyState(
          icon: Icons.hub_outlined,
          title: l10n.acpSessionReadyEmptyTitle,
          maxWidth: 460,
        ),
        if (header.capabilities.isNotEmpty) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cap in header.capabilities)
                  () {
                    final (icon, label) = _capabilityMeta(l10n, cap);
                    return StudioCompactChip(
                      icon: icon,
                      label: label,
                      tooltip: label,
                    );
                  }(),
              ],
            ),
          ),
        ],
        if (commands.isNotEmpty) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cmd in commands)
                  Tooltip(
                    message: [
                      if (cmd.inputHint case final hint?) '/${cmd.name} $hint',
                      if (cmd.description.isNotEmpty) cmd.description,
                    ].join('\n'),
                    child: ActionChip(
                      key: ValueKey('acp-empty-cmd:${cmd.name}'),
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.terminal_rounded, size: 15),
                      label: Text(
                        '/${cmd.name}',
                        style: context.text.labelMedium?.copyWith(
                          fontFamily: studioCodeFontFamily,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: onInsertSlashCommand == null
                          ? null
                          : () => onInsertSlashCommand!(cmd.name),
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

String _plainCopyText(List<AcpContentBlockPresentation> blocks) {
  final buffer = StringBuffer();
  for (final block in blocks) {
    switch (block) {
      case AcpTextBlockPresentation(:final text):
        if (text.trim().isEmpty) continue;
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(text);
      case AcpResourceLinkBlockPresentation(:final uri):
      case AcpTextResourceBlockPresentation(:final uri):
      case AcpBlobResourceBlockPresentation(:final uri):
        if (uri.trim().isEmpty) continue;
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(uri);
      case AcpImageBlockPresentation():
      case AcpAudioBlockPresentation():
        break;
    }
  }
  return buffer.toString();
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
    final bubbleColor = context.colors.surfaceContainerHigh;
    final copyText = _plainCopyText(item.blocks);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: StudioLayout.conversationPromptWidth,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(6),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: AcpCollapsibleUserBubble(
                  toggleKey: ValueKey('acp-user-bubble-toggle:${item.id}'),
                  bubbleColor: bubbleColor,
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
            if (copyText.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              AcpCopyIconButton(
                key: ValueKey('acp-copy-message:${item.id}'),
                text: copyText,
                tooltip: context.l10n.acpCopyMessage,
                baseOpacity: 0.42,
              ),
            ],
          ],
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
    final copyText = _plainCopyText(item.blocks);
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
        if (copyText.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: AcpCopyIconButton(
              key: ValueKey('acp-copy-message:${item.id}'),
              text: copyText,
              tooltip: context.l10n.acpCopyMessage,
              baseOpacity: 0.5,
            ),
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

  final List<AcpSlashCommandPresentation> commands;

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
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final cmd in commands)
              Text(
                cmd.inputHint == null
                    ? '/${cmd.name} — ${cmd.description}'
                    : '/${cmd.name} (${cmd.inputHint}) — ${cmd.description}',
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
