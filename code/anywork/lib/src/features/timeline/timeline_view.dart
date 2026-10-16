import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';

import '../../presentation/providers/client_provider.dart';
import '../../l10n/studio_l10n.dart';
import '../../platform/external_url_launcher.dart';
import '../../shared/studio_chrome.dart';
import '../../shared/chat_view_events.dart';
import '../../shared/chat_view_metrics.dart';
import '../../shared/studio_driver_keys.dart';
import '../../shared/studio_driver_state.dart';
import '../../shared/typed_json.dart';
import 'markdown_repair.dart';

part 'timeline_blocks.dart';
part 'timeline_image_blocks.dart';
part 'timeline_markdown_blocks.dart';
part 'timeline_plan_blocks.dart';
part 'timeline_agent_blocks.dart';
part 'timeline_remote_image_blocks.dart';
part 'timeline_tool_blocks.dart';
part 'timeline_chat_controller.dart';
part 'timeline_paging.dart';
part 'timeline_layout_changes.dart';

typedef TimelineRemoteImageProviderFactory = ImageProvider Function(String url);

typedef _TimelineCorrectionToken = ({
  String? threadId,
  String? viewId,
  int windowEpoch,
  int readingGeneration,
});

final timelineRemoteImageProviderFactoryProvider =
    Provider<TimelineRemoteImageProviderFactory>((ref) => NetworkImage.new);

/// 纯显示组件：全部事实经构造参数进入，不内部订阅 provider、不在 props 与 store
/// 之间运行时选择事实来源（design/25 §25.8）。订阅与命令派发由连接组件
/// （`_AgentTimelineHost` 等）负责。
class TimelineView extends StatelessWidget {
  const TimelineView({
    required this.threadId,
    required this.rows,
    required this.body,
    required this.turn,
    this.planConfirmation,
    this.planExpanded = false,
    this.onPlanToggle,
    required this.onCommand,
    this.isLoadingOlder = false,
    this.isLoadingNewer = false,
    this.anchor,
    this.olderError,
    this.newerError,
    this.hasOlder = false,
    this.hasNewer = false,
    this.canExtendLatest = false,
    this.olderCursor,
    this.newerCursor,
    this.windowEpoch = 0,
    this.viewId,
    super.key,
  });

  final String? threadId;
  final List<TimelineRow> rows;

  /// canonical 窗口交付的正文状态：预览、回源在途、待落盘、不可用与错误。
  final ThreadHistoryWindow body;
  final StudioTurnView? turn;
  final PlanConfirmationView? planConfirmation;
  final bool planExpanded;
  final VoidCallback? onPlanToggle;
  final ValueChanged<TimelineCommand> onCommand;
  final bool isLoadingOlder;
  final bool isLoadingNewer;
  final TimelineAnchor? anchor;
  final String? olderError;
  final String? newerError;
  final bool hasOlder;
  final bool hasNewer;
  final bool canExtendLatest;
  final String? olderCursor;
  final String? newerCursor;
  final int windowEpoch;
  final String? viewId;

  @override
  Widget build(BuildContext context) {
    return _TimelineSurface(
      // ChatAnimatedList keeps removed children in an outgoing subtree even
      // when its remove duration is zero. The list controller and its render
      // objects therefore belong to one ChatView identity, not just to the
      // StatelessWidget element that receives the next window.
      // Replacing this key disposes the old sliver before a new thread/view
      // can reuse its children or layout offsets.
      key: ValueKey<(String?, String?)>((threadId, viewId)),
      threadId: threadId,
      rows: rows,
      body: body,
      turn: turn,
      planConfirmation: planConfirmation,
      planExpanded: planExpanded,
      onPlanToggle: onPlanToggle,
      onCommand: onCommand,
      isLoadingOlder: isLoadingOlder,
      isLoadingNewer: isLoadingNewer,
      anchor: anchor,
      olderError: olderError,
      newerError: newerError,
      hasOlder: hasOlder,
      hasNewer: hasNewer,
      canExtendLatest: canExtendLatest,
      olderCursor: olderCursor,
      newerCursor: newerCursor,
      windowEpoch: windowEpoch,
      viewId: viewId,
    );
  }
}

class _TimelineSurface extends StatefulWidget {
  const _TimelineSurface({
    required this.threadId,
    required this.rows,
    required this.body,
    required this.turn,
    this.planConfirmation,
    this.planExpanded = false,
    this.onPlanToggle,
    required this.onCommand,
    this.isLoadingOlder = false,
    this.isLoadingNewer = false,
    this.anchor,
    this.olderError,
    this.newerError,
    this.hasOlder = false,
    this.hasNewer = false,
    this.canExtendLatest = false,
    this.olderCursor,
    this.newerCursor,
    this.windowEpoch = 0,
    this.viewId,
    super.key,
  });

  final String? threadId;
  final List<TimelineRow> rows;
  final ThreadHistoryWindow body;
  final StudioTurnView? turn;
  final PlanConfirmationView? planConfirmation;
  final bool planExpanded;
  final VoidCallback? onPlanToggle;
  final ValueChanged<TimelineCommand> onCommand;
  final bool isLoadingOlder;
  final bool isLoadingNewer;
  final TimelineAnchor? anchor;
  final String? olderError;
  final String? newerError;
  final bool hasOlder;
  final bool hasNewer;
  final bool canExtendLatest;
  final String? olderCursor;
  final String? newerCursor;
  final int windowEpoch;
  final String? viewId;

