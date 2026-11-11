import 'package:anywork_client/models.dart' show ConversationActivityView;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import '../state/timeline_display_unit.dart';
import 'completion_run_view.dart';

/// An immutable Main Run header with local disclosure. The builder is invoked
/// only on real expansion, never while constructing hidden UI.
class TimelineDisplayUnitView extends StatefulWidget {
  const TimelineDisplayUnitView({
    required this.unit,
    required this.childBuilder,
    this.onExpandedChanged,
    this.activity,
    super.key,
  });
  final TimelineDisplayUnit unit;
  final WidgetBuilder childBuilder;
  final ValueChanged<bool>? onExpandedChanged;
  final ConversationActivityView? activity;
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
    return CompletionRunView(
      id: unit.id,
      summary: unit.summary!,
      executionPresent: unit.executionPresent,
      state: unit.state,
      initiallyExpanded: unit.expansion.expanded!,
      location: unit.historyPos == null
          ? WorkDisplayLocation.live
          : WorkDisplayLocation.history,
      activity: widget.activity,
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
