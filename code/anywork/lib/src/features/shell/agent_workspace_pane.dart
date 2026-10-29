part of 'studio_shell.dart';

/// 会话阅读区域与输入栏的组合。
///
/// 阅读布局（并排 / 全宽 / 窄窗）只替换 [readingArea]；[footer] 始终是同一个子位置，
/// 因此布局切换、窗口跨阈值与计划详情关开都不会重建反馈栏的 State（草稿、错误与
/// 在途决定锁）。这条契约由 `test/client/plan_feedback_lifecycle_test.dart` 直接
/// 挂上真实 `PlanConfirmationDock` 断言。
class StudioWorkspaceBody extends StatelessWidget {
  const StudioWorkspaceBody({
    required this.readingArea,
    required this.footer,
    this.overlays = const [],
    this.todoPanel,
    super.key,
  });

  final Widget readingArea;
  final Widget footer;

  /// 覆盖在阅读区域上的瞬态提示（失败条、加载遮罩）；它们不参与布局分配。
  final List<Widget> overlays;

  /// 右侧 Todo 侧栏；计划详情打开时由调用方传 null 让位。
  final Widget? todoPanel;

  static const _todoPanelWidth = 304.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: readingArea),
                    for (final overlay in overlays)
                      if (_fillsReadingArea(overlay))
                        Positioned.fill(child: overlay)
                      else
                        Positioned(top: 0, left: 0, right: 0, child: overlay),
                  ],
                ),
              ),
              footer,
            ],
          ),
        ),
        if (todoPanel case final panel?)
          SizedBox(width: _todoPanelWidth, child: panel),
      ],
    );
  }

  /// 加载遮罩铺满阅读区域，行内失败条只贴上边缘。
  static bool _fillsReadingArea(Widget overlay) =>
      overlay.key == const ValueKey('agent-workspace-loading');
}

class _ReadingErrorBanner extends StatelessWidget {
  const _ReadingErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: Text(message)),
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.runtimeFatalRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class AgentWorkspacePane extends ConsumerStatefulWidget {
  const AgentWorkspacePane({
    required this.threadId,
    this.needsOpen = false,
    super.key,
  });

  final String? threadId;
  final bool needsOpen;

  @override
  ConsumerState<AgentWorkspacePane> createState() => _AgentWorkspacePaneState();
}

class _AgentWorkspacePaneState extends ConsumerState<AgentWorkspacePane> {
  static const _todoPanelWidth = 304.0;

  /// 计划详情默认宽度（design/13-plan.md §13.5）。只作为初始值与「恢复默认」目标，
  /// 打开后由分栏组件持有实际宽度。
  static const _defaultPlanPanelWidth = 720.0;

  /// 并排时计划至少保留的宽度，以及对话与操作至少保留的宽度。
  static const _minimumPlanPanelWidth = 360.0;
  static const _minimumConversationWidth = 400.0;

  /// 分隔条自身占用的布局宽度；命中区域由组件的 handle buffer 扩展到两侧。
  static const _planDividerThickness = 1.0;
  static const _planDividerHandleBuffer = 4.0;

  /// 分隔条聚焦后方向键的逐级步长。
  static const _planResizeStep = 24.0;

  /// 能否并排只由实际可用宽度与分隔条尺寸决定，不依据设备类型。
  static const _minimumSideBySideWidth =
      _minimumPlanPanelWidth +
      _minimumConversationWidth +
      _planDividerThickness;

  static const _minimumTimelineWidth = 560.0;

  /// footer 的高度上限 = 窗口高度 − 时间线**最小可视高度**。
  ///
  /// 这里刻意不用固定比例（例如半屏）：固定比例在矮窗口会把 composer 与状态栏之后的
  /// 剩余高度压到几像素，展开详情退化成「假展开」（实测 640×600 只剩 8.5px）。改为
  /// 先给时间线留出随窗口缩放的最小可视高度，再把其余高度交给 footer。
  static const _minimumTimelineHeight = 96.0;
  static const _maximumTimelineReserve = 200.0;
  static const _timelineReserveFraction = 0.3;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final Map<String, bool> _todoExpandedByThread = {};

  /// 当前打开的计划详情身份（`interaction:` 或 `approved:` 前缀）。
  final Map<String, String> _openedPlanByThread = {};
  final Map<String, String> _autoOpenedPlanByThread = {};

