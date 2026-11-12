import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart' show ConversationActivityView;
import 'package:material_ui/material_ui.dart';

import '../live_status/live_status_state.dart';
import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_display_unit.dart';
import '../state/timeline_image_resources.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/timeline_display_unit_view.dart';
import 'completion_run_connector.dart';
import 'timeline_member_atom.dart';

enum ConversationLiveSection { work, output }

/// 实时展示租约作用域适配器（`implements TimelineCurrentDisplay`）：
/// 仅负责将 `LiveStatusViewModel` 已归约好的
/// 表面与分页结果绑定到原始 `TimelineDisplayLease` 生命周期，管理 `SingleDisplayBlock` 退役通知。
/// 不在 Widget `build()` 内重复执行阶段吸收、工作组归属筛选或外部状态发布。
class ConversationCurrentConnector extends StatefulWidget {
  const ConversationCurrentConnector({
    required this.threadId,
    this.turnId,
    this.activityId,
    required this.section,
    required this.content,
    required this.liveUnit,
    required this.images,
    required this.readAttachment,
    required this.isDisplayActive,
    this.presenting,
    this.workSlice,
    this.onLoadOlder,
    this.onReturnToLatest,
    this.registerDisplay,
    this.onExpandedChanged,
    this.now,
    super.key,
  }) : assert(section != ConversationLiveSection.work || workSlice != null);

  final String threadId;
  final String? turnId;
  final String? activityId;
  final ConversationLiveSection section;
  final ConversationContent content;
  final TimelineDisplayUnit Function(LiveDisplayBlock, bool) liveUnit;
  final TimelineImageResources images;
  final Future<Uint8List> Function(String) readAttachment;
  final bool Function() isDisplayActive;

  /// 生产路径由 `LiveStatusViewModel` 预计算交付的底部实时状态栏呈现状态。
  final LiveStatusPresenting? presenting;

  /// 生产路径由 `LiveStatusViewModel` 预计算交付的时间线实时工作区切片。
  final LiveStatusTimelineWorkSlice? workSlice;

  /// 生产路径委托给 `LiveStatusViewModel` 的更早窗口分页动作。
  final ValueChanged<String>? onLoadOlder;
  final VoidCallback? onReturnToLatest;

  final VoidCallback Function(TimelineCurrentDisplay)? registerDisplay;
  final ValueChanged<bool>? onExpandedChanged;
  final DateTime Function()? now;

  @override
  State<ConversationCurrentConnector> createState() => _CurrentState();
}

