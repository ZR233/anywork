import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../platform/external_url_launcher.dart';
import '../../presentation/providers/client_provider.dart';
import '../../presentation/view_models/timeline_session_owner.dart';
import '../../shared/studio_chrome.dart';
import '../../shared/studio_driver_key_values.dart';
import '../../shared/studio_driver_keys.dart';
import '../../shared/typed_json.dart';
import 'markdown_repair.dart';
import 'timeline_wait_blocks.dart';

part 'timeline_agent_blocks.dart';
part 'timeline_detail_viewer.dart';
part 'timeline_image_blocks.dart';
part 'timeline_markdown_blocks.dart';
part 'timeline_message_blocks.dart';
part 'timeline_group_blocks.dart';
part 'timeline_plan_blocks.dart';
part 'timeline_preview_host.dart';
part 'timeline_remote_image_blocks.dart';
part 'timeline_tool_blocks.dart';
part 'timeline_user_input_blocks.dart';

typedef TimelineRemoteImageProviderFactory = ImageProvider Function(String url);

final timelineRemoteImageProviderFactoryProvider =
    Provider<TimelineRemoteImageProviderFactory>((ref) => NetworkImage.new);

/// 读者自己的作者身份：库只把它用于气泡布局。
const String _timelineUserAuthorId = 'user';

/// 唯一 Timeline 列表。
///
/// 全部事实经构造参数进入：展示元数据、当前代次的 [TimelineDisplayLease] 与显式意图回调。
/// 没有行投影、没有像素恢复、没有 observer：库自己的反向列表、标准
/// `ScrollController(keepScrollOffset: false)` 与 stock controller 是唯一列表实现
/// （design/26 §26.3、§26.4、§26.8）。
class TimelineView extends StatelessWidget {
  const TimelineView({
    required this.threadId,
    required this.view,
    required this.lease,
    required this.onLoadOlder,
    required this.onRetryOlder,
    required this.onReturnLive,
    required this.onEnterHistory,
    required this.onRetryConnection,
    this.planConfirmation,
    this.planExpanded = false,
    this.onPlanToggle,
    super.key,
  });

  final String threadId;
  final TimelineSessionViewState view;

  /// 当前展示代次借出的 controller 与滚动控制器。
  final TimelineDisplayLease lease;

  /// 自动触底与显式「加载更早」共用的同一个在途动作。
  final Future<void> Function() onLoadOlder;
  final Future<void> Function() onRetryOlder;
  final Future<void> Function() onReturnLive;

  /// 真实用户滚动离开底端：冻结已展示内容（内容发布策略，不是滚动 owner）。
  final VoidCallback onEnterHistory;

  /// 连接失败后的显式重试：保持当前 History 冻结，不改代次。
  final Future<void> Function() onRetryConnection;

  final PlanConfirmationView? planConfirmation;
  final bool planExpanded;
  final VoidCallback? onPlanToggle;

  @override
  Widget build(BuildContext context) {
    // 每个代次整棵 Chat 子树换 key：新的消息控制器与滚动控制器不能沿用旧列表 state。
    return _TimelineGeneration(
      key: lease.chatKey,
      threadId: threadId,
      view: view,
      lease: lease,
      onLoadOlder: onLoadOlder,
      onRetryOlder: onRetryOlder,
      onReturnLive: onReturnLive,
      onEnterHistory: onEnterHistory,
      onRetryConnection: onRetryConnection,
      planConfirmation: planConfirmation,
      planExpanded: planExpanded,
      onPlanToggle: onPlanToggle,
    );
  }
}

/// 一个展示代次的真实子树。
///
/// 挂载时 [TimelineDisplayLease.bind]、卸载时 [TimelineDisplayLease.unbind]；lease 据此
/// 等待真实子树释放后才销毁 controller（design/26 §26.8）。这里不另建 controller、不镜像
/// 消息集合，也不做整表 diff。
class _TimelineGeneration extends StatefulWidget {
  const _TimelineGeneration({
    required this.threadId,
    required this.view,
    required this.lease,
    required this.onLoadOlder,
    required this.onRetryOlder,
    required this.onReturnLive,
    required this.onEnterHistory,
    required this.onRetryConnection,
    required this.planConfirmation,
    required this.planExpanded,
    required this.onPlanToggle,
    super.key,
  });

