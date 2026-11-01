import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../domain/models/timeline_commands.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../state/chat_item_presentation.dart';
import '../state/timeline_ui_controllers.dart';
import '../state/timeline_view_state.dart';
import '../widgets/chat_item_view.dart';
import '../widgets/timeline_markdown.dart';
import '../widgets/timeline_scroll_intent.dart';

/// Pure view: immutable presentation state, typed actions and borrowed UI-only
/// controllers. Media, detail and platform actions are injected by Connector.
class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.threadId,
    required this.view,
    required this.controls,
    required this.onLoadOlder,
    required this.onRetryOlder,
    required this.onReturnLive,
    required this.onEnterHistory,
    required this.onRetryConnection,
    required this.onLink,
    required this.isSafeLink,
    required this.remoteImageBuilder,
    this.planSummary,
    this.pendingPlanInteractionId,
    this.readContent,
    this.childrenBuilder,
    this.attachmentBuilder,
    this.monotonicMicros,
    this.onContentLayout,
    this.isDisplayActive,
  });
  final String threadId;
  final TimelineSessionViewState view;
  final TimelineUiControllers controls;
  final Future<void> Function() onLoadOlder;
  final Future<void> Function() onRetryOlder;
  final Future<void> Function() onReturnLive;
  final VoidCallback onEnterHistory;
  final VoidCallback onRetryConnection;
  final ValueChanged<String> onLink;
  final bool Function(String) isSafeLink;
  final Widget Function(BuildContext, String) remoteImageBuilder;
  final Widget? planSummary;
  final String? pendingPlanInteractionId;
  final ChatContentRead? readContent;
  final Widget Function(String parentId)? childrenBuilder;
  final Widget Function(ChatItemPresentation item)? attachmentBuilder;
  final int Function()? monotonicMicros;
  final void Function(String itemId, int layoutCompletedMicros)?
  onContentLayout;
  final bool Function()? isDisplayActive;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  StreamSubscription<ChatOperation>? _operations;
  VoidCallback? _scrollToBottom;
  bool _userIntent = false;
  bool _actionIntent = false;
  bool _scheduled = false;
  bool _paging = false;
  int _fillBudget = 8;
  bool _fillStopped = false;
  @override
  void initState() {
    super.initState();
    widget.controls.bind();
    _operations = widget.controls.controller.operationsStream.listen(
      (_) => _scheduleFill(),
    );
    _scheduleFill();
  }

  @override
  void didUpdateWidget(covariant TimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      identical(widget.controls, oldWidget.controls),
      'A new generation requires a new Chat subtree key',
    );
    _scheduleFill();
  }

  @override
  void dispose() {
    unawaited(_operations?.cancel());
    unawaited(widget.controls.unbind());
    super.dispose();
  }

  bool get _canPage =>
      !widget.controls.isRetired &&
      widget.view.hasOlder &&
      !widget.view.isLoadingOlder &&
      widget.view.olderError == null;
  void _scheduleFill() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted ||
          !_canPage ||
          _paging ||
          _fillStopped ||
          _fillBudget == 0) {
        return;
      }
      final scroll = widget.controls.scrollController;
      if (!scroll.hasClients) return;
      final position = scroll.position;
      if (position.hasContentDimensions &&
          position.viewportDimension > 0 &&
          position.maxScrollExtent <= position.minScrollExtent + .5) {
        _paging = true;
        _fillBudget--;
        unawaited(_fill());
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _fill() async {
    final controls = widget.controls;
    final before = widget.view.olderCursor;
    try {
      await widget.onLoadOlder();
      // The SDK has published metadata when its Future completes, but this
      // widget receives that publication on the next actual build/layout frame.
      // Join that frame once; do not mistake the previous widget for no progress.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted &&
          identical(widget.controls, controls) &&
          !controls.isRetired &&
          widget.view.olderCursor == before) {
        _fillStopped = true;
      }
    } catch (_) {
      _fillStopped = true;
      rethrow;
    } finally {
      _paging = false;
      // A successful page/state publication supplies the next real layout
      // event. This is not a frame-by-frame prefetch loop.
      if (mounted &&
          identical(widget.controls, controls) &&
          !controls.isRetired &&
          widget.view.olderCursor != before) {
        _scheduleFill();
      }
    }
  }

  bool _scroll(ScrollNotification notification) {
    if (notification.depth != 0 || widget.controls.isRetired) return false;
    if (notification is UserScrollNotification) {
      _userIntent = notification.direction != ScrollDirection.idle;
    }
    if (notification is ScrollEndNotification) {
      _userIntent = false;
      _actionIntent = false;
    }
    if (notification is ScrollUpdateNotification &&
        (notification.dragDetails != null || _userIntent || _actionIntent)) {
      final metrics = notification.metrics;
      if (widget.view.mode == TimelineDisplayMode.live && metrics.pixels > .5) {
        widget.onEnterHistory();
      }
      if (_canPage &&
          (notification.scrollDelta ?? 0) > 0 &&
          metrics.extentAfter <= metrics.viewportDimension) {
        unawaited(widget.onLoadOlder());
      }
    }
    return false;
  }

  Future<void> _returnToLatest() async {
    final controls = widget.controls;
    final scrollToBottom = _scrollToBottom;
    if (scrollToBottom == null) return;
    await widget.onReturnLive();
    if (!mounted ||
        !identical(widget.controls, controls) ||
        controls.isRetired ||
        !controls.scrollController.hasClients) {
      return;
    }
    // Keep our explicit reading intent/footer, but delegate geometry and timing
    // to Flyer's public builder callback for this mounted list.
    scrollToBottom();
    // The official callback only registers a postFrameCallback, which never
    // schedules a frame itself. If this continuation lands after the last
    // scheduled frame, guarantee one frame so that scroll can actually run.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _body(String id, String text) => TimelineMarkdown(
    id: id,
    text: text,
    onLink: widget.onLink,
    isSafeLink: widget.isSafeLink,
    imageBuilder: widget.remoteImageBuilder,
  );

  @override
  Widget build(BuildContext context) {
    final controls = widget.controls;
    final returnLiveLabel = context.l10n.timelineBackToLive;
    final newOutputReturnLiveLabel = '有新输出 · $returnLiveLabel';
    return Column(
      children: [
        if (widget.view.connection != TimelineConnectionPhase.ready)
          SelectionContainer.disabled(
            child: Row(
              key: StudioDriverKeys.timelineConnectionNotice,
              children: [
                Expanded(
                  child: Text(
                    widget.view.connectionError?.toString() ??
                        context.l10n.workspaceLoading,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.view.connection == TimelineConnectionPhase.failed)
                  TextButton(
                    key: StudioDriverKeys.timelineRetryConnection,
                    onPressed: widget.onRetryConnection,
                    child: Text(context.l10n.sidebarRetry),
                  ),
              ],
            ),
          ),
        if (widget.view.isLoadingOlder)
          const LinearProgressIndicator(
            key: StudioDriverKeys.timelineLoadingOlder,
            minHeight: 1,
          ),
        if (widget.view.olderError != null)
          TextButton.icon(
            key: StudioDriverKeys.timelineRetryOlder,
            onPressed: widget.view.connection == TimelineConnectionPhase.ready
                ? () => unawaited(widget.onRetryOlder())
                : null,
            icon: const Icon(Icons.refresh),
            label: Text(
              widget.view.olderError.toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Expanded(
          child: Actions(
            actions: <Type, Action<Intent>>{
              ScrollIntent: TimelineScrollIntentAction(
                controller: controls.scrollController,
                onUserIntent: () => _actionIntent = true,
                onNoMovement: () => _actionIntent = false,
              ),
            },
            child: PrimaryScrollController(
              controller: controls.scrollController,
              automaticallyInheritForPlatforms: const <TargetPlatform>{},
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (notification) {
                  if (notification.depth == 0) {
                    if (_actionIntent &&
                        (!controls.scrollController.hasClients ||
                            !controls
                                .scrollController
                                .position
                                .isScrollingNotifier
                                .value)) {
                      _actionIntent = false;
                    }
                    _scheduleFill();
                  }
                  return false;
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: _scroll,
                  child: SelectionArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: StudioLayout.conversationWidth,
                        ),
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: TimelineScrollbar(
                            controller: controls.scrollController,
                            thumbVisibility: false,
                            onTrackTap: () => _actionIntent = true,
                            onNoMovement: () => _actionIntent = false,
                            child: KeyedSubtree(
                              key: StudioDriverKeys.timeline,
                              child: Chat(
                                currentUserId: 'user',
                                resolveUser: (id) async => User(id: id),
                                chatController: controls.controller,
                                backgroundColor: Colors.transparent,
                                builders: Builders(
                                  composerBuilder: (_) =>
                                      const SizedBox.shrink(),
                                  scrollToBottomBuilder: (_, _, onPressed) {
                                    _scrollToBottom = onPressed;
                                    return const SizedBox.shrink();
                                  },
                                  emptyChatListBuilder: (_) => Center(
                                    child: SelectionContainer.disabled(
                                      child: Text(
                                        context.l10n.timelineEmptyMessage,
                                        style: context.text.bodyMedium,
                                      ),
                                    ),
                                  ),
                                  chatAnimatedListBuilder:
                                      (
                                        context,
                                        itemBuilder,
                                      ) => ChatAnimatedListReversed(
                                        // Preserve Flyer's ID lookup for moves
                                        // while replacing its row State when a
                                        // Set supplies a new immutable Message.
                                        // ChatMessageInternal otherwise retains
                                        // its initState message for the same ID.
                                        itemBuilder:
                                            (
                                              context,
                                              message,
                                              index,
                                              animation, {
                                              messagesGroupingMode,
                                              messageGroupingTimeoutInSeconds,
                                              isRemoved,
                                            }) => KeyedSubtree(
                                              key: ValueKey(message.id),
                                              child: KeyedSubtree(
                                                key: ObjectKey(message),
                                                child: itemBuilder(
                                                  context,
                                                  message,
                                                  index,
                                                  animation,
                                                  messagesGroupingMode:
                                                      messagesGroupingMode,
                                                  messageGroupingTimeoutInSeconds:
                                                      messageGroupingTimeoutInSeconds,
                                                  isRemoved: isRemoved,
                                                ),
                                              ),
                                            ),
                                        scrollController:
                                            controls.scrollController,
                                        insertAnimationDuration: Duration.zero,
                                        removeAnimationDuration: Duration.zero,
                                        scrollToEndAnimationDuration:
                                            Duration.zero,
                                        shouldScrollToEndWhenSendingMessage:
                                            false,
                                        handleSafeArea: false,
                                        topPadding: 16,
                                        bottomPadding: 16,
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior
                                                .manual,
                                        onEndReached: widget.view.hasOlder
                                            ? widget.onLoadOlder
                                            : null,
                                        paginationThreshold: 0,
                                        bottomSliver: widget.planSummary == null
                                            ? null
                                            : SliverToBoxAdapter(
                                                child: widget.planSummary,
                                              ),
                                      ),
                                  chatMessageBuilder:
                                      (
                                        context,
                                        message,
                                        index,
                                        animation,
                                        child, {
                                        bool? isRemoved,
                                        required bool isSentByMe,
                                        MessageGroupStatus? groupStatus,
                                      }) {
                                        if (isRemoved == true) {
                                          return const SizedBox.shrink();
                                        }
                                        return ChatMessage(
                                          key: StudioDriverKeys.timelineRow(
                                            message.id,
                                          ),
                                          message: message,
                                          index: index,
                                          animation: animation,
                                          isRemoved: isRemoved,
                                          groupStatus: groupStatus,
                                          horizontalPadding: 24,
                                          verticalPadding: 8,
                                          child: isSentByMe
                                              ? Container(
                                                  constraints: const BoxConstraints(
                                                    maxWidth: StudioLayout
                                                        .conversationPromptWidth,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 10,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: context
                                                        .colors
                                                        .surfaceContainerLow,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: child,
                                                )
                                              : SizedBox(
                                                  width: double.infinity,
                                                  child: child,
                                                ),
                                        );
                                      },
                                  customMessageBuilder:
                                      (
                                        context,
                                        message,
                                        index, {
                                        required bool isSentByMe,
                                        MessageGroupStatus? groupStatus,
                                      }) => ChatItemView(
                                        item: chatItemPresentationOf(message)!,
                                        bodyBuilder: _body,
                                        readContent: widget.readContent,
                                        childrenBuilder: widget.childrenBuilder,
                                        attachmentBuilder:
                                            widget.attachmentBuilder,
                                        monotonicMicros: widget.monotonicMicros,
                                        onContentLayout: widget.onContentLayout,
                                        isDisplayActive: widget.isDisplayActive,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SelectionContainer.disabled(
          // IndexedStack reserves both labels' natural size, including text
          // scaling, but only the real History control is ever onstage. This
          // footer never overlays body text or changes height with the mode.
          child: IndexedStack(
            index: widget.view.mode == TimelineDisplayMode.history ? 0 : null,
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: StudioDriverKeys.timelineReturnLive,
                  onPressed: widget.view.mode != TimelineDisplayMode.history
                      ? null
                      : () => unawaited(_returnToLatest()),
                  icon: const Icon(Icons.south),
                  label: Text(
                    widget.view.hasNewOutput
                        ? newOutputReturnLiveLabel
                        : returnLiveLabel,
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.south),
                  label: Text(newOutputReturnLiveLabel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
