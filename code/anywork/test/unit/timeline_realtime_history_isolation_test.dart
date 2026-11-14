import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/display_fixtures.dart';
import '../support/mapped_conversation_feed.dart';

import 'package:anywork/src/domain/models/timeline_commands.dart';

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
    await timelineReady(graph.timeline, threadId);

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
    await feed.waitForAccepted(feed.deliveredFrames);
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

    final live = TailSnapshot(
      currentWorkId: null,
      revision: (lease.live.value?.revision ?? 0) + 1,
      layoutRevision: (lease.live.value?.revision ?? 0) + 1,
      readyFrontier: feed.readyFrontier,
      executionPresent: true,
      blocks: [
        LiveDisplayBlock(
          id: 'live',
          blockOrder: feed.readyFrontier + 1,
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
      displayBatch(
        [],
        placement: ChatPlacement.append,
        from: feed.readyFrontier,
        through: feed.readyFrontier,
        live: live,
      ),
    );
    expect(lease.live.value, same(live));
    expect(lease.live.value!.blocks.single.id, 'live');
    expectRealtimeOnly('live snapshot');
    await feed.emitAndWait(
      displayBatch(
        [],
        placement: ChatPlacement.append,
        from: feed.readyFrontier,
        through: feed.readyFrontier,
        live: live,
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
    expect(feed.acceptedCursors.length, feed.deliveredFrames);
    expect(framesBeforeUpdates, lessThan(feed.deliveredFrames));
    expect(
      graph.timeline.source.value!.connection,
      TimelineConnectionPhase.ready,
    );

    // Positive control: an explicit producer item traverses the same SDK/ACK path.
    final acksBeforeSeed = feed.acceptedCursors.length;
    await feed.emitAndWait(
      displayBatch(
        [
          displaySingle(
            chatMessage('isolation-completed', completionSeq: 200),
            blockOrder: feed.readyFrontier + 1,
          ),
        ],
        placement: ChatPlacement.append,
        from: feed.readyFrontier,
      ),
    );
    await operationSeen.future.timeout(const Duration(seconds: 5));
    await feed
        .waitForAccepted(acksBeforeSeed + 1)
        .timeout(const Duration(seconds: 5));
    expect(operations, isNotEmpty, reason: '正对照：真实完成批次必须产生历史 Controller 操作');
    expect(lease.loadedCount, baselineLoaded + 1);
    expect(lease.controller.messages.last.id, 'isolation-completed');
    expect(feed.reader.queries + feed.timelineQueries, 0);
    await feed.emitAndWait(
      displayBatch(
        [],
        placement: ChatPlacement.append,
        from: feed.readyFrontier,
        through: feed.readyFrontier,
        live: TailSnapshot(
          currentWorkId: null,
          revision: live.revision + 1,
          layoutRevision: live.revision + 1,
          readyFrontier: feed.readyFrontier,
          executionPresent: false,
          blocks: const [],
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
  Future<TimelineReader> openTimelineReader(
    String threadId, {
    required int presentationVersion,
    required int readerProtocolVersion,
    required ReadDemand demand,
  }) async {
    final feed = _InjectingFeed(
      await super.openTimelineReader(
        threadId,
        presentationVersion: presentationVersion,
        readerProtocolVersion: timelineReaderProtocolVersion,
        demand: demand,
      ),
    );
    feeds.add(feed);
    return feed;
  }
}

/// Injects only peer responses. Application and all cursor decisions remain in the real GUI owner.
final class _InjectingFeed extends RecordingTimelineReader {
  _InjectingFeed(TimelineReader inner)
    : super(
        inner: MappedTimelineReader(
          inner,
          reader: _CountingReader(inner.reader),
        ),
      );
  @override
  _CountingReader get reader => super.reader as _CountingReader;
  int readyFrontier = 0;
  int get timelineQueries => pageCalls + detailCalls;
  @override
  Future<ViewUpdate> next({required ViewCursor after}) async {
    final update = await super.next(after: after);
    readyFrontier = update.history.throughOrder;
    return update;
  }

  Future<void> emitAndWait(ViewUpdate update) {
    final response = deliveredFrames + 1;
    emitTimeline(update);
    return waitForAccepted(response);
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
