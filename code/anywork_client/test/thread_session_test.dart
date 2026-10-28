import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

ThreadWorkspace _workspace({int revision = 1, ThreadRuntimeView? runtime}) {
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
            ),
          ),
        ),
      ),
    );
    expect(
      session.state.runtime!.plan!.document!.markdown,
      '# Plan\n\nOriginal.\n',
    );
    await feed.deliver(
      ConversationStateEvent(
        frame: ThreadNotificationFrame(
          threadId: 'thread',
          revision: 2,
          baseRevision: 1,
          epoch: 7,
          update: ThreadRuntimeUpdate(
            runtime: _approvedPlanRuntime(
              markdown: '# Revised\n\nKeep exact trailing newline.\n',
              version: 4,
            ),
            todo: null,
          ),
        ),
      ),
    );
    expect(session.state.streamEpoch, 7);
    expect(session.state.revision, 2);
    expect(session.state.runtime!.plan!.document!.version, 4);
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
}
