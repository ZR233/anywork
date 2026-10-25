import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multi_split_view/multi_split_view.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../state/plan_view_state.dart';

/// Divider layout width; its hit area is widened to both sides by the component
/// handle buffer, not by this widget.
const double _planDividerThickness = 1;
const double _planDividerHandleBuffer = 4;

/// Focused-divider arrow-key step.
const double _planResizeStep = 24;

/// Can the real available width hold both minimums plus the divider?
///
/// The decision reads actual width only, never the current dragged width, so a
/// drag can never cross a threshold and rebuild the layout mid-gesture.
bool planSideBySideFeasible(double availableWidth) =>
    availableWidth >=
    planMinimumPanelWidth +
        planMinimumConversationWidth +
        _planDividerThickness;

/// Side-by-side reading of the conversation and the Plan panel.
///
/// Drag, size allocation and boundary solving belong to the stock split
/// component; this widget keeps no drag delta, no duplicate convergence and no
/// second width model. The plan may be wider than the conversation, and always
/// leaves the conversation its minimum width (design/13-plan.md §13.5).
class PlanSplitView extends StatefulWidget {
  const PlanSplitView({
    required this.initialPlanWidth,
    required this.dividerLabel,
    required this.onPlanWidthChanged,
    required this.conversation,
    required this.plan,
    super.key,
  });

  /// Width to restore on open: the last dragged width of this GUI session.
  final double initialPlanWidth;
  final String dividerLabel;
  final ValueChanged<double> onPlanWidthChanged;
  final Widget conversation;
  final Widget plan;

  @override
  State<PlanSplitView> createState() => _PlanSplitViewState();
}

class _PlanSplitViewState extends State<PlanSplitView> {
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

  /// Only the first layout knows the real width: areas and bounds are created
  /// then, clamped by the actual available width.
  void _ensureAreas(double containerWidth) {
    if (_controller != null) return;
    final maximumPlanWidth = _maximumPlanWidth(containerWidth);
    final initialWidth = widget.initialPlanWidth
        .clamp(planMinimumPanelWidth, maximumPlanWidth)
        .toDouble();
    final planArea = Area(
      id: _planAreaId,
      size: initialWidth,
      min: planMinimumPanelWidth,
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

  /// The plan keeps at most what still leaves the conversation its minimum.
  double _maximumPlanWidth(double containerWidth) {
    final available =
        containerWidth - planMinimumConversationWidth - _planDividerThickness;
    return available < planMinimumPanelWidth
        ? planMinimumPanelWidth
        : available;
  }

  /// A container width change is applied after layout: `Area` setters notify
  /// listeners, so geometry must not change during build.
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

  /// Arrow keys hand the component a target width; min/max still converge it.
  void _adjustPlanWidth(double delta) {
    final area = _planArea;
    if (area == null) return;
    final current = area.size ?? planDefaultPanelWidth;
    area.size = current + delta;
  }

  void _resetPlanWidth() => _planArea?.size = planDefaultPanelWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _ensureAreas(constraints.maxWidth);
      if (_appliedContainerWidth != constraints.maxWidth) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _applyContainerWidth(constraints.maxWidth);
        });
      }
      return MultiSplitViewTheme(
        data: MultiSplitViewThemeData(
          dividerThickness: _planDividerThickness,
          dividerHandleBuffer: _planDividerHandleBuffer,
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

  Widget _buildDivider(
    Axis axis,
    int index,
    bool resizable,
    bool dragging,
    bool highlighted,
    MultiSplitViewThemeData themeData,
  ) => _PlanDividerHandle(
    key: StudioDriverKeys.planResizeHandle,
    label: widget.dividerLabel,
    thickness: themeData.dividerThickness,
    dragging: dragging,
    highlighted: highlighted,
    onAdjust: _adjustPlanWidth,
    onReset: _resetPlanWidth,
    step: _planResizeStep,
  );
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

/// The draggable divider: pointer drag is the component's, while keyboard
/// adjustment and Home reset stay available from this handle only.
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

  /// Accessibility semantics and tooltip text.
  final String label;
  final double thickness;
  final bool dragging;
  final bool highlighted;

  /// Positive widens the plan, negative narrows it.
  final ValueChanged<double> onAdjust;
  final VoidCallback onReset;
  final double step;

  @override
  State<_PlanDividerHandle> createState() => _PlanDividerHandleState();
}

class _PlanDividerHandleState extends State<_PlanDividerHandle> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = widget.dragging || widget.highlighted || _focused;
    final color = active
        ? colors.primary.withValues(alpha: 0.65)
        : colors.outlineVariant.withValues(alpha: 0.7);
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