  @override
  State<_TimelineSurface> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<_TimelineSurface> {
  static const _bottomThreshold = 80.0;

  /// 向旧加载的触发阈值：滚动位置进入列表顶部 3% 时请求旧页。
  static const _olderPaginationThreshold = 0.03;

  /// 向新加载的触发阈值：滚动位置进入列表底部 3% 时请求新页。
  static const _newerPaginationThreshold = 0.97;

  late final ScrollController _controller = ScrollController(
    keepScrollOffset: false,
  );
  final Map<String, _TimelineScrollSnapshot> _threadScroll = {};
  final Set<String> _expandedReasoningGroups = {};
  final Set<String> _expandedToolGroups = {};
  final _ThreadImageLoader _imageLoader = _ThreadImageLoader();

  /// 行外壳的复用缓存：只有承载该行的 `Message` 实例或本行展开态变化时才重建子树。
  ///
  /// `Message` 实例在「行内容、正文状态」都未变化时被控制器复用，因此这个缓存与
  /// 「未变化的行复用同一消息实例」是同一判据的两种用法：视图重建不会让未变化的行
  /// 重新布局 Markdown、工具详情或图片（design/19 §19.10）。
  final Map<String, _TimelineRowWidgetCache> _rowWidgets = {};

  /// 应用侧唯一的窗口 → 消息集合写入者（design/19 §19.10「渲染组件与行模型」）。
  late final TimelineChatController _chatController = TimelineChatController();

  /// 上游组件需要的构建器。它们只捕获本 State，不读取业务 provider。
  late final Builders _chatBuilders = Builders(
    chatMessageBuilder: _buildChatMessage,
    customMessageBuilder: (
      context,
      message,
      index, {
      isSentByMe = false,
      groupStatus,
    }) => const SizedBox.shrink(),
    chatAnimatedListBuilder: _buildChatList,
    composerBuilder: (context) => const SizedBox.shrink(),
    // 「跳到最新」的操作区保留布局空间、显隐不改变消息视口高度（design/19 §19.10），
    // 因此不使用上游浮动按钮，也不让加载提示占据列表高度：两者继续由外层承载。
    scrollToBottomBuilder: (context, animation, onPressed) =>
        const SizedBox.shrink(),
    loadMoreBuilder: (context) => const SizedBox.shrink(),
    emptyChatListBuilder: (context) => const _EmptyTimeline(),
  );

  TimelineReadingIntent _readingIntent = TimelineReadingIntent.followLatest;
  bool get _followingBottom =>
      _readingIntent == TimelineReadingIntent.followLatest;
  bool get _detachedByUser => !_followingBottom;
  bool get _canLoadOlder => widget.hasOlder;
  bool get _canLoadNewer => widget.hasNewer;
  bool get _canExtendLatest => widget.canExtendLatest;

  void _dispatch(TimelineCommand command) {
    widget.onCommand(command);
  }

  int _readingGeneration = 0;
  List<TimelineRow> _layoutRows = const [];
  TimelineAnchor? _settledAnchor;
  bool _programmaticScroll = false;
  bool _keyboardScrolling = false;
  bool _userScrollActive = false;
  double _textScale = 1;
  bool _resumeAfterNewerPage = false;
  bool _olderLoadRequested = false;
  bool _newerLoadRequested = false;
  _TimelineCorrectionToken? _prefetchScheduled;
  _TimelineCorrectionToken? _anchorPublishScheduled;

  /// 已进入历史阅读、但还没用一次 focus 意图表达出来的待发送标记。
  ///
  /// 只在意图切换的那一刻置位，发布锚点时消费一次；因此窗口内继续滚动不会重发 focus。
  bool _browseFocusPending = false;

  double? _viewportWidth;
  _TimelineCorrectionToken? _geometrySyncScheduled;

  /// 上一次上报的可见文本条目签名（身份 + 正文状态），用于去重（见 [_publishVisibleItemBodies]）。
  String? _visibleItemBodySignature;

  /// 只读诊断计数：真实指针拖动产生的滚动更新次数（`ScrollUpdateNotification.dragDetails`
  /// 非空；程序化 jump/animate 与滚轮不会+1）。
  ///
  /// 与 [_publishScrollDiagnostic] 里的 `programmaticScroll` 一起读，用来区分下面两种
  /// 「拖动后位置没变」：
  /// - 计数增长 → 手势确实到达了滚动视图，位置是本状态机（跟随/锚点恢复）改回去的；
  /// - 计数不增长 → 手势/命中测试没有到达滚动视图，问题不在锚点逻辑里。
  int _userDragUpdates = 0;

  final _viewportKey = GlobalKey();
  final Map<String, GlobalKey> _rowKeys = {};

  /// 上一帧进入布局的行身份，用于把「视觉异常」对应到具体的 mount/unmount。
  ///
  /// 帧末做一次集合差；只有身份集合真正变化才写事件，稳定输出不产生记录
  /// （design/25 §25.10）。
  Set<String>? _mountedRowIds;

  /// 滚动事件的公共身份：thread 与窗口 epoch 一起限定一次校正的归属。
  Map<String, String> get _scrollIdentity => {
    'thread': widget.threadId ?? '',
    'view': widget.viewId ?? '',
    'epoch': '${widget.windowEpoch}',
    'readingGeneration': '$_readingGeneration',
  };

  /// 记录本帧行身份的进入/离开；同一帧内只在集合变化时产生一条事件。
  void _trackMountedRows() {
    final next = {
      for (final entry in _rowKeys.entries)
        if (entry.value.currentContext?.mounted == true) entry.key,
    };
    final previous = _mountedRowIds;
    _mountedRowIds = next;
    if (previous == null) {
      ChatViewEvents.record(
        ChatViewEventKind.rowsMounted,
        identity: _scrollIdentity,
        details: {'reason': 'initialLayout', 'count': next.length},
      );
      return;
    }
    final mounted = next.difference(previous);
    final unmounted = previous.difference(next);
    if (mounted.isEmpty && unmounted.isEmpty) return;
    ChatViewEvents.record(
      ChatViewEventKind.rowsMounted,
      identity: _scrollIdentity,
      details: {
        'reason': 'frameLayout',
        'count': mounted.length,
        'items': mounted.take(8).join(','),
      },
    );
    ChatViewEvents.record(
      ChatViewEventKind.rowsUnmounted,
      identity: _scrollIdentity,
      details: {
        'reason': 'frameLayout',
        'count': unmounted.length,
        'items': unmounted.take(8).join(','),
      },
    );
  }

  /// 最近一次拖动方向是否朝更早的内容（`ScrollDirection.forward`）。
  ///
  /// 由 [_handleScrollPositionChanged] 维护，供 [_schedulePrefetch] 决定向前/向后补页。
  bool _scrollingOlder = true;
  int _pendingNewEvents = 0;
  int _contentVersion = 0;
  _TimelineRestore _pendingRestore = const _TimelineRestore.bottom();

  /// 待恢复的阅读意图（身份 + offset）是否还没被当前布局表达出来。
  ///
  /// 切回会话时正文可能先以**预览**布局出现（`omittedBytes > 0`）：目标内容偏移会被当前
  /// `maxScrollExtent` 钳位成更浅的位置。此时不能把钳位结果当成读者新的阅读位置——否则
  /// 完整正文到位、滚动范围变大后，读者会停在这个更浅的位置上（锚点被覆盖）。保持 `true`
  /// 直到目标能被布局表达；期间不据此判定“跟随最新”，也不重建/发布锚点。
  bool _restoreClamped = false;

  /// 最近一次非空选区的文本。
  ///
  /// Flutter 3.47 桌面端右键会把选区折叠后再构建菜单,菜单的 Copy 只能
  /// 依赖此缓存执行;线程切换时失效。
  String? _lastSelectedText;

  void _handleTimelineSelectionChanged(SelectedContent? content) {
    final text = content?.plainText;
    if (text != null && text.isNotEmpty) {
      _lastSelectedText = text;
    }
  }

  Widget _buildTimelineContextMenu(
    BuildContext context,
    SelectableRegionState selectableRegion,
  ) {
    final items = selectableRegion.contextMenuButtonItems;
    final hasCopy = items.any(
      (item) => item.type == ContextMenuButtonType.copy,
    );
    final cached = _lastSelectedText;
    if (!hasCopy && cached != null && cached.isNotEmpty) {
      items.insert(
        0,
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: cached));
            selectableRegion.hideToolbar();
          },
        ),
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      buttonItems: items,
      anchors: selectableRegion.contextMenuAnchors,
    );
  }

  @override
  void initState() {
    super.initState();
    _layoutRows = widget.rows;
    _contentVersion = _timelineContentVersion(
      widget.rows,
      widget.planConfirmation,
    );
    _restoreThreadState();
    _controller.addListener(_handleScrollPositionChanged);
    final token = _correctionToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && token == _correctionToken) {
        _restorePendingPosition();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _TimelineSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldRows = _layoutRows;
    _layoutRows = widget.rows;
    final threadChanged = widget.threadId != oldWidget.threadId;
    if (threadChanged) {
      _saveThreadState(oldWidget.threadId);
      _cancelLayoutRestore();
      _settledAnchor = null;
      _expandedReasoningGroups.clear();
      _expandedToolGroups.clear();
      _rowKeys.clear();
      _rowWidgets.clear();
      _visibleItemBodySignature = null;
      _lastSelectedText = null;
      _imageLoader.clear();
      _restoreThreadState();
      _contentVersion = _timelineContentVersion(
        widget.rows,
        widget.planConfirmation,
      );
      final token = _correctionToken;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && token == _correctionToken) {
          _restorePendingPosition();
        }
      });
      return;
    }
    final inspection = _pendingRestore.anchor ?? _settledAnchor;
    final viewChanged = oldWidget.viewId != widget.viewId;
    if (viewChanged || oldWidget.windowEpoch != widget.windowEpoch) {
      _cancelLayoutRestore();
    }
    if (_readingIntent == TimelineReadingIntent.inspectItem &&
        inspection != null &&
        _anchorRowId(inspection.itemId) == null) {
      _setReadingIntent(TimelineReadingIntent.followLatest);
      _cancelLayoutRestore();
    }
    _retainExpandedGroups(oldRows);
    if (viewChanged ||
        oldWidget.windowEpoch != widget.windowEpoch ||
        (oldWidget.olderCursor ?? oldRows.firstOrNull?.id) !=
            (widget.olderCursor ?? widget.rows.firstOrNull?.id) ||
        oldWidget.hasOlder != widget.hasOlder ||
        oldWidget.canExtendLatest != widget.canExtendLatest) {
      _olderLoadRequested = false;
    }

    if (viewChanged ||
        oldWidget.windowEpoch != widget.windowEpoch ||
        (oldWidget.newerCursor ?? oldRows.lastOrNull?.id) !=
            (widget.newerCursor ?? widget.rows.lastOrNull?.id) ||
        oldWidget.hasNewer != widget.hasNewer) {
      _newerLoadRequested = false;
    }
    if (_detachedByUser &&
        oldWidget.hasNewer &&
        !widget.hasNewer &&
        !_scrollingOlder) {
      _resumeAfterNewerPage = true;
    }
    _schedulePrefetch();
    final nextContentVersion = _timelineContentVersion(
      widget.rows,
      widget.planConfirmation,
    );
    if (nextContentVersion == _contentVersion) return;
    // 上一次恢复还没被几何表达（目标偏移被预览布局钳位）时，**意图优先**于当前可见位置：
    // 完整正文到达后要按同一身份 + offset 重新落位，而不是拿钳位后的 `_captureAnchor()`
    // 重建锚点，把读者真实的阅读位置覆盖掉。意图行还没进入窗口时同样保留意图：
    final restoreIntent = _restoreClamped ? _pendingRestore.anchor : null;
    // 后端 focus 只决定取窗范围，不是读者刚刚看到的位置。分页换掉分组
    // 首条时不能退回旧 focus 的 offset；切换会话的恢复意图已由上面的
    // _pendingRestore 单独保留，其余变化始终捕获更新前实际可见的身份。
    final anchor = restoreIntent ?? _captureAnchor(rows: oldRows);
    final hasNewEvent = _hasNewTimelineEvent(oldWidget, widget, oldRows);
    _contentVersion = nextContentVersion;
    final structureChanged =
        oldRows.length != widget.rows.length ||
        oldRows.indexed.any((entry) => entry.$2.id != widget.rows[entry.$1].id);
    if (structureChanged) _readingGeneration++;

    // 贴在窗口末尾时，内容变化（追加 / 历史分页 / 窗口替换）都保持跟随：`hasNewer`
    // 只表示窗口之外还有更新条目（由「跳到最新」入口表达），不代表读者离开了末尾。
    if (!_detachedByUser && _followingBottom) {
      _pendingNewEvents = 0;
      // The frame-end geometry sync follows the newly laid out max extent.
    } else {
      if (hasNewEvent || widget.hasNewer) _pendingNewEvents += 1;
      if (anchor != null &&
          _anchorRowId(anchor.itemId) != null &&
          (_restoreClamped ||
              structureChanged ||
              _needsAnchorRebase(anchor, oldRows))) {
        _prepareAnchorRestore(anchor);
      }
    }
  }

  @override
  void dispose() {
    _saveThreadState(widget.threadId);
    // 诊断投影随视图一起失效，避免驱动快照残留已销毁视图的几何。
    StudioDriverState.publishTimelineScroll(null);
    _controller.removeListener(_handleScrollPositionChanged);
    _controller.dispose();
    _chatController.dispose();
    _imageLoader.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (textScale != _textScale) {
      if (_detachedByUser && !_restoreClamped) {
        final anchor = _captureAnchor();
        if (anchor != null) _prepareAnchorRestore(anchor);
      }
      _textScale = textScale;
      _readingGeneration++;
    }
    _schedulePrefetch();
    final activeTurn = widget.turn?.state.isBusy == true ? widget.turn : null;
    if (widget.rows.isEmpty &&
        activeTurn == null &&
        widget.planConfirmation == null &&
        !_canLoadOlder &&
        !_canLoadNewer &&
        widget.olderError == null &&
        widget.newerError == null) {
      _chatController.applyWindow(widget.rows, widget.body);
      return const _EmptyTimeline();
    }
    _retainWindow(widget.rows);
    // 窗口 → 消息集合只在这里对齐一次：未变化的行复用同一 `Message` 实例。
    _chatController.applyWindow(
      widget.rows,
      widget.body,
      expandedReasoningGroups: _expandedReasoningGroups,
      expandedToolGroups: _expandedToolGroups,
    );
    // 本帧结束后按实际几何做一次归一 + 诊断发布。
    _scheduleGeometrySync();
    return PrimaryScrollController(
      controller: _controller,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ScrollIntent: _TimelineScrollAction(
            _controller,
            _handleKeyboardScroll,
          ),
        },
        child: _ThreadImageCacheScope(
          loader: _imageLoader,
          child: SelectionArea(
            onSelectionChanged: _handleTimelineSelectionChanged,
            contextMenuBuilder: _buildTimelineContextMenu,
            child: Stack(
              children: [
                // "跳到最新"占用滚动区之外的独立横条，而不是浮在消息列上：用户气泡右对齐，
                // 恰好落在底部角落，悬浮覆盖会挡住正文末尾。无提示时该横条不占高度。
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: StudioLayout.conversationWidth,
                      ),
                      child: Column(
                        children: [
                          Expanded(child: _buildViewport()),
                          Visibility(
                            visible: _showJumpToLatest,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: _JumpToLatestButton(
                                  pendingCount: _pendingNewEvents,
                                  onPressed: _jumpToLatest,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.isLoadingOlder || widget.olderError != null)
                  _edgeIndicator(older: true),
                if (widget.isLoadingNewer || widget.newerError != null)
                  _edgeIndicator(older: false),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 行身份、展开意图与图片缓存的窗口保留：淘汰的窗口条目不再留下展示状态。
  void _retainWindow(List<TimelineRow> rows) {
    final activeIds = {for (final row in rows) row.id};
    _rowKeys.removeWhere((id, _) => !activeIds.contains(id));
    _rowWidgets.removeWhere((id, _) => !activeIds.contains(id));
    _imageLoader.retainWindow(widget.threadId, rows);
    // 展开态按稳定分组身份保存，但只保留仍在窗口内的身份：历史分页淘汰/切回
    // 不留下再也用不到的 id，避免集合无界增长。
    _expandedReasoningGroups.retainAll({
      for (final row in rows)
        if (row.reasoningGroup case final group?) group.id,
    });
    _expandedToolGroups.retainAll({
      for (final row in rows)
        if (row.toolGroup case final group?) group.id,
    });
  }

  /// 上游列表的装配点：窗口消息集合交给 `ChatAnimatedList`。
  ///
  /// 应用侧只提供列表参数与方向回调：向旧由 `onEndReached` 表达、向新由
  /// `onStartReached` 表达，两端能力只从 canonical 窗口读（design/19 §19.10）。
  Widget _buildChatList(BuildContext context, ChatItem itemBuilder) {
    final planConfirmation = widget.planConfirmation;
    final planSummary = planConfirmation == null
        ? null
        : _layoutItem(
            'plan:${planConfirmation.interactionId}',
            TimelinePlanSummaryCard(
              plan: planConfirmation,
              expanded: widget.planExpanded,
              onPressed: widget.onPlanToggle ?? () {},
            ),
          );
    return ChatAnimatedList(
      itemBuilder: itemBuilder,
      scrollController: _controller,
      topPadding: 0,
      bottomPadding: 0,
      handleSafeArea: false,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: 600,
      insertAnimationDuration: Duration.zero,
      removeAnimationDuration: Duration.zero,
      scrollToEndAnimationDuration: Duration.zero,
      shouldScrollToEndWhenSendingMessage: false,
      shouldScrollToEndWhenAtBottom: false,
      initialScrollToEndMode: InitialScrollToEndMode.none,
      paginationThreshold: _olderPaginationThreshold,
      startPaginationThreshold: _newerPaginationThreshold,
      onEndReached: _handleOlderEdgeReached,
      onStartReached: _handleNewerEdgeReached,
      bottomSliver: SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _TimelineTail(planSummary: planSummary),
        ),
      ),
    );
  }

  /// 行外壳由应用渲染：不使用上游默认气泡、时间戳与对齐。
  Widget _buildChatMessage(
    BuildContext context,
    Message message,
    int index,
    Animation<double> animation,
    Widget child, {
    bool? isRemoved,
    required bool isSentByMe,
    MessageGroupStatus? groupStatus,
  }) {
    final row = TimelineChatController.rowOf(message);
    if (row == null) return const SizedBox.shrink();
    final reasoningExpanded = _expandedReasoningGroups.contains(
      row.reasoningGroup?.id,
    );
    final toolExpanded = _expandedToolGroups.contains(row.toolGroup?.id);
    final cached = _rowWidgets[row.id];
    if (cached != null &&
        identical(cached.message, message) &&
        cached.reasoningExpanded == reasoningExpanded &&
        cached.toolExpanded == toolExpanded) {
      return cached.child;
    }
    final built = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _buildRow(
        row,
        body: TimelineChatController.bodyOf(message),
        reasoningExpanded: reasoningExpanded,
        toolExpanded: toolExpanded,
      ),
    );
    _rowWidgets[row.id] = _TimelineRowWidgetCache(
      message: message,
      reasoningExpanded: reasoningExpanded,
      toolExpanded: toolExpanded,
      child: built,
    );
    return built;
  }

  Widget _buildViewport() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_viewportWidth != null &&
            _viewportWidth != constraints.maxWidth &&
            _detachedByUser &&
            !_restoreClamped) {
          final anchor = _captureAnchor();
          if (anchor != null) _prepareAnchorRestore(anchor);
        }
        _viewportWidth = constraints.maxWidth;
        return SizedBox(
          key: _viewportKey,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _handleScrollMetricsChanged,
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: _handleScrollUpdate,
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: Listener(
                  onPointerSignal: _handleBottomWheel,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(scrollbars: false),
                    child: RawScrollbar(
                      controller: _controller,
                      thumbVisibility: true,
                      child: KeyedSubtree(
                        key: StudioDriverKeys.timeline,
                        child: Chat(
                          currentUserId: TimelineChatController.localAuthorId,
                          resolveUser: _resolveChatUser,
                          chatController: _chatController,
                          backgroundColor: Colors.transparent,
                          builders: _chatBuilders,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool get _showJumpToLatest {
    return (widget.rows.isNotEmpty || widget.planConfirmation != null) &&
        (widget.hasNewer ||
            _detachedByUser ||
            _pendingNewEvents > 0 ||
            !_isNearBottom());
  }

  bool _isNearBottom() {
    if (!_controller.hasClients) {
      return true;
    }
    return _controller.position.extentAfter <= _bottomThreshold;
  }

  /// 用户是否正在主动把内容拉离末尾。
  ///
  /// 判据是滚动方向而不是单帧 `extentAfter`：Driver / 触摸拖动会被拆成每帧十几像素的
  /// 小步，单帧的 `extentAfter` 在累积离开 [_bottomThreshold] 之前一直落在阈值内。若
  /// 「近底即跟随」不看方向，就会在拖动还没真正离开阈值时把位置每帧拉回末尾——表现为
  /// `pixels` 恒定、`detachedByUser` 恒为 false，历史永远翻不动。
  ///
  /// `ScrollDirection.forward` = 手指下拖、内容向更早方向移动（位置朝 `minScrollExtent`）。
  /// 内容不足一屏但还有旧页时，上翻意图仍然有效；真正没有旧页的短会话才保持贴底。
  bool get _userPullingAwayFromBottom {
    if (!_controller.hasClients) return false;
    final position = _controller.position;
    if (position.userScrollDirection != ScrollDirection.forward) return false;
    return _canLoadOlder || position.pixels > position.minScrollExtent + 0.5;
  }

  void _handleKeyboardScroll(ScrollDirection direction) {
    _keyboardScrolling = true;
    _cancelLayoutRestore();
    _programmaticScroll = false;
    _handleScrollPositionChanged(direction: direction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      if (!_controller.position.isScrollingNotifier.value) {
        _keyboardScrolling = false;
      }
    });
  }

  void _handleBottomWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy <= 0 ||
        !_controller.hasClients ||
        _followingBottom ||
        widget.hasNewer ||
        _controller.position.extentAfter > 0.5) {
      return;
    }
    // A clamped Scrollable emits no update for this downward wheel. Register
    // behind the real Scrollable, so a nested scrollable that consumes the
    // event keeps its priority. Only the unconsumed edge expresses Latest.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted || !_controller.hasClients) return;
      _jumpToLatest();
    });
  }

  /// 列表的向旧加载回调。能力只从 canonical 窗口读，且每个在途方向只请求一次。
  Future<void> _handleOlderEdgeReached() async {
    if (!_canLoadOlder ||
        _olderLoadRequested ||
        widget.olderError != null ||
        widget.isLoadingOlder) {
      return;
    }
    _olderLoadRequested = true;
    ChatViewMetrics.prefetchLoadOlder += 1;
    _dispatch(const TimelineLoadOlder());
  }

  /// 列表的向新加载回调。
  Future<void> _handleNewerEdgeReached() async {
    if (!_canLoadNewer ||
        _newerLoadRequested ||
        widget.newerError != null ||
        widget.isLoadingNewer) {
      return;
    }
    _newerLoadRequested = true;
    ChatViewMetrics.prefetchLoadNewer += 1;
    _dispatch(const TimelineLoadNewer());
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.depth == 0 &&
        notification.dragDetails != null) {
      // Flutter establishes the drag before its first scroll
      // update. Layout correction in that gap would cancel it.
      _userScrollActive = true;
      _cancelLayoutRestore();
    }
    if (notification is UserScrollNotification) {
      return _handleUserScroll(notification);
    }
    if (notification is ScrollEndNotification &&
        notification.depth == 0 &&
        !_programmaticScroll) {
      _keyboardScrolling = false;
      _userScrollActive = false;
      _saveThreadState(widget.threadId);
      _scheduleGeometrySync();
    }
    return false;
  }

  bool _handleUserScroll(UserScrollNotification notification) {
    if (notification.depth == 0) {
      _userScrollActive = notification.direction != ScrollDirection.idle;
    }
    if (notification.depth == 0 &&
        notification.direction != ScrollDirection.idle) {
      // 不足一屏时 pixels 不会变化，但用户仍能选择向旧/向新补页。
      _cancelLayoutRestore();
      _handleScrollPositionChanged(direction: notification.direction);
    }
    return false;
  }

  /// 只读诊断：记录一次由真实指针拖动产生的滚动更新（见 [_userDragUpdates]）。
  ///
  /// 同时识别键盘/滚动条引起的位移；内层滚动不改变外层阅读意图。
  bool _handleScrollUpdate(ScrollUpdateNotification notification) {
    if (notification.depth != 0) return false;
    if (notification.dragDetails != null) {
      _userDragUpdates += 1;
      // 读者主动接管位置：放弃尚未被布局表达的恢复意图（不再回落到原锚点）。
      _cancelLayoutRestore();
    } else if (!_programmaticScroll &&
        _controller.hasClients &&
        _controller.position.userScrollDirection != ScrollDirection.idle) {
      // 滚轮 / 触控板等非拖动滚动同样是读者接管。
      _cancelLayoutRestore();
    }
    final delta = notification.scrollDelta;
    if (!_programmaticScroll &&
        (_userScrollActive || _keyboardScrolling) &&
        delta != null &&
        delta != 0 &&
        _controller.hasClients &&
        _controller.position.userScrollDirection == ScrollDirection.idle) {
      // 键盘和滚动条也能移动位置，但不一定设置 userScrollDirection。
      // 只在真实指针/键盘操作期间采纳，排除布局修正触发的空闲位移。
      _cancelLayoutRestore();
      _handleScrollPositionChanged(
        direction: delta < 0
            ? ScrollDirection.forward
            : ScrollDirection.reverse,
      );
    }
    // ScrollPosition listeners run before this notification. Cancelling the
    // old reading generation invalidates their callbacks, so register again
    // under the current identity while the pointer is still down.
    _scheduleGeometrySync();
    _schedulePrefetch();
    return false;
  }

  void _handleScrollPositionChanged({ScrollDirection? direction}) {
    // 位置变化（含程序化 jump）后按帧做几何同步并发布只读诊断。
    _scheduleGeometrySync();
    if (!_controller.hasClients || _programmaticScroll) {
      return;
    }
    direction ??= _controller.position.userScrollDirection;
    // 拖动方向既是"是否正在上翻历史"的判据，也决定向前/向后补页（见 [_schedulePrefetch]）：
    // `forward` = 手指下拖、朝更早内容；`reverse` = 朝更新的内容。`idle` 保持上一次方向。
    switch (direction) {
      case ScrollDirection.forward:
        _scrollingOlder = true;
        _resumeAfterNewerPage = false;
      case ScrollDirection.reverse:
        _scrollingOlder = false;
      case ScrollDirection.idle:
        break;
    }
    // 读者正在主动上翻历史时，即使本帧仍在「近底」阈值内，也不能当成想跟随最新：
    // 拖动分步到达，单帧距离可能永远不超过阈值（见 [_userPullingAwayFromBottom]）。
    final pullingAway = _userPullingAwayFromBottom;
    // 待恢复意图还没被布局表达时，当前位置只是预览布局下的钳位结果，不构成“读者在末尾”
    // 的事实：据此恢复跟随会直接吞掉待恢复的锚点。
    final nearBottom = _isNearBottom() && !widget.hasNewer && !_restoreClamped;
    if (nearBottom && direction == ScrollDirection.reverse && !pullingAway) {
      if (!_followingBottom || _detachedByUser || _pendingNewEvents != 0) {
        if (_userScrollActive) {
          _resumeAfterNewerPage = true;
          _saveThreadState(widget.threadId);
          return;
        }
        _followLatestBottom();
        // 用户滚回最新与点击“跳到最新”使用同一命令，恢复 ChatView 的 Latest
        // 聚焦；只改 UI 标志会让后续新消息继续留在历史窗口之外。
        _dispatch(const TimelineJumpToLatest());
      }
    } else if (direction != ScrollDirection.idle &&
        _readingIntent != TimelineReadingIntent.browseHistory) {
      setState(() {
        _setReadingIntent(TimelineReadingIntent.browseHistory);
      });
      // 进入历史阅读是一次真正的定位意图切换：只在这里登记一次 focus 意图。
      _browseFocusPending = true;
    }
    _saveThreadState(widget.threadId);
    _schedulePrefetch();
  }

  bool _handleScrollMetricsChanged(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;
    // 布局改变滚动范围后按帧做几何同步并发布只读诊断。
    _scheduleGeometrySync();
    _schedulePrefetch();
    return false;
  }

  void _scheduleBottomScroll() {
    if (!_followingBottom || _detachedByUser || _userScrollActive) return;
    _scheduleGeometrySync();
  }

  void _scrollToBottom() {
    if (!_controller.hasClients || _userScrollActive) return;
    if (!_followingBottom || _detachedByUser || _pendingNewEvents != 0) {
      setState(() {
        _setReadingIntent(TimelineReadingIntent.followLatest);
        _pendingNewEvents = 0;
      });
      _saveThreadState(widget.threadId);
    }
    final position = _controller.position;
    final previousPixels = position.pixels;
    if ((previousPixels - position.maxScrollExtent).abs() > 0.5) {
      _programmaticScroll = true;
      try {
        _controller.jumpTo(position.maxScrollExtent);
      } finally {
        _programmaticScroll = false;
      }
      ChatViewEvents.record(
        ChatViewEventKind.scrollCorrection,
        identity: _scrollIdentity,
        details: {
          'reason': 'followLatestBottom',
          'from': previousPixels,
          'to': position.maxScrollExtent,
        },
      );
    }
  }

  void _jumpToLatest() {
    // 阅读方向与最新窗口填充互不影响；扩充由布局与 canonical 容量决定。
    _scrollingOlder = false;
    _followLatestBottom();
    _dispatch(const TimelineJumpToLatest());
    _scheduleBottomScroll();
  }

  void _beginItemInspection() {
    setState(() => _setReadingIntent(TimelineReadingIntent.inspectItem));
  }

  void _setReadingIntent(TimelineReadingIntent intent) {
    if (_readingIntent == intent) return;
    _readingIntent = intent;
    _readingGeneration++;
  }

  void _followLatestBottom() {
    setState(() {
      _setReadingIntent(TimelineReadingIntent.followLatest);
      _pendingNewEvents = 0;
      _cancelLayoutRestore();
      _resumeAfterNewerPage = false;
    });
    _scheduleBottomScroll();
    _saveThreadState(widget.threadId);
  }

  void _toggleReasoning(String groupId) {
    setState(() {
      if (!_expandedReasoningGroups.remove(groupId)) {
        _expandedReasoningGroups.add(groupId);
      }
    });
  }

  /// 分页或聚焦会改变分组首条身份；仍有共同条目的组保留展开意图。
  /// 只迁移当前窗口的身份，不保留被淘汰的正文或远端分组状态。
  void _retainExpandedGroups(List<TimelineRow> previousRows) {
    final reasoningItems = <String>{};
    final toolItems = <String>{};
    for (final row in previousRows) {
      final reasoning = row.reasoningGroup;
      if (reasoning != null &&
          _expandedReasoningGroups.contains(reasoning.id)) {
        reasoningItems.addAll(reasoning.parts.map((part) => part.id));
      }
      final tools = row.toolGroup;
      if (tools != null && _expandedToolGroups.contains(tools.id)) {
        toolItems.addAll(tools.items.map((item) => item.id));
      }
    }
    for (final row in widget.rows) {
      final reasoning = row.reasoningGroup;
      if (reasoning != null &&
          reasoning.parts.any((part) => reasoningItems.contains(part.id))) {
        _expandedReasoningGroups.add(reasoning.id);
      }
      final tools = row.toolGroup;
      if (tools != null &&
          tools.items.any((item) => toolItems.contains(item.id))) {
        _expandedToolGroups.add(tools.id);
      }
    }
  }

  void _toggleToolGroup(String groupId) {
    setState(() {
      if (!_expandedToolGroups.remove(groupId)) {
        _expandedToolGroups.add(groupId);
      }
    });
  }

  /// 帧末做一次几何同步并发布只读滚动诊断（每帧最多一次）。
  ///
  /// 放在帧末是因为两者都依赖本帧最终布局出来的滚动几何：`build` 期间
  /// [ScrollPosition] 的 min/max/pixels 还是上一帧的值。
  ///
  /// 这是 Timeline 唯一的被动校正调度点：跟随底线、锚点落位与条目布局变化都登记到同一次
  /// 帧末校正，不再各自安排一次 post-frame。回调带下发时的（thread, view, windowEpoch,
  /// readingGeneration）身份，任一变化即丢弃——旧会话的回调不能作用于新会话。
  void _scheduleGeometrySync() {
    final token = _correctionToken;
    if (_geometrySyncScheduled == token) return;
    _geometrySyncScheduled = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_geometrySyncScheduled != token) return;
      _geometrySyncScheduled = null;
      if (!mounted || token != _correctionToken) return;
      _syncTimelineGeometry();
    });
  }

  _TimelineCorrectionToken get _correctionToken => (
    threadId: widget.threadId,
    viewId: widget.viewId,
    windowEpoch: widget.windowEpoch,
    readingGeneration: _readingGeneration,
  );

  void _syncTimelineGeometry() {
    _trackMountedRows();
    _restoreVisibleAnchor();
    // The lazy list may refine the extent of a very tall row over several
    // layouts. Keep followLatest attached to the real max extent; this is a
    // layout event response, never a timer or polling loop.
    if (_followingBottom &&
        !_detachedByUser &&
        !_userScrollActive &&
        !_keyboardScrolling) {
      _scrollToBottom();
    }
    // 索引定位和真实几何校正后确认恢复完成，再发布位置。
    if (_refreshRestorePending()) _saveThreadState(widget.threadId);
    if (_resumeAfterNewerPage &&
        !_programmaticScroll &&
        !_restoreClamped &&
        !_userScrollActive &&
        _controller.hasClients) {
      _resumeAfterNewerPage = false;
      // 用户向新翻页后真正抵达最新端，分页响应代替最后一次滚动事件完成跟随。
      // 只响应 hasNewer 从 true 到 false，不因普通内容增长或窗口缩放抢占阅读。
      if (_detachedByUser &&
          !_scrollingOlder &&
          !widget.hasNewer &&
          _isNearBottom()) {
        _followLatestBottom();
        _dispatch(const TimelineJumpToLatest());
      }
    }
    _publishVisibleItemBodies();
    _publishScrollDiagnostic();
    if (!_restoreClamped) _settledAnchor = _captureAnchor();
  }

  /// 上报当前视口内的文本条目身份；身份与正文状态都没变化时不上报，避免无谓的重建。
  ///
  /// 只上报文本行（用户 / parentAgent / 智能体正文）：它们的正文由窗口按身份自动补齐。
  /// 折叠的推理与工具分组不在此列，读者展开时的入口仍由分组行自己给出。
  ///
  /// 签名里同时带上该身份的正文状态与补齐标记，因此**新交付的窗口预览**（含会话重开后的
  /// 首窗）、**身份进入预览**与**补齐完成**都会重新上报一次，不需要读者滚动去触发补齐；
  /// 上报只在状态真正变化时发生，因此稳定的流式帧不会重复上报、不会自激。
  void _publishVisibleItemBodies() {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final body = widget.body;
    final ids = <String>[];
    final signature = StringBuffer();
    for (final row in widget.rows) {
      if (row.type != TimelineRowType.userMessage &&
          row.type != TimelineRowType.parentAgentMessage &&
          row.type != TimelineRowType.commentary &&
          row.type != TimelineRowType.finalAnswer) {
        continue;
      }
      final part = row.part;
      if (part == null) continue;
      final box = _rowKeys[row.id]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top + box.size.height <= 0 || top >= viewport.size.height) continue;
      ids.add(part.id);
      signature
        ..write(part.id)
        // 补齐按身份发起：进入/离开预览、在途、待落盘都会改变签名而重新上报一次，
        // 因此运行中的流式正文补齐后不会因内容继续增长而反复重发同一请求。
        ..write(part.status)
        ..write(body.previewedItemIds.contains(part.id) ? '1' : '0')
        ..write(body.loadingItemIds.contains(part.id) ? '1' : '0')
        ..write(body.pendingItemBodyIds.contains(part.id) ? '1' : '0')
        ..write('|');
    }
    final next = signature.toString();
    if (next == _visibleItemBodySignature) return;
    _visibleItemBodySignature = next;
    if (ids.isNotEmpty) _dispatch(TimelineVisibleBodies(ids));
  }

  /// Driver reports both window size and actually mounted lazy rows.
  void _publishScrollDiagnostic() {
    final position = _controller.hasClients ? _controller.position : null;
    StudioDriverState.publishTimelineScroll(
      TimelineScrollDiagnostic(
        threadId: widget.threadId,
        mountedRowCount: _rowKeys.values
            .where((key) => key.currentContext != null)
            .length,
        rowCount: widget.rows.length,
        readingIntent: _readingIntent,
        detachedByUser: _detachedByUser,
        pendingNewEvents: _pendingNewEvents,
        pixels: position?.pixels,
        minScrollExtent: position?.minScrollExtent,
        maxScrollExtent: position?.maxScrollExtent,
        viewportDimension: position?.viewportDimension,
        extentAfter: position?.extentAfter,
        bottomSlack: 0,
        hasNewer: widget.hasNewer,
        showJumpToLatest: _showJumpToLatest,
        programmaticScroll: _programmaticScroll,
        isScrolling: position?.isScrollingNotifier.value ?? false,
        userDragUpdates: _userDragUpdates,
        anchor: _captureAnchor(),
        restorePending: _restoreClamped,
        restoreAnchor: _pendingRestore.anchor,
      ),
    );
  }

  void _prepareAnchorRestore(TimelineAnchor anchor) {
    if (_userScrollActive || _keyboardScrolling) return;
    _pendingRestore = _TimelineRestore.anchor(
      anchor,
      target: _validLayoutTarget,
    );
    _restoreClamped = true;
    _scheduleGeometrySync();
  }

  void _restoreThreadState() {
    _programmaticScroll = false;
    _keyboardScrolling = false;
    _userScrollActive = false;
    _resumeAfterNewerPage = false;
    _scrollingOlder = true;
    final snapshot = _threadScroll[widget.threadId];
    final anchor = widget.anchor ?? snapshot?.anchor;
    _setReadingIntent(
      anchor?.readingIntent ?? TimelineReadingIntent.followLatest,
    );
    final detached = !_followingBottom;
    _pendingNewEvents = detached ? snapshot?.pendingNewEvents ?? 0 : 0;
    _pendingRestore = detached
        ? _TimelineRestore.anchor(anchor)
        : const _TimelineRestore.bottom();
    _restoreClamped = detached;
    _olderLoadRequested = false;
    _newerLoadRequested = false;
  }

  void _restorePendingPosition() {
    _scheduleGeometrySync();
    _schedulePrefetch();
  }

  /// Locate an unbuilt row by index, then correct against its painted position.
  /// A bounded number of frames settles estimates. A still-short preview retains
  /// the intent until its canonical body arrives; it never spins a frame loop.
  void _restoreVisibleAnchor() {
    if (!_restoreClamped ||
        _userScrollActive ||
        _keyboardScrolling ||
        !_controller.hasClients) {
      return;
    }
    final anchor = _pendingRestore.anchor;
    final layoutTarget = _validLayoutTarget;
    if (anchor == null && layoutTarget == null) return;
    final rowId = anchor == null ? null : _anchorRowId(anchor.itemId);
    final index = widget.rows.indexWhere((row) => row.id == rowId);
    if (index < 0 && layoutTarget == null) {
      // A new view initially opens at latest. Its Client owner restores the
      // historical focus through the same content pump; that first Reset is
      // not evidence that the saved reading identity has been evicted.
      if (widget.isLoadingOlder || widget.olderError != null) return;
      // The canonical window has evicted the requested identity. Keeping the
      // restore flag set forever would suppress new anchors and make every
      // later layout look like a pending recovery. Preserve the current
      // visible geometry and let the next real anchor establish a new intent.
      _restoreClamped = false;
      _pendingRestore = const _TimelineRestore.bottom();
      _settledAnchor = _captureAnchor();
      return;
    }
    var moved = false;
    _programmaticScroll = true;
    try {
      final target =
          (layoutTarget == null ? null : _layoutTargetPixels(layoutTarget)) ??
          (anchor == null ? null : _restoreTargetPixels(anchor));
      if (target != null) {
        final position = _controller.position;
        final clamped = target
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        if ((position.pixels - clamped).abs() > 0.5) {
          _controller.jumpTo(clamped);
          moved = true;
          ChatViewEvents.record(
            ChatViewEventKind.scrollCorrection,
            identity: {
              ..._scrollIdentity,
              'item': layoutTarget?.itemId ?? anchor?.itemId ?? '',
            },
            details: {
              'reason': layoutTarget == null
                  ? 'restoreReadingAnchor'
                  : 'restoreLayoutTarget',
              'from': position.pixels,
              'to': clamped,
              'clamped': (clamped - target).abs() > 0.5,
              'offset': anchor?.offset,
            },
          );
        }
      }
    } finally {
      _programmaticScroll = false;
    }
    if (moved) _scheduleGeometrySync();
  }

  double? _restoreTargetPixels(TimelineAnchor anchor) {
    final rowId = _anchorRowId(anchor.itemId);
    final box = _rowKeys[rowId]?.currentContext?.findRenderObject();
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        !box.hasSize ||
        !box.attached ||
        viewport is! RenderBox ||
        !_controller.hasClients) {
      return null;
    }
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    return _controller.position.pixels + top - anchor.offset;
  }

  bool _refreshRestorePending() {
    if (!_restoreClamped || _userScrollActive) return false;
    final anchor = _pendingRestore.anchor;
    if (!_controller.hasClients) return false;
    final layoutTarget = _validLayoutTarget;
    final rawTarget =
        (layoutTarget == null ? null : _layoutTargetPixels(layoutTarget)) ??
        (anchor == null ? null : _restoreTargetPixels(anchor));
    final target = layoutTarget != null
        ? rawTarget
              ?.clamp(
                _controller.position.minScrollExtent,
                _controller.position.maxScrollExtent,
              )
              .toDouble()
        : rawTarget;
    if (target == null || (_controller.position.pixels - target).abs() > 0.5) {
      return false;
    }
    _restoreClamped = false;
    return true;
  }

  void _saveThreadState(String? threadId) {
    if (threadId == null || !_controller.hasClients) return;
    if (threadId != widget.threadId) return;
    final token = _correctionToken;
    if (_anchorPublishScheduled == token) return;
    // 恢复意图还没被几何表达出来时，当前可见位置只是钳位结果，不能把它当成读者的阅读
    // 位置发布出去覆盖原锚点（原锚点要留给完整正文到位后的重新落位）。
    if (_restoreClamped) return;
    _anchorPublishScheduled = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_anchorPublishScheduled != token) return;
      _anchorPublishScheduled = null;
      if (!mounted || token != _correctionToken || _restoreClamped) return;
      final anchor = _captureAnchor();
      if (anchor == null) return;
      _threadScroll[threadId] = _TimelineScrollSnapshot(
        anchor: anchor,
        pendingNewEvents: _pendingNewEvents,
      );
      // 「要改后端焦点」是一次意图动作，不是消息里的状态：`browseHistory` 是持续意图，
      // 滚动每定稿一次都会重新发布锚点；按状态判断会让窗口内继续滚动每次都换后端焦点，
      // 而后端焦点变化会让内容流交付整窗 Reset。进入历史阅读只发一次 focus 意图。
      final action = _browseFocusPending
          ? TimelineViewAction.enterHistory
          : null;
      _browseFocusPending = false;
      _dispatch(TimelineAnchorChanged(anchor, viewAction: action));
    });
  }
}

