import 'dart:async';

import 'package:anywork_client/anywork_client.dart';
import 'package:anywork_client/models.dart';

/// 一条 timeline 条目在测试里的最小预览值（正文用 [body] 承载）。
StudioTimelineItem timelineItem(
  int revision, {
  String id = 'item',
  String body = 'body',
  String threadId = 'thread',
  int ordinal = 0,
  bool saved = false,
  StudioTimelineLifecycle lifecycle = StudioTimelineLifecycle.streaming,
  int omittedBytes = 0,
  List<StudioTimelineDetailRef> details = const [],
}) => StudioTimelineItem(
  item: ThreadItemView(
    id: id,
    threadId: threadId,
    turnId: 'turn',
    ordinal: ordinal,
    revision: revision,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    state: ThreadTextItemStateView(
      channel: ThreadTextChannel.finalAnswer,
      text: body,
      attachments: const <ThreadAttachmentView>[],
      lifecycle: lifecycle == StudioTimelineLifecycle.terminal
          ? CompletedThreadContentView(DateTime.utc(2026))
          : const StreamingThreadContentView(),
    ),
    saved: saved,
  ),
  saved: saved,
  lifecycle: lifecycle,
  omittedBytes: omittedBytes,
  details: details,
);

StudioTimelineBaseline baseline(
  int version, {
  String subscriptionId = 'sub',
  List<StudioTimelineItem>? items,
  String? before,
  bool hasOlder = false,
}) => StudioTimelineBaseline(
  subscriptionId: subscriptionId,
  version: version,
  items: items ?? [timelineItem(version)],
  before: before,
  hasOlder: hasOlder,
);

StudioTimelinePatch patch(
  int from,
  int to, {
  String subscriptionId = 'sub',
  List<StudioTimelineChange> changes = const [],
}) => StudioTimelinePatch(
  subscriptionId: subscriptionId,
  from: from,
  to: to,
  changes: changes,
  priority: StudioTimelinePriority.coalesced,
);

/// 记录 open/initial/next/page/readDetail/close 的测试替身。
///
/// 它只模拟生命周期交错，不实现业务内容：所有返回值都由测试显式给出。
final class TestTimelineTransport implements TimelineTransport {
  final List<Completer<TestTimelineConnection>> opens = [];

  @override
  Future<TestTimelineConnection> openTimeline(String threadId) {
    final pending = Completer<TestTimelineConnection>();
    opens.add(pending);
    return pending.future;
  }
}

final class TestTimelineConnection implements StudioTimelineConnection {
  TestTimelineConnection({StudioTimelineBaseline? initial}) {
    if (initial != null) initialResult.complete(initial);
  }

  final Completer<StudioTimelineBaseline> initialResult = Completer();
  final Completer<void> initialStarted = Completer();
  final Completer<void> nextStarted = Completer();
  final Completer<void> closeCompleted = Completer();
  final Completer<void> closeStarted = Completer();
  Completer<void>? closeGate;
  Completer<StudioTimelinePage>? pageResult;
  final List<({String? before, int? limit})> pageRequests = [];
  final List<({String itemId, StudioTimelineDetailQuery query})>
  detailRequests = [];
  Completer<StudioTimelineDetailChunk>? detailResult;
  Completer<StudioTimelineUpdate?>? _pending;
  bool _closed = false;
  int initialCalls = 0;
  int nextCalls = 0;
  int closeCalls = 0;
  int requestCloseCalls = 0;
  Object? closeFailure;

  @override
  Future<StudioTimelineBaseline> initial() {
    initialCalls++;
    if (!initialStarted.isCompleted) initialStarted.complete();
    return initialResult.future;
  }

  @override
  Future<StudioTimelineUpdate?> next() {
    if (_closed) return Future.value(null);
    if (_pending != null) throw StateError('Two concurrent next calls');
    nextCalls++;
    final pending = Completer<StudioTimelineUpdate?>();
    _pending = pending;
    if (!nextStarted.isCompleted) nextStarted.complete();
    return pending.future;
  }

  void emit(StudioTimelineUpdate? update) {
    final pending = _pending;
    if (pending == null) throw StateError('No pending content read');
    _pending = null;
    pending.complete(update);
  }

  void emitError(Object error, [StackTrace? stackTrace]) {
    final pending = _pending;
    if (pending == null) throw StateError('No pending content read');
    _pending = null;
    pending.completeError(error, stackTrace);
  }

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) {
    pageRequests.add((before: before, limit: limit));
    // 每次页调用都是一次独立 RPC：复用同一个 Completer 会让第二次调用直接
    // 卡在已完成的 future 上（或抛 Future already completed）。
    final result = Completer<StudioTimelinePage>();
    pageResult = result;
    return result.future;
  }

  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) {
    detailRequests.add((itemId: itemId, query: query));
    // 每次详情读取都是一次独立 RPC：复用同一个 Completer 会让按块续读直接崩。
    final result = Completer<StudioTimelineDetailChunk>();
    detailResult = result;
    return result.future;
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    _closed = true;
    if (initialCalls > 0 && !initialResult.isCompleted) {
      initialResult.completeError(const StaleTimelineAttempt());
    }
    final pending = _pending;
    _pending = null;
    pending?.complete(null);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    if (!closeStarted.isCompleted) closeStarted.complete();
    await closeGate?.future;
    if (closeFailure case final error?) throw error;
    if (!closeCompleted.isCompleted) closeCompleted.complete();
  }
}

StudioTimelineChannel timelineChannel(
  TestTimelineTransport transport, {
  ResourceBudget? budget,
}) => StudioTimelineChannel(
  threadId: 'thread',
  transport: transport,
  retryPolicy: const RetryPolicy(delays: []),
  budget: budget,
);
