import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/conversation_fixtures.dart';
import 'support/test_statistics_feed.dart';

// 聚合回归：没有完成/分页时，typed 实时事实（Activity 正文 Begin/Text/Commit、
// runtime/token/usage、Turn/活动进度、计时 typed 事实、存储保存水位）经过真实
// SDK 归约后，不得产生任何历史 Controller 操作，也不得触发任何历史查询。
//
// 这里是完整生产链路：真实 Demo transport 事实 + 真实 AnyworkClient/SDK 归约 +
// 真实 TimelineSessionOwner + 真实 Flyer InMemoryChatController。替身只位于
// transport 输入边界（转发原生帧并按需注入显式 typed 事实、等待 SDK 的真实
// ACK），不手工归约任何业务状态。完成批次正对照使用 Demo 官方夹具
// seedConversationItems，经真实完成尾部（Begin/Commit 携带 completed batch）
// 交付，证明 operationsStream 监听确实生效。
//
// 计时的 UI 层节拍显示（elapsed ticker）不在本层驱动，属于 widget 层证据；
// 本文件只覆盖 typed 计时事实（turnResponseMillis/liveUsage）的投递与收敛。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const threadId = 'thread-main';
  const liveGeneration = 'isolation-live-body';
  const responseRegion = ActivityRegion(
    ActivityRegionKind.response,
    'isolation-live-response',
  );

  test('实时正文/token/进度/计时/保存ACK更新不产生历史Controller操作或历史查询', () async {
    final transport = _IsolationTransport();
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'realtime-history-isolation',
    );
    addTearDown(() async {
      final report = await graph.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      );
      expect(
        report.complete,
        isTrue,
        reason: report.unresolved
            .map((entry) => '${entry.owner}: ${entry.reason}')
            .join('; '),
      );
    });

    await graph.client.bootstrap();
    await (graph..setConversationPageVisible(true)).client.directoryCommands
        .selectThread(threadId);
    final session = graph.client.conversations.session(threadId);
    await session.source.waitFor((state) => state.hasSnapshot);
    await session.content.ready;

    // 首个非空历史 baseline 已由 owner 接纳为当前展示 lease。
    final display = graph.timeline.lease(threadId);
    expect(display, isNotNull, reason: 'baseline 接纳后必须存在展示 lease');
    final lease = display!;
    expect(lease.items, isNotEmpty, reason: 'demo 根会话 baseline 非空');
    final baselineCursor = lease.completedCursor!;
    final baselineLoaded = lease.loadedCount;
    // Controller 展示组与原子数是两个口径：一组可含多个原子，分别捕获。
    final baselineMessageCount = lease.controller.messages.length;
    final baselineMessageIds = [
      for (final message in lease.controller.messages) message.id,
    ];
    final baselineIds = [for (final item in lease.items) item.header.id];
    final baselineEntries = <String, Object?>{
      for (final id in baselineIds) id: lease.presentationFor(id),
    };

    // 操作记录从 baseline 之后开始；正对照在同一监听上验证有效性。
    final operations = <ChatOperation>[];
    final operationSeen = Completer<void>();
    final operationSubscription = lease.controller.operationsStream.listen((
      operation,
    ) {
      operations.add(operation);
      if (!operationSeen.isCompleted) operationSeen.complete();
    });
    addTearDown(operationSubscription.cancel);

    final feed = transport.feeds.singleWhere(
      (candidate) => candidate.threadId == threadId,
    );
    // 等待 Demo 自身的初始 activity 事务（Begin/Commit）全部被 SDK 处理，
    // 注入的 Begin 才不会与原生事务交叠。
    await session.currentActivity
        .waitFor((activity) => activity != null)
        .timeout(const Duration(seconds: 5));
    await feed
        .waitForAcknowledgements(feed.deliveredFrames)
        .timeout(const Duration(seconds: 5));
    final framesBeforeUpdates = feed.deliveredFrames;

    void expectRealtimeOnly(String phase) {
      expect(operations, isEmpty, reason: '$phase: 实时更新不得产生历史 Controller 操作');
      expect(
        transport.historyReaderOpens,
        0,
        reason: '$phase: 实时更新不得打开历史 reader',
      );
      expect(
        transport.readers,
        isEmpty,
        reason: '$phase: 实时更新不得产生任何历史查询 scope',
      );
      expect(
        graph.timeline.lease(threadId),
        same(lease),
        reason: '$phase: 展示 lease 身份不变',
      );
      expect(
        lease.completedCursor?.timelineEpoch,
        baselineCursor.timelineEpoch,
        reason: '$phase: 完成水位 epoch 不变',
      );
      expect(
        lease.completedCursor?.appendSeq,
        baselineCursor.appendSeq,
        reason: '$phase: 完成水位不前进',
      );
      expect(lease.loadedCount, baselineLoaded, reason: '$phase: 已加载原子数不变');
      expect(
        lease.controller.messages,
        hasLength(baselineMessageCount),
        reason: '$phase: Controller 展示组数不变',
      );
      expect(
        [for (final message in lease.controller.messages) message.id],
        equals(baselineMessageIds),
        reason: '$phase: Controller 消息身份集合不变',
      );
      expect(
        [for (final item in lease.items) item.header.id],
        equals(baselineIds),
        reason: '$phase: 原子集合不变',
      );
      for (final entry in baselineEntries.entries) {
        expect(
          lease.presentationFor(entry.key),
          same(entry.value),
          reason: '$phase: 原子/组展示身份不变: ${entry.key}',
        );
      }
    }

    // 1. typed 实时正文：Begin -> Text(replace) -> Text(append) -> Commit，
    //    不携带任何完成批次。
    await feed
        .emitAndWait(
          ConversationActivityContentEvent(
            frame: ActivityBegin(
              generation: liveGeneration,
              revision: 1,
              baseRevision: null,
              activity: null,
              reasoning: const [],
              response: const [
                ActivityPartMetadata(
                  itemId: 'isolation-live-response',
                  complete: false,
                  totalBytes: 11,
                ),
              ],
              tools: const [],
              totalBytes: 11,
            ),
          ),
        )
        .timeout(const Duration(seconds: 5));
    await feed
        .emitAndWait(
          ConversationActivityContentEvent(
            frame: ActivityText(
              generation: liveGeneration,
              revision: 1,
              operations: [ActivityReplace(responseRegion, 'hello ')],
            ),
          ),
        )
        .timeout(const Duration(seconds: 5));
    await feed
        .emitAndWait(
          ConversationActivityContentEvent(
            frame: ActivityText(
              generation: liveGeneration,
              revision: 1,
              operations: [ActivityAppend(responseRegion, 'live!')],
            ),
          ),
        )
        .timeout(const Duration(seconds: 5));
    await feed
        .emitAndWait(
          const ConversationActivityContentEvent(
            frame: ActivityCommit(generation: liveGeneration, revision: 1),
          ),
        )
        .timeout(const Duration(seconds: 5));
    final liveBody = session.currentActivity.value;
    expect(liveBody, isNotNull, reason: '实时正文 Commit 后必须发布 CurrentActivity');
    expect(liveBody!.generation, liveGeneration);
    expect(liveBody.response.single.text, 'hello live!');
    expectRealtimeOnly('实时正文');

    // 2. typed runtime/token/usage/计时事实。
    final runtimeBefore = session.state.runtime!;
    final liveUsage = ThreadRuntimeLiveUsageView(
      turnId: 'turn-isolation',
      attemptId: 'attempt-isolation',
      completionTokens: 8,
      responseMillis: 1200,
      latestContextTokens: runtimeBefore.contextTokens + 40,
      state: ThreadRuntimeUsageState.live,
      observationSequence: 2,
    );
    Future<void> publish(ThreadWorkspaceUpdate update) => feed
        .emitAndWait(
          ConversationStateEvent(
            frame: ThreadNotificationFrame(
              threadId: threadId,
              epoch: session.state.streamEpoch ?? 1,
              baseRevision: session.state.revision,
              revision: session.state.revision + 1,
              update: update,
            ),
          ),
        )
        .timeout(const Duration(seconds: 5));

    await publish(
      ThreadRuntimeUpdate(
        runtime: runtimeBefore.copyWith(
          promptTokens: runtimeBefore.promptTokens + 32,
          completionTokens: runtimeBefore.completionTokens + 8,
          totalTokens: runtimeBefore.totalTokens + 40,
          inferenceCount: runtimeBefore.inferenceCount + 1,
          turnCompletionTokens: 8,
          turnResponseMillis: 1200,
          liveUsage: liveUsage,
        ),
        todo: null,
      ),
    );
    final runtimeAfter = session.state.runtime!;
    expect(runtimeAfter.totalTokens, runtimeBefore.totalTokens + 40);
    expect(runtimeAfter.inferenceCount, runtimeBefore.inferenceCount + 1);
    expect(runtimeAfter.turnResponseMillis, 1200);
    expect(runtimeAfter.liveUsage, liveUsage);
    expectRealtimeOnly('runtime/token/usage/计时');

    // 3. typed 进度：运行中 Turn 与当前活动摘要。
    await publish(
      ThreadTurnUpdate(
        StudioTurnView(
          turnId: 'turn-isolation',
          threadId: threadId,
          revision: 1,
          state: const RunningStudioTurnState(
            startedAt: 1767225600,
            activity: StudioTurnActivity.responding,
          ),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ),
    );
    expect(session.state.activeTurn?.turnId, 'turn-isolation');
    await publish(
      ThreadActivityUpdate(
        activity: const ThreadActivityView(
          threadId: threadId,
          identity: 'activity:isolation:responding',
          revision: 1,
          turnId: 'turn-isolation',
          kind: ThreadActivityKind.responding,
          summary: 'streaming',
        ),
      ),
    );
    expect(session.state.activity?.identity, 'activity:isolation:responding');
    expectRealtimeOnly('Turn/活动进度');

    // 4. typed 存储保存水位（保存 ACK）。
    await publish(
      const ThreadStorageUpdate(
        storage: ThreadStorageStateView(
          acceptedSequence: 9,
          durableSequence: 8,
        ),
      ),
    );
    expect(session.state.storage?.acceptedSequence, 9);
    expect(session.state.storage?.durableSequence, 8);
    expectRealtimeOnly('存储保存水位');

    // 所有注入事实均被 SDK 处理并 ACK；连接保持 ready。
    expect(feed.acknowledgements.length, feed.deliveredFrames);
    expect(framesBeforeUpdates, lessThan(feed.deliveredFrames));
    expect(session.content.state.value, isA<ChatReady<bool>>());

    // 正对照：Demo 官方夹具写入一个完成原子，经真实完成尾部
    // （Begin/Commit 携带 completed batch）交付，owner 接纳后必须产生
    // 真实 Controller 操作并推进完成水位；完成尾部不需要任何历史查询。
    final acksBeforeSeed = feed.acknowledgements.length;
    transport.seedConversationItems(threadId, [
      conversationFixture(id: 'isolation-completed', threadId: threadId),
    ]);
    await operationSeen.future.timeout(const Duration(seconds: 5));
    await feed
        .waitForAcknowledgements(acksBeforeSeed + 2)
        .timeout(const Duration(seconds: 5));
    expect(operations, isNotEmpty, reason: '正对照：真实完成批次必须产生历史 Controller 操作');
    expect(
      lease.completedCursor?.appendSeq,
      baselineCursor.appendSeq + 1,
      reason: '正对照：完成批次推进完成水位',
    );
    expect(lease.loadedCount, baselineLoaded + 1);
    expect(transport.historyReaderOpens, 0, reason: '完成尾部经 feed 交付，同样不需要历史查询');
  });
}

