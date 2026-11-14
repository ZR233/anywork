import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/display_fixtures.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_statistics_feed.dart';

// Main Timeline and State facts traverse the real SDK and display owner.
// Pure-live Append must not touch the historical component collection. A
// explicit producer-item Append below is the positive control for operation observation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const threadId = 'thread-main';
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
    graph.timeline.updateReadDemand(chatDemand);
    await (graph..setConversationPageVisible(true)).client.directoryCommands
        .selectThread(threadId);
    final session = graph.client.conversations.session(threadId);
    await session.source.waitFor((state) => state.hasSnapshot);
    await session.content.ready;

    final lease = graph.timeline.lease(threadId)!;
    expect(lease.controller.messages, isNotEmpty);
    final baselineLoaded = lease.loadedCount;
    final baselineMessages = lease.controller.messages.toList();
    final baselineBefore = lease.olderCursor;
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
    await feed.waitForAcknowledgements(feed.deliveredFrames);
    final framesBeforeUpdates = feed.deliveredFrames;
    void expectRealtimeOnly(String phase) {
      expect(operations, isEmpty, reason: '$phase must not mutate history');
      expect(graph.timeline.lease(threadId), same(lease));
      expect(lease.loadedCount, baselineLoaded);
      expect(lease.olderCursor, baselineBefore);
      expect(lease.controller.messages.length, baselineMessages.length);
      for (var i = 0; i < baselineMessages.length; i++) {
        expect(lease.controller.messages[i], same(baselineMessages[i]));
      }
      expect(
        feed.reader.queries + feed.timelineQueries,
        0,
        reason: '$phase must not query any content or older page',
      );
    }

    final live = LiveDisplayWindow(
      currentWorkId: null,
      revision: (lease.live.value?.revision ?? 0) + 1,
      readyFrontier: feed.readyFrontier,
      executionPresent: true,
      blocks: [
        LiveDisplayBlock(
          id: 'live',
          blockOrder: 1,
          state: DisplayBlockState.open,
          body: SingleDisplayBlock(
            visibility: SingleVisibility.content,
            record: DisplayRecord(
              atom: ChatAtom(
                id: 'live',
                source: const ForegroundTurnChatSource(
                  turnId: 'turn-isolation',
                ),
                sourceOrder: 1,
                kind: ChatAtomKind.text,
                delivery: ChatDeliveryKind.foreground,
                lifecycle: const ActiveChatAtom(
                  started: null,
                  status: ChatActiveStatus.running,
                ),
                contents: const [],
                payload: InlinePayload(bytes: [65]),
              ),
              contentSource: const CurrentAtom(),
            ),
          ),
        ),
      ],
    );
    await feed.emitAndWait(
      ConversationTimelineEvent(
        batch: displayBatch(
          [],
          placement: ChatPlacement.append,
          from: feed.readyFrontier,
          through: feed.readyFrontier,
          live: live,
        ),
      ),
    );
    expect(lease.live.value, same(live));
    expect(lease.live.value!.blocks.single.id, 'live');
    expectRealtimeOnly('live snapshot');
    await feed.emitAndWait(
      ConversationTimelineEvent(
        batch: displayBatch(
          [],
          placement: ChatPlacement.append,
          from: feed.readyFrontier,
          through: feed.readyFrontier,
          live: live,
        ),
      ),
    );
    expect(
      lease.live.value,
      same(live),
      reason: 'Pure live changes do not retire accepted blocks',
    );
    expectRealtimeOnly('pure-live Append');
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
    Future<void> publish(ThreadWorkspaceUpdate update) => transport
        .stateFeeds
        .last
        .emitStateAndWait(
          ThreadNotificationFrame(
            threadId: threadId,
            epoch: session.state.streamEpoch ?? 1,
            baseRevision: session.state.revision,
            revision: session.state.revision + 1,
            update: update,
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
        // 本帧只交付 runtime/用量事实，既有 route 必须原样带过，不清空。
        modelRoute: session.state.modelRoute,
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
    expect(
      lease.live.value,
      same(live),
      reason: 'State turn cannot overwrite accepted live',
    );
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
    expect(
      lease.live.value,
      same(live),
      reason: 'State activity cannot overwrite accepted live',
    );
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

    // Positive control: an explicit producer item traverses the same SDK/ACK path.
    final acksBeforeSeed = feed.acknowledgements.length;
    await feed.emitAndWait(
      ConversationTimelineEvent(
        batch: displayBatch(
          [
            displaySingle(
              chatMessage('isolation-completed', completionSeq: 200),
              blockOrder: feed.readyFrontier + 1,
            ),
          ],
          placement: ChatPlacement.append,
          from: feed.readyFrontier,
        ),
      ),
    );
    await operationSeen.future.timeout(const Duration(seconds: 5));
    await feed
        .waitForAcknowledgements(acksBeforeSeed + 1)
        .timeout(const Duration(seconds: 5));
    expect(operations, isNotEmpty, reason: '正对照：真实完成批次必须产生历史 Controller 操作');
    expect(lease.loadedCount, baselineLoaded + 1);
    expect(lease.controller.messages.last.id, 'isolation-completed');
    expect(feed.reader.queries + feed.timelineQueries, 0);
    await feed.emitAndWait(
      ConversationTimelineEvent(
        batch: displayBatch(
          [],
          placement: ChatPlacement.append,
          from: feed.readyFrontier,
          through: feed.readyFrontier,
          live: LiveDisplayWindow(
            currentWorkId: null,
            revision: live.revision + 1,
            readyFrontier: feed.readyFrontier,
            executionPresent: false,
            blocks: const [],
          ),
        ),
      ),
    );
    expect(
      lease.live.value!.blocks,
      isEmpty,
      reason: 'An explicit empty live window retires unfinished operations',
    );
  });
}

