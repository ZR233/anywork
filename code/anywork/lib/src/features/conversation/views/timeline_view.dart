import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../state/timeline_view_state.dart';
import '../timeline/canvas_binding.dart';
import '../widgets/native_scroll_intent.dart';

/// Stock Chat is the only list. The view never traverses Message metadata,
/// performs queries, mutates the controller, or owns a domain/display lease.
class TimelineView extends StatelessWidget {
  const TimelineView({
    required this.threadId,
    required this.state,
    required this.binding,
    required this.onLoadOlder,
    required this.onRetryOlder,
    required this.onReturnLive,
    required this.onEnterHistory,
    required this.onRetryConnection,
    required this.messageBuilder,
    super.key,
  });

  final String threadId;
  final TimelineViewState state;
  final TimelineCanvasBinding binding;
  final Future<void> Function() onLoadOlder;
  final Future<void> Function() onRetryOlder;
  final Future<void> Function() onReturnLive;
  final VoidCallback onEnterHistory;
  final Future<void> Function() onRetryConnection;
  final Widget Function(BuildContext, Message) messageBuilder;

  @override
  Widget build(BuildContext context) =>
      _TimelineCanvas(key: binding.chatKey, props: this);
}

class _TimelineCanvas extends StatefulWidget {
  const _TimelineCanvas({required this.props, super.key});
  final TimelineView props;
  @override
  State<_TimelineCanvas> createState() => _TimelineCanvasState();
}

class _TimelineCanvasState extends State<_TimelineCanvas> {
  late final TimelineCanvasMount _mount;
  StreamSubscription<ChatOperation>? _operations;
  bool _pointerIntent = false;
  bool _actionIntent = false;
  bool _checkScheduled = false;
  bool _filling = false;
  TimelineView get props => widget.props;
  ScrollController get scroll => props.binding.scrollController;
  bool get _canPage =>
      props.state.hasOlder &&
      !props.state.olderLoading &&
      props.state.olderError == null &&
      !props.state.preparingLive &&
      props.state.connectionPhase == TimelineConnectionPhase.ready;

  @override
  void initState() {
    super.initState();
    _mount = props.binding.mount();
    // Observe operation completion for layout demand only, not its payload.
    _operations = props.binding.chatController.operationsStream.listen(
      (_) => _scheduleFill(),
    );
    _scheduleFill();
  }

  @override
  void didUpdateWidget(covariant _TimelineCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleFill();
  }

  @override
  void dispose() {
    _operations?.cancel();
    _operations = null;
    _mount.unmount();
    super.dispose();
  }

