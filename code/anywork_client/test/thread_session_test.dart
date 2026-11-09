import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/controlled_batch_consumer.dart';
import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 20, maxBytes: 65536);

ThreadWorkspace _workspace({
  int revision = 1,
  ThreadRuntimeView? runtime,
  ThreadModelRouteView? modelRoute,
  StudioTurnView? latestTurn,
  StudioTurnView? activeTurn,
}) {
  final thread = StudioThread(
    id: 'thread',
    workspaceId: 'project',
    title: 'Thread',
    mode: ThreadModeId.simple,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    updatedAt: DateTime.utc(2026),
    workspacePath: '/tmp/thread',
  );
  return ThreadWorkspace(
    businessRefs: const ThreadBusinessRefs(plan: null, interactions: null),
    thread: thread,
    revision: revision,
    interactions: const [],
    modelRoute: modelRoute,
    activeTurn: activeTurn,
    latestTurn: latestTurn,
    runtime:
        runtime ??
        const ThreadRuntimeView(
          modelId: 'model',
          contextTokens: 0,
          contextWindow: 1,
          totalTokens: 0,
          costLabel: '',
          activeSkills: [],
          activeMcpServers: [],
          activeLspServers: [],
        ),
  );
}

ThreadModelRouteView _route(int revision) => ThreadModelRouteView(
  accountId: 'account',
  modelId: 'model',
  effort: 'medium',
  revision: revision,
  available: true,
);

StudioTurnView _turnView({
  String turnId = 'turn',
  int revision = 1,
  DateTime? updatedAt,
  StudioTurnState state = const RunningStudioTurnState(
    startedAt: 1,
    activity: StudioTurnActivity.thinking,
  ),
}) => StudioTurnView(
  inputId: 'input-$turnId',
  turnId: turnId,
  threadId: 'thread',
  revision: revision,
  state: state,
  updatedAt: updatedAt ?? DateTime.utc(2026),
);

ThreadRuntimeView _approvedPlanRuntime({
  required String markdown,
  required int version,
  String contentHash = 'hash-v3',
}) {
  return ThreadRuntimeView(
    modelId: 'model',
    contextTokens: 0,
    contextWindow: 1,
    totalTokens: 0,
    costLabel: '',
    activeSkills: const [],
    activeMcpServers: const [],
    activeLspServers: const [],
    plan: PlanRuntimeView(
      revision: 7,
      state: PlanRuntimePhase.approved,
      updatedAt: DateTime.utc(2026, 3, 1),
      document: PlanDocumentView(
        version: version,
        markdown: markdown,
        contentHash: contentHash,
      ),
    ),
  );
}

ThreadRuntimeView _runtimeUsage(int completionTokens) => ThreadRuntimeView(
  modelId: 'model',
  contextTokens: 1,
  contextWindow: 100000,
  totalTokens: completionTokens + 1,
  completionTokens: completionTokens,
  inferenceCount: 1,
  costLabel: '',
  activeSkills: const [],
  activeMcpServers: const [],
  activeLspServers: const [],
);

