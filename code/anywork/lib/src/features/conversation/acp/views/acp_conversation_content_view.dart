import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../timeline/widgets/timeline_activity_row.dart';
import '../../timeline/widgets/timeline_reasoning_view.dart';
import '../state/acp_timeline_row.dart';
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
    required this.rows,
    required this.itemBuilder,
    this.onInsertSlashCommand,
  });

  final String threadId;
  final AcpTimelineHeaderViewState header;
  final List<AcpTimelineRow> rows;
  final Widget Function(BuildContext context, AcpTimelineRow row) itemBuilder;
  final ValueChanged<String>? onInsertSlashCommand;

  @override
  State<AcpConversationContentView> createState() =>
      _AcpConversationContentViewState();
}

class _AcpConversationContentViewState
    extends State<AcpConversationContentView> {
  static const _userId = 'user';
  static const _agentId = 'agent';

  late InMemoryChatController _chatController;
  late Map<String, AcpTimelineRow> _rowsById;

  @override
  void initState() {
    super.initState();
    _chatController = InMemoryChatController(messages: _updateRows());
  }

  @override
  void didUpdateWidget(covariant AcpConversationContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId) {
      _chatController.dispose();
      _chatController = InMemoryChatController(messages: _updateRows());
    } else if (!identical(oldWidget.rows, widget.rows)) {
      final messages = _updateRows();
      if (!listEquals(_chatController.messages, messages)) {
        unawaited(_chatController.setMessages(messages, animated: false));
      }
    }
  }

  List<Message> _updateRows() {
    _rowsById = {for (final row in widget.rows) row.id: row};
    // Flyer only needs row identity and sender for layout and send scrolling.
    // Streaming content updates the existing row without replacing its widget.
    return [
      for (final row in widget.rows)
        Message.custom(
          id: row.id,
          authorId: switch (row) {
            AcpTimelineMessageRow(item: AcpTimelineUserMessage()) => _userId,
            _ => _agentId,
          },
        ),
    ];
  }

  @override
  void dispose() {
    _chatController.dispose();
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
    final welcome = _EmptySessionState(
      header: widget.header,
      onInsertSlashCommand: widget.onInsertSlashCommand,
    );
    final notices = _buildNotices(context);
    final noticeColumn = notices.isEmpty
        ? null
        : _CenteredReadingConstraint(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: notices,
            ),
          );
    final isEmpty = widget.rows.isEmpty;
    final topSliver = isEmpty
        ? SliverFillRemaining(
            hasScrollBody: false,
            child: noticeColumn == null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: welcome),
                  )
                : Align(alignment: Alignment.topCenter, child: noticeColumn),
          )
        : noticeColumn == null
        ? null
        : SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: noticeColumn,
            ),
          );

    return LiveStatusMotionHost(
      child: SelectionArea(
        key: ValueKey(widget.threadId),
        child: Chat(
          chatController: _chatController,
          currentUserId: _userId,
          resolveUser: (id) async => User(id: id),
          theme: ChatTheme.fromThemeData(Theme.of(context)),
          backgroundColor: Colors.transparent,
          builders: Builders(
            composerBuilder: (_) => const SizedBox.shrink(),
            emptyChatListBuilder: (_) => const SizedBox.shrink(),
            scrollToBottomBuilder: (context, animation, onPressed) =>
                ScrollToBottom(
                  key: StudioDriverKeys.timelineReturnLatest,
                  animation: animation,
                  onPressed: onPressed,
                  useComposerHeightForBottomOffset: false,
                  icon: Tooltip(
                    message: context.l10n.timelineJumpToLatest,
                    child: const Icon(Icons.keyboard_arrow_down),
                  ),
                ),
            chatAnimatedListBuilder: (_, _) => ChatAnimatedList(
              reversed: true,
              itemBuilder: _buildItem,
              handleSafeArea: false,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              topPadding: isEmpty ? 0 : 16,
              bottomPadding: 8,
              topSliver: topSliver,
              bottomSliver:
                  !isEmpty &&
                      !widget.header.hasConversationalContent &&
                      notices.isEmpty
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                        child: Center(child: welcome),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    Message message,
    int index,
    Animation<double> animation, {
    MessagesGroupingMode? messagesGroupingMode,
    int? messageGroupingTimeoutInSeconds,
    bool? isRemoved,
  }) {
    if (isRemoved == true) return const SizedBox.shrink();
    final row = _rowsById[message.id];
    if (row == null) return const SizedBox.shrink();
    return _CenteredReadingConstraint(
      key: ValueKey(message.id),
      child: widget.itemBuilder(context, row),
    );
  }
}

class _CenteredReadingConstraint extends StatelessWidget {
  const _CenteredReadingConstraint({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: StudioLayout.conversationWidth,
          ),
          child: SizedBox(width: double.infinity, child: child),
        ),
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
    this.onOpenMarkdownResource,
    this.padding = const EdgeInsets.only(bottom: 14),
  });

  final AcpTimelineItemPresentation item;
  final bool Function(String url)? isSafeLink;
  final ValueChanged<String>? onOpenLink;
  final AcpImageWidgetBuilder? imageBuilder;
  final void Function(String uri, String text)? onOpenMarkdownResource;
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
        onOpenMarkdownResource: onOpenMarkdownResource,
      ),
      final AcpTimelineAssistantMessage assistant => _AssistantProseBlock(
        item: assistant,
        isSafeLink: isSafeLink,
        onOpenLink: onOpenLink,
        imageBuilder: imageBuilder,
        onOpenMarkdownResource: onOpenMarkdownResource,
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
        onOpenMarkdownResource: onOpenMarkdownResource,
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
                  onOpenMarkdownResource: onOpenMarkdownResource,
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
    this.onOpenMarkdownResource,
  });

  final AcpTimelineUserMessage item;
  final bool Function(String url)? isSafeLink;
  final ValueChanged<String>? onOpenLink;
  final AcpImageWidgetBuilder? imageBuilder;
  final void Function(String uri, String text)? onOpenMarkdownResource;

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
                          onOpenMarkdownResource: onOpenMarkdownResource,
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
    this.onOpenMarkdownResource,
  });

  final AcpTimelineAssistantMessage item;
  final bool Function(String url)? isSafeLink;
  final ValueChanged<String>? onOpenLink;
  final AcpImageWidgetBuilder? imageBuilder;
  final void Function(String uri, String text)? onOpenMarkdownResource;

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
            onOpenMarkdownResource: onOpenMarkdownResource,
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