  /// 已显式切到「展开阅读」的会话；窄窗口直接全宽阅读，不写这里。
  final Set<String> _fullWidthPlanByThread = {};

  /// 计划宽度属于当前 GUI 的临时视图状态：关开面板与切换阅读布局都沿用它。
  double _planPanelWidth = _defaultPlanPanelWidth;

  /// 阅读布局之间保持同一 Element：并排、全宽与窄窗切换只改变几何，
  /// 不重建时间线（滚动、订阅、焦点）与计划正文滚动。
  final GlobalKey _timelineHostKey = GlobalKey(debugLabel: 'timeline-host');
  final GlobalKey _planPanelKey = GlobalKey(debugLabel: 'plan-panel');

  @override
  Widget build(BuildContext context) {
    final threadId = widget.threadId;
    if (threadId == null) return const _StudioStartPage();
    final workspaceProvider = conversationWorkspaceProvider(
      threadId,
      needsOpen: widget.needsOpen,
    );
    final workspace = ref.watch(workspaceProvider);
    if (workspace == null) {
      return TimelineConnector(threadId: threadId);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final todo = workspace.todo;
        final pendingPlan = workspace.activeInteraction?.planConfirmation;
        final approvedPlan = _approvedPlanPresentation(workspace.runtime.plan);
        // pending 与 approved 互斥：确认中只用 interaction 正文，批准后才用投影文档。
        final presentedPlan = pendingPlan != null
            ? _WorkspacePlanPresentation.fromPending(pendingPlan)
            : approvedPlan;
        final planIdentity = presentedPlan?.identity;
        if (_openedPlanByThread[threadId] != planIdentity) {
          _openedPlanByThread.remove(threadId);
        }
        if (planIdentity == null) _fullWidthPlanByThread.remove(threadId);
        final planOpen =
            planIdentity != null &&
            _openedPlanByThread[threadId] == planIdentity;
        // 能否并排只看真实可用宽度：窄窗口直接全宽阅读，不把文档挤进狭小侧栏，
        // 也不提供无意义的分隔条与宽度切换。判定不读当前拖动宽度，因此拖动过程中
        // 不会跨人为阈值重建布局。
        final sideBySideFeasible =
            constraints.maxWidth >= _minimumSideBySideWidth;
        final fullWidthReading =
            planOpen &&
            (!sideBySideFeasible || _fullWidthPlanByThread.contains(threadId));
        final todoInDrawer =
            constraints.maxWidth < _todoPanelWidth + _minimumTimelineWidth;
        final todoExpanded = _todoExpandedByThread[threadId] ?? false;
        final footerMaxHeight = constraints.hasBoundedHeight
            ? _footerMaxHeight(constraints.maxHeight)
            : null;
        if (pendingPlan != null &&
            _autoOpenedPlanByThread[threadId] != pendingPlan.interactionId) {
          _autoOpenedPlanByThread[threadId] = pendingPlan.interactionId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final current = ref.read(workspaceProvider);
            if (current?.threadId != threadId ||
                current?.activeInteraction?.planConfirmation?.interactionId !=
                    pendingPlan.interactionId) {
              return;
            }
            setState(
              () => _openedPlanByThread[threadId] =
                  'interaction:${pendingPlan.interactionId}',
            );
          });
        }
        final splitPlan =
            planOpen && !fullWidthReading && presentedPlan != null;
        final timelineDisplay = ref
            .watch(timelineViewModelProvider(threadId))
            .asData
            ?.value;
        final readingArea = _buildReadingArea(
          threadId: threadId,
          pendingPlan: pendingPlan,
          planOpen: planOpen,
          splitPlan: splitPlan,
          presentedPlan: presentedPlan,
          sideBySideFeasible: sideBySideFeasible,
        );
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: context.colors.surface,
          endDrawerEnableOpenDragGesture: false,
          endDrawer: !planOpen && todoInDrawer && todo != null
              ? Drawer(
                  width: 328,
                  backgroundColor: context.colors.surfaceContainer,
                  child: TodoPanel(
                    key: const ValueKey('todo-drawer-panel'),
                    todo: todo,
                    inDrawer: true,
                    onClose: () => _scaffoldKey.currentState?.closeEndDrawer(),
                  ),
                )
              : null,
          body: Column(
            children: [
              // 首帧后自动打开当前选择；打开前仍保留显式入口与输入区，
              // 便于用户直接开始交互或在失败后重试。
              if (widget.needsOpen) _OpenThreadBanner(threadId: threadId),
              Expanded(
                child: StudioWorkspaceBody(
                  readingArea: readingArea,
                  overlays: [
                    if (workspace.loadError case final error?)
                      _ReadingErrorBanner(
                        message: error,
                        onRetry: () => _retryThreadLoad(threadId),
                      ),
                    if (workspace.isLoading)
                      StudioWorkspaceLoading(
                        key: const ValueKey('agent-workspace-loading'),
                        hasContent:
                            timelineDisplay != null &&
                            timelineDisplay.threadId == threadId &&
                            timelineDisplay.generation > 0,
                      ),
                  ],
                  footer: _AdaptiveFooter(
                    threadId: threadId,
                    maxHeight: footerMaxHeight,
                    showTodo: !planOpen && todo != null,
                    todoExpanded: !planOpen && todoExpanded,
                    onToggleTodo: planOpen || todo == null
                        ? null
                        : () {
                            if (todoInDrawer) {
                              _scaffoldKey.currentState?.openEndDrawer();
                            } else {
                              setState(
                                () => _todoExpandedByThread[threadId] =
                                    !todoExpanded,
                              );
                            }
                          },
                    showPlanEntry: approvedPlan != null,
                    onOpenPlan: approvedPlan == null
                        ? null
                        : () => _openPlan(threadId, approvedPlan.identity),
                  ),
                  // 计划详情打开时优先于 Todo 侧栏；关闭后 Todo 按自己的 UI 状态恢复。
                  todoPanel:
                      !planOpen && !todoInDrawer && todo != null && todoExpanded
                      ? TodoPanel(
                          key: const ValueKey('todo-side-panel'),
                          todo: todo,
                          onClose: () => setState(
                            () => _todoExpandedByThread[threadId] = false,
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 会话阅读区域：只负责几何。所有分支共用同一时间线 Element（[KeyedSubtree]
  /// 携带 [_timelineHostKey]），全宽阅读时计划面板以同一 [_planPanelKey] 覆盖它。
  Widget _buildReadingArea({
    required String threadId,
    required PlanConfirmationView? pendingPlan,
    required bool planOpen,
    required bool splitPlan,
    required _WorkspacePlanPresentation? presentedPlan,
    required bool sideBySideFeasible,
  }) {
    final timeline = KeyedSubtree(
      key: _timelineHostKey,
      child: _AgentTimelineHost(
        threadId: threadId,
        planConfirmation: pendingPlan,
        planExpanded: planOpen,
        onPlanToggle: pendingPlan == null
            ? null
            : () => _togglePlan(
                threadId,
                'interaction:${pendingPlan.interactionId}',
              ),
      ),
    );
    final planPanel = presentedPlan == null
        ? null
        : KeyedSubtree(
            key: _planPanelKey,
            child: _buildPlanPanel(
              presentation: presentedPlan,
              threadId: threadId,
              fullWidth: !splitPlan,
              sideBySideFeasible: sideBySideFeasible,
            ),
          );
    if (splitPlan && planPanel != null) {
      return _PlanSplitView(
        initialPlanWidth: _planPanelWidth,
        defaultPlanWidth: _defaultPlanPanelWidth,
        minimumPlanWidth: _minimumPlanPanelWidth,
        minimumConversationWidth: _minimumConversationWidth,
        dividerThickness: _planDividerThickness,
        dividerHandleBuffer: _planDividerHandleBuffer,
        resizeStep: _planResizeStep,
        dividerLabel: context.l10n.planResize,
        onPlanWidthChanged: (width) => _planPanelWidth = width,
        conversation: timeline,
        plan: planPanel,
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: timeline),
        if (planOpen && planPanel != null) Positioned.fill(child: planPanel),
      ],
    );
  }

  /// 会话流失败重试。没有 thread 级 load 命令：重订阅当前 attachment，
  /// 并先标 reconnecting，避免失败条在新帧到达前一直盖住时间线。
  /// `selectThread` 对已选中会话只 `markOpened`，不能重开已关闭的流。
  void _retryThreadLoad(String threadId) {
    ref.read(anyworkClientProvider).conversations.session(threadId).refresh();
  }

  void _togglePlan(String threadId, String identity) {
    setState(() {
      if (_openedPlanByThread[threadId] == identity) {
        _openedPlanByThread.remove(threadId);
      } else {
        _openedPlanByThread[threadId] = identity;
      }
    });
  }

  void _openPlan(String threadId, String identity) {
    setState(() => _openedPlanByThread[threadId] = identity);
  }

  void _closePlan(String threadId) {
    setState(() => _openedPlanByThread.remove(threadId));
  }

  /// 并排 ↔ 全宽阅读：只切换阅读布局，不改正文、决定或阅读位置。
  void _toggleReadingMode(String threadId) {
    setState(() {
      if (!_fullWidthPlanByThread.remove(threadId)) {
        _fullWidthPlanByThread.add(threadId);
      }
    });
  }

  static _WorkspacePlanPresentation? _approvedPlanPresentation(
    PlanRuntimeView? plan,
  ) {
    final document = plan?.document;
    if (plan == null ||
        plan.state != PlanRuntimePhase.approved ||
        document == null) {
      return null;
    }
    return _WorkspacePlanPresentation.fromApproved(document);
  }

  /// footer 可用高度上限：先给时间线留下最小可视高度，剩余高度交给 footer。
  double _footerMaxHeight(double viewportHeight) {
    final reserve = (viewportHeight * _timelineReserveFraction)
        .clamp(_minimumTimelineHeight, _maximumTimelineReserve)
        .toDouble();
    final available = viewportHeight - reserve;
    return available > 0 ? available : 0;
  }

  /// 计划详情面板：只读文档页，并排与全宽共用同一构造，避免两套语义。
  Widget _buildPlanPanel({
    required _WorkspacePlanPresentation presentation,
    required String threadId,
    required bool fullWidth,
    required bool sideBySideFeasible,
  }) {
    return PlanDetailConnector(
      identity: presentation.identity,
      markdown: presentation.markdown,
      awaitingConfirmation: presentation.pending,
      fullWidth: fullWidth,
      onToggleReadingMode: sideBySideFeasible
          ? () => _toggleReadingMode(threadId)
          : null,
      onClose: () => _closePlan(threadId),
    );
  }
}

class _WorkspacePlanPresentation {
  const _WorkspacePlanPresentation({
    required this.identity,
    required this.markdown,
    required this.pending,
  });

  factory _WorkspacePlanPresentation.fromPending(PlanConfirmationView plan) {
    return _WorkspacePlanPresentation(
      identity: 'interaction:${plan.interactionId}',
      markdown: plan.markdown,
      pending: true,
    );
  }

  factory _WorkspacePlanPresentation.fromApproved(PlanDocumentView document) {
    return _WorkspacePlanPresentation(
      identity: 'approved:${document.version}',
      markdown: document.markdown,
      pending: false,
    );
  }

  final String identity;
  final String markdown;
  final bool pending;
}

/// 计划并排阅读区：会话列 + 计划详情的可拖动分栏。
///
/// 拖动、尺寸分配与边界求解全部交给 `multi_split_view`；这里只补三件它没有的能力：
/// 用真实可用宽度给计划区一次 `max` 边界（保证对话仍有最小宽度）、把分隔条接到键盘
/// 与语义（薄 [FocusableActionDetector]），以及把实际宽度回报给上层视图状态。
class _PlanSplitView extends StatefulWidget {
  const _PlanSplitView({
    required this.initialPlanWidth,
    required this.defaultPlanWidth,
    required this.minimumPlanWidth,
    required this.minimumConversationWidth,
    required this.dividerThickness,
    required this.dividerHandleBuffer,
    required this.resizeStep,
    required this.dividerLabel,
    required this.onPlanWidthChanged,
    required this.conversation,
    required this.plan,
  });

  final double initialPlanWidth;
  final double defaultPlanWidth;
  final double minimumPlanWidth;
  final double minimumConversationWidth;
  final double dividerThickness;
  final double dividerHandleBuffer;
  final double resizeStep;
  final String dividerLabel;
  final ValueChanged<double> onPlanWidthChanged;
  final Widget conversation;
  final Widget plan;

  @override
  State<_PlanSplitView> createState() => _PlanSplitViewState();
}

class _PlanSplitViewState extends State<_PlanSplitView> {
  static const _conversationAreaId = 'conversation';
  static const _planAreaId = 'plan';

  MultiSplitViewController? _controller;
  Area? _planArea;
  double? _appliedContainerWidth;

  @override
  void dispose() {
    _controller
      ?..removeListener(_reportWidth)
      ..dispose();
    super.dispose();
  }

  /// 首次布局才有真实宽度：此时才按实际可用宽度创建区域与边界。
  void _ensureAreas(double containerWidth) {
    if (_controller != null) return;
    final maximumPlanWidth = _maximumPlanWidth(containerWidth);
    final initialWidth = widget.initialPlanWidth
        .clamp(widget.minimumPlanWidth, maximumPlanWidth)
        .toDouble();
    final planArea = Area(
      id: _planAreaId,
      size: initialWidth,
      min: widget.minimumPlanWidth,
      max: maximumPlanWidth,
    );
    _planArea = planArea;
    _appliedContainerWidth = containerWidth;
    _controller = MultiSplitViewController(
      areas: [
        Area(id: _conversationAreaId, flex: 1),
        planArea,
      ],
    )..addListener(_reportWidth);
    widget.onPlanWidthChanged(initialWidth);
  }

  /// 计划最多能占的宽度：任何时刻都给对话与操作留下最小宽度。
  double _maximumPlanWidth(double containerWidth) {
    final available =
        containerWidth -
        widget.minimumConversationWidth -
        widget.dividerThickness;
    return available < widget.minimumPlanWidth
        ? widget.minimumPlanWidth
        : available;
  }

  /// 容器宽度变化只在布局后应用：`Area` 的 setter 会通知重建，不能在构建期间改几何。
  void _applyContainerWidth(double containerWidth) {
    if (_appliedContainerWidth == containerWidth) return;
    _appliedContainerWidth = containerWidth;
    final area = _planArea;
    if (area == null) return;
    final maximumPlanWidth = _maximumPlanWidth(containerWidth);
    if (area.max != maximumPlanWidth) area.max = maximumPlanWidth;
    final size = area.size;
    if (size != null && size > maximumPlanWidth) area.size = maximumPlanWidth;
  }

  void _reportWidth() {
    final size = _planArea?.size;
    if (size != null) widget.onPlanWidthChanged(size);
  }

  /// 方向键逐级调整：只给组件一个目标宽度，边界收敛仍由它的 min/max 完成。
  void _adjustPlanWidth(double delta) {
    final area = _planArea;
    if (area == null) return;
    final current = area.size ?? widget.defaultPlanWidth;
    area.size = current + delta;
  }

  void _resetPlanWidth() {
    final area = _planArea;
    if (area == null) return;
    area.size = widget.defaultPlanWidth;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureAreas(constraints.maxWidth);
        if (_appliedContainerWidth != constraints.maxWidth) {
          // 宽度变化只在布局后应用：`Area` 的 setter 会通知重建。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _applyContainerWidth(constraints.maxWidth);
          });
        }
        return MultiSplitViewTheme(
          data: MultiSplitViewThemeData(
            dividerThickness: widget.dividerThickness,
            dividerHandleBuffer: widget.dividerHandleBuffer,
          ),
          child: MultiSplitView(
            controller: _controller,
            dividerBuilder: _buildDivider,
            onDividerDoubleTap: (_) => _resetPlanWidth(),
            builder: (context, area) =>
                area.id == _planAreaId ? widget.plan : widget.conversation,
          ),
        );
      },
    );
  }

  /// 分隔条：组件负责拖动与双击，这里只补键盘/语义与安静的悬停高亮。
  Widget _buildDivider(
    Axis axis,
    int index,
    bool resizable,
    bool dragging,
    bool highlighted,
    MultiSplitViewThemeData themeData,
  ) {
    return _PlanDividerHandle(
      key: StudioDriverKeys.planResizeHandle,
      label: widget.dividerLabel,
      thickness: themeData.dividerThickness,
      dragging: dragging,
      highlighted: highlighted,
      onAdjust: _adjustPlanWidth,
      onReset: _resetPlanWidth,
      step: widget.resizeStep,
    );
  }
}

/// 计划分隔条：只承载键盘与语义，拖动与双击属于分栏组件。
class _PlanDividerHandle extends StatefulWidget {
  const _PlanDividerHandle({
    required this.label,
    required this.thickness,
    required this.dragging,
    required this.highlighted,
    required this.onAdjust,
    required this.onReset,
    required this.step,
    super.key,
  });

