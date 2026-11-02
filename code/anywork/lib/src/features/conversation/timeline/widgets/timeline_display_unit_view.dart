import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../state/timeline_display_unit.dart';
import '../state/timeline_display_diagnostics.dart';
import 'timeline_activity_row.dart';

/// Shared live/history process structure. This widget never classifies atoms or
/// decides completion. Only explicit expansion asks the original atomic pager
/// for another bounded page; it does not chase a group head.
class TimelineDisplayUnitView extends StatefulWidget {
  const TimelineDisplayUnitView({
    required this.unit,
    required this.memberBuilder,
    this.onLoadEarlier,
    this.onExpandedChanged,
    super.key,
  });
  final TimelineDisplayUnit unit;
  final Widget Function(ChatAtom atom) memberBuilder;
  final Future<void> Function()? onLoadEarlier;
  final ValueChanged<bool>? onExpandedChanged;
  @override
  State<TimelineDisplayUnitView> createState() =>
      _TimelineDisplayUnitViewState();
}

class _TimelineDisplayUnitViewState extends State<TimelineDisplayUnitView>
    implements TimelineGroupDisplay {
  Timer? _ticker;
  Future<void>? _reading;
  final Object _visibility = Object();
  late bool _expanded = widget.unit.expansion.expanded ?? widget.unit.live;
  VoidCallback? _unregister;
  bool _rebuildScheduled = false;
  @override
  String get unitId => widget.unit.id;
  @override
  bool get isCurrent =>
      mounted && (widget.unit.expansion.isDisplayActive?.call() ?? true);
  @override
  bool get expanded => isCurrent && _expanded;
  @override
  int? get completionAnchor => widget.unit.expansion.completionAnchor;
  @override
  String? get before => widget.unit.expansion.before;
  @override
  bool get loading => expanded && widget.unit.expansion.loading;
  @override
  Object? get error => isCurrent ? widget.unit.expansion.error : null;
  @override
  Iterable<ChatAtom> get atoms => expanded ? widget.unit.members : const [];
  @override
  void initState() {
    super.initState();
    widget.unit.expansion.addListener(_changed);
    if (widget.unit.kind == TimelineUnitKind.work) {
      _unregister = widget.unit.expansion.registerDisplay?.call(this);
      widget.unit.expansion.setBodyVisible(_visibility, _expanded);
      widget.unit.expansion.onVisibilityChanged?.call(_visibility, _expanded);
    }
    _syncTicker();
  }

  void _changed() {
    if (!mounted || _rebuildScheduled) return;
    // A different live/history view can release the last body token while
    // finalizeTree has locked the tree. Resource revocation stays synchronous;
    // only this UI rebuild is coalesced until the current frame is complete.
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

  void _syncTicker() {
    if (widget.unit.live && widget.unit.startedAt != null) {
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
      throw StateError(
        'Mounted process cannot change its original display identity',
      );
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.unit.expansion.removeListener(_changed);
    widget.unit.expansion.setBodyVisible(_visibility, false);
    widget.unit.expansion.onVisibilityChanged?.call(_visibility, false);
    _unregister?.call();
    super.dispose();
  }

  void _older() {
    final action = widget.unit.expansion.readEarlier ?? widget.onLoadEarlier;
    if (_reading != null || action == null) return;
    setState(() {
      _reading = Future<void>.sync(action).whenComplete(() {
        if (mounted) setState(() => _reading = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    if (unit.kind != TimelineUnitKind.work) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: unit.members.map(widget.memberBuilder).toList(),
      );
    }
    final working = unit.members.any(
      (atom) =>
          atom.kind == ChatAtomKind.toolCall &&
          atom.lifecycle is ActiveChatAtom,
    );
    final start = unit.olderCursor == null ? unit.startedAt : null;
    final end = unit.live
        ? DateTime.now().millisecondsSinceEpoch ~/ 1000
        : unit.finishedAt;
    final elapsed = start == null || end == null ? null : end - start;
    final label = unit.live
        ? working
              ? '工作中'
              : unit.activeCount > 0 || unit.sourceLifecycle is ActiveChatSource
              ? '思考中'
              : '状态未知'
        : elapsed == null || elapsed < 0
        ? '工作记录'
        : '工作了 $elapsed 秒';
    final meta = [
      '已加载 ${unit.memberCount} 项',
      if (unit.failedCount > 0) '${unit.failedCount} 项执行失败',
      if (unit.stoppedCount > 0) '${unit.stoppedCount} 项已停止',
      if (unit.live && elapsed != null && elapsed >= 0) '$elapsed 秒',
    ].join(' · ');
    return TimelineActivityDisclosure(
      initiallyExpanded: unit.expansion.expanded ?? unit.live,
      onExpansionChanged: (expanded) {
        _expanded = expanded;
        unit.expansion.expanded = expanded;
        unit.expansion.setBodyVisible(_visibility, expanded);
        unit.expansion.onVisibilityChanged?.call(_visibility, expanded);
        widget.onExpandedChanged?.call(expanded);
      },
      titleBuilder: (_, expanded) => TimelineActivityRow(
        key: ValueKey('source-unit-header:${unit.id}'),
        label: label,
        meta: meta,
        expanded: expanded,
        active: unit.live,
        summaryWidget: unit.categories.isEmpty
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final category in unit.categories.entries)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(switch (category.key) {
                            TimelineProcessKind.thinking =>
                              Icons.psychology_alt_outlined,
                            TimelineProcessKind.read =>
                              Icons.description_outlined,
                            TimelineProcessKind.image => Icons.image_outlined,
                            TimelineProcessKind.command => Icons.terminal,
                            TimelineProcessKind.search => Icons.search,
                            TimelineProcessKind.edit => Icons.edit_outlined,
                            TimelineProcessKind.wait => Icons.hourglass_empty,
                            TimelineProcessKind.other => Icons.more_horiz,
                          }, size: 13),
                          const SizedBox(width: 2),
                          Text('${category.value}'),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      children: [
        for (final atom in unit.members)
          if (unit.live)
            widget.memberBuilder(atom)
          else
            TimelineGroupBodyIntent(
              key: ValueKey((atom.id, unit.expansion.bodyGeneration)),
              intent: unit.expansion,
              child: widget.memberBuilder(atom),
            ),
        if ((unit.olderCursor != null ||
                unit.memberCount > unit.members.length ||
                unit.expansion.hasPage) &&
            (unit.expansion.readEarlier != null ||
                widget.onLoadEarlier != null) &&
            (!unit.expansion.hasPage || unit.expansion.before != null))
          FutureBuilder<void>(
            future: _reading,
            builder: (context, snapshot) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snapshot.hasError) Text(snapshot.error.toString()),
                TextButton(
                  key: ValueKey('source-unit-older:${unit.id}'),
                  onPressed: _reading == null ? _older : null,
                  child: const Text('读取更早过程'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