/// Retains Flutter's keyboard scrolling and observes only the outer timeline's
/// actions. Keyboard navigation inside a nested tool-output scroller stays local.
class _TimelineScrollAction extends ScrollAction {
  _TimelineScrollAction(this.controller, this.onScroll);

  final ScrollController controller;
  final ValueChanged<ScrollDirection> onScroll;

  @override
  void invoke(ScrollIntent intent, [BuildContext? context]) {
    final nested = context == null ? null : Scrollable.maybeOf(context);
    if (controller.hasClients &&
        (nested == null || nested.position == controller.position) &&
        axisDirectionToAxis(intent.direction) == Axis.vertical) {
      onScroll(
        intent.direction == AxisDirection.up
            ? ScrollDirection.forward
            : ScrollDirection.reverse,
      );
    }
    super.invoke(intent, context);
  }
}

class _TimelineRestore {
  const _TimelineRestore.bottom() : anchor = null, target = null;
  const _TimelineRestore.anchor(this.anchor, {this.target});
  final TimelineAnchor? anchor;
  final _TimelineLayoutTarget? target;
}

/// 一行的行外壳子树及其有效性判据：承载它的消息实例与展开意图。
class _TimelineRowWidgetCache {
  const _TimelineRowWidgetCache({
    required this.message,
    required this.reasoningExpanded,
    required this.toolExpanded,
    required this.child,
  });

