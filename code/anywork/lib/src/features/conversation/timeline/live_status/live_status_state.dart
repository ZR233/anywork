import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../widgets/timeline_activity_row.dart';

/// 根据类型化活动阶段、前台活跃工具事实以及当前顶栏是否正在展示思考摘要解析指示器样式：
/// - `responding` -> 分层书写动态图标；
/// - `compacting` -> 经典拉链齿动态 ZIP 压缩图标；
/// - 当前顶栏正在展示思考摘要（`displayingThinkingSummary == true`）-> 趴卧摇尾猫图标；
/// - `runningTool` 且前台正在运行 `exec`（无思考摘要时）-> 圆形进度指示器；
/// - 其余等待/思考阶段 -> 趴卧摇尾猫图标。
TimelineActivityIndicatorStyle resolveLiveHeaderIndicatorStyle(
  ConversationActivityView? view, {
  bool displayingThinkingSummary = false,
}) {
  if (view == null) return TimelineActivityIndicatorStyle.restingCat;
  if (view.kind == ConversationActivityKind.responding) {
    return TimelineActivityIndicatorStyle.writing;
  }
  if (view.kind == ConversationActivityKind.compacting) {
    return TimelineActivityIndicatorStyle.compactingZip;
  }
  if (displayingThinkingSummary) {
    return TimelineActivityIndicatorStyle.restingCat;
  }
  if (view.isRunningExecTool) {
    return TimelineActivityIndicatorStyle.circularProgress;
  }
  return TimelineActivityIndicatorStyle.restingCat;
}

/// 区分底部实时状态栏与上方时间线实时工作区两条独立的更早窗口分页通道。
enum LiveStatusSectionTarget { outputBar, timelineWork }

/// 实时窗口有效性切面身份：只要窗口修订、历史水位、执行在场性、尝试代数或展示资格改变，
/// 已打开的 `older` 实时分页窗口立即失效归零，绝不跨切面残留旧实时页。
@immutable
final class LiveWindowCut {
  const LiveWindowCut({
    required this.revision,
    required this.readyFrontier,
    required this.executionPresent,
    required this.attemptId,
    required this.isDisplayActive,
  });

  const LiveWindowCut.inactive()
    : revision = null,
      readyFrontier = null,
      executionPresent = null,
      attemptId = null,
      isDisplayActive = false;

  final int? revision;
  final int? readyFrontier;
  final bool? executionPresent;
  final Object? attemptId;
  final bool isDisplayActive;

  bool get hasWindow => isDisplayActive && revision != null;

  bool matchesWindow(TailSnapshot window) =>
      revision == window.layoutRevision &&
      readyFrontier == window.readyFrontier &&
      executionPresent == window.executionPresent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveWindowCut &&
          revision == other.revision &&
          readyFrontier == other.readyFrontier &&
          executionPresent == other.executionPresent &&
          attemptId == other.attemptId &&
          isDisplayActive == other.isDisplayActive;

  @override
  int get hashCode => Object.hash(
    revision,
    readyFrontier,
    executionPresent,
    attemptId,
    isDisplayActive,
  );
}

/// 实时窗口分页状态机子状态：替代原先散落在 Widget `State` 中的 `_older`/`_loadingOlder`/`_olderError`。
@immutable
sealed class LiveWindowPagingState {
  const LiveWindowPagingState();

  TailSnapshot? get olderWindow => switch (this) {
    ViewingOlderLiveWindow(:final window) => window,
    LatestLiveWindow() ||
    LoadingOlderLiveWindow() ||
    OlderLiveWindowFailed() => null,
  };

  bool get isLoading => this is LoadingOlderLiveWindow;
  bool get isViewingOlder => this is ViewingOlderLiveWindow;

  Object? get error => switch (this) {
    OlderLiveWindowFailed(:final error) => error,
    _ => null,
  };

  /// 切面变化时自动重置回最新实时窗口。
  LiveWindowPagingState reconcile(LiveWindowCut currentCut) {
    if (!currentCut.hasWindow) return const LatestLiveWindow();
    return switch (this) {
      LatestLiveWindow() => this,
      LoadingOlderLiveWindow(:final cut) ||
      ViewingOlderLiveWindow(:final cut) ||
      OlderLiveWindowFailed(
        :final cut,
      ) => cut == currentCut ? this : const LatestLiveWindow(),
    };
  }
}