  final String threadId;
  final TimelineSessionViewState view;
  final TimelineDisplayLease lease;
  final Future<void> Function() onLoadOlder;
  final Future<void> Function() onRetryOlder;
  final Future<void> Function() onReturnLive;
  final VoidCallback onEnterHistory;
  final Future<void> Function() onRetryConnection;
  final PlanConfirmationView? planConfirmation;
  final bool planExpanded;
  final VoidCallback? onPlanToggle;

  @override
  State<_TimelineGeneration> createState() => _TimelineGenerationState();
}

class _TimelineGenerationState extends State<_TimelineGeneration> {
  final _ThreadImageLoader _imageLoader = _ThreadImageLoader();

  /// 用户当前这次滚动手势是否来自真实输入（拖动 / 滚轮 / 键盘 / 滚条）。
  ///
  /// 只用来区分「读者主动离开底端」与「布局修正、改窗、内容扩展」。它不拦截任何手势，
  /// 也不改变滚动位置（design/26 §26.3）。
  bool _pointerScrollIntent = false;

  /// 键盘/滚条触发的**一次性**用户意图。
  ///
  /// Flutter 的 `ScrollAction`（PageUp/PageDown/方向键等）与 `RawScrollbar` 的轨道点击都
  /// 直接 `position.moveTo(...)`，既不带 `dragDetails` 也不发 `UserScrollNotification`；
  /// 只靠这两个信号会把真实阅读意图误判成程序滚动。这里由官方扩展点登记意图，滚动本身
  /// 仍由 Flutter 完成（应用不写 pixels）。
  bool _actionScrollIntent = false;
  bool _shortContent = false;

  StreamSubscription<ChatOperation>? _operations;

