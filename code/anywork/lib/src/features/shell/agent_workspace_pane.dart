part of 'studio_shell.dart';

/// 会话阅读区域与输入栏的组合。
///
/// 阅读布局（并排 / 全宽 / 窄窗）只替换 [readingArea]；[footer] 始终是同一个子位置，
/// 因此布局切换、窗口跨阈值与计划详情关开都不会重建反馈栏的 State（草稿、错误与
/// 在途决定锁）。这条契约由 `test/ui/plan_feedback_lifecycle_test.dart` 直接
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
    final planHead = widget.needsOpen
        ? null
        : ref.watch(
            threadSessionStoreProvider(threadId)
                .select((state) => state.businessRefs?.plan),
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final todo = workspace.todo;
        final pendingPlan = workspace.activeInteraction?.planConfirmation;
        final referencedPlan = _referencedPlanPresentation(planHead);
        // pending 独占确认动作与 interaction 正文；无 pending 时，有 document 的
        // 起草 / 要求修订 / 已批准映射真实 status 作为只读入口，无文档不伪造。
        final presentedPlan = pendingPlan != null
            ? _WorkspacePlanPresentation.fromPending(pendingPlan)
            : referencedPlan;
        final todoInDrawer =
            constraints.maxWidth < _todoPanelWidth + _minimumTimelineWidth;
        final todoExpanded = _todoExpandedByThread[threadId] ?? false;
        final footerMaxHeight = constraints.hasBoundedHeight
            ? _footerMaxHeight(constraints.maxHeight)
            : null;
        final timelineDisplay = ref
            .watch(timelineViewModelProvider(threadId))
            .asData
            ?.value;
        return _WorkspaceReading(
          threadId: threadId,
          pendingPlan: pendingPlan,
          presentedPlan: presentedPlan,
          builder: (context, readingArea, readingOpen, onOpenPlan) {
            return Scaffold(
              key: _scaffoldKey,
              backgroundColor: context.colors.surface,
              endDrawerEnableOpenDragGesture: false,
              endDrawer: !readingOpen && todoInDrawer && todo != null
                  ? Drawer(
                      width: 328,
                      backgroundColor: context.colors.surfaceContainer,
                      child: TodoPanel(
                        key: const ValueKey('todo-drawer-panel'),
                        todo: todo,
                        inDrawer: true,
                        onClose: () =>
                            _scaffoldKey.currentState?.closeEndDrawer(),
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
                        scrollPlan: pendingPlan != null,
                        showTodo: !readingOpen && todo != null,
                        todoExpanded: !readingOpen && todoExpanded,
                        onToggleTodo: readingOpen || todo == null
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
                        showPlanEntry:
                            pendingPlan == null && referencedPlan != null,
                        onOpenPlan:
                            pendingPlan != null || referencedPlan == null
                            ? null
                            : onOpenPlan,
                      ),
                      // 计划详情打开时优先于 Todo 侧栏；关闭后 Todo 按自己的 UI 状态恢复。
                      todoPanel:
                          !readingOpen &&
                              !todoInDrawer &&
                              todo != null &&
                              todoExpanded
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
      },
    );
  }

  /// 会话流失败重试。没有 thread 级 load 命令：重订阅当前 attachment，
  /// 并先标 reconnecting，避免失败条在新帧到达前一直盖住时间线。
  /// `selectThread` 对已选中会话只 `markOpened`，不能重开已关闭的流。
  void _retryThreadLoad(String threadId) {
    ref.read(anyworkClientProvider).conversations.session(threadId).refresh();
  }

  static _WorkspacePlanPresentation? _referencedPlanPresentation(
    CurrentPlanHead? plan,
  ) {
    if (plan == null) {
      return null;
    }
    return _WorkspacePlanPresentation.fromHead(plan);
  }

  /// footer 可用高度上限：先给时间线留下最小可视高度，剩余高度交给 footer。
  double _footerMaxHeight(double viewportHeight) {
    final reserve = (viewportHeight * _timelineReserveFraction)
        .clamp(_minimumTimelineHeight, _maximumTimelineReserve)
        .toDouble();
    final available = viewportHeight - reserve;
    return available > 0 ? available : 0;
  }
}

/// footer 预算低于该值时启用紧凑布局：让 composer 适度收起留白与输入行数（保留操作），
/// 把省下的高度让给展开详情，同时避免矮窗口 `RenderFlex` 溢出。
const _compactFooterBudget = 400.0;

/// 使用 workspace 的高度预算。常规 composer 保持输入区完整可见、只压缩活动条；
/// Plan 的完整确认表单允许区内滚动，让短窗和大字下的两项决定仍可到达。
class _AdaptiveFooter extends StatelessWidget {
  const _AdaptiveFooter({
    required this.threadId,
    required this.maxHeight,
    required this.scrollPlan,
    required this.showTodo,
    required this.todoExpanded,
    required this.onToggleTodo,
    this.showPlanEntry = false,
    this.onOpenPlan,
  });

  final String threadId;
  final double? maxHeight;
  final bool scrollPlan;
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
        builder: (context, constraints) {
          final footer = _Footer(
            threadId: threadId,
            showTodo: showTodo,
            todoExpanded: todoExpanded,
            onToggleTodo: onToggleTodo,
            showPlanEntry: showPlanEntry,
            onOpenPlan: onOpenPlan,
            compact: constraints.maxHeight < _compactFooterBudget,
            contentKey: StudioDriverKeys.workspaceFooterScroll,
          );
          return scrollPlan
              ? SingleChildScrollView(
                  key: const ValueKey('plan-workspace-footer-scroll'),
                  primary: false,
                  child: footer,
                )
              : footer;
        },
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
    final workspaceId = ref.watch(
      selectionStoreProvider.select((selection) => selection.selectedProjectId),
    );
    final project = ref
        .watch(projectStoreProvider)
        .projects
        ?.values
        .where((project) => project.id == workspaceId)
        .firstOrNull;
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

    if (project == null) {
      return Scaffold(
        key: StudioDriverKeys.startPage,
        backgroundColor: context.colors.surface,
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (preparationState.error case final error?)
                  failureView(error),
              ],
            ),
          ),
        ),
      );
    }
    final standalone = project.isStandalone;
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
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (preparationState.error case final error?)
                          failureView(error),
                        ...[
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
                        Composer(
                          target: ComposerTarget.start(workspaceId: project.id),
                          onAddProject: () =>
                              unawaited(showAddProjectDialog(context)),
                        ),
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
