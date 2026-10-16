part of 'studio_shell.dart';

class AgentWorkspacePane extends ConsumerStatefulWidget {
  const AgentWorkspacePane({super.key});

  @override
  ConsumerState<AgentWorkspacePane> createState() => _AgentWorkspacePaneState();
}

class _AgentWorkspacePaneState extends ConsumerState<AgentWorkspacePane> {
  static const _todoPanelWidth = 304.0;
  static const _defaultPlanPanelWidth = 560.0;
  static const _minimumPlanPanelWidth = 320.0;
  static const _minimumTimelineWidth = 560.0;
  static const _minimumPlanTimelineWidth = 600.0;
  static const _planResizeStep = 24.0;

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
  final Map<String, String> _expandedPlanByThread = {};
  final Map<String, String> _autoOpenedPlanByThread = {};
  double? _planPanelWidth;

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(shellSelectionProvider);
    final threadId = selection.selectedThreadId;
    final workspace = ref.watch(shellComposerWorkspaceProvider);
    final timeline = ref.watch(timelineSessionWindowProvider);
    // 无选中会话即起始页；新会话模式由 selection 清除 threadId 表达，不另读旧起始页。
    if (threadId == null) return const _StudioStartPage();
    if (workspace == null || workspace.threadId != threadId) {
      return const StudioWorkspaceLoading();
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
        if (_expandedPlanByThread[threadId] != planIdentity) {
          _expandedPlanByThread.remove(threadId);
        }
        // 覆盖与否只取决于窗口能否并排放置默认宽度面板与最小对话区，
        // 不受用户当前目标宽度影响，避免拖拽跨阈值时布局跳变打断手势。
        final planOverlaysTimeline =
            constraints.maxWidth <
            _defaultPlanPanelWidth + _minimumPlanTimelineWidth;
        final planExpanded =
            planIdentity != null &&
            _expandedPlanByThread[threadId] == planIdentity;
        // 并排上限 = min(可用宽度 − 对话区最小宽度, 可用宽度 × 0.5)；
        // 覆盖布局占满可用宽度。像素宽度只在 LayoutBuilder 内由可用宽度推导一次。
        final planMaximumWidth = planOverlaysTimeline
            ? constraints.maxWidth
            : [
                constraints.maxWidth - _minimumPlanTimelineWidth,
                constraints.maxWidth * 0.5,
              ].reduce((a, b) => a < b ? a : b);
        final planMinimumWidth = planMaximumWidth < _minimumPlanPanelWidth
            ? planMaximumWidth
            : _minimumPlanPanelWidth;
        final planPanelWidth = _normalizePlanPanelWidth(
          _planPanelWidth ?? _defaultPlanPanelWidth,
          planMinimumWidth,
          planMaximumWidth,
        );
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
            final current = ref.read(shellComposerWorkspaceProvider);
            if (current?.threadId != threadId ||
                current?.activeInteraction?.planConfirmation?.interactionId !=
                    pendingPlan.interactionId) {
              return;
            }
            setState(
              () => _expandedPlanByThread[threadId] =
                  'interaction:${pendingPlan.interactionId}',
            );
          });
        }
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: context.colors.surface,
          endDrawerEnableOpenDragGesture: false,
          endDrawer: !planExpanded && todoInDrawer && todo != null
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
              if (selection.needsOpen) _OpenThreadBanner(threadId: threadId),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: _AgentTimelineHost(
                                          threadId: threadId,
                                          planConfirmation: pendingPlan,
                                          planExpanded: planExpanded,
                                          onPlanToggle: pendingPlan == null
                                              ? null
                                              : () => _togglePlan(
                                                  threadId,
                                                  'interaction:${pendingPlan.interactionId}',
                                                ),
                                        ),
                                      ),
                                      if (workspace.loadError case final error?)
                                        Positioned(
                                          top: 0,
                                          left: 0,
                                          right: 0,
                                          child: Material(
                                            color:
                                                context.colors.errorContainer,
                                            child: Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: Row(
                                                children: [
                                                  Expanded(child: Text(error)),
                                                  TextButton(
                                                    onPressed: () =>
                                                        _retryThreadLoad(
                                                          threadId,
                                                        ),
                                                    child: Text(
                                                      context
                                                          .l10n
                                                          .runtimeFatalRetry,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (workspace.isLoading)
                                        Positioned.fill(
                                          child: StudioWorkspaceLoading(
                                            key: const ValueKey(
                                              'agent-workspace-loading',
                                            ),
                                            hasContent:
                                                (timeline != null &&
                                                timeline.threadId == threadId &&
                                                timeline.rows.isNotEmpty),
                                          ),
                                        ),
                                      if (planOverlaysTimeline &&
                                          presentedPlan != null &&
                                          planExpanded)
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          bottom: 0,
                                          width: planPanelWidth,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              minWidth: planMinimumWidth,
                                              maxWidth: planMaximumWidth,
                                            ),
                                            child: _buildPlanPanel(
                                              presentation: presentedPlan,
                                              threadId: threadId,
                                              minimumWidth: planMinimumWidth,
                                              maximumWidth: planMaximumWidth,
                                              overlay: true,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                _AdaptiveFooter(
                                  threadId: threadId,
                                  maxHeight: footerMaxHeight,
                                  showTodo: !planExpanded && todo != null,
                                  todoExpanded: !planExpanded && todoExpanded,
                                  onToggleTodo: planExpanded || todo == null
                                      ? null
                                      : () {
                                          if (todoInDrawer) {
                                            _scaffoldKey.currentState
                                                ?.openEndDrawer();
                                          } else {
                                            setState(
                                              () =>
                                                  _todoExpandedByThread[threadId] =
                                                      !todoExpanded,
                                            );
                                          }
                                        },
                                  showPlanEntry: approvedPlan != null,
                                  onOpenPlan: approvedPlan == null
                                      ? null
                                      : () => _openPlan(
                                          threadId,
                                          approvedPlan.identity,
                                        ),
                                ),
                              ],
                            ),
                          ),
                          if (!planOverlaysTimeline &&
                              presentedPlan != null &&
                              planExpanded)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: planMinimumWidth,
                                maxWidth: planMaximumWidth,
                              ),
                              child: SizedBox(
                                width: planPanelWidth,
                                child: _buildPlanPanel(
                                  presentation: presentedPlan,
                                  threadId: threadId,
                                  minimumWidth: planMinimumWidth,
                                  maximumWidth: planMaximumWidth,
                                  overlay: false,
                                ),
                              ),
                            ),
                          if (!planExpanded &&
                              !todoInDrawer &&
                              todo != null &&
                              todoExpanded)
                            SizedBox(
                              width: _todoPanelWidth,
                              child: TodoPanel(
                                key: const ValueKey('todo-side-panel'),
                                todo: todo,
                                onClose: () => setState(
                                  () => _todoExpandedByThread[threadId] = false,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 会话流失败重试。没有 thread 级 load 命令：重订阅当前 attachment，
  /// 并先标 reconnecting，避免失败条在新帧到达前一直盖住时间线。
  /// `selectThread` 对已选中会话只 `markOpened`，不能重开已关闭的流。
  void _retryThreadLoad(String threadId) {
    ref.read(anyworkClientProvider).retrySession(threadId);
  }

  void _togglePlan(String threadId, String identity) {
    setState(() {
      if (_expandedPlanByThread[threadId] == identity) {
        _expandedPlanByThread.remove(threadId);
      } else {
        _expandedPlanByThread[threadId] = identity;
      }
    });
  }

  void _openPlan(String threadId, String identity) {
    setState(() => _expandedPlanByThread[threadId] = identity);
  }

  void _closePlan(String threadId) {
    setState(() => _expandedPlanByThread.remove(threadId));
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

  /// 计划详情面板：左边缘分隔条 + 内容。并排与覆盖共用，避免语义偏差。
  Widget _buildPlanPanel({
    required _WorkspacePlanPresentation presentation,
    required String threadId,
    required double minimumWidth,
    required double maximumWidth,
    required bool overlay,
  }) {
    return Row(
      children: [
        _PlanResizeHandle(
          key: StudioDriverKeys.planResizeHandle,
          label: context.l10n.planResize,
          onDelta: (delta) =>
              _applyPlanPanelDelta(delta, minimumWidth, maximumWidth),
          onReset: _resetPlanPanelWidth,
          step: _planResizeStep,
        ),
        Expanded(
          child: PlanDetailPanel(
            identity: presentation.identity,
            markdown: presentation.markdown,
            statusLabel: presentation.pending
                ? context.l10n.interactionPlanAwaitingConfirmation
                : context.l10n.interactionPlanApproved,
            markdownStatus: presentation.pending ? 'pending' : 'approved',
            overlay: overlay,
            onClose: () => _closePlan(threadId),
          ),
        ),
      ],
    );
  }

  /// 在当前目标宽度基础上累计增量，而非从本次 build 的宽度重算：
  /// 先把当前状态收敛到当前限制，再加 delta 并再次收敛，确保连续拖拽或连按
  /// 方向键的增量逐步累加，不会相互覆盖。
  void _applyPlanPanelDelta(
    double delta,
    double minimumWidth,
    double maximumWidth,
  ) {
    setState(() {
      final base = _normalizePlanPanelWidth(
        _planPanelWidth ?? _defaultPlanPanelWidth,
        minimumWidth,
        maximumWidth,
      );
      _planPanelWidth = _normalizePlanPanelWidth(
        base + delta,
        minimumWidth,
        maximumWidth,
      );
    });
  }

  void _resetPlanPanelWidth() {
    setState(() => _planPanelWidth = _defaultPlanPanelWidth);
  }

  /// 用 LayoutBuilder 算出的同一 bounds 规范化目标宽度，避免拖拽死区。
  static double _normalizePlanPanelWidth(
    double desired,
    double minimum,
    double maximum,
  ) {
    if (maximum <= minimum) return maximum;
    return desired.clamp(minimum, maximum);
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

/// 计划详情面板左边缘分隔条（design/13-plan.md §13）。
///
/// 拖拽或双击调整宽度；宽度只属于当前 GUI 的临时视图状态，不写入 Plan
/// 状态机或持久化。
const double _planResizeHandleWidth = 5.0;

class _PlanResizeHandle extends StatefulWidget {
  const _PlanResizeHandle({
    required this.label,
    required this.onDelta,
    required this.onReset,
    required this.step,
    super.key,
  });

  /// 无障碍语义与 tooltip 文案。
  final String label;

  /// 宽度增量，正值加宽、负值收窄。
  final ValueChanged<double> onDelta;

  /// 恢复到默认宽度。
  final VoidCallback onReset;

  /// 方向键逐级调整的步长。
  final double step;

  @override
  State<_PlanResizeHandle> createState() => _PlanResizeHandleState();
}

class _PlanResizeHandleState extends State<_PlanResizeHandle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovering;
    final color = active
        ? context.colors.primary.withValues(alpha: 0.6)
        : context.colors.outlineVariant.withValues(alpha: 0.5);
    return FocusableActionDetector(
      actions: {
        _WidenPlanIntent: CallbackAction<_WidenPlanIntent>(
          onInvoke: (_) {
            widget.onDelta(widget.step);
            return null;
          },
        ),
        _NarrowPlanIntent: CallbackAction<_NarrowPlanIntent>(
          onInvoke: (_) {
            widget.onDelta(-widget.step);
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
      onShowHoverHighlight: (hovering) => setState(() => _hovering = hovering),
      mouseCursor: SystemMouseCursors.resizeColumn,
      child: Semantics(
        label: widget.label,
        button: true,
        child: Tooltip(
          message: widget.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (event) => widget.onDelta(-event.delta.dx),
            onDoubleTap: widget.onReset,
            child: Container(width: _planResizeHandleWidth, color: color),
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
    final project = ref.watch(startPageComposerViewProvider).project;
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
                        Text(
                          project == null
                              ? context.l10n.startPageOpenProjectTitle
                              : context.l10n.startPageWelcome,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: context.colors.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          project == null
                              ? context.l10n.startPageOpenProjectBody
                              : context.l10n.startPageProject(project.name),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 28),
                        const StartPageComposerDock(),
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
    return TimelineSessionConnector(
      threadId: threadId,
      planConfirmation: planConfirmation,
      planExpanded: planExpanded,
      onPlanToggle: onPlanToggle,
    );
  }
}