class _CurrentState extends State<ConversationCurrentConnector>
    implements TimelineCurrentDisplay {
  final Set<TimelineMemberDisplay> _members = {};
  final Map<String, ValueNotifier<bool>> _retirements = {};
  VoidCallback? _unregister;
  bool _disposed = false;
  @override
  bool get isCurrent => mounted && !_disposed && widget.isDisplayActive();

  @override
  String? get turnId => isCurrent ? widget.turnId : null;

  @override
  String? get activityId => isCurrent ? widget.activityId : null;

  @override
  bool get expanded => isCurrent && _members.isNotEmpty;

  @override
  Iterable<TimelineCurrentCollectionDisplay> get collections => const [];

  @override
  Iterable<TimelineCurrentWindowDisplay> get windows sync* {
    if (!isCurrent) return;
    for (final member in _members) {
      yield* member.windows;
    }
  }

  @override
  void initState() {
    super.initState();
    _unregister = widget.registerDisplay?.call(this);
    _synchronizeRetirements();
  }

  @override
  void didUpdateWidget(covariant ConversationCurrentConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.content, widget.content)) {
      throw StateError('Live content cannot change its original lease');
    }
    _synchronizeRetirements();
  }

  void _synchronizeRetirements() {
    final blocks = widget.section == ConversationLiveSection.output
        ? (widget.presenting?.surface.blocks ?? const <LiveDisplayBlock>[])
        : const <LiveDisplayBlock>[];
    final wanted = {
      if (isCurrent)
        for (final block in blocks)
          if (block.body is SingleDisplayBlock) block.id,
    };
    for (final id in _retirements.keys.toList()) {
      if (wanted.contains(id)) continue;
      final notifier = _retirements.remove(id)!;
      notifier.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => notifier.dispose());
    }
    for (final id in wanted) {
      _retirements.putIfAbsent(id, () => ValueNotifier(false));
    }
  }

  void _requestOlder(String before) {
    if (isCurrent) widget.onLoadOlder?.call(before);
  }

  void _returnToLatest() {
    if (isCurrent) widget.onReturnToLatest?.call();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final notifier in _retirements.values) {
      notifier.value = true;
      notifier.dispose();
    }
    _retirements.clear();
    _members.clear();
    _unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isCurrent) return const SizedBox.shrink();
    if (widget.section == ConversationLiveSection.work) {
      return _buildWorkSection(
        widget.workSlice ?? LiveStatusTimelineWorkSlice(),
      );
    }
    final presenting = widget.presenting;
    if (presenting == null) return const SizedBox.shrink();
    return _buildOutputSection(presenting);
  }

  Widget _buildWorkSection(LiveStatusTimelineWorkSlice slice) {
    Widget pad(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: child,
    );
    final window = slice.effectiveWindow;
    final children = <Widget>[
      ..._pagingWidgets(
        paging: slice.paging,
        olderCursor: window?.older,
        wrap: pad,
      ),
      if (window != null)
        for (final block in slice.workBlocks)
          pad(_work(block, window.executionPresent)),
    ];
    return Column(
      key: const ValueKey('timeline-current-work'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildOutputSection(LiveStatusPresenting presenting) {
    final surface = presenting.surface;
    final window = presenting.effectiveWindow;
    final hasPagingControls =
        presenting.paging.isLoading ||
        presenting.paging.isViewingOlder ||
        presenting.paging.error != null;
    if (surface.blocks.isEmpty &&
        surface.standaloneNotices.isEmpty &&
        !hasPagingControls) {
      return const SizedBox.shrink();
    }
    final leading = <Widget>[
      if (surface.standaloneNotices.isNotEmpty)
        ConversationRealtimeNotices(notices: surface.standaloneNotices),
      ..._pagingWidgets(
        paging: presenting.paging,
        olderCursor: window?.older,
        wrap: (child) => child,
      ),
    ];
    final children = <Widget>[
      if (window != null)
        for (final block in surface.blocks)
          switch (block.body) {
            WorkDisplayBlock() => _work(
              block,
              window.executionPresent,
              activity: surface.mergedActivityFor(block.id),
            ),
            SingleDisplayBlock(
              visibility: SingleVisibility.finalEmptyAfterContent,
            ) =>
              const Text('该输出的最终内容为空'),
            SingleDisplayBlock(:final record) => TimelineMemberAtom(
              key: ValueKey((block.id, _retirements[block.id])),
              record: record,
              displayId: block.id,
              executionPresent: window.executionPresent,
              retirement: _retirements[block.id],
              content: widget.content,
              isActive: () =>
                  isCurrent && _retirements[block.id]?.value == false,
              images: widget.images,
              readAttachment: widget.readAttachment,
              registerDisplay: (member) {
                _members.add(member);
                return () => _members.remove(member);
              },
            ),
          },
    ];
    return ConversationActivityBar(leading: leading, children: children);
  }

  List<Widget> _pagingWidgets({
    required LiveWindowPagingState paging,
    required String? olderCursor,
    required Widget Function(Widget) wrap,
  }) => [
    if (paging.error case final error?) wrap(Text(error.toString())),
    if (paging.isLoading) wrap(const LinearProgressIndicator()),
    if (olderCursor case final before?)
      wrap(
        TextButton(
          onPressed: () => _requestOlder(before),
          child: const Text('更早实时片段'),
        ),
      ),
    if (paging.isViewingOlder)
      wrap(TextButton(onPressed: _returnToLatest, child: const Text('最新实时片段'))),
  ];

  Widget _work(
    LiveDisplayBlock block,
    bool executionPresent, {
    ConversationActivityView? activity,
  }) {
    final unit = widget.liveUnit(block, executionPresent);
    return TimelineDisplayUnitView(
      key: ValueKey(block.id),
      unit: unit,
      activity: activity,
      now: widget.now,
      onExpandedChanged: widget.onExpandedChanged,
      childBuilder: (_) => CompletionRunConnector(
        unit: unit,
        threadId: widget.threadId,
        content: widget.content,
        images: widget.images,
        readAttachment: widget.readAttachment,
        registerMemberDisplay: (member) {
          _members.add(member);
          return () => _members.remove(member);
        },
      ),
    );
  }
}
