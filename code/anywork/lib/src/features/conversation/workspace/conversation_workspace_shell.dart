import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:multi_split_view/multi_split_view.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../shared/studio_driver_keys.dart';
import 'conversation_sidebar_panel.dart';

/// Native 与 ACP 共用的统一会话工作区壳。
///
/// 布局结构：
/// - 底部状态栏始终横贯全宽；
/// - 右侧可收缩边栏向下延伸至状态栏顶部，宽屏并排时将左侧时间线、实时状态栏与
///   输入区 / Plan 确认栏整体压缩至左侧列，支持分隔条拖动、双击复位与无障碍调宽；
/// - 跨收起 / 并排 / 全宽 / 窄窗浮层切换时，通过稳定 [GlobalKey] 保持左侧时间线、
///   输入区 / Plan 确认栏及边栏内容组件实例与状态零重建。
class ConversationWorkspaceShell extends StatefulWidget {
  const ConversationWorkspaceShell({
    required this.readingArea,
    required this.footerDockBuilder,
    required this.statusBar,
    this.topBanner,
    this.readingAction,
    this.readingBanner,
    this.readingOverlay,
    this.scrollFooter = false,
    this.sidebarBuilder,
    this.sidebarExpanded = false,
    this.expandedDockBehavior = ConversationExpandedDockBehavior.coverAll,
    this.sidebarCustomWidth,
    this.sidebarDefaultWidthBuilder,
    this.onSidebarWidthChanged,
    this.onCollapseSidebar,
    super.key,
  });

  static const double minimumConversationWidth = 380.0;
  static const double minimumSidebarWidth = 320.0;
  static const double dividerThickness = 1.0;
  static const double dividerHandleBuffer = 4.0;
  static const double sideBySideThreshold =
      minimumConversationWidth + minimumSidebarWidth + dividerThickness;
  static const double resizeStep = 24.0;

  static const double _minimumTimelineHeight = 96.0;
  static const double _maximumTimelineReserve = 200.0;
  static const double _timelineReserveFraction = 0.30;
  static const double _compactFooterBudget = 400.0;

  final Widget? topBanner;
  final Widget readingArea;
  final Widget? readingAction;
  final Widget? readingBanner;
  final Widget? readingOverlay;
  final Widget Function(BuildContext context, bool compact) footerDockBuilder;
  final bool scrollFooter;
  final Widget statusBar;

  final Widget? Function(
    BuildContext context,
    ConversationSidebarPresentation presentation,
  )?
  sidebarBuilder;
  final bool sidebarExpanded;
  final ConversationExpandedDockBehavior expandedDockBehavior;
  final double? sidebarCustomWidth;
  final double Function(double containerWidth)? sidebarDefaultWidthBuilder;
  final ValueChanged<double?>? onSidebarWidthChanged;
  final VoidCallback? onCollapseSidebar;

  @override
  State<ConversationWorkspaceShell> createState() =>
      _ConversationWorkspaceShellState();
}