void main() {
  test('model route is independent of cold runtime and clears without stale resurrection', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    final state = fixture.stateFeed();
    final session = fixture.session();
    await state.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace(revision: 1, modelRoute: _route(4)),
        ),
      ),
    );
    expect(session.state.runtime, isNotNull);
    expect(session.state.runtime!.execution, isNull);
    expect(session.state.modelRoute, _route(4));

    await state.deliver(
      ConversationStateEvent(
        frame: ThreadNotificationFrame(
          threadId: 'thread',
          revision: 2,
          baseRevision: 1,
          epoch: 7,
          update: ThreadRuntimeUpdate(
            runtime: _runtimeUsage(1),
            todo: null,
            modelRoute: _route(5),
          ),
        ),
      ),
    );
    expect(session.state.modelRoute, _route(5));

    await state.deliver(
      ConversationStateEvent(
        frame: ThreadNotificationFrame(
          threadId: 'thread',
          revision: 3,
          baseRevision: 2,
          epoch: 7,
          update: ThreadRuntimeUpdate(
            runtime: _runtimeUsage(2),
            todo: null,
            modelRoute: null,
          ),
        ),
      ),
    );
    expect(session.state.modelRoute, isNull);

    final staleSequence = state.send(
      ConversationStateEvent(
        frame: ThreadNotificationFrame(
          threadId: 'thread',
          revision: 3,
          baseRevision: 2,
          epoch: 6,
          update: ThreadRuntimeUpdate(
            runtime: _runtimeUsage(99),
            todo: null,
            modelRoute: _route(99),
          ),
        ),
      ),
    );
    // An old epoch requires resync and is not ACKed. Observe the original
    // state feed's retirement instead of waiting forever for the delivery
    // acknowledgement; the content feed keeps its live owner.
    await state.requestCloseStarted.future;
    await state.closeCompleted.future;
    expect(state.acknowledgements, isNot(contains(staleSequence)));
    expect(
      feed.requestCloseCalls,
      0,
      reason: 'state resync must not retire valid content',
    );
    expect(session.state.modelRoute, isNull);
    expect(session.state.runtime!.completionTokens, 2);
    expect((await fixture.close()).complete, isTrue);
  });

  test('combined feed preserves approved plan and independently advances state/content clocks', () async {
    final fixture = ConversationFixture();
    final diagnostics = ThreadUsageDiagnostics(
      incompleteCalls: 1,
      missingCalls: 1,
      partialCalls: 0,
      invalidCalls: 0,
      overflowCalls: 0,
      otherPurposeCalls: 0,
      latestCall: null,
      legacyUnknown: true,
      countsOverflowed: false,
    );
    final feed = await fixture.open(
      initial: chatSet(messages: [chatMessage(id: 'item-100')]),
      demand: _demand,
    );
    final state = fixture.stateFeed();
    final session = fixture.session();
    await state.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace(
            revision: 1,
            runtime: _approvedPlanRuntime(
              markdown: '# Plan\n\nOriginal.\n',
              version: 3,
            ).copyWith(usageDiagnostics: diagnostics),
          ),
        ),
      ),
    );
    expect(
      session.state.runtime!.plan!.document!.markdown,
      '# Plan\n\nOriginal.\n',
    );
    expect(session.state.runtime!.usageDiagnostics, same(diagnostics));
    expect(
      session.state.runtime!.copyWith(modelId: 'renamed').usageDiagnostics,
      same(diagnostics),
    );
    await state.deliver(
      ConversationStateEvent(
        frame: ThreadNotificationFrame(
          threadId: 'thread',
          revision: 2,
          baseRevision: 1,
          epoch: 7,
          update: ThreadRuntimeUpdate(
            runtime:
                _approvedPlanRuntime(
                  markdown: '# Revised\n\nKeep exact trailing newline.\n',
                  version: 4,
                ).copyWith(
                  usageDiagnostics: diagnostics,
                  cacheUsage: const CacheUsageView(
                    inputTokens: 20,
                    cacheReadTokens: 10,
                    hitRate: 0.5,
                    sampleCount: 2,
                    legacySampleCountUnknown: true,
                  ),
                ),
            todo: null,
            modelRoute: null,
          ),
        ),
      ),
    );
    expect(session.state.streamEpoch, 7);
    expect(session.state.revision, 2);
    expect(session.state.runtime!.plan!.document!.version, 4);
    expect(session.state.runtime!.usageDiagnostics, same(diagnostics));
    expect(session.state.runtime!.cacheUsage.sampleCount, 2);
    expect(session.state.runtime!.cacheUsage.legacySampleCountUnknown, isTrue);
    expect(
      (fixture.consumers['thread']!.batches.single.entries.single).recordId,
      'item-100',
    );
    await feed.deliver(
      ConversationChatEvent(
        batch: ChatBatch(
          placement: ChatPlacement.append,
          fromSeq: 1,
          throughSeq: 2,
          entries: [chatMessage(id: 'next', seq: 2)],
        ),
      ),
    );
    expect(session.state.revision, 2);
    expect(feed.acknowledgements, [1, 2]);
    expect(state.acknowledgements, [1, 2]);
    await state.deliver(
      ConversationStateEvent(
        frame: ThreadNotificationFrame(
          threadId: 'thread',
          revision: 3,
          baseRevision: 2,
          epoch: 7,
          update: ThreadRuntimeUpdate(
            runtime: _runtimeUsage(2),
            todo: null,
            modelRoute: null,
          ),
        ),
      ),
    );
    expect(session.state.runtime!.plan, isNull);
    await fixture.close();
  });

  test(
    'state continuity failure retains last good facts and refuses ACK',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open(demand: _demand);
      final state = fixture.stateFeed();
      final session = fixture.session();
      await state.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
            schemaVersion: 17,
            completedHistoryVersion: 1,
            workspace: _workspace(revision: 4),
          ),
        ),
      );
      final failed = session.source.waitFor(
        (state) => state.sync.phase == DomainSyncPhase.reconnecting,
      );
      state.send(
        ConversationStateEvent(
          frame: ThreadNotificationFrame(
            threadId: 'thread',
            revision: 6,
            baseRevision: 5,
            epoch: 1,
            update: ThreadRuntimeUpdate(
              runtime: _runtimeUsage(99),
              todo: null,
              modelRoute: null,
            ),
          ),
        ),
      );
      await failed;
      expect(session.state.revision, 4);
      expect(session.state.runtime!.completionTokens, 0);
      expect(feed.acknowledgements, [1]);
      expect(state.acknowledgements, [1]);
      await fixture.close();
    },
  );

  test('resync rebuilds only the state feed; new baseline may have lower state revision', () async {
    final fixture = ConversationFixture();
    final first = await fixture.open(demand: _demand);
    final state = fixture.stateFeed();
    final session = fixture.session();
    await state.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace(revision: 40),
        ),
      ),
    );
    final resync = session.resyncRuntime();
    await fixture.transport.stateOpened(1);
    final second = fixture.stateFeed();
    expect(second, isNot(same(state)));
    await second.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace(revision: 3),
        ),
      ),
    );
    expect((await resync).revision, 3);
    // Only the state baseline is replaced: the original content feed keeps
    // its live owner and continues bounded delivery.
    await state.requestCloseStarted.future;
    await first.deliver(
      ConversationChatEvent(
        batch: ChatBatch(
          placement: ChatPlacement.append,
          fromSeq: 1,
          throughSeq: 2,
          entries: [chatMessage(id: 'item-7', seq: 2)],
        ),
      ),
    );
    expect(
      first.requestCloseCalls,
      0,
      reason: 'state resync must not reopen valid content',
    );
    expect(session.state.revision, 3);
    expect(session.state.streamEpoch, isNull);
    await fixture.close();
  });

  test('snapshot publication cannot complete a resync created synchronously by its listener', () async {
    final fixture = ConversationFixture();
    final first = await fixture.open(demand: _demand);
    final state = fixture.stateFeed();
    final session = fixture.session();
    Future<ThreadWorkspace>? resync;
    var completed = false;
    final observation = session.source.watch((state) {
      if (state.workspace?.revision == 4 && resync == null) {
        resync = session.resyncRuntime();
        unawaited(
          resync!.then<void>(
            (_) => completed = true,
            onError: (_) => completed = true,
          ),
        );
      }
    });
    state.send(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace(revision: 4),
        ),
      ),
    );
    await fixture.transport.stateOpened(1);
    expect(resync, isNotNull);
    expect(
      completed,
      isFalse,
      reason: 'The old snapshot cannot steal the new request',
    );
    final second = fixture.stateFeed();
    await second.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace(revision: 3),
        ),
      ),
    );
    expect((await resync!).revision, 3);
    expect(
      first.requestCloseCalls,
      0,
      reason: 'a state resync never replaces the content owner',
    );
    observation.cancel();
    await fixture.close();
  });

  test('failure publication cannot fail a resync created synchronously by its listener', () async {
    final fixture = ConversationFixture();
    final first = await fixture.open(demand: _demand);
    final state = fixture.stateFeed();
    final session = fixture.session();
    await state.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace(revision: 4),
        ),
      ),
    );
    Future<ThreadWorkspace>? resync;
    var completed = false;
    final observation = session.source.watch((state) {
      if (state.sync.phase == DomainSyncPhase.reconnecting && resync == null) {
        resync = session.resyncRuntime();
        unawaited(
          resync!.then<void>(
            (_) => completed = true,
            onError: (_) => completed = true,
          ),
        );
      }
    });
    state.send(
      ConversationStateEvent(
        frame: ThreadNotificationFrame(
          threadId: 'thread',
          revision: 6,
          baseRevision: 5,
          epoch: 1,
          update: ThreadRuntimeUpdate(
            runtime: _runtimeUsage(99),
            todo: null,
            modelRoute: null,
          ),
        ),
      ),
    );
    await fixture.transport.stateOpened(1);
    expect(resync, isNotNull);
    expect(
      completed,
      isFalse,
      reason: 'The old failure cannot steal the new request',
    );
    final second = fixture.stateFeed();
    const newFailure = StudioFailure(
      code: StudioFailureCode.busy,
      message: 'new attempt failed',
      retryable: true,
      correlationId: 'new-attempt',
    );
    second.send(const ConversationFailureEvent(failure: newFailure));
    await expectLater(resync!, throwsA(same(newFailure)));
    expect(
      first.requestCloseCalls,
      0,
      reason: 'a state failure never retires the content owner',
    );
    observation.cancel();
    await fixture.close();
  });

  test('directory identity rebind does not overwrite runtime facts or reset state watermarks', () async {
    final fixture = ConversationFixture();
    await fixture.open(demand: _demand);
    final state = fixture.stateFeed();
    final session = fixture.session();
    await state.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace(revision: 12),
        ),
      ),
    );
    final snapshotThread = session.state.workspace!.thread;
    final changed = SessionDirectoryRow(
      sessionId: 'thread',
      agentId: 'thread',
      threadId: 'thread',
      workspaceId: 'project',
      title: 'Renamed',
      mode: ThreadModeId.simple,
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      workspacePath: '/tmp/thread',
      updatedAt: DateTime.utc(2026),
    );
    fixture.transport.emitThread(changed, 'thread', revision: 1);
    await Future<void>.delayed(Duration.zero);
    expect(session.state.directoryRow, same(changed));
    expect(session.state.workspace!.thread, same(snapshotThread));
    expect(session.state.revision, 12);
    expect(session.state.hasSnapshot, isTrue);
    await fixture.close();
  });

  test('same Turn terminal fact and latestTurn survive duplicate busy notifications', () async {
    final fixture = ConversationFixture();
    await fixture.open(demand: _demand);
    final state = fixture.stateFeed();
    final session = fixture.session();
    final terminal = StudioTurnView(
      inputId: 'input',
      turnId: 'turn',
      threadId: 'thread',
      revision: 2,
      state: const CompletedStudioTurnState(
        startedAt: 1,
        completedAt: 2,
        completion: StudioTurnCompletion.normal,
      ),
      updatedAt: DateTime.utc(2026),
    );
    await state.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace().copyWith(latestTurn: terminal),
        ),
      ),
    );
    await state.deliver(
      ConversationStateEvent(
        frame: ThreadNotificationFrame(
          threadId: 'thread',
          revision: 2,
          baseRevision: 1,
          epoch: 1,
          update: ThreadTurnUpdate(
            StudioTurnView(
              inputId: 'input',
              turnId: 'turn',
              threadId: 'thread',
              revision: 2,
              state: const RunningStudioTurnState(
                startedAt: 1,
                activity: StudioTurnActivity.thinking,
              ),
              updatedAt: DateTime.utc(2026),
            ),
          ),
        ),
      ),
    );
    expect(session.state.workspace!.latestTurn!.state.isTerminal, isTrue);
    expect(session.state.activeTurn, isNull);
    expect(session.state.revision, 2);
    await fixture.close();
  });

  test('demand retire then re-demand never reuses an old baseline', () async {
    final fixture = ConversationFixture();
    final first = await fixture.open(demand: _demand);
    final session = fixture.session();
    fixture.repository.setVisibleThread(null);
    await first.closeCompleted.future;
    expect(first.closeCalls, 1);
    expect(session.isActive, isFalse);

    fixture.repository.setVisibleThread('thread');
    await fixture.transport.opened(1);
    final second = TestConversationFeed(subscriptionId: 'second');
    fixture.transport.opens[1].result.complete(second);
    final replacement = chatSet(messages: [chatMessage(id: 'replacement')]);
    await second.deliver(ConversationChatEvent(batch: replacement));
    await session.content.ready;
    expect(fixture.consumers['thread']!.batches.last, same(replacement));
    expect(second.acknowledgements, [1]);
    await fixture.close();
  });

  test(
    'content demand belongs to the session, not the thread snapshot',
    () async {
      final fixture = ConversationFixture();
      // 没有 Thread 快照时内容连接同样建立：正文与状态流互相独立。
      final feed = await fixture.open(
        initial: chatSet(messages: [chatMessage(id: 'item-2')]),
        demand: _demand,
      );
      final session = fixture.session();
      await session.content.ready;
      expect(
        (fixture.consumers['thread']!.batches.single.entries.single).recordId,
        'item-2',
      );
      expect(session.state.hasSnapshot, isFalse);
      expect(session.state.workspace, isNull);
      await fixture.close();
      expect(feed.closeCalls, 1);
    },
  );

  test(
    'ChatOpening listener withdrawing demand never opens the feed',
    () async {
      final fixture = ConversationFixture();
      final session = fixture.repository.session('thread');
      fixture.attach('thread', demand: _demand);
      final observation = session.content.state.watch((state) {
        if (state is ChatOpening<bool>) {
          fixture.repository.setVisibleThread(null);
        }
      });
      fixture.repository.setVisibleThread('thread');
      // 同步撤销在调用返回前生效：attempt 已退役，transport 从未打开，
      // 没有 ACK 与任何后继帧；isActive 立即为 false。
      expect(fixture.transport.opens, isEmpty);
      expect(session.isActive, isFalse);
      expect(session.isActive, isFalse);
      await fixture.close();
      observation.cancel();
    },
  );

  test('ChatOpening listener closing the client synchronously never opens the feed', () async {
    final fixture = ConversationFixture();
    final session = fixture.repository.session('thread');
    fixture.attach('thread', demand: _demand);
    final observation = session.content.state.watch((state) {
      if (state is ChatOpening<bool>) {
        unawaited(fixture.client.close());
      }
    });
    fixture.repository.setVisibleThread('thread');
    await fixture.close();
    expect(fixture.transport.opens, isEmpty);
    observation.cancel();
  });

  test('synchronous A to B to A during ChatOpening withdraws old demand and recovers once', () async {
    final fixture = ConversationFixture();
    final session = fixture.repository.session('thread');
    final consumer = TestCompletionConsumer();
    session.content.attachConsumer(consumer, demand: _demand);
    var phase = 0;
    final observation = session.content.state.watch((state) {
      if (state is ChatOpening<bool> && phase == 0) {
        phase = 1;
        fixture.repository.setVisibleThread('other');
        fixture.repository.setVisibleThread('thread');
      }
    });
    fixture.repository.setVisibleThread('thread');
    // 第一个 A attempt 已被同步撤销，transport 从未为它或 B 打开连接；
    // identity 回到 A 后按新 attempt 恢复恰好一次。
    expect(
      fixture.transport.opens.where((open) => open.threadId == 'thread'),
      hasLength(1),
    );
    expect(
      fixture.transport.opens.where((open) => open.threadId == 'other'),
      isEmpty,
    );
    expect(fixture.repository.existingSession('other'), isNull);
    expect(session.isActive, isTrue);
    final feed = TestConversationFeed();
    fixture.transport.opens[0].result.complete(feed);
    await feed.deliver(
      ConversationChatEvent(
        batch: chatSet(messages: [chatMessage(id: 'item-9')]),
      ),
    );
    expect((consumer.batches.single.entries.single).recordId, 'item-9');
    observation.cancel();
    await fixture.close();
  });

  test('synchronous switch to B during the state connecting publication revokes the stale stack', () async {
    final fixture = ConversationFixture();
    final session = fixture.repository.session('thread');
    fixture.attach('thread', demand: _demand);
    var phase = 0;
    final observation = session.source.watch((value) {
      if (phase == 0 && value.sync.phase == DomainSyncPhase.connecting) {
        phase = 1;
        fixture.repository.setVisibleThread('other');
      }
    });
    fixture.repository.setVisibleThread('thread');
    // The state owner already admitted demand when its connecting
    // publication reentered the switch; the stale stack must be revoked
    // instead of resurrecting content demand after the reentrant drain.
    expect(
      session.isActive,
      isFalse,
      reason: 'the reentrant revoke retired the stale state demand',
    );
    expect(
      fixture.transport.opens.where((open) => open.threadId == 'thread'),
      isEmpty,
      reason: 'the stale stack must never open content',
    );
    expect(fixture.repository.existingSession('other'), isNotNull);
    observation.cancel();
    await fixture.close();
  });

  test('closing the client during the state connecting publication seals both owners cleanly', () async {
    final fixture = ConversationFixture();
    final session = fixture.repository.session('thread');
    fixture.attach('thread', demand: _demand);
    Future<CloseReport>? closing;
    final observation = session.source.watch((value) {
      if (value.sync.phase == DomainSyncPhase.connecting) {
        closing = fixture.client.close();
      }
    });
    fixture.repository.setVisibleThread('thread');
    expect(closing, isNotNull, reason: 'the connecting publication ran');
    expect(
      fixture.transport.stateOpens,
      isEmpty,
      reason: 'the sealed state owner never touched the transport',
    );
    expect(
      fixture.transport.opens,
      isEmpty,
      reason: 'the sealed session never demanded content',
    );
    expect((await closing!).complete, isTrue);
    observation.cancel();
    // The original close result stays clean; no retryCleanup is needed.
    expect((await fixture.close()).complete, isTrue);
  });

  test('synchronous A to B to A during the state connecting publication recovers once', () async {
    final fixture = ConversationFixture();
    final session = fixture.repository.session('thread');
    fixture.attach('thread', demand: _demand);
    var phase = 0;
    final observation = session.source.watch((value) {
      if (phase == 0 && value.sync.phase == DomainSyncPhase.connecting) {
        phase = 1;
        fixture.repository.setVisibleThread('other');
        fixture.repository.setVisibleThread('thread');
      }
    });
    fixture.repository.setVisibleThread('thread');
    expect(session.isActive, isTrue);
    expect(
      fixture.transport.opens.where((open) => open.threadId == 'thread'),
      hasLength(1),
      reason: 'only the newest stack owns the recovered content demand',
    );
    expect(
      fixture.transport.stateOpens.where((open) => open.threadId == 'thread'),
      hasLength(1),
      reason:
          'the stale stack retired before opening; the newest stack owns '
          'the single state feed',
    );
    final feed = TestConversationFeed();
    fixture.transport.opens[0].result.complete(feed);
    await feed.deliver(
      ConversationChatEvent(
        batch: chatSet(messages: [chatMessage(id: 'item-11')]),
      ),
    );
    expect(
      (fixture.consumers['thread']!.batches.single.entries.single).recordId,
      'item-11',
    );
    observation.cancel();
    await fixture.close();
  });

  test('synchronous same-target reentry during ChatOpening does not retire or reopen', () async {
    final fixture = ConversationFixture();
    final session = fixture.repository.session('thread');
    final consumer = TestCompletionConsumer();
    session.content.attachConsumer(consumer, demand: _demand);
    var openings = 0;
    final observation = session.content.state.watch((state) {
      if (state is ChatOpening<bool>) {
        openings++;
        fixture.repository.setVisibleThread('thread');
      }
    });
    fixture.repository.setVisibleThread('thread');
    expect(openings, 1, reason: '同目标重入不得引发 retire/reopen 循环');
    expect(fixture.transport.opens, hasLength(1));
    expect(session.isActive, isTrue);
    final feed = TestConversationFeed();
    fixture.transport.opens[0].result.complete(feed);
    await feed.deliver(
      ConversationChatEvent(
        batch: chatSet(messages: [chatMessage(id: 'item-4')]),
      ),
    );
    expect((consumer.batches.single.entries.single).recordId, 'item-4');
    observation.cancel();
    await fixture.close();
  });

  test(
    'latestTurn adoption is revision-strict, left-associated and terminal-safe',
    () async {
      final fixture = ConversationFixture();
      await fixture.open(demand: _demand);
      final state = fixture.stateFeed();
      final session = fixture.session();
      final terminalA = _turnView(
        turnId: 'turn-a',
        revision: 5,
        updatedAt: DateTime.utc(2026, 6),
        state: const CompletedStudioTurnState(
          startedAt: 1,
          completedAt: 2,
          completion: StudioTurnCompletion.normal,
        ),
      );
      await state.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
            schemaVersion: 17,
            completedHistoryVersion: 1,
            workspace: _workspace(latestTurn: terminalA),
          ),
        ),
      );
      expect(session.state.workspace!.latestTurn!.turnId, 'turn-a');

      // equal revision、不同身份：保已采纳，不制造额外顺序。
      await state.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
            schemaVersion: 17,
            completedHistoryVersion: 1,
            workspace: _workspace(
              revision: 2,
              latestTurn: _turnView(turnId: 'turn-b', revision: 5),
            ),
          ),
        ),
      );
      expect(session.state.workspace!.latestTurn!.turnId, 'turn-a');

      // 跨 Turn：payload revision 更高者胜，即使 updatedAt 逆序更旧。
      await state.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
            schemaVersion: 17,
            completedHistoryVersion: 1,
            workspace: _workspace(
              revision: 3,
              latestTurn: _turnView(
                turnId: 'turn-b',
                revision: 7,
                updatedAt: DateTime.utc(2025, 1),
                state: const CompletedStudioTurnState(
                  startedAt: 1,
                  completedAt: 2,
                  completion: StudioTurnCompletion.normal,
                ),
              ),
            ),
          ),
        ),
      );
      expect(session.state.workspace!.latestTurn!.turnId, 'turn-b');
      expect(session.state.workspace!.latestTurn!.revision, 7);

      // 同身份：已采纳终态不被更高 revision 的 busy 候选回退。
      await state.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
            schemaVersion: 17,
            completedHistoryVersion: 1,
            workspace: _workspace(
              revision: 4,
              latestTurn: _turnView(turnId: 'turn-b', revision: 9),
            ),
          ),
        ),
      );
      final guarded = session.state.workspace!.latestTurn!;
      expect(guarded.turnId, 'turn-b');
      expect(guarded.revision, 7);
      expect(guarded.state.isTerminal, isTrue);
      await fixture.close();
    },
  );

  test('left-associated fold lets an active revision outrank an earlier terminal fold', () async {
    final fixture = ConversationFixture();
    await fixture.open(demand: _demand);
    final state = fixture.stateFeed();
    final session = fixture.session();
    final terminalA = _turnView(
      turnId: 'turn-a',
      revision: 5,
      state: const CompletedStudioTurnState(
        startedAt: 1,
        completedAt: 2,
        completion: StudioTurnCompletion.normal,
      ),
    );
    await state.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace(latestTurn: terminalA),
        ),
      ),
    );
    final activeA = _turnView(turnId: 'turn-a', revision: 7);
    await state.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace(
            revision: 2,
            latestTurn: _turnView(turnId: 'turn-b', revision: 6),
            activeTurn: activeA,
          ),
        ),
      ),
    );
    // choose(choose(A5, B6), A7) == A7；右折叠会错误停在 A 的终态 5。
    final folded = session.state.workspace!.latestTurn!;
    expect(folded.turnId, 'turn-a');
    expect(folded.revision, 7);
    expect(folded.state.isTerminal, isFalse);
    // active 身份直接来自权威 snapshot，不凭比较另造。
    expect(session.state.workspace!.activeTurn!.revision, 7);
    await fixture.close();
  });

  test('a new attempt baseline may lower the state watermark while payload folding stays independent', () async {
    final fixture = ConversationFixture();
    final first = await fixture.open(demand: _demand);
    final session = fixture.session();
    final state = fixture.stateFeed();
    await state.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace(
            revision: 10,
            latestTurn: _turnView(
              turnId: 'turn-c',
              revision: 8,
              state: const CompletedStudioTurnState(
                startedAt: 1,
                completedAt: 2,
                completion: StudioTurnCompletion.normal,
              ),
            ),
          ),
        ),
      ),
    );
    expect(session.state.revision, 10);
    expect(session.state.workspace!.latestTurn!.revision, 8);

    fixture.repository.setVisibleThread(null);
    await first.closeCompleted.future;
    fixture.repository.setVisibleThread('thread');
    await fixture.transport.stateOpened(1);
    await fixture.transport.opened(1);
    final second = TestConversationFeed();
    fixture.transport.opens[1].result.complete(second);
    await fixture.stateFeed().deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace(
            revision: 3,
            latestTurn: _turnView(
              turnId: 'turn-c',
              revision: 2,
              state: const CompletedStudioTurnState(
                startedAt: 1,
                completedAt: 2,
                completion: StudioTurnCompletion.normal,
              ),
            ),
          ),
        ),
      ),
    );
    expect(session.state.revision, 3, reason: '新订阅代次允许状态水位回退');
    expect(
      session.state.workspace!.latestTurn!.revision,
      8,
      reason: 'payload 折叠按自身 revision，独立于状态水位',
    );
    await fixture.close();
  });

  test(
    'blocked content admission and ACK never block state notifications',
    () async {
      final fixture = ConversationFixture();
      final consumer = ControlledBatchConsumer();
      final gate = Completer<void>();
      consumer.onApply = (_) => gate.future;
      fixture.session().content.attachConsumer(consumer, demand: _demand);
      fixture.repository.setVisibleThread('thread');
      await fixture.transport.opened(0);
      final feed = TestConversationFeed();
      fixture.transport.opens[0].result.complete(feed);
      final state = fixture.stateFeed();
      await state.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
            schemaVersion: 17,
            completedHistoryVersion: 1,
            workspace: _workspace(revision: 1),
          ),
        ),
      );
      // The unaccepted Chat holds the sole content credit and its ACK.
      feed.send(ConversationChatEvent(batch: chatSet()));
      await consumer.waitForCount(1);
      expect(feed.acknowledgements, isEmpty);
      await state.deliver(
        ConversationStateEvent(
          frame: ThreadNotificationFrame(
            threadId: 'thread',
            revision: 2,
            baseRevision: 1,
            epoch: 1,
            update: ThreadRuntimeUpdate(
              runtime: _runtimeUsage(5),
              todo: null,
              modelRoute: null,
            ),
          ),
        ),
      );
      expect(
        fixture.session().state.revision,
        2,
        reason: 'state progresses while content admission is blocked',
      );
      expect(fixture.session().state.runtime!.completionTokens, 5);
      expect(
        feed.acknowledgements,
        isEmpty,
        reason: 'the blocked Chat still owns the content credit',
      );
      gate.complete();
      await feed.acknowledged(1);
      await fixture.close();
    },
  );

  test(
    'an independent state stream break swaps only the state baseline',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open(demand: _demand);
      final state = fixture.stateFeed();
      final session = fixture.session();
      await state.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
            schemaVersion: 17,
            completedHistoryVersion: 1,
            workspace: _workspace(revision: 4),
          ),
        ),
      );
      const failure = StudioFailure(
        code: StudioFailureCode.busy,
        message: 'state stream broke',
        retryable: true,
        correlationId: 'state-break',
      );
      state.send(const ConversationFailureEvent(failure: failure));
      await state.closeCompleted.future;
      expect(session.state.sync.phase, DomainSyncPhase.reconnecting);
      expect(
        feed.requestCloseCalls,
        0,
        reason: 'a state break never retires valid content',
      );
      // The bounded retry rebuilds the state feed alone; the content feed and
      // its accepted Set are untouched.
      await fixture.transport.stateOpened(1);
      final replacement = fixture.stateFeed();
      await replacement.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
            schemaVersion: 17,
            completedHistoryVersion: 1,
            workspace: _workspace(revision: 2),
          ),
        ),
      );
      expect(session.state.revision, 2, reason: '新订阅代次允许状态水位回退');
      expect(session.state.sync.phase, DomainSyncPhase.ready);
      expect(feed.requestCloseCalls, 0);
      expect(
        fixture.transport.opens,
        hasLength(1),
        reason: 'only the state feed was reopened',
      );
      expect(fixture.consumers['thread']!.batches, hasLength(1));
      await fixture.close();
    },
  );

  test(
    'a late state open is closed by its original owner, never detached',
    () async {
      final fixture = ConversationFixture();
      fixture.transport.stateFeedFactory = null;
      final consumer = TestCompletionConsumer();
      fixture.session().content.attachConsumer(consumer, demand: _demand);
      fixture.repository.setVisibleThread('thread');
      await fixture.transport.stateOpened(0);
      await fixture.transport.opened(0);
      // Withdraw the demand before the pending state open completes.
      fixture.repository.setVisibleThread(null);
      final late = TestConversationStateFeed();
      fixture.transport.stateOpens.single.result.complete(late);
      await late.closeCompleted.future;
      expect(late.requestCloseCalls, greaterThan(0));
      expect(
        late.closeCalls,
        1,
        reason: 'the retired owner collects the late feed',
      );
      final feed = TestConversationFeed();
      fixture.transport.opens[0].result.complete(feed);
      await feed.closeCompleted.future;
      expect(fixture.transport.stateOpens, hasLength(1));
      expect(fixture.transport.opens, hasLength(1));
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test(
    'page hide and session close retire both feed owners without leftovers',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open(demand: _demand);
      final state = fixture.stateFeed();
      final session = fixture.session();
      await state.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
            schemaVersion: 17,
            completedHistoryVersion: 1,
            workspace: _workspace(revision: 3),
          ),
        ),
      );
      fixture.repository.setVisibleThread(null);
      await feed.closeCompleted.future;
      await state.closeCompleted.future;
      expect(session.isActive, isFalse);
      expect(feed.closeCalls, 1);
      expect(state.closeCalls, 1);
      final report = await fixture.close();
      expect(report.complete, isTrue);
      expect(report.unresolved, isEmpty);
    },
  );

  test('the retired agent role has one trimmed judgement', () {
    expect(isRetiredAgentRole('planner'), isTrue);
    expect(isRetiredAgentRole(' planner '), isTrue);
    expect(isRetiredAgentRole('executor'), isFalse);
    expect(isRetiredAgentRole(''), isFalse);
    StudioThread agent({
      String role = 'planner',
      String? parentThreadId = 'root',
    }) => StudioThread(
      id: 'member',
      workspaceId: 'project',
      title: 'Member',
      mode: ThreadModeId.simple,
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      parentThreadId: parentThreadId,
      rootThreadId: 'root',
      agentPath: 'root/member',
      role: role,
      updatedAt: DateTime.utc(2026),
      workspacePath: '/tmp/member',
    );
    // The role judgement is shared; the caller still owns the membership context.
    expect(agent().isRetiredAgent, isTrue);
    expect(agent(role: ' planner ').isRetiredAgent, isTrue);
    expect(agent(role: 'executor').isRetiredAgent, isFalse);
    expect(agent(parentThreadId: null).isRetiredAgent, isFalse);
  });
}