  /// 无障碍语义与 tooltip 文案。
  final String label;

  /// 分隔条本身的宽度。
  final double thickness;

  final bool dragging;
  final bool highlighted;

  /// 宽度增量，正值加宽计划、负值收窄。
  final ValueChanged<double> onAdjust;

  /// 恢复到默认宽度。
  final VoidCallback onReset;

  /// 方向键逐级调整的步长。
  final double step;

  @override
  State<_PlanDividerHandle> createState() => _PlanDividerHandleState();
}

class _PlanDividerHandleState extends State<_PlanDividerHandle> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.dragging || widget.highlighted || _focused;
    final color = active
        ? context.colors.primary.withValues(alpha: 0.65)
        : context.colors.outlineVariant.withValues(alpha: 0.7);
    return FocusableActionDetector(
      actions: {
        _WidenPlanIntent: CallbackAction<_WidenPlanIntent>(
          onInvoke: (_) {
            widget.onAdjust(widget.step);
            return null;
          },
        ),
        _NarrowPlanIntent: CallbackAction<_NarrowPlanIntent>(
          onInvoke: (_) {
            widget.onAdjust(-widget.step);
            return null;
          },
        ),
        _ResetPlanWidthIntent: CallbackAction<_ResetPlanWidthIntent>(
          onInvoke: (_) {
            widget.onReset();
            return null;
          },
        ),
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _WidenPlanIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NarrowPlanIntent(),
        SingleActivator(LogicalKeyboardKey.home): _ResetPlanWidthIntent(),
      },
      onShowFocusHighlight: (focused) => setState(() => _focused = focused),
      mouseCursor: SystemMouseCursors.resizeColumn,
      child: Semantics(
        label: widget.label,
        slider: true,
        child: Tooltip(
          message: widget.label,
          child: ColoredBox(
            color: color,
            child: SizedBox(width: widget.thickness),
          ),
        ),
      ),
    );
  }
}

