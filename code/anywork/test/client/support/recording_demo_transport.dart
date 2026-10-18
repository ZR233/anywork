import 'dart:async';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';

/// Uses Demo's real directory/runtime/content behavior. Only resource ownership
/// is recorded; this fixture never claims to exercise a native FRB handle.
class RecordingDemoTransport extends DemoStudioTransport {
  RecordingDemoTransport() : super(lspActivityLoop: false);

  /// 本传输打开过的内容连接（按打开顺序）。
  final List<RecordingTimelineConnection> timelines = [];
  final bootstrapDelivered = Completer<void>();
  int bootstrapCalls = 0;

  /// 非空时下一次打开的内容连接首帧失败（消费一次）。
  Object? failNextInitial;

  @override
  Duration get shutdownPhaseDelay => Duration.zero;

  @override
  Future<StudioBootstrap> readBootstrap() async {
    bootstrapCalls++;
    final result = await super.readBootstrap();
    if (!bootstrapDelivered.isCompleted) bootstrapDelivered.complete();
    return result;
  }

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) async {
    final failure = failNextInitial;
    failNextInitial = null;
    final connection = RecordingTimelineConnection(
      threadId: threadId,
      inner: await super.openTimeline(threadId),
      initialFailure: failure,
    );
    timelines.add(connection);
    return connection;
  }
}

/// 记录一条内容连接的生命周期事实：打开、首帧、取帧、查询、取消与真实 join。
///
/// 它只替换故障点/门槛，不实现业务内容：正文仍由 demo 的 [`DemoStudioTransport`] 提供。
class RecordingTimelineConnection implements StudioTimelineConnection {
  RecordingTimelineConnection({
    required this.threadId,
    required this.inner,
    this.initialFailure,
  });

  final String threadId;
  final StudioTimelineConnection inner;

  /// 非空时首帧以该错误收束（消费一次），用于故障注入。
  Object? initialFailure;
  final nextEntered = Completer<void>();
  final joined = Completer<void>();

  /// 非空时首帧被挂起，用于观察“连接已打开但首帧未到”的中间状态。
  Completer<void>? initialGate;

  int initialCalls = 0;
  int nextCalls = 0;
  int pageCalls = 0;
  int detailCalls = 0;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  bool _closed = false;

  /// 非空时由测试脚本提供尾部帧（仍走 production 的唯一内容泵）。
  bool scriptFrames = false;
  final List<Completer<StudioTimelineUpdate?>> _scriptedFrames = [];

  /// 非空时由测试脚本提供页结果，用于观察分页在途/失败/去重。
  Completer<StudioTimelinePage>? scriptedPage;

  @override
  Future<StudioTimelineBaseline> initial() async {
    initialCalls++;
    await initialGate?.future;
    final failure = initialFailure;
    if (failure != null) {
      initialFailure = null;
      throw failure;
    }
    return inner.initial();
  }

  @override
  Future<StudioTimelineUpdate?> next() {
    nextCalls++;
    if (!nextEntered.isCompleted) nextEntered.complete();
    if (scriptFrames) {
      final pending = Completer<StudioTimelineUpdate?>();
      _scriptedFrames.add(pending);
      return pending.future;
    }
    return inner.next();
  }

  void emit(StudioTimelineUpdate? update) {
    if (_scriptedFrames.isEmpty) throw StateError('No pending content read');
    _scriptedFrames.removeAt(0).complete(update);
  }

  void emitError(Object error) {
    if (_scriptedFrames.isEmpty) throw StateError('No pending content read');
    _scriptedFrames.removeAt(0).completeError(error);
  }

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) {
    pageCalls++;
    final scripted = scriptedPage;
    if (scripted != null) return scripted.future;
    return inner.page(before: before, limit: limit);
  }

  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) {
    detailCalls++;
    return inner.readDetail(itemId: itemId, query: query);
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    if (_closed) return;
    _closed = true;
    inner.requestClose();
    for (final pending in _scriptedFrames) {
      if (!pending.isCompleted) pending.complete(null);
    }
    _scriptedFrames.clear();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    await inner.close();
    if (!joined.isCompleted) joined.complete();
  }
}