  @override
  void initState() {
    super.initState();
    widget.lease.bind();
    // 附件/图片缓存按 stock controller 的真实 operation 做小增量：中间条目变化也会释放，
    // 但不会每帧/resize 做全表扫描（design/26 §26.5 的内存边界）。
    _operations = widget.lease.controller.operationsStream.listen(_onOperation);
    widget.lease.addItemListener(_onItemChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncShortContent();
      // 基线可能在监听建立前就已交付：首帧按当前集合建一次引用账目。
      _imageLoader.reset(widget.threadId, widget.lease.controller.messages);
    });
  }

  @override
  void dispose() {
    widget.lease.removeItemListener(_onItemChange);
    unawaited(_operations?.cancel());
    _operations = null;
    _imageLoader.clear();
    unawaited(widget.lease.unbind());
    super.dispose();
  }

  void _onItemChange(String id, TimelineMessagePayload? payload) {
    if (payload == null) {
      _imageLoader.dropItem(widget.threadId, id);
    } else {
      _imageLoader.retainItem(widget.threadId, payload);
    }
  }

  /// 一条 stock operation 的增量：只更新受影响的 Message，不保留正文副本。
  void _onOperation(ChatOperation operation) {
    final threadId = widget.threadId;
    switch (operation.type) {
      case ChatOperationType.set:
        _imageLoader.reset(threadId, operation.messages ?? const <Message>[]);
      case ChatOperationType.insertAll:
        for (final message in operation.messages ?? const <Message>[]) {
          _imageLoader.retainMessage(threadId, message);
        }
      case ChatOperationType.insert:
      case ChatOperationType.update:
        final message = operation.message;
        if (message != null) _imageLoader.retainMessage(threadId, message);
      case ChatOperationType.remove:
        final message = operation.message ?? operation.oldMessage;
        if (message != null) _imageLoader.dropMessage(threadId, message);
    }
  }

  void _syncShortContent() {
    final position = widget.lease.scrollController.hasClients
        ? widget.lease.scrollController.position
        : null;
    final short = position == null || position.maxScrollExtent <= 0;
    if (short == _shortContent) return;
    setState(() => _shortContent = short);
  }

  // ---- 被动观察：真实用户意图才进入 History ------------------------------

  bool _handleUserScroll(UserScrollNotification notification) {
    if (notification.depth != 0) return false;
    // 方向通知先于像素变化：只登记「这次是用户滚动」，并在 end/idle 立刻失效。
    _pointerScrollIntent = notification.direction != ScrollDirection.idle;
    return false;
  }

  bool _handleScrollEnd(ScrollEndNotification notification) {
    if (notification.depth != 0) return false;
    _pointerScrollIntent = false;
    _actionScrollIntent = false;
    return false;
  }

  bool _handleScrollUpdate(ScrollUpdateNotification notification) {
    if (notification.depth != 0) return false;
    final userIntent =
        notification.dragDetails != null ||
        _pointerScrollIntent ||
        _actionScrollIntent;
    // 一次性键盘/轨道意图：消费一次即可，避免动画期间的后续帧被误当成持续手势。
    _actionScrollIntent = false;
    if (!userIntent) {
      // 惰性几何、改窗或内容扩展引起的像素修正没有读者意图，不是阅读意图。
      return false;
    }
    if (widget.view.mode == TimelineDisplayMode.live &&
        widget.lease.scrollController.hasClients &&
        widget.lease.scrollController.position.pixels > 0.5) {
      widget.onEnterHistory();
    }
    return false;
  }

  /// 轨道点击总是作用于本 Timeline 自己的 controller，无需再从 context 反查。
  void _recordTrackTapIntent() {
    if (!widget.lease.scrollController.hasClients) return;
    _actionScrollIntent = true;
  }

  /// 官方动作/轨道分页未产生实际滚动：撤回意图，避免悬挂。
  void _clearActionIntent() => _actionScrollIntent = false;

  bool _handleMetrics(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;
    // 一次键盘/轨道动作若没有真的进入滚动（底端、被 clamp），不得把意图泄漏给后续的
    // 布局/内容几何修正。
    final controller = widget.lease.scrollController;
    if (_actionScrollIntent &&
        (!controller.hasClients ||
            !controller.position.isScrollingNotifier.value)) {
      _actionScrollIntent = false;
    }
    _syncShortContent();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.lease.controller.messages;
    final plan = widget.planConfirmation;
    final showTail = plan != null;
    if (messages.isEmpty && !showTail && !widget.view.hasOlder) {
      return const _EmptyTimeline();
    }
    return _ThreadImageCacheScope(
      loader: _imageLoader,
      child: Stack(
        children: [
          Positioned.fill(
            // 键盘意图必须在焦点祖先处登记：选择区域的焦点在滚动视图之外，因此 Actions
            // 包在选择区域外层；滚动仍由官方 ScrollAction 执行，应用不写 pixels。
            //
            // PrimaryScrollController 是官方键盘滚动目标：桌面上 ScrollView.primary 不会
            // 被嵌套竖向滚动视图继承（`shouldInherit` 只在移动平台为真），因此内部工具
            // 滚动不会 attach 到本代次的 controller。
            child: Actions(
              actions: <Type, Action<Intent>>{
                ScrollIntent: _TimelineScrollIntentAction(
                  controller: widget.lease.scrollController,
                  onUserIntent: _recordTrackTapIntent,
                  onNoMovement: _clearActionIntent,
                ),
              },
              child: PrimaryScrollController(
                controller: widget.lease.scrollController,
                // 稳定的 controller 所有权薄配置：只有官方 ScrollAction 通过
                // `PrimaryScrollController.of` 使用它；显式空的自动继承集合保证任何
                // 嵌套竖向滚动视图都不会 attach 到本代次的 controller（否则同一
                // ScrollController 会有多个 position）。
                automaticallyInheritForPlatforms: const <TargetPlatform>{},
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: _handleMetrics,
                  child: NotificationListener<ScrollEndNotification>(
                    onNotification: _handleScrollEnd,
                    child: NotificationListener<UserScrollNotification>(
                      onNotification: _handleUserScroll,
                      child: NotificationListener<ScrollUpdateNotification>(
                        onNotification: _handleScrollUpdate,
                        // 选择与复制使用 Flutter 官方选择区域：跨行、行内代码与长路径都可选。
                        child: SelectionArea(
                          child: LayoutBuilder(
                            builder: (context, constraints) => Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: StudioLayout.conversationWidth,
                                ),
                                child: ScrollConfiguration(
                                  behavior: ScrollConfiguration.of(context)
                                      .copyWith(scrollbars: false),
                                  child: _TimelineScrollbar(
                                    controller: widget.lease.scrollController,
                                    // 轨道未设 trackColor 时不绘制（视觉不变），但
                                    // trackVisibility 让轨道仍可点击分页。
                                    thumbVisibility: true,
                                    trackVisibility: true,
                                    onTrackTap: _recordTrackTapIntent,
                                    onNoMovement: _clearActionIntent,
                                    child: KeyedSubtree(
                                      key: StudioDriverKeys.timeline,
                                      child: _buildChat(context, plan: plan),
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
          if (_showConnectionNotice)
            Positioned(
              top: 8,
              left: 24,
              right: 24,
              child: Center(child: _buildConnectionNotice(context)),
            ),
          if (_showOlderAffordance)
            Positioned(
              top: _showConnectionNotice ? 56 : 8,
              left: 24,
              right: 24,
              child: Center(child: _buildOlderAffordance(context)),
            ),
          if (widget.view.mode == TimelineDisplayMode.history)
            Positioned(
              bottom: 12,
              right: 24,
              child: _ReturnLiveButton(
                pendingNewOutput: widget.view.hasNewOutput,
                preparing: widget.view.isPreparingLive,
                onPressed: widget.view.isPreparingLive
                    ? null
                    // 失败由 owner 的状态流呈现（connection failed/error 可见），
                    // 这里不留下未处理异常。
                    : () => unawaited(
                        widget.onReturnLive().catchError((Object _) {}),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  /// 已有展示时连接重连/失败必须可见，且不清掉冻结的 History。
  bool get _showConnectionNotice =>
      widget.view.connection == TimelineConnectionPhase.reconnecting ||
      widget.view.connection == TimelineConnectionPhase.failed;

  Widget _buildConnectionNotice(BuildContext context) {
    final failed = widget.view.connection == TimelineConnectionPhase.failed;
    final error = widget.view.connectionError;
    final message = failed
        ? context.l10n.timelineConnectionFailed
        : context.l10n.timelineReconnecting;
    return Tooltip(
      message: error?.toString() ?? message,
      child: Material(
        color: failed
            ? context.colors.errorContainer
            : context.colors.surfaceContainerHigh,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                failed ? Icons.sync_problem : Icons.sync,
                size: 16,
                color: failed
                    ? context.colors.error
                    : context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  key: StudioDriverKeys.timelineConnectionNotice,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: failed
                        ? context.colors.error
                        : context.colors.onSurfaceVariant,
                  ),
                ),
              ),
              if (failed) ...[
                const SizedBox(width: 6),
                TextButton(
                  key: StudioDriverKeys.timelineRetryConnection,
                  onPressed: () => unawaited(widget.onRetryConnection()),
                  child: Text(context.l10n.sidebarRetry),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 短内容（不足一屏）或分页失败时给出显式入口；滚动中的 loading 由库自己的触底驱动。
  bool get _showOlderAffordance {
    if (widget.view.olderError != null) return true;
    if (widget.view.isLoadingOlder) return false;
    if (!widget.view.hasOlder) return false;
    return _shortContent;
  }

  Widget _buildOlderAffordance(BuildContext context) {
    final error = widget.view.olderError;
    if (error != null) {
      return Tooltip(
        message: error.toString(),
        child: TextButton.icon(
          key: StudioDriverKeys.timelineRetryOlder,
          onPressed: () => unawaited(widget.onRetryOlder()),
          icon: const Icon(Icons.refresh),
          label: Text(context.l10n.timelineItemBodyRetry),
        ),
      );
    }
    // 短内容不足一屏时的显式「加载更早」入口：与触底分页共用同一个在途动作。
    final label = context.l10n.timelineLoadEarlier;
    return Tooltip(
      message: label,
      child: Material(
        color: context.colors.surfaceContainer,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: TextButton.icon(
          key: StudioDriverKeys.timelineLoadOlder,
          onPressed: () => unawaited(widget.onLoadOlder()),
          icon: const Icon(Icons.history, size: 18),
          label: Text(label),
        ),
      ),
    );
  }

  Widget _buildChat(
    BuildContext context, {
    required PlanConfirmationView? plan,
  }) {
    final lease = widget.lease;
    return Chat(
      currentUserId: _timelineUserAuthorId,
      resolveUser: (id) async => User(id: id),
      chatController: lease.controller,
      backgroundColor: Colors.transparent,
      builders: Builders(
        chatAnimatedListBuilder: (context, itemBuilder) =>
            ChatAnimatedListReversed(
              itemBuilder: itemBuilder,
              scrollController: lease.scrollController,
              insertAnimationDuration: Duration.zero,
              removeAnimationDuration: Duration.zero,
              scrollToEndAnimationDuration: Duration.zero,
              topPadding: 0,
              bottomPadding: 0,
              handleSafeArea: false,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              physics: const AlwaysScrollableScrollPhysics(),
              cacheExtent: 600,
              // 发送后由库的自然 offset 0 跟随，不启用额外强制滚动分支。
              shouldScrollToEndWhenSendingMessage: false,
              onEndReached: widget.onLoadOlder,
              // 反向列表的视觉底端：计划摘要位于最新消息之后、输入区之前。
              bottomSliver: plan == null
                  ? null
                  : SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _TimelineTail(
                          planSummary: TimelinePlanSummaryCard(
                            plan: plan,
                            expanded: widget.planExpanded,
                            onPressed: widget.onPlanToggle ?? () {},
                          ),
                        ),
                      ),
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
              if (isRemoved == true) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: child,
              );
            },
        customMessageBuilder:
            (
              context,
              message,
              index, {
              required bool isSentByMe,
              MessageGroupStatus? groupStatus,
            }) => _TimelinePresentationBlock(
              key: ValueKey<String>('timeline-message-${message.id}'),
              message: message,
              lease: lease,
              threadId: widget.threadId,
            ),
        composerBuilder: (context) => const SizedBox.shrink(),
        scrollToBottomBuilder: (context, animation, onPressed) =>
            const SizedBox.shrink(),
        // 分页 loading/失败由本视图自己的显式入口表达，不用库的默认 spinner。
        loadMoreBuilder: (context) => const SizedBox.shrink(),
        emptyChatListBuilder: (context) => const SizedBox.shrink(),
      ),
    );
  }
}

/// 底部收束区：计划摘要位于最新消息之后（反向列表的视觉底端）。
class _TimelineTail extends StatelessWidget {
  const _TimelineTail({this.planSummary});

  final Widget? planSummary;

  @override
  Widget build(BuildContext context) {
    final currentPlan = planSummary;
    final alignedPlan = currentPlan == null
        ? null
        : Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: currentPlan,
            ),
          );
    return Column(
      key: const ValueKey('timeline-tail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?alignedPlan,
        const SizedBox(key: ValueKey('timeline-tail-bottom-gap'), height: 14),
      ],
    );
  }
}

/// 回到实时：显式建立新代次；后台已有更新输出时在同一入口提示。
class _ReturnLiveButton extends StatelessWidget {
  const _ReturnLiveButton({
    required this.pendingNewOutput,
    required this.preparing,
    required this.onPressed,
  });

  final bool pendingNewOutput;
  final bool preparing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelSmall;
    // 语义与“跳到最新”不同：这是显式建立新代次回到实时。
    final label = context.l10n.timelineBackToLive;
    return Tooltip(
      message: label,
      child: Material(
        elevation: 0,
        color: context.colors.primaryContainer,
        shape: StadiumBorder(
          side: BorderSide(
            color: context.colors.primary.withValues(alpha: 0.18),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: StudioDriverKeys.timelineReturnLive,
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: pendingNewOutput ? 10 : 8,
              vertical: 7,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (preparing)
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Icons.vertical_align_bottom_rounded,
                    size: 18,
                    color: context.colors.onPrimaryContainer,
                  ),
                if (!preparing) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: textStyle?.copyWith(
                      color: context.colors.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (pendingNewOutput && !preparing) ...[
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.timelineNew,
                    key: StudioDriverKeys.timelineNewOutput,
                    style: textStyle?.copyWith(
                      color: context.colors.onPrimaryContainer,
                    ),
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

/// 键盘滚动意图的薄适配。
///
/// Flutter 的 `ScrollAction`（PageUp/PageDown/方向键/Home/End）通过
/// `position.moveTo(...)` 滚动，既不带 `dragDetails` 也不发 `UserScrollNotification`。
/// 这里只**登记**“这次滚动来自真实用户”，随后交给官方 `ScrollAction` 完成滚动：应用不写
/// pixels、不改 physics、不吞事件（design/26 §26.3）。
///
/// 焦点可能在滚动视图内（正文/嵌套工具），也可能在它外面（选择区域）。后者由官方动作对
/// 本代次的 `notificationContext` 执行；本子树另外提供的 `PrimaryScrollController` 只是
/// 官方动作找不到焦点滚动视图时的 fallback，并不自动向嵌套视图继承（否则同一 controller
/// 会被 attach 到多个 position）。
class _TimelineScrollIntentAction extends ScrollAction {
  _TimelineScrollIntentAction({
    required this.controller,
    required this.onUserIntent,
    required this.onNoMovement,
  });

  final ScrollController controller;
  final VoidCallback onUserIntent;
  final VoidCallback onNoMovement;

  @override
  void invoke(ScrollIntent intent, [BuildContext? context]) {
    if (context == null) {
      super.invoke(intent, context);
      return;
    }
    if (axisDirectionToAxis(intent.direction) != Axis.vertical) {
      super.invoke(intent, context);
      return;
    }
    final target = Scrollable.maybeOf(context);
    if (target != null) {
      // 焦点在某个滚动视图内：只有它就是本代次的滚动视图时才算本 Timeline 的阅读意图。
      if (controller.hasClients &&
          identical(target.position, controller.position)) {
        _invokeAndPrune(intent, context);
      } else {
        super.invoke(intent, context);
      }
      return;
    }
    if (!controller.hasClients) return;
    // 焦点在滚动视图之外（选择区域）：仍是本 Timeline 的键盘滚动，官方动作会通过
    // 本子树提供的 PrimaryScrollController 找到代次的滚动位置。
    _invokeAndPrune(intent, context);
  }

  /// 登记意图 → 交给官方动作 → 若实际没有位移也没进入滚动活动，立刻撤回意图。
  ///
  /// 这覆盖“已在底端按 PageDown/Home/End”等无位移动作：官方不会发 Start/Update/End，
  /// 悬挂的意图会让之后的布局修正被误判成阅读意图（design/26 §26.3）。
  void _invokeAndPrune(ScrollIntent intent, BuildContext context) {
    final before = controller.hasClients ? controller.position.pixels : null;
    onUserIntent();
    super.invoke(intent, context);
    if (!controller.hasClients) {
      onNoMovement();
      return;
    }
    final position = controller.position;
    if (before != null &&
        position.pixels == before &&
        !position.isScrollingNotifier.value) {
      onNoMovement();
    }
  }
}

/// 标准滚动条的薄适配：只把“轨道点击”这一真实用户动作登记为意图。
///
/// `RawScrollbarState.handleTrackTapDown` 是官方 `@protected @mustCallSuper` 扩展点：它自己
/// 用 `position.moveTo(...)` 分页，我们只在其前登记意图并调用 `super`，不重算像素、不复制
/// 命中测试（design/26 §26.4）。thumb 拖动本来就走 `position.drag`（带 dragDetails），
/// 不在此处理。
class _TimelineScrollbar extends RawScrollbar {
  const _TimelineScrollbar({
    required super.controller,
    required super.thumbVisibility,
    required super.trackVisibility,
    required super.child,
    required this.onTrackTap,
    required this.onNoMovement,
  });

  final VoidCallback onTrackTap;
  final VoidCallback onNoMovement;

  @override
  RawScrollbarState<RawScrollbar> createState() => _TimelineScrollbarState();
}

class _TimelineScrollbarState extends RawScrollbarState<RawScrollbar> {
  @override
  void handleTrackTapDown(TapDownDetails details) {
    // 该 state 只由 [_TimelineScrollbar] 创建，回调来自它自己的 widget 字段。
    final scrollbar = widget as _TimelineScrollbar;
    final controller = scrollbar.controller;
    final before = controller != null && controller.hasClients
        ? controller.position.pixels
        : null;
    scrollbar.onTrackTap();
    super.handleTrackTapDown(details);
    if (before == null || controller == null || !controller.hasClients) {
      scrollbar.onNoMovement();
      return;
    }
    final position = controller.position;
    if (position.pixels == before && !position.isScrollingNotifier.value) {
      scrollbar.onNoMovement();
    }
  }
}