class _WidenPlanIntent extends Intent {
  const _WidenPlanIntent();
}

class _NarrowPlanIntent extends Intent {
  const _NarrowPlanIntent();
}

class _ResetPlanWidthIntent extends Intent {
  const _ResetPlanWidthIntent();
}

/// footer 预算低于该值时启用紧凑布局：让 composer 适度收起留白与输入行数（保留操作），
/// 把省下的高度让给展开详情，同时避免矮窗口 `RenderFlex` 溢出。
const _compactFooterBudget = 400.0;

/// 在窗口较矮时把可伸缩的活动条压进剩余空间，而不是让整条 footer 滚动。
///
/// 整条 footer 放进滚动容器会把「装不下」变成「输入区被裁到窗口外」：容器只保证
/// `maxHeight` 内的内容可见，超出的部分（正好是底部的输入区与发送/停止按钮）被静默
/// 裁掉。这里只给出高度上限，footer 内部把唯一可伸缩的活动条压到剩余高度里（见
/// [_Footer]），因此输入区始终完整可见，活动条详情在自身范围内滚动。
///
/// footer 的总高度上限由 [AgentWorkspacePane] 按「窗口高度 − 时间线最小可视高度」给出；
/// 这里仅据该预算决定是否进入紧凑布局（唯一所有者，不在别处重复读窗口尺寸）。
class _AdaptiveFooter extends StatelessWidget {
  const _AdaptiveFooter({
    required this.threadId,
    required this.maxHeight,
    required this.showTodo,
    required this.todoExpanded,
    required this.onToggleTodo,
    this.showPlanEntry = false,
    this.onOpenPlan,
  });