class _ConversationWorkspaceShellState
    extends State<ConversationWorkspaceShell> {
  final GlobalKey _timelineAreaKey = GlobalKey(
    debugLabel: 'conversation-timeline-area',
  );
  final GlobalKey _footerDockKey = GlobalKey(
    debugLabel: 'conversation-footer-dock',
  );
  final GlobalKey _sidebarHostKey = GlobalKey(
    debugLabel: 'conversation-right-sidebar',
  );

  double _footerMaxHeight(double viewportHeight) {
    final reserve =
        (viewportHeight * ConversationWorkspaceShell._timelineReserveFraction)
            .clamp(
              ConversationWorkspaceShell._minimumTimelineHeight,
              ConversationWorkspaceShell._maximumTimelineReserve,
            )
            .toDouble();
    final available = viewportHeight - reserve;
    return available > 0 ? available : 0;
  }

  Widget _buildTimelineArea() {
    return KeyedSubtree(
      key: _timelineAreaKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: widget.readingArea),
                if (widget.readingBanner case final banner?)
                  Positioned(top: 0, left: 0, right: 0, child: banner),
                if (widget.readingOverlay case final overlay?)
                  Positioned.fill(child: overlay),
              ],
            ),
          ),
          ?widget.readingAction,
        ],
      ),
    );
  }

  Widget _buildFooterDock(double? maxHeight) {
    Widget buildChild(bool compact) {
      final footer = widget.footerDockBuilder(context, compact);
      return widget.scrollFooter
          ? SingleChildScrollView(
              key: const ValueKey('plan-workspace-footer-scroll'),
              primary: false,
              child: footer,
            )
          : footer;
    }

    if (maxHeight == null) {
      return KeyedSubtree(key: _footerDockKey, child: buildChild(false));
    }
    return KeyedSubtree(
      key: _footerDockKey,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: LayoutBuilder(
          builder: (context, constraints) => buildChild(
            constraints.maxHeight <
                ConversationWorkspaceShell._compactFooterBudget,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?widget.topBanner,
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final hasSidebarBuilder = widget.sidebarBuilder != null;
              final sideBySideFeasible =
                  constraints.maxWidth >=
                  ConversationWorkspaceShell.sideBySideThreshold;
              final isKeepFooterExpanded =
                  hasSidebarBuilder &&
                  ((sideBySideFeasible && widget.sidebarExpanded) ||
                      !sideBySideFeasible) &&
                  widget.expandedDockBehavior ==
                      ConversationExpandedDockBehavior.keepFooterBelow;
              final isCoverAllExpanded =
                  hasSidebarBuilder &&
                  sideBySideFeasible &&
                  widget.sidebarExpanded &&
                  widget.expandedDockBehavior ==
                      ConversationExpandedDockBehavior.coverAll;
              final isNarrowOverlay =
                  hasSidebarBuilder &&
                  !sideBySideFeasible &&
                  widget.expandedDockBehavior ==
                      ConversationExpandedDockBehavior.coverAll;

              final presentation = ConversationSidebarPresentation(
                sideBySideFeasible: sideBySideFeasible,
                isExpandedFull: isKeepFooterExpanded || isCoverAllExpanded,
              );
              final rawSidebar = widget.sidebarBuilder?.call(
                context,
                presentation,
              );
              final sidebar = rawSidebar == null
                  ? null
                  : KeyedSubtree(key: _sidebarHostKey, child: rawSidebar);

              final footerMaxHeight = constraints.hasBoundedHeight
                  ? _footerMaxHeight(constraints.maxHeight)
                  : null;
              final timelineArea = _buildTimelineArea();
              final footerDock = _buildFooterDock(footerMaxHeight);

              final mainColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: timelineArea),
                  footerDock,
                ],
              );
              if (sidebar == null) return mainColumn;

              if (isKeepFooterExpanded) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Visibility(
                              visible: false,
                              maintainState: true,
                              child: timelineArea,
                            ),
                          ),
                          Positioned.fill(child: sidebar),
                        ],
                      ),
                    ),
                    footerDock,
                  ],
                );
              }

              if (isCoverAllExpanded) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Visibility(
                        visible: false,
                        maintainState: true,
                        child: mainColumn,
                      ),
                    ),
                    Positioned.fill(child: sidebar),
                  ],
                );
              }

              if (isNarrowOverlay) {
                final overlayWidth = constraints.maxWidth <= 480
                    ? constraints.maxWidth
                    : constraints.maxWidth.clamp(0.0, 440.0);
                return CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape): () =>
                        widget.onCollapseSidebar?.call(),
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(child: mainColumn),
                      Positioned.fill(
                        child: GestureDetector(
                          key: StudioDriverKeys.rightSidebarOverlayScrim,
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onCollapseSidebar,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.24),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        width: overlayWidth,
                        child: Material(
                          elevation: 8,
                          shadowColor: Colors.black26,
                          surfaceTintColor: Colors.transparent,
                          shape: overlayWidth < constraints.maxWidth
                              ? Border(
                                  left: BorderSide(
                                    color: context.colors.outlineVariant,
                                  ),
                                )
                              : null,
                          child: sidebar,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final defaultWidth =
                  widget.sidebarDefaultWidthBuilder?.call(
                    constraints.maxWidth,
                  ) ??
                  (constraints.maxWidth * 0.4).clamp(360.0, 520.0);

              return _WorkspaceSplitView(
                defaultWidth: defaultWidth,
                customWidth: widget.sidebarCustomWidth,
                minimumSidebarWidth:
                    ConversationWorkspaceShell.minimumSidebarWidth,
                minimumConversationWidth:
                    ConversationWorkspaceShell.minimumConversationWidth,
                dividerThickness: ConversationWorkspaceShell.dividerThickness,
                dividerHandleBuffer:
                    ConversationWorkspaceShell.dividerHandleBuffer,
                resizeStep: ConversationWorkspaceShell.resizeStep,
                dividerLabel: context.l10n.rightSidebarResize,
                onWidthChanged: widget.onSidebarWidthChanged,
                conversation: mainColumn,
                sidebar: sidebar,
              );
            },
          ),
        ),
        widget.statusBar,
      ],
    );
  }
}

