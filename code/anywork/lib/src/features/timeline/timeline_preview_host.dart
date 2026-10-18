part of 'timeline_view.dart';

/// 开发预览的只读渲染：用一次性展示 lease 走与生产相同的列表与 builder。
///
/// 预览不打开任何业务资源：没有内容订阅、没有页查询、没有 Driver 事件；结束即退役这个
/// 本地代次（design/26 §26.8）。它也不为观感读取其它会话正文，所以只建立空代次
/// （design/26 §26.9）。
class TimelinePreview extends StatefulWidget {
  const TimelinePreview({required this.threadId, super.key});

  final String threadId;

  @override
  State<TimelinePreview> createState() => _TimelinePreviewState();
}

class _TimelinePreviewState extends State<TimelinePreview> {
  TimelineDisplayLease? _lease;
  TimelineSessionViewState? _state;

  @override
  void initState() {
    super.initState();
    _buildGeneration();
  }

  @override
  void didUpdateWidget(covariant TimelinePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId) {
      final previous = _lease;
      _buildGeneration();
      if (previous != null) unawaited(previous.retire());
    }
  }

  @override
  void dispose() {
    final lease = _lease;
    if (lease != null) unawaited(lease.retire());
    super.dispose();
  }

  void _buildGeneration() {
    final lease = TimelineDisplayLease(
      threadId: widget.threadId,
      generation: (_lease?.generation ?? 0) + 1,
      openQueries: (_) => null,
    );
    lease.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'preview:${widget.threadId}',
        version: 0,
        items: const [],
        before: null,
        hasOlder: false,
      ),
    );
    _lease = lease;
    _state = TimelineSessionViewState(
      threadId: widget.threadId,
      generation: lease.generation,
      mode: TimelineDisplayMode.live,
      connection: TimelineConnectionPhase.ready,
      connectionError: null,
      olderCursor: null,
      hasOlder: false,
      isLoadingOlder: false,
      olderError: null,
      hasNewOutput: false,
      isPreparingLive: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lease = _lease;
    final state = _state;
    if (lease == null || state == null) return const SizedBox.shrink();
    return TimelineView(
      threadId: widget.threadId,
      view: state,
      lease: lease,
      onLoadOlder: () async {},
      onRetryOlder: () async {},
      onReturnLive: () async {},
      onEnterHistory: () {},
      onRetryConnection: () async {},
    );
  }
}
