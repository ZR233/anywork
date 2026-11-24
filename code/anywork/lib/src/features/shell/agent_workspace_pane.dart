part of 'studio_shell.dart';

class _ConversationDirectoryUnavailable extends ConsumerWidget {
  const _ConversationDirectoryUnavailable({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadata = ref.watch(threadMetadataStoreProvider(threadId));
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            metadata.error?.message ??
                context.l10n.conversationDirectoryUnavailable,
          ),
          TextButton(
            key: const ValueKey('conversation-directory-retry'),
            onPressed: metadata.isLoading
                ? null
                : () => unawaited(
                    ref.read(threadMetadataDemandProvider(threadId)).refresh(),
                  ),
            child: Text(context.l10n.sidebarRetry),
          ),
        ],
      ),
    );
  }
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
  final Map<String, ConversationSidebarState<FileReadingRequest>>
  _sidebarByThread = {};
  double? _sidebarCustomWidth;
  final GlobalKey _timelineHostKey = GlobalKey(debugLabel: 'timeline-host');

  @override
  void didUpdateWidget(covariant AgentWorkspacePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.threadId != oldWidget.threadId) {
      _sidebarByThread[oldWidget.threadId]?.closeFile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final threadId = widget.threadId;
    if (threadId == null) return const _StudioStartPage();
    switch (ref.watch(conversationBackendViewModelProvider(threadId))) {
      case ConversationBackendKind.acp:
        return AcpWorkspaceConnector(threadId: threadId);
      case ConversationBackendKind.loading:
        return const Center(
          key: ValueKey('agent-workspace-loading'),
          child: CircularProgressIndicator(),
        );
      case ConversationBackendKind.unresolved:
        return _ConversationDirectoryUnavailable(threadId: threadId);
      case ConversationBackendKind.native:
        break;
    }
    return LatestScrollScope(child: _buildNativeWorkspace(threadId));
  }

  Widget _buildNativeWorkspace(String threadId) {
    final workspaceProvider = conversationWorkspaceProvider(
      threadId,
      needsOpen: widget.needsOpen,
    );
    final workspace = ref.watch(workspaceProvider);
    if (workspace == null) {
      return Column(
        children: [
          Expanded(child: TimelineConnector(threadId: threadId)),
          const ReturnToLatestButton(),
        ],
      );
    }
    final planHead = widget.needsOpen
        ? null
        : ref.watch(
            threadSessionStoreProvider(threadId)
                .select((state) => state.businessRefs?.plan),
          );
    final workflowRun = ref.watch(
      statusBarViewProvider(threadId).select((value) => value?.workflowRun),
    );
    final hasWorkflow =
        workflowRun != null ||
        workspace.runtime.deferredField('workflow') != null;
    return _DeferredTodoPanel(
      threadId: threadId,
      runtime: workspace.runtime,
      inline: workspace.todo,
      builder: (todo) {
        final pendingPlan = workspace.activeInteraction?.planConfirmation;
        final referencedPlan = _referencedPlanPresentation(planHead);
        // pending 独占确认动作与 interaction 正文；无 pending 时，有 document 的
        // 起草 / 要求修订 / 已批准映射真实 status 作为只读入口，无文档不伪造。
        final presentedPlan = pendingPlan != null
            ? _WorkspacePlanPresentation.fromPending(pendingPlan)
            : referencedPlan;
        final sidebar = _sidebarByThread.putIfAbsent(
          threadId,
          ConversationSidebarState<FileReadingRequest>.new,
        );
        // 同步接收输入，不排队首帧回调，避免旧交互的延迟展开覆盖新选择。
        sidebar.observePlan(
          identity: presentedPlan?.identity,
          pending: pendingPlan != null,
        );

        final l10n = context.l10n;
        final timelineDisplay = ref
            .watch(timelineViewModelProvider(threadId))
            .asData
            ?.value;
        final entries = <ConversationSidebarPanelEntry>[
          if (hasWorkflow)
            ConversationSidebarPanelEntry(
              kind: ConversationSidebarPanelKind.workflow,
              icon: Icons.account_tree_outlined,
              label: l10n.rightSidebarTabWorkflow,
              tooltip: l10n.workflowGraphPanelTitle,
              defaultWidthBuilder: (w) => (w * 0.36).clamp(360.0, 440.0),
              builder: (_) =>
                  ThreadWorkflowGraphPanelConnector(threadId: threadId),
            ),
          if (presentedPlan != null)
            ConversationSidebarPanelEntry(
              kind: ConversationSidebarPanelKind.plan,
              icon: Icons.description_outlined,
              label: l10n.rightSidebarTabPlan,
              tooltip: l10n.interactionPlanDetailsTitle,
              badge: PlanDetailStatusBadge(
                status: planHead == null
                    ? presentedPlan.status
                    : planDetailStatusFromRuntime(planHead.phase),
              ),
              defaultLayoutMode: pendingPlan != null
                  ? ConversationSidebarLayoutMode.expanded
                  : ConversationSidebarLayoutMode.split,
              expandedDockBehavior: pendingPlan != null
                  ? ConversationExpandedDockBehavior.keepFooterBelow
                  : ConversationExpandedDockBehavior.coverAll,
              defaultWidthBuilder: (w) => (w * 0.48).clamp(360.0, 620.0),
              builder: (_) => PlanDetailConnector(
                threadId: threadId,
                identity: presentedPlan.identity,
              ),
            ),
          if (sidebar.file case final file?)
            ConversationSidebarPanelEntry(
              kind: ConversationSidebarPanelKind.file,
              icon: Icons.article_outlined,
              label: file.filename,
              tooltip: file.filename,
              onDismiss: () {
                final remaining = [
                  if (hasWorkflow) ConversationSidebarPanelKind.workflow,
                  if (presentedPlan != null) ConversationSidebarPanelKind.plan,
                  if (todo != null) ConversationSidebarPanelKind.todo,
                ];
                setState(
                  () => sidebar.closeFile(remainingAvailable: remaining),
                );
              },
              defaultWidthBuilder: (w) => (w * 0.48).clamp(360.0, 620.0),
              builder: (_) => FileReadingPanel(request: file),
            ),
          if (todo != null)
            ConversationSidebarPanelEntry(
              kind: ConversationSidebarPanelKind.todo,
              icon: Icons.checklist_outlined,
              label: l10n.rightSidebarTabTodo,
              tooltip: todo.explanation?.trim().isNotEmpty == true
                  ? todo.explanation!.trim()
                  : l10n.timelineTodoListFallback,
              badge: _TodoCountBadge(
                completed: todo.items
                    .where((item) => item.status == 'completed')
                    .length,
                total: todo.items.length,
              ),
              defaultWidthBuilder: (w) => (w * 0.34).clamp(340.0, 420.0),
              builder: (_) => TodoPanel(todo: todo),
            ),
        ];
        sidebar.reconcileAvailable({for (final entry in entries) entry.kind});

        final activeEntry = sidebar.isOpen && entries.isNotEmpty
            ? entries.firstWhere(
                (entry) => entry.kind == sidebar.activeKind,
                orElse: () => entries.first,
              )
            : null;
        final activeLayoutMode = activeEntry == null
            ? ConversationSidebarLayoutMode.split
            : sidebar.layoutModeFor(
                activeEntry.kind,
                defaultMode: activeEntry.defaultLayoutMode,
              );
        final availableOrder = [for (final entry in entries) entry.kind];

        final readingArea = KeyedSubtree(
          key: _timelineHostKey,
          child: FileReadingScope(
            onOpen: (request) {
              if (!request.isActive()) return;
              final conversations = ref
                  .read(anyworkClientProvider)
                  .conversations;
              final session = conversations.existingSession(threadId);
              final timeline = ref.read(appGraphProvider).timeline;
              final content = timeline.lease(threadId);
              setState(() {
                // A document is a shell-local demand, not a borrow from a virtual
                // timeline row. Scrolling that row away must not retire the panel.
                sidebar.openFile(
                  FileReadingRequest(
                    identity: request.identity,
                    filename: request.filename,
                    readBytes: request.readBytes,
                    isActive: () =>
                        mounted &&
                        widget.threadId == threadId &&
                        conversations.visibleThreadId.value == threadId &&
                        identical(
                          conversations.existingSession(threadId),
                          session,
                        ) &&
                        content != null &&
                        !content.isRetired &&
                        identical(timeline.lease(threadId), content),
                  ),
                );
              });
            },
            child: TimelineConnector(
              threadId: threadId,
              planConfirmation: pendingPlan,
              planExpanded: sidebar.isPanelOpen(
                ConversationSidebarPanelKind.plan,
              ),
              onPlanToggle: pendingPlan == null
                  ? null
                  : () => setState(
                      () => sidebar.togglePanel(
                        ConversationSidebarPanelKind.plan,
                        defaultMode: ConversationSidebarLayoutMode.expanded,
                      ),
                    ),
            ),
          ),
        );

        return ConversationWorkspaceShell(
          topBanner: widget.needsOpen
              ? _OpenThreadBanner(threadId: threadId)
              : null,
          readingArea: readingArea,
          readingAction: const ReturnToLatestButton(),
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
          scrollFooter: pendingPlan != null,
          footerDockBuilder: (context, compact) => _Footer(
            threadId: threadId,
            compact: compact,
            contentKey: StudioDriverKeys.workspaceFooterScroll,
          ),
          sidebarBuilder: activeEntry == null
              ? null
              : (context, presentation) => ConversationRightSidebar(
                  entries: entries,
                  activeKind: activeEntry.kind,
                  presentation: presentation,
                  onSelectKind: (kind) {
                    final target = entries.firstWhere(
                      (entry) => entry.kind == kind,
                    );
                    setState(
                      () => sidebar.openPanel(
                        kind,
                        defaultMode: target.defaultLayoutMode,
                      ),
                    );
                  },
                  onToggleLayoutMode: () => setState(
                    () => sidebar.toggleLayoutMode(
                      activeEntry.kind,
                      defaultMode: activeEntry.defaultLayoutMode,
                    ),
                  ),
                  onCollapse: () => setState(sidebar.collapse),
                ),
          sidebarExpanded:
              activeEntry != null &&
              activeLayoutMode == ConversationSidebarLayoutMode.expanded,
          expandedDockBehavior:
              activeEntry?.expandedDockBehavior ??
              ConversationExpandedDockBehavior.coverAll,
          sidebarCustomWidth: _sidebarCustomWidth,
          sidebarDefaultWidthBuilder: activeEntry?.defaultWidthBuilder,
          onSidebarWidthChanged: (width) => _sidebarCustomWidth = width,
          onCollapseSidebar: () => setState(sidebar.collapse),
          statusBar: ThreadStatusConnector(
            threadId: threadId,
            showTodo: todo != null,
            todoExpanded: sidebar.isPanelOpen(
              ConversationSidebarPanelKind.todo,
            ),
            onToggleTodo: todo == null
                ? null
                : () => setState(
                    () =>
                        sidebar.togglePanel(ConversationSidebarPanelKind.todo),
                  ),
            workflowExpanded: sidebar.isPanelOpen(
              ConversationSidebarPanelKind.workflow,
            ),
            onToggleWorkflow: () => setState(
              () => sidebar.togglePanel(ConversationSidebarPanelKind.workflow),
            ),
            showPlanEntry: pendingPlan == null && referencedPlan != null,
            planExpanded: sidebar.isPanelOpen(
              ConversationSidebarPanelKind.plan,
            ),
            onOpenPlan: pendingPlan != null || referencedPlan == null
                ? null
                : () => setState(
                    () => sidebar.togglePanel(
                      ConversationSidebarPanelKind.plan,
                      defaultMode: ConversationSidebarLayoutMode.split,
                    ),
                  ),
            hasSidebarPanels: entries.isNotEmpty,
            sidebarOpen: sidebar.isOpen,
            onToggleSidebar: entries.isEmpty
                ? null
                : () => setState(
                    () => sidebar.toggleSidebar(availableOrder: availableOrder),
                  ),
          ),
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
}

class _WorkspacePlanPresentation {
  const _WorkspacePlanPresentation({
    required this.identity,
    required this.status,
  });

  factory _WorkspacePlanPresentation.fromPending(PlanConfirmationView plan) {
    return _WorkspacePlanPresentation(
      identity: 'interaction:${plan.interactionId}',
      status: PlanDetailStatus.awaitingConfirmation,
    );
  }

  factory _WorkspacePlanPresentation.fromHead(CurrentPlanHead plan) {
    return _WorkspacePlanPresentation(
      identity: 'plan:${plan.revision}',
      status: planDetailStatusFromRuntime(plan.phase),
    );
  }

  final String identity;
  final PlanDetailStatus status;
}

class _TodoCountBadge extends StatelessWidget {
  const _TodoCountBadge({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final allDone = total > 0 && completed == total;
    final tone = allDone ? StudioTone.success : StudioTone.brand;
    return StudioPill(label: '$completed/$total', tone: tone);
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
                        Text(
                          context.l10n.startPageWelcome,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: context.colors.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
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

/// Reads the deferred todo value only while the Todo surface is mounted.
///
/// The inline field is a size placeholder, never a complete empty todo list.
/// Each generation owns one Current read scope and retires it when the field,
/// Thread or widget lifetime changes.
class _DeferredTodoPanel extends ConsumerStatefulWidget {
  const _DeferredTodoPanel({
    required this.threadId,
    required this.runtime,
    required this.inline,
    required this.builder,
  });

  final String threadId;
  final ThreadRuntimeView runtime;
  final TimelineTodoListUpdate? inline;
  final Widget Function(TimelineTodoListUpdate? todo) builder;

  @override
  ConsumerState<_DeferredTodoPanel> createState() => _DeferredTodoPanelState();
}

class _DeferredTodoPanelState extends ConsumerState<_DeferredTodoPanel> {
  CurrentStateField? _field;
  CurrentQueryScope? _scope;
  TimelineTodoListUpdate? _loaded;
  Object? _error;
  bool _loading = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant _DeferredTodoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId ||
        oldWidget.runtime.deferredField('todo') !=
            widget.runtime.deferredField('todo')) {
      _scheduleSync();
    }
  }

  void _scheduleSync() {
    unawaited(Future<void>.microtask(_sync));
  }

  void _retire() {
    _epoch++;
    final scope = _scope;
    _scope = null;
    scope?.retire();
    if (scope != null) unawaited(scope.close());
  }

  Future<void> _sync() async {
    if (!mounted) return;
    final field = widget.runtime.deferredField('todo');
    if (field == null) {
      _retire();
      _field = null;
      _loaded = null;
      _error = null;
      _loading = false;
      if (mounted) setState(() {});
      return;
    }
    if (_loading && field == _field) return;
    _retire();
    _field = field;
    _loaded = null;
    _error = null;
    final lease = ref.read(timelineSessionOwnerProvider).lease(widget.threadId);
    if (lease == null || lease.isRetired) return;
    final epoch = ++_epoch;
    final scope = lease.openCurrentScope(generation: lease.generation);
    _scope = scope;
    _loading = true;
    if (mounted) setState(() {});
    try {
      final value = await scope.readStateField(field);
      final todo = decodeCurrentTodoState(value);
      if (!mounted || epoch != _epoch || field != _field || lease.isRetired) {
        return;
      }
      _loaded = todo;
    } catch (error) {
      if (mounted && epoch == _epoch && field == _field) _error = error;
    } finally {
      if (epoch == _epoch) {
        _loading = false;
        final current = _scope;
        if (identical(current, scope)) _scope = null;
        scope.retire();
        unawaited(scope.close());
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _retire();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.runtime.deferredField('todo');
    final todo = field == null
        ? widget.inline
        : field == _field
        ? _loaded
        : null;
    if (field != null && field != _field && !_loading && _error == null) {
      _scheduleSync();
    }
    return widget.builder(todo);
  }
}