class _WorkspaceSplitView extends StatefulWidget {
  const _WorkspaceSplitView({
    required this.defaultWidth,
    required this.customWidth,
    required this.minimumSidebarWidth,
    required this.minimumConversationWidth,
    required this.dividerThickness,
    required this.dividerHandleBuffer,
    required this.resizeStep,
    required this.dividerLabel,
    required this.onWidthChanged,
    required this.conversation,
    required this.sidebar,
  });

  final double defaultWidth;
  final double? customWidth;
  final double minimumSidebarWidth;
  final double minimumConversationWidth;
  final double dividerThickness;
  final double dividerHandleBuffer;
  final double resizeStep;
  final String dividerLabel;
  final ValueChanged<double?>? onWidthChanged;
  final Widget conversation;
  final Widget sidebar;

  @override
  State<_WorkspaceSplitView> createState() => _WorkspaceSplitViewState();
}

class _WorkspaceSplitViewState extends State<_WorkspaceSplitView> {
  static const _conversationAreaId = 'conversation';
  static const _sidebarAreaId = 'sidebar';

  MultiSplitViewController? _controller;
  Area? _sidebarArea;
  double? _appliedContainerWidth;
  double? _appliedDefaultWidth;
  bool _hasCustomWidth = false;
  bool _suppressReport = false;

  @override
  void initState() {
    super.initState();
    _hasCustomWidth = widget.customWidth != null;
  }