final class LatestLiveWindow extends LiveWindowPagingState {
  const LatestLiveWindow();

  @override
  bool operator ==(Object other) => other is LatestLiveWindow;

  @override
  int get hashCode => (LatestLiveWindow).hashCode;
}

final class LoadingOlderLiveWindow extends LiveWindowPagingState {
  const LoadingOlderLiveWindow({
    required this.before,
    required this.cut,
    this.previousOlder,
  });

  final String before;
  final LiveWindowCut cut;
  final TailSnapshot? previousOlder;

  @override
  TailSnapshot? get olderWindow => previousOlder;

  @override
  bool get isViewingOlder => previousOlder != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoadingOlderLiveWindow &&
          before == other.before &&
          cut == other.cut &&
          identical(previousOlder, other.previousOlder);

  @override
  int get hashCode => Object.hash(before, cut, previousOlder);
}

final class ViewingOlderLiveWindow extends LiveWindowPagingState {
  const ViewingOlderLiveWindow({
    required this.before,
    required this.window,
    required this.cut,
  });

  final String before;
  final TailSnapshot window;
  final LiveWindowCut cut;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewingOlderLiveWindow &&
          before == other.before &&
          identical(window, other.window) &&
          cut == other.cut;

  @override
  int get hashCode => Object.hash(before, window, cut);
}

final class OlderLiveWindowFailed extends LiveWindowPagingState {
  const OlderLiveWindowFailed({
    required this.before,
    required this.error,
    required this.cut,
    this.previousOlder,
  });

  final String before;
  @override
  final Object error;
  final LiveWindowCut cut;
  final TailSnapshot? previousOlder;

  @override
  TailSnapshot? get olderWindow => previousOlder;

  @override
  bool get isViewingOlder => previousOlder != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OlderLiveWindowFailed &&
          before == other.before &&
          error == other.error &&
          cut == other.cut &&
          identical(previousOlder, other.previousOlder);

  @override
  int get hashCode => Object.hash(before, error, cut, previousOlder);
}

/// 实时状态栏顶层特殊通知封闭联合类型。
@immutable
sealed class LiveStatusNotice {
  const LiveStatusNotice();
}

final class ExecutionLiveNotice extends LiveStatusNotice {
  const ExecutionLiveNotice(this.view);
  final ConversationActivityView view;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExecutionLiveNotice && view == other.view;

  @override
  int get hashCode => view.hashCode;
}

final class UnrestoredLiveNotice extends LiveStatusNotice {
  const UnrestoredLiveNotice();

  @override
  bool operator ==(Object other) => other is UnrestoredLiveNotice;

  @override
  int get hashCode => (UnrestoredLiveNotice).hashCode;
}

/// 实时状态栏可见时的主表面封闭联合类型：
/// 仅在对应表面有意义的载荷严格内聚在各自变体内部，禁止平行可空字段。
@immutable
sealed class LiveStatusPrimarySurface {
  const LiveStatusPrimarySurface();

  /// 按稳定顺序交付给底部实时状态栏渲染的实时展示块。
  List<LiveDisplayBlock> get blocks;

  /// 独立渲染在块列表上方的阶段/故障通知（已被开放 Work 头或流式正文吸收的通知不含在内）。
  List<LiveStatusNotice> get standaloneNotices;

  /// 若指定开放 `Work` 吸收了当前轮次活动通知，返回其吸收后的通知视图。
  ConversationActivityView? mergedActivityFor(String blockId) => null;
}

/// 表面 1：当前活跃前台轮次的开放工作组（`WorkDisplayBlock`）占据实时状态栏。
final class LiveStatusWorkSurface extends LiveStatusPrimarySurface {
  LiveStatusWorkSurface({
    required this.workBlock,
    List<LiveDisplayBlock> precedingSingles = const [],
    this.mergedActivity,
    required this.headerIndicatorStyle,
    List<LiveStatusNotice> standaloneNotices = const [],
  }) : precedingSingles = List.unmodifiable(precedingSingles),
       standaloneNotices = List.unmodifiable(standaloneNotices),
       blocks = List.unmodifiable([...precedingSingles, workBlock]);