  final Message message;
  final bool reasoningExpanded;
  final bool toolExpanded;
  final Widget child;
}

class _TimelineScrollSnapshot {
  const _TimelineScrollSnapshot({
    required this.anchor,
    required this.pendingNewEvents,
  });
  final TimelineAnchor anchor;
  final int pendingNewEvents;
}

int _timelineContentVersion(
  List<TimelineRow> rows,
  PlanConfirmationView? plan,
) {
  return Object.hashAll([
    // 当前活动只在固定活动条里渲染，Turn 阶段帧不再影响 Timeline 布局；
    // 因此这里只跟踪消息行与计划，阶段变化不会重排/抢走阅读锚点。
    plan?.interactionId,
    plan?.markdown,
    rows.length,
    for (final row in rows) ...[row.id, row.type, row.renderVersion],
  ]);
}

/// 一条条目在窗口中的“完整正文”状态：预览 / 正在回源 / 回源失败。
///
/// 身份、顺序与 ordinal 由条目自身携带；这里只表达载荷是否需要回源，因此不会改变阅读位置。
class _ItemBodyState {
  const _ItemBodyState({
    required this.itemId,
    required this.isPreviewed,
    required this.isLoading,
    required this.isPending,
    required this.isUnavailable,
    this.label,
    this.error,
    this.onLoad,
  });