  final String threadId;
  final double? maxHeight;
  final bool showTodo;
  final bool todoExpanded;
  final VoidCallback? onToggleTodo;
  final bool showPlanEntry;
  final VoidCallback? onOpenPlan;

  @override
  Widget build(BuildContext context) {
    if (maxHeight == null) {
      return _Footer(
        threadId: threadId,
        showTodo: showTodo,
        todoExpanded: todoExpanded,
        onToggleTodo: onToggleTodo,
        showPlanEntry: showPlanEntry,
        onOpenPlan: onOpenPlan,
        compact: false,
        contentKey: StudioDriverKeys.workspaceFooterScroll,
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight!),
      child: LayoutBuilder(
        // ConstrainedBox 已把窗口预算收成有界 maxHeight，这里据此决定紧凑与否，避免在
        // composer 里再读一次窗口尺寸形成第二套事实源。
        builder: (context, constraints) => _Footer(
          threadId: threadId,
          showTodo: showTodo,
          todoExpanded: todoExpanded,
          onToggleTodo: onToggleTodo,
          showPlanEntry: showPlanEntry,
          onOpenPlan: onOpenPlan,
          compact: constraints.maxHeight < _compactFooterBudget,
          // footer 区域的可定位句柄：内容不再整体滚动，但保持同一 key，便于驱动按区域定位。
          contentKey: StudioDriverKeys.workspaceFooterScroll,
        ),
      ),
    );
  }
}

