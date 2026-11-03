import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../state/timeline_display_unit.dart';
import 'timeline_activity_row.dart';

/// The same summary-driven production header for current and history. The
/// builder is invoked only on real expansion, not while constructing hidden UI.
class TimelineDisplayUnitView extends StatefulWidget {
  const TimelineDisplayUnitView({
    required this.unit,
    required this.childBuilder,
    this.onExpandedChanged,
    super.key,
  });
  final TimelineDisplayUnit unit;
  final WidgetBuilder childBuilder;
  final ValueChanged<bool>? onExpandedChanged;
  @override
  State<TimelineDisplayUnitView> createState() => _TimelineDisplayUnitViewState();
}

class _TimelineDisplayUnitViewState extends State<TimelineDisplayUnitView> {
  Timer? _ticker;
  final Object _visibility = Object();
  late bool _expanded = widget.unit.expansion.expanded ?? false;
  bool _rebuildScheduled = false;
  @override
  void initState() {
    super.initState();
    widget.unit.expansion.addListener(_changed);
    widget.unit.expansion.setBodyVisible(_visibility, _expanded);
    _syncTicker();
  }

  void _changed() {
    if (!mounted || _rebuildScheduled) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      _rebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rebuildScheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  bool get _active => widget.unit.live && (widget.unit.item.summary?.activeCount ?? 0) > 0;
  void _syncTicker() {
    if (_active && widget.unit.item.summary?.startedAt != null &&
        widget.unit.item.summary?.finishedAt == null) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void didUpdateWidget(covariant TimelineDisplayUnitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.unit.expansion, widget.unit.expansion)) {
      throw StateError('A mounted group cannot change its disclosure identity');
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.unit.expansion.removeListener(_changed);
    widget.unit.expansion.setBodyVisible(_visibility, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    final summary = unit.item.summary;
    final start = summary?.startedAt;
    final end = summary?.finishedAt ?? (_active ? DateTime.now().millisecondsSinceEpoch ~/ 1000 : null);
    final elapsed = start == null || end == null || end < start ? null : end - start;
    final label = _active
        ? '工作中'
        : unit.live && !unit.item.admissionClosed
        ? '等待后继边界'
        : elapsed == null ? '工作记录' : '工作了 $elapsed 秒';
    final meta = [
      if (summary != null) '${summary.memberCount} 项',
      if ((summary?.failedCount ?? 0) > 0) '${summary!.failedCount} 项执行失败',
      if ((summary?.cancelledCount ?? 0) > 0) '${summary!.cancelledCount} 项已停止',
      if (_active && elapsed != null) '$elapsed 秒',
    ].join(' · ');
    return TimelineActivityDisclosure(
      initiallyExpanded: _expanded,
      onExpansionChanged: (expanded) {
        // This revocation happens before an animation can keep old descendants
        // mounted; the next build removes their captured props altogether.
        unit.expansion.expanded = expanded;
        unit.expansion.setBodyVisible(_visibility, expanded);
        setState(() => _expanded = expanded);
        widget.onExpandedChanged?.call(expanded);
      },
      titleBuilder: (_, expanded) => TimelineActivityRow(
        key: ValueKey('source-unit-header:${unit.id}'),
        label: label,
        meta: meta,
        expanded: expanded,
        active: _active,
        summaryWidget: summary == null || summary.categories.isEmpty ? null : Row(
          mainAxisSize: MainAxisSize.min,
          children: [for (final category in summary.categories)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(switch (category.category) {
                  TimelineCategory.thinking => Icons.psychology_alt_outlined,
                  TimelineCategory.read => Icons.description_outlined,
                  TimelineCategory.image => Icons.image_outlined,
                  TimelineCategory.command => Icons.terminal,
                  TimelineCategory.search => Icons.search,
                  TimelineCategory.edit => Icons.edit_outlined,
                  TimelineCategory.wait => Icons.hourglass_empty,
                  TimelineCategory.other => Icons.more_horiz,
                }, size: 13),
                const SizedBox(width: 2),
                Text('${category.count}'),
              ]),
            ),
          ],
        ),
      ),
      children: [if (_expanded && !unit.expansion.isRetired) Builder(builder: widget.childBuilder)],
    );
  }
}