/// 真实 Demo transport；只拦截真实历史读取入口并包装原生 feed 以注入显式
/// typed 事实。所有业务归约仍由生产 SDK 完成。
final class _IsolationTransport extends DemoStudioTransport {
  final feeds = <_InjectingFeed>[];
  final readers = <_CountingHistoryReader>[];
  int historyReaderOpens = 0;

  @override
  Duration get shutdownPhaseDelay => Duration.zero;

  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    ConversationCompletionCursor? resumeAfter,
  }) async {
    final inner = await super.openConversationFeed(
      threadId,
      resumeAfter: resumeAfter,
    );
    final feed = _InjectingFeed(inner);
    feeds.add(feed);
    return feed;
  }

  @override
  Future<ConversationHistoryReader> openHistoryReader(String threadId) async {
    historyReaderOpens++;
    final inner = await super.openHistoryReader(threadId);
    final reader = _CountingHistoryReader(inner);
    readers.add(reader);
    return reader;
  }
}

/// 输入边界包装：原样转发原生帧并重排连续 deliverySequence，注入的显式
/// typed 事实在同一序列上排队，并等待 SDK 处理后的真实 ACK。不是归约者。
final class _InjectingFeed implements ConversationFeed {
  _InjectingFeed(this.inner);
  final ConversationFeed inner;
  final acknowledgements = <int>[];
  int deliveredFrames = 0;
  bool _closed = false;
  bool _claimed = false;
  int _sequence = 0;
  final Map<int, int> _nativeSequences = {};
  final Map<int, Completer<void>> _ackWaiters = {};
  final _ackEvents = StreamController<void>.broadcast();
  StreamSubscription<ConversationFrame>? _subscription;
  Future<void>? _closing;
  late final StreamController<ConversationFrame> _events = StreamController(
    onListen: _listen,
    onCancel: () {
      requestClose();
      return close();
    },
  );