  @override
  void didUpdateWidget(covariant _WorkspaceSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.customWidth != oldWidget.customWidth) {
      _hasCustomWidth = widget.customWidth != null;
    }
  }

  @override
  void dispose() {
    _controller
      ?..removeListener(_reportWidth)
      ..dispose();
    super.dispose();
  }

  double _maximumSidebarWidth(double containerWidth) {
    final available =
        containerWidth -
        widget.minimumConversationWidth -
        widget.dividerThickness;
    return available < widget.minimumSidebarWidth
        ? widget.minimumSidebarWidth
        : available;
  }

  void _ensureAreas(double containerWidth) {
    if (_controller != null) return;
    final maximumWidth = _maximumSidebarWidth(containerWidth);
    final initialWidth = (widget.customWidth ?? widget.defaultWidth)
        .clamp(widget.minimumSidebarWidth, maximumWidth)
        .toDouble();
    final sidebarArea = Area(
      id: _sidebarAreaId,
      size: initialWidth,
      min: widget.minimumSidebarWidth,
      max: maximumWidth,
    );
    _sidebarArea = sidebarArea;
    _appliedContainerWidth = containerWidth;
    _appliedDefaultWidth = widget.defaultWidth;
    _controller = MultiSplitViewController(
      areas: [
        Area(id: _conversationAreaId, flex: 1),
        sidebarArea,
      ],
    )..addListener(_reportWidth);
  }

  void _applyUpdates(double containerWidth) {
    final area = _sidebarArea;
    if (area == null) return;
    final containerChanged = _appliedContainerWidth != containerWidth;
    final defaultChanged = _appliedDefaultWidth != widget.defaultWidth;
    if (!containerChanged && !defaultChanged) return;

    _appliedContainerWidth = containerWidth;
    _appliedDefaultWidth = widget.defaultWidth;
    final maximumWidth = _maximumSidebarWidth(containerWidth);

    _suppressReport = true;
    try {
      if (area.max != maximumWidth) area.max = maximumWidth;
      if (!_hasCustomWidth && defaultChanged) {
        area.size = widget.defaultWidth
            .clamp(widget.minimumSidebarWidth, maximumWidth)
            .toDouble();
      } else {
        final size = area.size;
        if (size != null && size > maximumWidth) {
          area.size = maximumWidth;
        }
      }
    } finally {
      _suppressReport = false;
    }
  }

  void _reportWidth() {
    if (_suppressReport) return;
    final size = _sidebarArea?.size;
    if (size != null) {
      _hasCustomWidth = true;
      widget.onWidthChanged?.call(size);
    }
  }

  void _resetWidth() {
    final area = _sidebarArea;
    final containerWidth = _appliedContainerWidth;
    if (area == null || containerWidth == null) return;
    final maximumWidth = _maximumSidebarWidth(containerWidth);
    _suppressReport = true;
    try {
      area.size = widget.defaultWidth
          .clamp(widget.minimumSidebarWidth, maximumWidth)
          .toDouble();
    } finally {
      _suppressReport = false;
    }
    _hasCustomWidth = false;
    widget.onWidthChanged?.call(null);
  }

  void _adjustWidth(double delta) {
    final area = _sidebarArea;
    final containerWidth = _appliedContainerWidth;
    if (area == null || containerWidth == null) return;
    final current = area.size ?? widget.defaultWidth;
    final maximumWidth = _maximumSidebarWidth(containerWidth);
    final next = (current + delta)
        .clamp(widget.minimumSidebarWidth, maximumWidth)
        .toDouble();
    _suppressReport = true;
    try {
      area.size = next;
    } finally {
      _suppressReport = false;
    }
    _hasCustomWidth = true;
    widget.onWidthChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureAreas(constraints.maxWidth);
        if (_appliedContainerWidth != constraints.maxWidth ||
            _appliedDefaultWidth != widget.defaultWidth) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _applyUpdates(constraints.maxWidth);
          });
        }
        return MultiSplitViewTheme(
          data: MultiSplitViewThemeData(
            dividerThickness: widget.dividerThickness,
            dividerHandleBuffer: widget.dividerHandleBuffer,
          ),
          child: MultiSplitView(
            controller: _controller,
            dividerBuilder: (axis, index, resizable, dragging, highlighted, t) {
              final containerWidth =
                  _appliedContainerWidth ?? constraints.maxWidth;
              final maximumWidth = _maximumSidebarWidth(containerWidth);
              final current = (_sidebarArea?.size ?? widget.defaultWidth)
                  .clamp(widget.minimumSidebarWidth, maximumWidth)
                  .toDouble();
              final increased = (current + widget.resizeStep)
                  .clamp(widget.minimumSidebarWidth, maximumWidth)
                  .round();
              final decreased = (current - widget.resizeStep)
                  .clamp(widget.minimumSidebarWidth, maximumWidth)
                  .round();
              return _SidebarDividerHandle(
                key: StudioDriverKeys.rightSidebarResizeHandle,
                label: widget.dividerLabel,
                thickness: t.dividerThickness,
                dragging: dragging,
                highlighted: highlighted,
                value: '${current.round()}',
                increasedValue: '$increased',
                decreasedValue: '$decreased',
                onIncrease: () => _adjustWidth(widget.resizeStep),
                onDecrease: () => _adjustWidth(-widget.resizeStep),
              );
            },
            onDividerDoubleTap: (_) => _resetWidth(),
            builder: (context, area) => area.id == _sidebarAreaId
                ? widget.sidebar
                : widget.conversation,
          ),
        );
      },
    );
  }
}

class _SidebarDividerHandle extends StatelessWidget {
  const _SidebarDividerHandle({
    required this.label,
    required this.thickness,
    required this.dragging,
    required this.highlighted,
    required this.value,
    required this.increasedValue,
    required this.decreasedValue,
    required this.onIncrease,
    required this.onDecrease,
    super.key,
  });

  final String label;
  final double thickness;
  final bool dragging;
  final bool highlighted;
  final String value;
  final String increasedValue;
  final String decreasedValue;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  Widget build(BuildContext context) {
    final active = dragging || highlighted;
    final color = active
        ? context.colors.primary.withValues(alpha: 0.72)
        : context.colors.outlineVariant.withValues(alpha: 0.8);
    return Semantics(
      label: label,
      slider: true,
      value: value,
      increasedValue: increasedValue,
      decreasedValue: decreasedValue,
      onIncrease: onIncrease,
      onDecrease: onDecrease,
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