  final LiveDisplayBlock workBlock;
  final List<LiveDisplayBlock> precedingSingles;
  final ConversationActivityView? mergedActivity;
  final TimelineActivityIndicatorStyle headerIndicatorStyle;
  @override
  final List<LiveStatusNotice> standaloneNotices;
  @override
  final List<LiveDisplayBlock> blocks;

  @override
  ConversationActivityView? mergedActivityFor(String blockId) =>
      workBlock.id == blockId ? mergedActivity : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusWorkSurface &&
          identical(workBlock, other.workBlock) &&
          listEquals(precedingSingles, other.precedingSingles) &&
          mergedActivity == other.mergedActivity &&
          headerIndicatorStyle == other.headerIndicatorStyle &&
          listEquals(standaloneNotices, other.standaloneNotices);

  @override
  int get hashCode => Object.hash(
    workBlock,
    Object.hashAll(precedingSingles),
    mergedActivity,
    headerIndicatorStyle,
    Object.hashAll(standaloneNotices),
  );
}

/// 表面 2：流式正文、活跃压缩原子或更早实时单块（`SingleDisplayBlock`）占据实时状态栏。
final class LiveStatusStreamingSurface extends LiveStatusPrimarySurface {
  LiveStatusStreamingSurface({
    required List<LiveDisplayBlock> singleBlocks,
    List<LiveStatusNotice> standaloneNotices = const [],
  }) : singleBlocks = List.unmodifiable(singleBlocks),
       standaloneNotices = List.unmodifiable(standaloneNotices);

  final List<LiveDisplayBlock> singleBlocks;
  @override
  final List<LiveStatusNotice> standaloneNotices;

  @override
  List<LiveDisplayBlock> get blocks => singleBlocks;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusStreamingSurface &&
          listEquals(singleBlocks, other.singleBlocks) &&
          listEquals(standaloneNotices, other.standaloneNotices);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(singleBlocks),
    Object.hashAll(standaloneNotices),
  );
}

/// 表面 3：无实时块占据底栏，仅展示纯阶段通知（思考中、压缩中、`exec` 运行中、审批或存储故障等）或分页回退。
final class LiveStatusNoticeOnlySurface extends LiveStatusPrimarySurface {
  LiveStatusNoticeOnlySurface({List<LiveStatusNotice> notices = const []})
    : standaloneNotices = List.unmodifiable(notices);

  @override
  final List<LiveStatusNotice> standaloneNotices;

  @override
  List<LiveDisplayBlock> get blocks => const [];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusNoticeOnlySurface &&
          listEquals(standaloneNotices, other.standaloneNotices);

  @override
  int get hashCode => Object.hashAll(standaloneNotices);
}

/// 底部实时状态栏封闭生命周期状态机状态。
@immutable
sealed class LiveStatusMachineState {
  const LiveStatusMachineState();

  bool get showInteractionDetails => switch (this) {
    LiveStatusHidden() => false,
    LiveStatusDockMasked(:final showInteractionDetails) =>
      showInteractionDetails,
    LiveStatusPresenting(:final showInteractionDetails) =>
      showInteractionDetails,
  };
}

/// 状态 1：完全收起隐藏（无活动、无开放块、无待决交互详情）。
final class LiveStatusHidden extends LiveStatusMachineState {
  const LiveStatusHidden();

  @override
  bool operator ==(Object other) => other is LiveStatusHidden;

  @override
  int get hashCode => (LiveStatusHidden).hashCode;
}

/// 状态 2：待决问答或实施计划确认遮蔽底部活动条（普通问答保留只读交互详情入口，确认计划完全隐藏）。
final class LiveStatusDockMasked extends LiveStatusMachineState {
  const LiveStatusDockMasked({
    required this.interactionId,
    required this.showInteractionDetails,
    this.obscured,
  });

  final String interactionId;
  final LiveStatusPresenting? obscured;
  @override
  final bool showInteractionDetails;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusDockMasked &&
          interactionId == other.interactionId &&
          obscured == other.obscured &&
          showInteractionDetails == other.showInteractionDetails;

