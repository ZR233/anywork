import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../state/timeline_display_unit.dart';
import 'timeline_work_group_view.dart';

/// The same summary-driven production header for current and history. The
/// builder is invoked only on real expansion, not while constructing hidden UI.
class TimelineDisplayUnitView extends StatefulWidget {
  const TimelineDisplayUnitView({
    required this.unit,
    required this.executionPresent,
    required this.childBuilder,
    this.onExpandedChanged,
    super.key,
  });
  final TimelineDisplayUnit unit;
  final bool executionPresent;
  final WidgetBuilder childBuilder;
  final ValueChanged<bool>? onExpandedChanged;
  @override
  State<TimelineDisplayUnitView> createState() =>
      _TimelineDisplayUnitViewState();
}

class _TimelineDisplayUnitViewState extends State<TimelineDisplayUnitView> {
  final Object _visibility = Object();
  bool _rebuildScheduled = false;
  @override
  void initState() {
    super.initState();
    widget.unit.expansion.expanded ??= false;
    widget.unit.expansion.addListener(_changed);
    widget.unit.expansion.setBodyVisible(
      _visibility,
      widget.unit.expansion.expanded!,
    );
  }

  void _changed() {
    if (!mounted || _rebuildScheduled) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _rebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rebuildScheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant TimelineDisplayUnitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.unit.expansion, widget.unit.expansion)) {
      throw StateError('A mounted group cannot change its disclosure identity');
    }
  }

  @override
  void dispose() {
    widget.unit.expansion.removeListener(_changed);
    widget.unit.expansion.setBodyVisible(_visibility, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    return TimelineWorkGroupView(
      id: unit.id,
      summary: unit.item.summary,
      live: unit.live,
      executionPresent: widget.executionPresent,
      admissionClosed: unit.item.admissionClosed,
      initiallyExpanded: unit.expansion.expanded!,
      onExpandedChanged: (expanded) {
        // 在关闭动画前同步撤销读取资格；纯视图不持有领域资源。
        unit.expansion.expanded = expanded;
        unit.expansion.setBodyVisible(_visibility, expanded);
        widget.onExpandedChanged?.call(expanded);
      },
      childBuilder: (_) => unit.expansion.isRetired
          ? const SizedBox.shrink()
          : KeyedSubtree(
              key: ValueKey((unit.expansion, unit.expansion.bodyGeneration)),
              child: Builder(builder: widget.childBuilder),
            ),
    );
  }
}
