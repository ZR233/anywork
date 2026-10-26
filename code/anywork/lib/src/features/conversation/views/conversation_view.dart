import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';
import 'plan_split_view.dart';

/// Builds the one Todo surface for its current placement.
///
/// [inDrawer] only changes presentation (no side border); [onClose] is the
/// placement's own close action, so the panel never guesses its container.
typedef TodoPanelBuilder = Widget Function({
  required bool inDrawer,
  required VoidCallback? onClose,
});

/// Screen geometry only. Child slots are Smart connectors; this view has no
/// provider, domain owner, selected-thread lookup or mutation admission logic.
///
/// The reading area has three geometries over the same children: side-by-side
/// (conversation | Plan panel through the stock split component), full-width
/// reading (the Plan panel covers the conversation), and conversation only. The
/// timeline subtree and the Plan panel keep their own `GlobalKey` so switching
/// reading geometry never rebuilds scroll, subscription, focus or document
/// scroll state (design/13-plan.md §13.5).
class ConversationView extends StatefulWidget {
  const ConversationView({
    required this.timeline,
    required this.status,
    required this.composerBuilder,
    required this.onToggleTodo,
    required this.todoExpanded,
    this.todoBuilder,
    this.interactions,
    this.planPanelBuilder,
    this.planOpen = false,
    this.planFullWidth = false,
    this.planPanelWidth = 720,
    this.onPlanWidthChanged,
    super.key,
  });
  final Widget timeline;

  /// The status-bar read-outs, context and throughput of this Thread. They are
  /// passed as one slot because the bar owns their placement only.
  final Widget status;
  final Widget Function(bool compact) composerBuilder;
  final VoidCallback onToggleTodo;
  final bool todoExpanded;
  final TodoPanelBuilder? todoBuilder;
  final Widget? interactions;

  /// Builds the Plan reading panel; only mounted while [planOpen]. The measured
  /// fact whether side-by-side is feasible comes from this view's constraints,
  /// so the panel never guesses a layout capability from its own width.
  final Widget Function(bool sideBySideFeasible)? planPanelBuilder;
  final bool planOpen;

  /// Full-width reading instead of side-by-side. A narrow window forces the
  /// same geometry at layout time.
  final bool planFullWidth;
  final double planPanelWidth;
  final ValueChanged<double>? onPlanWidthChanged;

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  /// Todo side panel width and the timeline width that still has to fit next to
  /// it; below that sum the Todo surface uses the end drawer instead of
  /// squeezing the conversation.
  static const _todoPanelWidth = 304.0;
  static const _minimumTimelineWidth = 560.0;

  /// The footer budget reserves a smallest visible timeline, then gives the
  /// rest of the window to the footer. A fixed fraction would collapse the
  /// composer in short windows.
  static const _minimumTimelineHeight = 96.0;
  static const _maximumTimelineReserve = 200.0;
  static const _timelineReserveFraction = 0.3;

  /// Below this footer budget the composer shrinks its own paddings and input
  /// lines instead of being clipped by the window.
  static const _compactFooterBudget = 400.0;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _timelineHostKey = GlobalKey(debugLabel: 'timeline-host');
  final GlobalKey _planPanelKey = GlobalKey(debugLabel: 'plan-panel');

  static double _footerMaxHeight(double viewportHeight) {
    final reserve = (viewportHeight * _timelineReserveFraction)
        .clamp(_minimumTimelineHeight, _maximumTimelineReserve)
        .toDouble();
    final available = viewportHeight - reserve;
    return available > 0 ? available : 0;
  }