  @override
  String get threadId => inner.threadId;
  @override
  String get subscriptionId => inner.subscriptionId;

  @override
  Stream<ConversationFrame> get events {
    if (_claimed) throw StateError('Injecting feed already has a consumer');
    _claimed = true;
    return _events.stream;
  }

  void _listen() {
    if (_closed) {
      unawaited(_events.close());
      return;
    }
    _subscription = inner.events.listen(
      (frame) {
        if (_closed) return;
        final terminal =
            frame.event is ConversationClosedEvent ||
            frame.event is ConversationFailureEvent;
        final sequence = terminal ? _sequence : ++_sequence;
        deliveredFrames = _sequence;
        if (!terminal) _nativeSequences[sequence] = frame.deliverySequence;
        _events.add(
          ConversationFrame(
            threadId: threadId,
            subscriptionId: subscriptionId,
            deliverySequence: sequence,
            event: frame.event,
          ),
        );
      },
      onError: (Object error, StackTrace stack) {
        if (!_closed) _events.addError(error, stack);
      },
      onDone: () {
        if (!_closed) unawaited(_events.close());
      },
    );
  }

  /// 在传输输入边界发布一条显式 typed 事实，并等待 SDK 的真实 ACK。
  Future<void> emitAndWait(ConversationEvent event) {
    if (_closed) return Future.error(StateError('Injecting feed is closed'));
    final accepted = Completer<void>();
    final sequence = ++_sequence;
    deliveredFrames = _sequence;
    _ackWaiters[sequence] = accepted;
    _events.add(
      ConversationFrame(
        threadId: threadId,
        subscriptionId: subscriptionId,
        deliverySequence: sequence,
        event: event,
      ),
    );
    return accepted.future;
  }