  @override
  int get hashCode =>
      Object.hash(interactionId, showInteractionDetails, obscured);
}

/// 状态 3：底部实时状态栏激活呈现中。
final class LiveStatusPresenting extends LiveStatusMachineState {
  const LiveStatusPresenting({
    required this.surface,
    required this.effectiveWindow,
    required this.paging,
    required this.showInteractionDetails,
  });

  final LiveStatusPrimarySurface surface;
  final TailSnapshot? effectiveWindow;
  final LiveWindowPagingState paging;
  @override
  final bool showInteractionDetails;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusPresenting &&
          surface == other.surface &&
          identical(effectiveWindow, other.effectiveWindow) &&
          paging == other.paging &&
          showInteractionDetails == other.showInteractionDetails;

  @override
  int get hashCode =>
      Object.hash(surface, effectiveWindow, paging, showInteractionDetails);
}

/// 交付给上方 `TimelineConnector` 的只读时间线实时工作区切片：
/// 仅当归属时间线区的封存/遮蔽/跨轮次 `Work` 块或分页变化时才通知重建。
@immutable
final class LiveStatusTimelineWorkSlice {
  LiveStatusTimelineWorkSlice({
    List<LiveDisplayBlock> workBlocks = const [],
    this.effectiveWindow,
    this.paging = const LatestLiveWindow(),
  }) : workBlocks = List.unmodifiable(workBlocks);

  static final empty = LiveStatusTimelineWorkSlice();

  final List<LiveDisplayBlock> workBlocks;
  final TailSnapshot? effectiveWindow;
  final LiveWindowPagingState paging;

  bool get hasVisibleContent =>
      workBlocks.isNotEmpty ||
      paging.isViewingOlder ||
      paging.isLoading ||
      paging.error != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusTimelineWorkSlice &&
          listEquals(workBlocks, other.workBlocks) &&
          identical(effectiveWindow, other.effectiveWindow) &&
          paging == other.paging;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(workBlocks), effectiveWindow, paging);
}

/// 状态机纯输入快照：仅保存客户端已归约的不可变领域值，不持有原生流或可变句柄。
@immutable
final class LiveStatusInputs {
  LiveStatusInputs({
    required this.cut,
    this.storage,
    List<PendingInteraction> interactions = const [],
    this.businessRefs,
    this.activeTurnId,
    this.activity,
    this.latestLive,
    this.hasContentOwner = false,
  }) : interactions = List.unmodifiable(interactions);

  const LiveStatusInputs.empty()
    : cut = const LiveWindowCut.inactive(),
      storage = null,
      interactions = const [],
      businessRefs = null,
      activeTurnId = null,
      activity = null,
      latestLive = null,
      hasContentOwner = false;

  final LiveWindowCut cut;
  final ThreadStorageStateView? storage;
  final List<PendingInteraction> interactions;
  final ThreadBusinessRefs? businessRefs;
  final String? activeTurnId;
  final ThreadActivityView? activity;
  final TailSnapshot? latestLive;
  final bool hasContentOwner;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusInputs &&
          cut == other.cut &&
          storage == other.storage &&
          listEquals(interactions, other.interactions) &&
          businessRefs == other.businessRefs &&
          activeTurnId == other.activeTurnId &&
          activity == other.activity &&
          identical(latestLive, other.latestLive) &&
          hasContentOwner == other.hasContentOwner;

  @override
  int get hashCode => Object.hash(
    cut,
    storage,
    Object.hashAll(interactions),
    businessRefs,
    activeTurnId,
    activity,
    latestLive,
    hasContentOwner,
  );
}

/// 当前组件实际使用的只读展示结果；只含派生表面，不保存业务输入镜像或诊断发布账本。
@immutable
final class LiveStatusView {
  const LiveStatusView({
    required this.threadId,
    required this.cut,
    required this.barState,
    required this.timelineWork,
    this.primaryActivity,
  });
  final String threadId;
  final LiveWindowCut cut;
  final LiveStatusMachineState barState;
  final LiveStatusTimelineWorkSlice timelineWork;
  final ConversationActivityView? primaryActivity;
  bool get hasAnyRealtimeRegion =>
      barState is! LiveStatusHidden || timelineWork.workBlocks.isNotEmpty;
}