  @override
  Widget build(BuildContext context) {
    final todoBuilder = widget.todoBuilder;
    return LayoutBuilder(
      builder: (context, constraints) {
        final footerBudget = constraints.hasBoundedHeight
            ? _footerMaxHeight(constraints.maxHeight)
            : null;
        final compact =
            footerBudget != null && footerBudget < _compactFooterBudget;
        final sideBySideFeasible = planSideBySideFeasible(constraints.maxWidth);
        final panel = widget.planOpen
            ? widget.planPanelBuilder?.call(sideBySideFeasible)
            : null;
        final planOpen = panel != null;
        final splitPlan =
            planOpen && !widget.planFullWidth && sideBySideFeasible;
        final todoInDrawer =
            constraints.maxWidth < _todoPanelWidth + _minimumTimelineWidth;
        final showTodo = !planOpen && todoBuilder != null;
        final timeline = KeyedSubtree(
          key: _timelineHostKey,
          child: widget.timeline,
        );
        final planPanel = panel == null
            ? null
            : KeyedSubtree(key: _planPanelKey, child: panel);
        final Widget readingArea;
        if (splitPlan && planPanel != null) {
          readingArea = PlanSplitView(
            initialPlanWidth: widget.planPanelWidth,
            dividerLabel: context.l10n.planResize,
            onPlanWidthChanged: (width) =>
                widget.onPlanWidthChanged?.call(width),
            conversation: timeline,
            plan: planPanel,
          );
        } else if (planPanel != null) {
          readingArea = Stack(
            children: [
              Positioned.fill(child: timeline),
              Positioned.fill(child: planPanel),
            ],
          );
        } else {
          readingArea = timeline;
        }
        // The Plan reading panel takes precedence over the Todo side panel;
        // closing it leaves Todo with its own untouched UI state.
        final todoPanel =
            todoBuilder != null &&
                showTodo &&
                !todoInDrawer &&
                widget.todoExpanded
            ? SizedBox(
                width: _todoPanelWidth,
                child: todoBuilder(
                  inDrawer: false,
                  onClose: widget.onToggleTodo,
                ),
              )
            : null;
        final footer = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fixed slot for the feedback docks and the composer: switching
            // reading geometry, crossing window thresholds or opening the Plan
            // panel never rebuilds their State (drafts, errors, in-flight
            // decisions).
            Padding(
              padding: compact
                  ? const EdgeInsets.fromLTRB(12, 4, 12, 6)
                  : const EdgeInsets.fromLTRB(12, 7, 12, 12),
              child: Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: StudioLayout.conversationWidth,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 与 HEAD 一致：同一位置只渲染其中之一。有待决交互时由决定
                      // 栏占用输入区位置，交互消失后 composer 当帧回来（两者都由
                      // 既有 props 驱动，不新增 provider 读取）。
                      if (widget.interactions case final interactions?)
                        interactions
                      else
                        widget.composerBuilder(compact),
                    ],
                  ),
                ),
              ),
            ),
            _statusBar(context, showTodo: showTodo, todoInDrawer: todoInDrawer),
          ],
        );
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: context.colors.surface,
          endDrawerEnableOpenDragGesture: false,
          endDrawer: !showTodo || !todoInDrawer
              ? null
              : Drawer(
                  width: 328,
                  backgroundColor: context.colors.surfaceContainer,
                  child: todoBuilder(
                    inDrawer: true,
                    onClose: () => _scaffoldKey.currentState?.closeEndDrawer(),
                  ),
                ),
          body: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: readingArea),
                    if (footerBudget != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: footerBudget),
                        child: footer,
                      )
                    else
                      footer,
                  ],
                ),
              ),
              ?todoPanel,
            ],
          ),
        );
      },
    );
  }

  /// The chat status bar: fixed to the bottom of the conversation column, below
  /// the composer, and never scrolled away with history.
  ///
  /// The Todo toggle is the leftmost high-frequency control; the read-outs and
  /// the「更多」menu arrive as the [ConversationView.status] slot so this view
  /// owns geometry only.
  Widget _statusBar(
    BuildContext context, {
    required bool showTodo,
    required bool todoInDrawer,
  }) => DecoratedBox(
    decoration: BoxDecoration(color: context.colors.surface),
    child: SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            if (showTodo)
              IconButton(
                key: const ValueKey('todo-open-button'),
                tooltip: context.l10n.timelineTodoListFallback,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                iconSize: 18,
                icon: Icon(
                  widget.todoExpanded
                      ? Icons.checklist
                      : Icons.checklist_outlined,
                  color: widget.todoExpanded
                      ? context.colors.onPrimaryContainer
                      : context.colors.onSurfaceVariant,
                ),
                onPressed: () {
                  if (!todoInDrawer) {
                    widget.onToggleTodo();
                    return;
                  }
                  // The drawer needs the Todo surface's requested state so its
                  // items are actually read; it is not a second owner.
                  if (!widget.todoExpanded) widget.onToggleTodo();
                  _scaffoldKey.currentState?.openEndDrawer();
                },
              ),
            Expanded(child: widget.status),
            const SizedBox(width: 8),
          ],
        ),
      ),
    ),
  );
}