  /// 事件驱动地等待 SDK 累计 ACK 数量；不是 sleep 轮询。
  Future<void> waitForAcknowledgements(int count) async {
    while (acknowledgements.length < count) {
      await _ackEvents.stream.first.timeout(const Duration(seconds: 5));
    }
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    acknowledgements.add(deliverySequence);
    final native = _nativeSequences.remove(deliverySequence);
    if (native != null) await inner.acknowledge(native);
    _nativeSequences.removeWhere((key, _) => key <= deliverySequence);
    _ackWaiters.remove(deliverySequence)?.complete();
    _ackEvents.add(null);
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    inner.requestClose();
    for (final waiter in _ackWaiters.values) {
      waiter.completeError(StateError('Injecting feed closed before ACK'));
    }
    _ackWaiters.clear();
  }

  @override
  Future<void> close() {
    requestClose();
    return _closing ??= _join();
  }

  Future<void> _join() async {
    try {
      await inner.close();
      await _subscription?.cancel();
      if (_claimed) unawaited(_events.close());
      await _ackEvents.close();
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }
}

/// 真实历史读取入口计数：包装 Demo 原生 reader，page/readDetail 每次真实
/// 调用都会递增，close 汇入在途读取。
final class _CountingHistoryReader implements ConversationHistoryReader {
  _CountingHistoryReader(this.inner);
  final ConversationHistoryReader inner;
  int pageCalls = 0;
  int detailCalls = 0;
  final Set<Future<void>> _accepted = {};

  @override
  String get threadId => inner.threadId;
  @override
  String get timelineEpoch => inner.timelineEpoch;

  @override
  Future<ConversationPage> page({ConversationQueryCursor? before, int? limit}) {
    pageCalls++;
    final result = inner.page(before: before, limit: limit);
    _track(result);
    return result;
  }

  @override
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  }) {
    detailCalls++;
    final result = inner.readDetail(itemId: itemId, query: query);
    _track(result);
    return result;
  }

  void _track(Future<Object?> future) {
    final settled = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _accepted.add(settled);
    unawaited(settled.then((_) => _accepted.remove(settled)));
  }

  @override
  void requestClose() => inner.requestClose();

  @override
  Future<void> close() async {
    requestClose();
    await inner.close();
    await Future.wait(_accepted.toList());
  }
}