  /// canonical item 身份；回源与去重都以它为准，分组行的合成行身份不参与。
  final String itemId;

  /// 可选的数据来源标签（例如工具名），用于在同一分组里区分多条回源入口。
  final String? label;
  final bool isPreviewed;
  final bool isLoading;

  /// 回源已发出但完整正文尚未可取（例如历史事务尚未 durable）：入口仍可见可重试。
  final bool isPending;

  /// 数据源无法提供完整正文；此时不提供重试入口（重试也不会取到完整内容）。
  final bool isUnavailable;
  final String? error;
  final VoidCallback? onLoad;
}

bool _hasNewTimelineEvent(
  _TimelineSurface oldWidget,
  _TimelineSurface newWidget,
  List<TimelineRow> oldRows,
) {
  if (newWidget.planConfirmation?.interactionId != null &&
      newWidget.planConfirmation?.interactionId !=
          oldWidget.planConfirmation?.interactionId) {
    return true;
  }
  final oldIds = oldRows.map((row) => row.id).toSet();
  // 现在活动只出现在固定活动条里，不再从 Timeline 推导“当前活动”，因此
  // “有新内容”只由新条目/新计划决定。
  return newWidget.rows.any((row) => !oldIds.contains(row.id));
}

/// 上游 `Chat` 需要从任意 `authorId` 解析 `User`。应用侧行外壳完全自绘，
/// 用户对象只用于上游内部路径，因此这里给出稳定且不访问网络的实现。
Future<User?> _resolveChatUser(String id) async => User(id: id);