  void _scheduleFill() {
    if (!mounted || _checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted || !_canPage || _filling || !scroll.hasClients) return;
      final position = scroll.position;
      if (!position.hasContentDimensions ||
          position.viewportDimension <= 0 ||
          position.maxScrollExtent - position.minScrollExtent > 0.5) {
        return;
      }
      _filling = true;
      props.onLoadOlder().whenComplete(() {
        _filling = false;
      }).ignore();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _onMetrics(ScrollMetricsNotification value) {
    if (value.depth != 0) return false;
    if (_actionIntent &&
        (!scroll.hasClients || !scroll.position.isScrollingNotifier.value)) {
      _actionIntent = false;
    }
    _scheduleFill();
    return false;
  }

  bool _onUpdate(ScrollUpdateNotification value) {
    if (value.depth != 0) return false;
    if (value.dragDetails == null && !_pointerIntent && !_actionIntent) {
      return false;
    }
    if (!scroll.hasClients) return false;
    final position = scroll.position;
    if (props.state.displayMode == TimelineDisplayMode.live &&
        position.pixels > 0.5) {
      props.onEnterHistory();
    }
    if (_canPage &&
        (value.scrollDelta ?? 0) > 0 &&
        position.extentAfter <= position.viewportDimension) {
      props.onLoadOlder().ignore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final state = props.state;
    final connected = state.connectionPhase == TimelineConnectionPhase.ready;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    ScrollIntent: TimelineScrollIntentAction(
                      controller: scroll,
                      onUserIntent: () => _actionIntent = true,
                      onNoMovement: () => _actionIntent = false,
                    ),
                  },
                  child: PrimaryScrollController(
                    controller: scroll,
                    child: NotificationListener<ScrollMetricsNotification>(
                      onNotification: _onMetrics,
                      child: NotificationListener<UserScrollNotification>(
                        onNotification: (value) {
                          if (value.depth == 0) {
                            _pointerIntent =
                                value.direction != ScrollDirection.idle;
                          }
                          return false;
                        },
                        child: NotificationListener<ScrollEndNotification>(
                          onNotification: (value) {
                            if (value.depth == 0) {
                              _pointerIntent = false;
                              _actionIntent = false;
                            }
                            return false;
                          },
                          child: NotificationListener<ScrollUpdateNotification>(
                            onNotification: _onUpdate,
                            child: TimelineScrollbar(
                              controller: scroll,
                              thumbVisibility: false,
                              onTrackTap: () => _actionIntent = true,
                              onNoMovement: () => _actionIntent = false,
                              child: SelectionArea(child: _chat(context)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (state.olderLoading)
                const Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SizedBox.square(
                      key: StudioDriverKeys.timelineLoadingOlder,
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              if (state.olderError != null)
                Positioned(
                  top: 4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: TextButton.icon(
                      key: StudioDriverKeys.timelineRetryOlder,
                      onPressed: connected
                          ? () => props.onRetryOlder().ignore()
                          : null,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.l10n.timelineItemBodyRetry),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!connected)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  state.connectionFailure?.message ??
                      (state.connectionError == null
                          ? context.l10n.workspaceLoading
                          : context.l10n.timelineConnectionFailed),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
              if (state.connectionError != null)
                TextButton(
                  key: StudioDriverKeys.timelineRetryConnection,
                  onPressed: () => props.onRetryConnection().ignore(),
                  child: Text(context.l10n.sidebarRetry),
                ),
            ],
          ),
        // Fixed geometry: showing the return-live affordance does not resize Chat.
        SizedBox(
          height: 40,
          child: Center(
            child:
                state.displayMode == TimelineDisplayMode.history ||
                    state.preparingLive
                ? TextButton.icon(
                    key: StudioDriverKeys.timelineReturnLive,
                    onPressed: state.preparingLive
                        ? null
                        : () => props.onReturnLive().ignore(),
                    icon: state.preparingLive
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.vertical_align_bottom_rounded,
                            size: 18,
                          ),
                    label: Text(context.l10n.timelineBackToLive),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _chat(BuildContext context) => Chat(
    key: StudioDriverKeys.timeline,
    currentUserId: 'user',
    resolveUser: (id) async => User(id: id),
    chatController: props.binding.chatController,
    backgroundColor: Colors.transparent,
    builders: Builders(
      chatAnimatedListBuilder: (context, itemBuilder) =>
          ChatAnimatedListReversed(
            itemBuilder: itemBuilder,
            scrollController: scroll,
            insertAnimationDuration: Duration.zero,
            removeAnimationDuration: Duration.zero,
            scrollToEndAnimationDuration: Duration.zero,
            topPadding: 0,
            bottomPadding: 0,
            handleSafeArea: false,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            physics: const AlwaysScrollableScrollPhysics(),
            cacheExtent: 600,
            shouldScrollToEndWhenSendingMessage: false,
            onEndReached: props.onLoadOlder,
            paginationThreshold: 0,
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
          }) => isRemoved == true
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: child,
            ),
      customMessageBuilder: (
        context,
        message,
        index, {
        required bool isSentByMe,
        MessageGroupStatus? groupStatus,
      }) => props.messageBuilder(context, message),
      composerBuilder: (_) => const SizedBox.shrink(),
      scrollToBottomBuilder: (_, animation, onPressed) =>
          const SizedBox.shrink(),
      loadMoreBuilder: (_) => const SizedBox.shrink(),
      emptyChatListBuilder: (_) => const SizedBox.shrink(),
    ),
  );
}
