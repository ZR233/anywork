part of 'studio_shell.dart';

/// 阅读会话的唯一局部状态 owner。外壳通过 builder 组合 Todo、footer 和遮罩，
/// 不参与计划/文件互斥、自动展开或阅读模式转换。
class _WorkspaceReading extends ConsumerStatefulWidget {
  const _WorkspaceReading({
    required this.threadId,
    required this.pendingPlan,
    required this.presentedPlan,
    required this.builder,
  });

  final String threadId;
  final PlanConfirmationView? pendingPlan;
  final _WorkspacePlanPresentation? presentedPlan;
  final Widget Function(
    BuildContext context,
    Widget readingArea,
    bool readingOpen,
    VoidCallback onOpenPlan,
  )
  builder;

  @override
  ConsumerState<_WorkspaceReading> createState() => _WorkspaceReadingState();
}

class _WorkspaceReadingState extends ConsumerState<_WorkspaceReading> {
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

  final Map<String, ReadingWorkspaceState<FileReadingRequest>> _sessions = {};
  ReadingWorkspaceState<FileReadingRequest> get _reading =>
      _sessions.putIfAbsent(
        widget.threadId,
        ReadingWorkspaceState<FileReadingRequest>.new,
      );
  double _planPanelWidth = _defaultPlanPanelWidth;
  final GlobalKey _timelineHostKey = GlobalKey(debugLabel: 'timeline-host');
  final GlobalKey _planPanelKey = GlobalKey(debugLabel: 'plan-panel');
  final GlobalKey _filePanelKey = GlobalKey(debugLabel: 'file-panel');

  @override
  void didUpdateWidget(covariant _WorkspaceReading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.threadId != oldWidget.threadId) {
      _sessions[oldWidget.threadId]?.closeFile();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 同步接收输入，不排队首帧回调，避免旧交互的延迟展开覆盖新选择。
    _reading.observePlan(
      identity: widget.presentedPlan?.identity,
      pending: widget.pendingPlan != null,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySideFeasible =
            constraints.maxWidth >= _minimumSideBySideWidth;
        final splitPlan =
            _reading.planOpen &&
            !_reading.fullWidth(sideBySideFeasible: sideBySideFeasible);
        return widget.builder(
          context,
          _buildReadingArea(
            threadId: widget.threadId,
            pendingPlan: widget.pendingPlan,
            planOpen: _reading.planOpen,
            splitPlan: splitPlan,
            presentedPlan: widget.presentedPlan,
            sideBySideFeasible: sideBySideFeasible,
          ),
          _reading.readingOpen,
          () => setState(_reading.openPlan),
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
      child: FileReadingScope(
        onOpen: (request) {
          if (!request.isActive()) return;
          final conversations = ref.read(anyworkClientProvider).conversations;
          final session = conversations.existingSession(threadId);
          final timeline = ref.read(appGraphProvider).timeline;
          final content = timeline.lease(threadId);
          setState(() {
            // A document is a shell-local demand, not a borrow from a virtual
            // timeline row. Scrolling that row away must not retire the panel.
            _reading.openFile(
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
          planExpanded: planOpen,
          onPlanToggle: pendingPlan == null
              ? null
              : () => setState(_reading.togglePlan),
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
    final file = _reading.file;
    final filePanel = file == null
        ? null
        : FileReadingPanel(
            key: _filePanelKey,
            request: file,
            onClose: () => setState(_reading.closeFile),
            fullWidth: _reading.fullWidth(
              sideBySideFeasible: sideBySideFeasible,
            ),
            onToggleReadingMode: sideBySideFeasible
                ? () => setState(_reading.toggleMode)
                : null,
          );
    final panel = filePanel ?? (planOpen ? planPanel : null);
    final split =
        panel != null &&
        !_reading.fullWidth(sideBySideFeasible: sideBySideFeasible);
    if (split) {
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
        plan: panel,
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: timeline),
        if (panel != null) Positioned.fill(child: panel),
      ],
    );
  }

  /// 计划详情面板：只读文档页，并排与全宽共用同一构造，避免两套语义。
  Widget _buildPlanPanel({
    required _WorkspacePlanPresentation presentation,
    required String threadId,
    required bool fullWidth,
    required bool sideBySideFeasible,
  }) {
    return PlanDetailConnector(
      threadId: threadId,
      identity: presentation.identity,
      status: presentation.status,
      fullWidth: fullWidth,
      onToggleReadingMode: sideBySideFeasible
          ? () => setState(_reading.toggleMode)
          : null,
      onClose: () => setState(_reading.closePlan),
    );
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
    );
  }
}

/// 计划分隔条：承载语义，拖动与双击属于分栏组件。
class _PlanDividerHandle extends StatelessWidget {
  const _PlanDividerHandle({
    required this.label,
    required this.thickness,
    required this.dragging,
    required this.highlighted,
    super.key,
  });

  /// 无障碍语义与 tooltip 文案。
  final String label;

  /// 分隔条本身的宽度。
  final double thickness;

  final bool dragging;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final active = dragging || highlighted;
    final color = active
        ? context.colors.primary.withValues(alpha: 0.65)
        : context.colors.outlineVariant.withValues(alpha: 0.7);
    return Semantics(
      label: label,
      slider: true,
      child: Tooltip(
        message: label,
        child: ColoredBox(
          color: color,
          child: SizedBox(width: thickness),
        ),
      ),
    );
  }
}
