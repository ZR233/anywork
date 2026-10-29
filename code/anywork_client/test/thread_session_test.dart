import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

ThreadWorkspace _workspace({
  int revision = 1,
  ThreadRuntimeView? runtime,
  StudioTurnView? latestTurn,
  StudioTurnView? activeTurn,
}) {
  final thread = StudioThread(
    id: 'thread',
    projectId: 'project',
    title: 'Thread',
    mode: ThreadModeId.simple,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    updatedAt: DateTime.utc(2026),
    workspacePath: '/tmp/thread',
  );
  return ThreadWorkspace(
    thread: thread,
    revision: revision,
    interactions: const [],
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
    final feed = await fixture.open(initial: baseline(100));
    final session = fixture.session();
    await feed.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
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
    await feed.deliver(
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
      (session.content.lastDeliveredFrame as ConversationBaselineFrame)
          .baseline
          .version,
      100,
    );
    await feed.deliver(ConversationUpdateEvent(update: patch(100, 101)));
    expect(session.state.revision, 2);
    expect(feed.acknowledgements, [1, 2, 3, 4]);
    await feed.deliver(
      ConversationStateEvent(
        frame: ThreadNotificationFrame(
          threadId: 'thread',
          revision: 3,
          baseRevision: 2,
          epoch: 7,
          update: ThreadRuntimeUpdate(runtime: _runtimeUsage(2), todo: null),
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
      final feed = await fixture.open();
      final session = fixture.session();
      await feed.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(workspace: _workspace(revision: 4)),
        ),
      );
      final failed = session.source.waitFor(
        (state) => state.sync.phase == DomainSyncPhase.reconnecting,
      );
      feed.send(
        ConversationStateEvent(
          frame: ThreadNotificationFrame(
            threadId: 'thread',
            revision: 6,
            baseRevision: 5,
            epoch: 1,
            update: ThreadRuntimeUpdate(runtime: _runtimeUsage(99), todo: null),
          ),
        ),
      );
      await failed;
      expect(session.state.revision, 4);
      expect(session.state.runtime!.completionTokens, 0);
      expect(feed.acknowledgements, [1, 2]);
      await fixture.close();
    },
  );

  test('resync replaces the actual combined feed; new baseline may have lower state revision', () async {
    final fixture = ConversationFixture();
    final first = await fixture.open();
    final session = fixture.session();
    await first.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(workspace: _workspace(revision: 40)),
      ),
    );
    final resync = session.resyncRuntime();
    await fixture.transport.opened(1);
    final second = TestConversationFeed(subscriptionId: 'second');
    fixture.transport.opens[1].result.complete(second);
    await second.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(workspace: _workspace(revision: 3)),
      ),
    );
    expect((await resync).revision, 3);
    await second.deliver(
      ConversationBaselineEvent(
        baseline: baseline(7, subscriptionId: 'second'),
      ),
    );
    await first.closeCompleted.future;
    expect(first.requestCloseCalls, greaterThan(0));
    expect(session.state.revision, 3);
    expect(session.state.streamEpoch, isNull);
    await fixture.close();
  });

  test('snapshot publication cannot complete a resync created synchronously by its listener', () async {
    final fixture = ConversationFixture();
    final first = await fixture.open();
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
    first.send(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(workspace: _workspace(revision: 4)),
      ),
    );
    await fixture.transport.opened(1);
    expect(resync, isNotNull);
    expect(
      completed,
      isFalse,
      reason: 'The old snapshot cannot steal the new request',
    );
    final second = TestConversationFeed(subscriptionId: 'snapshot-resync');
    fixture.transport.opens[1].result.complete(second);
    await second.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(workspace: _workspace(revision: 3)),
      ),
    );
    expect((await resync!).revision, 3);
    await second.deliver(
      ConversationBaselineEvent(
        baseline: baseline(7, subscriptionId: 'snapshot-resync'),
      ),
    );
    observation.cancel();
    await fixture.close();
  });

  test('failure publication cannot fail a resync created synchronously by its listener', () async {
    final fixture = ConversationFixture();
    final first = await fixture.open();
    final session = fixture.session();
    await first.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(workspace: _workspace(revision: 4)),
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
    first.send(
      ConversationStateEvent(
        frame: ThreadNotificationFrame(
          threadId: 'thread',
          revision: 6,
          baseRevision: 5,
          epoch: 1,
          update: ThreadRuntimeUpdate(runtime: _runtimeUsage(99), todo: null),
        ),
      ),
    );
    await fixture.transport.opened(1);
    expect(resync, isNotNull);
    expect(
      completed,
      isFalse,
      reason: 'The old failure cannot steal the new request',
    );
    final second = TestConversationFeed(subscriptionId: 'failure-resync');
    fixture.transport.opens[1].result.complete(second);
    const newFailure = StudioFailure(
      code: StudioFailureCode.busy,
      message: 'new attempt failed',
      retryable: true,
      correlationId: 'new-attempt',
    );
    second.send(const ConversationFailureEvent(failure: newFailure));
    await expectLater(resync!, throwsA(same(newFailure)));
    observation.cancel();
    await fixture.close();
  });

  test('directory identity rebind does not overwrite runtime facts or reset state watermarks', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open();
    final session = fixture.session();
    await feed.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(workspace: _workspace(revision: 12)),
      ),
    );
    final changed = StudioThread(
      id: 'thread',
      projectId: 'project',
      title: 'Renamed',
      workspacePath: '/tmp/thread',
      mode: ThreadModeId.simple,
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      updatedAt: DateTime.utc(2026),
    );
    fixture.client.threadDirectory.applyBaseline(
      ThreadDirectoryPage(threads: [changed], nextCursor: null, revision: 1),
      revision: 1,
    );
    expect(session.state.workspace!.thread, same(changed));
    expect(session.state.revision, 12);
    expect(session.state.hasSnapshot, isTrue);
    await fixture.close();
  });

  test('same Turn terminal fact and latestTurn survive duplicate busy notifications', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open();
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
    await feed.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          workspace: _workspace().copyWith(latestTurn: terminal),
        ),
      ),
    );
    await feed.deliver(
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
    final first = await fixture.open();
    final session = fixture.session();
    fixture.repository.setVisibleThread(null);
    await first.closeCompleted.future;
    expect(first.closeCalls, 1);
    expect(session.content.lastDeliveredFrame, isNull);

    fixture.repository.setVisibleThread('thread');
    await fixture.transport.opened(1);
    final second = TestConversationFeed(subscriptionId: 'second');
    fixture.transport.opens[1].result.complete(second);
    await second.deliver(
      ConversationBaselineEvent(
        baseline: baseline(1, subscriptionId: 'second'),
      ),
    );
    final reopened = await session.content.ready;
    expect(reopened.baseline.subscriptionId, 'second');
    expect(reopened.baseline.version, 1);
    // 新 attempt 的补丁必须从它自己的基线开始。
    await second.deliver(
      ConversationUpdateEvent(update: patch(1, 2, subscriptionId: 'second')),
    );
    final frame = session.content.lastDeliveredFrame as ConversationPatchFrame;
    expect(frame.patch.from, 1);
    await fixture.close();
  });

  test(
    'content demand belongs to the session, not the thread snapshot',
    () async {
      final fixture = ConversationFixture();
      // 没有 Thread 快照时内容连接同样建立：正文与状态流互相独立。
      final feed = await fixture.open(initial: baseline(2));
      final session = fixture.session();
      final ready = await session.content.ready;
      expect(ready.baseline.version, 2);
      expect(session.state.hasSnapshot, isFalse);
      expect(session.state.workspace, isNull);
      await fixture.close();
      expect(feed.closeCalls, 1);
    },
  );

  test(
    'ChatOpening listener withdrawing demand never opens the feed',
    () async {
      final budget = ResourceBudget();
      final fixture = ConversationFixture(budget: budget);
      final session = fixture.repository.session('thread');
      final observation = session.content.state.watch((state) {
        if (state is ChatOpening<ConversationContentFrame>) {
          fixture.repository.setVisibleThread(null);
        }
      });
      fixture.repository.setVisibleThread('thread');
      // 同步撤销在调用返回前生效：attempt 已退役，transport 从未打开，
      // 没有 ACK 与任何后继帧；isActive 立即为 false。
      expect(fixture.transport.opens, isEmpty);
      expect(session.isActive, isFalse);
      expect(session.content.lastDeliveredFrame, isNull);
      await fixture.close();
      expect(budget.usage, isEmpty);
      observation.cancel();
    },
  );

  test('ChatOpening listener closing the client synchronously never opens the feed', () async {
    final budget = ResourceBudget();
    final fixture = ConversationFixture(budget: budget);
    final session = fixture.repository.session('thread');
    final observation = session.content.state.watch((state) {
      if (state is ChatOpening<ConversationContentFrame>) {
        unawaited(fixture.client.close());
      }
    });
    fixture.repository.setVisibleThread('thread');
    await fixture.close();
    expect(fixture.transport.opens, isEmpty);
    expect(budget.usage, isEmpty);
    observation.cancel();
  });

  test('synchronous A to B to A during ChatOpening withdraws old demand and recovers once', () async {
    final budget = ResourceBudget();
    final fixture = ConversationFixture(budget: budget);
    final session = fixture.repository.session('thread');
    var phase = 0;
    final observation = session.content.state.watch((state) {
      if (state is ChatOpening<ConversationContentFrame> && phase == 0) {
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
    await feed.deliver(ConversationBaselineEvent(baseline: baseline(9)));
    expect(
      (session.content.lastDeliveredFrame! as ConversationBaselineFrame)
          .baseline
          .version,
      9,
    );
    observation.cancel();
    await fixture.close();
    expect(budget.usage, isEmpty);
  });

  test('synchronous same-target reentry during ChatOpening does not retire or reopen', () async {
    final fixture = ConversationFixture();
    final session = fixture.repository.session('thread');
    var openings = 0;
    final observation = session.content.state.watch((state) {
      if (state is ChatOpening<ConversationContentFrame>) {
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
    await feed.deliver(ConversationBaselineEvent(baseline: baseline(4)));
    expect(
      (session.content.lastDeliveredFrame! as ConversationBaselineFrame)
          .baseline
          .version,
      4,
    );
    observation.cancel();
    await fixture.close();
  });

  test(
    'latestTurn adoption is revision-strict, left-associated and terminal-safe',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open();
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
      await feed.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
            workspace: _workspace(latestTurn: terminalA),
          ),
        ),
      );
      expect(session.state.workspace!.latestTurn!.turnId, 'turn-a');

      // equal revision、不同身份：保已采纳，不制造额外顺序。
      await feed.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
            workspace: _workspace(
              revision: 2,
              latestTurn: _turnView(turnId: 'turn-b', revision: 5),
            ),
          ),
        ),
      );
      expect(session.state.workspace!.latestTurn!.turnId, 'turn-a');

      // 跨 Turn：payload revision 更高者胜，即使 updatedAt 逆序更旧。
      await feed.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
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
      await feed.deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
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
    final feed = await fixture.open();
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
    await feed.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          workspace: _workspace(latestTurn: terminalA),
        ),
      ),
    );
    final activeA = _turnView(turnId: 'turn-a', revision: 7);
    await feed.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
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
    final first = await fixture.open();
    final session = fixture.session();
    await first.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
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
    await fixture.transport.opened(1);
    final second = TestConversationFeed();
    fixture.transport.opens[1].result.complete(second);
    await second.deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
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
      projectId: 'project',
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