final class _IsolationTransport extends DemoStudioTransport {
  final feeds = <_InjectingFeed>[];
  final stateFeeds = <RecordingConversationStateFeed>[];
  @override
  Future<ConversationStateFeed> openConversationStateFeed(
    String threadId,
  ) async {
    final feed = RecordingConversationStateFeed(
      inner: await super.openConversationStateFeed(threadId),
    );
    stateFeeds.add(feed);
    return feed;
  }

  @override
  Duration get shutdownPhaseDelay => Duration.zero;
  @override
  Future<TimelineFeed> openTimelineFeed(
    String threadId, {
    required ReadDemand demand,
  }) async {
    final feed = _InjectingFeed(
      await super.openTimelineFeed(threadId, demand: demand),
    );
    feeds.add(feed);
    return feed;
  }
}

/// 输入边界包装：原样转发原生帧并重排连续 deliverySequence，注入的显式
/// typed 事实在同一序列上排队，并等待 SDK 处理后的真实 ACK。不是归约者。
final class _InjectingFeed implements TimelineFeed {
  _InjectingFeed(this.inner) : reader = _CountingReader(inner.reader);
  @override
  final _CountingReader reader;
  final TimelineFeed inner;
  int timelineQueries = 0;
  @override
  Future<TimelineBatch> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) {
    timelineQueries++;
    return inner.loadTimelineOlder(before: before, demand: demand);
  }

  @override
  Future<LiveDisplayWindow> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  }) {
    timelineQueries++;
    return inner.loadLiveOlder(before: before, demand: demand);
  }

  @override
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) {
    timelineQueries++;
    return inner.openDisplayMembers(
      reference: reference,
      window: window,
      demand: demand,
    );
  }

  final acknowledgements = <int>[];
  int deliveredFrames = 0;
  int readyFrontier = 0;
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
        if (frame.event case ConversationTimelineEvent(:final batch)) {
          readyFrontier = batch.throughOrder;
        }
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
    if (event case ConversationTimelineEvent(:final batch)) {
      readyFrontier = batch.throughOrder;
    }
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

// Count actual queries without retaining messages or implementing admission.
final class _CountingReader implements ConversationReader {
  @override
  Future<ThreadBusinessRefs> readBusinessRefs() {
    queries++;
    return inner.readBusinessRefs();
  }

  @override
  Future<CompletedEntry> readCompleted({
    required String recordId,
    required ReadDemand demand,
  }) {
    queries++;
    return inner.readCompleted(recordId: recordId, demand: demand);
  }

  _CountingReader(this.inner);
  final ConversationReader inner;
  int queries = 0;
  @override
  String get threadId => inner.threadId;
  @override
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  }) {
    queries++;
    return inner.loadOlder(before: before, demand: demand);
  }

  @override
  Future<ContentManifestPage> listContents({
    required String itemId,
    String? continuation,
    required ReadDemand demand,
  }) {
    queries++;
    return inner.listContents(
      itemId: itemId,
      continuation: continuation,
      demand: demand,
    );
  }

  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    queries++;
    return inner.readContent(reference: reference, range: range);
  }

  @override
  ConversationContentWatch watchContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    queries++;
    return inner.watchContent(reference: reference, range: range);
  }

  @override
  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) {
    queries++;
    return inner.pageCurrent(
      reference: reference,
      continuation: continuation,
      demand: demand,
    );
  }

  @override
  void requestClose() => inner.requestClose();
  @override
  Future<void> close() => inner.close();
}