/// 已选中但尚未打开的会话：显式打开入口。
///
/// 此处不读取会话状态、不打开 history 数据库、不加载历史（§6.1）。用户点击“打开会话”
/// （或在输入区输入/提交、滚动历史）才会激活会话；打开只恢复当前状态与订阅，不自动
/// 续跑模型/工具执行。
class _OpenThreadBanner extends ConsumerWidget {
  const _OpenThreadBanner({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      key: StudioDriverKeys.unopenedThread,
      color: context.colors.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            Tooltip(
              message: context.l10n.threadUnopenedTitle,
              child: Icon(
                Icons.play_circle_outline,
                size: 18,
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.threadUnopenedBody,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ),
            KeyedSubtree(
              key: StudioDriverKeys.openSelectedThread,
              child: FilledButton(
                key: StudioDriverKeys.openThread(threadId),
                onPressed: () => unawaited(
                  ref
                      .read(anyworkClientProvider)
                      .directoryCommands
                      .selectThread(threadId),
                ),
                child: Text(context.l10n.threadOpenAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioStartPage extends ConsumerWidget {
  const _StudioStartPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(startPageComposerViewModelProvider);
    final preparationState = ref.watch(_standalonePreparationStateProvider);
    void retryStandalonePreparation() {
      unawaited(
        ref
            .read(anyworkClientProvider)
            .directoryCommands
            .beginStandaloneThread()
            .catchError((Object _) {}),
      );
    }

    Widget failureView(String error) => _StandalonePreparationFailureView(
      message: context.l10n.sidebarStandalonePrepareFailed(error),
      onRetry: retryStandalonePreparation,
    );

    final projection = state.asData?.value;
    if (projection == null) {
      return Scaffold(
        key: StudioDriverKeys.startPage,
        backgroundColor: context.colors.surface,
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.hasError) ...[
                  Text(state.error.toString()),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(startPageComposerViewModelProvider),
                    child: Text(context.l10n.sidebarRetry),
                  ),
                ] else
                  const CircularProgressIndicator(),
                if (preparationState.error case final error?)
                  failureView(error),
              ],
            ),
          ),
        ),
      );
    }
    final project = projection.project;
    final standalone = project == null || project.isStandalone;
    final preparation = projection.preparation;
    return Scaffold(
      key: StudioDriverKeys.startPage,
      backgroundColor: context.colors.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: StudioLayout.conversationWidth,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (preparationState.error case final error?)
                          failureView(error),
                        if (project != null && preparation != null)
                          ThreadPreparationCard(
                            key: ValueKey(preparation.inputId),
                            project: project,
                            preparation: preparation,
                          )
                        else ...[
                          Text(
                            context.l10n.startPageWelcome,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: context.colors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            standalone
                                ? context.l10n.startPageStandaloneBody
                                : context.l10n.startPageProject(project.name),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        const StartPageComposerDockConnector(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StandalonePreparationFailureView extends StatelessWidget {
  const _StandalonePreparationFailureView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: StudioDriverKeys.standalonePreparationFailure,
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            key: StudioDriverKeys.standalonePreparationFailureMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.error),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: StudioDriverKeys.standalonePreparationRetry,
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(context.l10n.sidebarNewSession),
          ),
        ],
      ),
    );
  }
}

class _AgentTimelineHost extends ConsumerWidget {
  const _AgentTimelineHost({
    required this.threadId,
    required this.planConfirmation,
    required this.planExpanded,
    required this.onPlanToggle,
  });

  final String threadId;
  final PlanConfirmationView? planConfirmation;
  final bool planExpanded;
  final VoidCallback? onPlanToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TimelineConnector(
      threadId: threadId,
      planConfirmation: planConfirmation,
      planExpanded: planExpanded,
      onPlanToggle: onPlanToggle,
    );
  }
}
