import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

final class _FakeTransport implements StudioTransport {
  final StreamController<ThreadStreamFrame> frames =
      StreamController<ThreadStreamFrame>.broadcast();
  final List<Completer<StudioTimelineConnection>> pendingOpens = [];
  int subscriptions = 0;

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) {
    subscriptions++;
    return frames.stream;
  }

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) {
    final completer = Completer<StudioTimelineConnection>();
    pendingOpens.add(completer);
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused fake transport capability: ${invocation.memberName}',
  );

  Future<void> close() => frames.close();
}

/// Supplies Thread frames per binding; reduction and reconnection stay in the
/// actual StudioThreadSession. Timers are released separately by the test.
final class _RuntimeRetryTransport implements StudioTransport {
  final List<StreamController<ThreadStreamFrame>> sources = [];
  final List<Completer<StudioTimelineConnection>> pendingOpens = [];
  int opened = 0;

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) {
    final controller = StreamController<ThreadStreamFrame>(sync: true);
    sources.add(controller);
    return controller.stream;
  }

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) {
    final connection = TestTimelineConnection(
      initial: baseline(1, subscriptionId: 'sub-${++opened}'),
    );
    final pending = Completer<StudioTimelineConnection>()..complete(connection);
    pendingOpens.add(pending);
    return pending.future;
  }

  Future<void> close() async {
    await Future.wait([for (final source in sources) source.close()]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused retry transport capability: ${invocation.memberName}',
  );
}

/// Controls production retry timers without a dependency or wall-clock sleeps.
final class _RetryTimers {
  final List<_RetryTimer> _pending = [];
  Completer<_RetryTimer>? _scheduled;

  ZoneSpecification get specification => ZoneSpecification(
    createTimer: (self, parent, zone, delay, callback) {
      final timer = _RetryTimer(() => zone.runGuarded(callback));
      final scheduled = _scheduled;
      if (scheduled == null) {
        _pending.add(timer);
      } else {
        _scheduled = null;
        scheduled.complete(timer);
      }
      return timer;
    },
  );

  bool get hasPending => _pending.any((timer) => timer.isActive);

  Future<void> fireNext() async {
    final timer = _pending.isNotEmpty
        ? _pending.removeAt(0)
        : await (_scheduled ??= Completer<_RetryTimer>()).future;
    expect(timer.isActive, isTrue);
    timer.fire();
  }
}

final class _RetryTimer implements Timer {
  _RetryTimer(this._callback);
  final void Function() _callback;

  @override
  bool isActive = true;
  @override
  int tick = 0;

  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    _callback();
  }

  @override
  void cancel() => isActive = false;
}

ThreadWorkspace _workspace({int revision = 1, ThreadRuntimeView? runtime}) {
  final thread = StudioThread(
    id: 'thread',
    projectId: 'project',
    title: 'Thread',
    mode: ThreadModeId.simple,
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

StudioThreadSession _session(_FakeTransport transport) => StudioThreadSession(
  'thread',
  transport: transport,
  directory: ThreadDirectoryStore(),
  budget: ResourceBudget(),
);

Future<void> _deliverSnapshot(
  StudioThreadSession session,
  _FakeTransport transport,
) async {
  session.start();
  final established = session.source.waitFor((value) => value.hasSnapshot);
  transport.frames.add(ThreadSnapshotFrame(workspace: _workspace()));
  await established;
}

Future<StudioTimelineBaselineFrame> _deliverContent(
  _FakeTransport transport,
  StudioThreadSession session, {
  int version = 1,
  String subscriptionId = 'sub',
}) async {
  final connection = TestTimelineConnection(
    initial: baseline(version, subscriptionId: subscriptionId),
  );
  transport.pendingOpens.last.complete(connection);
  return session.timeline.ready;
}

void main() {
  test('runtime snapshot and updates expose approved plan markdown', () async {
    final transport = _FakeTransport();
    final session = _session(transport);
    addTearDown(() async {
      for (final open in transport.pendingOpens) {
        if (!open.isCompleted) {
          open.complete(TestTimelineConnection(initial: baseline(1)));
        }
      }
      await session.close();
      await transport.close();
    });
    session.start();
    final established = session.source.waitFor((value) => value.hasSnapshot);
    transport.frames.add(
      ThreadSnapshotFrame(
        workspace: _workspace(
          runtime: _approvedPlanRuntime(
            markdown: '# Approved plan\n\nKeep the current document.',
            version: 3,
          ),
        ),
      ),
    );
    await established;
    expect(session.state.runtime!.plan, isNotNull);
    expect(session.state.runtime!.plan!.state, PlanRuntimePhase.approved);
    expect(session.state.runtime!.plan!.document!.version, 3);
    expect(
      session.state.runtime!.plan!.document!.markdown,
      '# Approved plan\n\nKeep the current document.',
    );

    transport.frames.add(
      ThreadNotificationFrame(
        threadId: 'thread',
        epoch: 1,
        baseRevision: 1,
        revision: 2,
        update: ThreadRuntimeUpdate(
          runtime: _approvedPlanRuntime(
            markdown: '# Revised approved plan\n\nUse the replacement body.',
            version: 4,
            contentHash: 'hash-v4',
          ),
          todo: null,
        ),
      ),
    );
    await session.source.waitFor(
      (value) => value.runtime?.plan?.document?.version == 4,
    );
    expect(
      session.state.runtime!.plan!.document!.markdown,
      '# Revised approved plan\n\nUse the replacement body.',
    );

    transport.frames.add(
      ThreadNotificationFrame(
        threadId: 'thread',
        epoch: 1,
        baseRevision: 2,
        revision: 3,
        update: ThreadRuntimeUpdate(runtime: _runtimeUsage(1), todo: null),
      ),
    );
    await session.source.waitFor((value) => value.runtime?.plan == null);
    expect(session.state.runtime!.plan, isNull);
  });

  test(
    'content capacity recovery keeps runtime synchronization independent',
    () async {
      final transport = _FakeTransport();
      final budget = ResourceBudget(
        capacities: {
          ResourceKind.chatHandle: 1,
          ResourceKind.observer: 4,
          ResourceKind.pendingOperation: 4,
        },
      );
      final retiring = budget.acquire(
        ResourceKind.chatHandle,
        owner: 'old-view',
      );
      final session = StudioThreadSession(
        'thread',
        transport: transport,
        directory: ThreadDirectoryStore(),
        budget: budget,
      );
      addTearDown(() async {
        retiring.release();
        for (final open in transport.pendingOpens) {
          if (!open.isCompleted) {
            open.complete(TestTimelineConnection(initial: baseline(1)));
          }
        }
        await session.close();
        await transport.close();
      });
      await _deliverSnapshot(session, transport);
      expect(
        session.timeline.state.value,
        isA<ChatFailed<StudioTimelineFrame>>(),
      );
      expect(session.state.sync.phase, DomainSyncPhase.ready);
      expect(session.state.sync.errorMessage, isNull);

      retiring.release();
      final connection = TestTimelineConnection(initial: baseline(1));
      transport.pendingOpens.single.complete(connection);
      await session.timeline.ready;
      expect(session.state.sync.phase, DomainSyncPhase.ready);
      expect(session.state.sync.errorMessage, isNull);

      // 内容进度也不能清除真实的 Thread 状态失败。
      session.markResync(StateError('runtime offline'), failed: true);
      await connection.nextStarted.future;
      connection.emit(patch(1, 2));
      await session.timeline.state.waitFor(
        (state) => state.snapshot is StudioTimelinePatchFrame,
      );
      expect(session.state.sync.phase, DomainSyncPhase.failed);
      expect(session.state.sync.errorMessage, contains('runtime offline'));
    },
  );

  test(
    'runtime progress renews retries and eventually observes terminal usage',
    () async {
      final timers = _RetryTimers();
      await runZoned(() async {
        final transport = _RuntimeRetryTransport();
        final session = StudioThreadSession(
          'thread',
          transport: transport,
          directory: ThreadDirectoryStore(),
          budget: ResourceBudget(),
        );
        addTearDown(() async {
          await session.close();
          await transport.close();
        });
        session.start();
        await session.timeline.ready;
        // More outages than the consecutive-failure limit, with actual owner
        // notification progress between them. A successful baseline alone is
        // not sufficient progress; the snapshot-only cases retain that limit.
        for (var cycle = 0; cycle < 5; cycle++) {
          final baselineRevision = 100 * (cycle + 1);
          transport.sources.last.add(
            ThreadSnapshotFrame(
              workspace: _workspace(revision: baselineRevision),
            ),
          );
          transport.sources.last.add(
            ThreadNotificationFrame(
              threadId: 'thread',
              epoch: 1,
              baseRevision: baselineRevision,
              revision: baselineRevision + 1,
              update: ThreadRuntimeUpdate(
                runtime: _runtimeUsage(cycle + 1),
                todo: null,
              ),
            ),
          );
          expect(session.state.runtime!.completionTokens, cycle + 1);
          transport.sources.last.add(
            const ThreadResyncRequiredFrame(
              threadId: 'thread',
              dropped: 512,
              epoch: 2,
            ),
          );
          expect(
            session.state.sync.phase,
            DomainSyncPhase.reconnecting,
            reason: 'an outage after real progress is a new recovery episode',
          );
          expect(
            session.state.sync.errorMessage,
            allOf(contains('Thread state lagged'), contains('dropped=512')),
          );
          await timers.fireNext();
          expect(transport.sources, hasLength(cycle + 2));
        }

        transport.sources.last.add(
          ThreadSnapshotFrame(workspace: _workspace(revision: 1000)),
        );
        final terminal = StudioTurnView(
          inputId: 'input',
          turnId: 'turn',
          threadId: 'thread',
          revision: 20000,
          state: const CompletedStudioTurnState(
            startedAt: 1,
            completedAt: 2,
            completion: StudioTurnCompletion.normal,
          ),
          updatedAt: DateTime.utc(2026),
        );
        transport.sources.last.add(
          ThreadNotificationFrame(
            threadId: 'thread',
            epoch: 1,
            baseRevision: 1000,
            revision: 1001,
            update: ThreadTurnUpdate(terminal),
          ),
        );
        transport.sources.last.add(
          ThreadNotificationFrame(
            threadId: 'thread',
            epoch: 1,
            baseRevision: 1001,
            revision: 1002,
            update: ThreadRuntimeUpdate(
              runtime: _runtimeUsage(20000),
              todo: null,
            ),
          ),
        );
        expect(session.state.sync.phase, DomainSyncPhase.ready);
        expect(session.state.workspace!.lastTurn, terminal);
        expect(session.state.activeTurn, isNull);
        expect(session.state.runtime!.completionTokens, 20000);
        // 正文帧不反写 Thread 状态：状态 revision 只由状态流推进。
        expect(session.state.revision, 1002);
      }, zoneSpecification: timers.specification);
    },
  );

  for (final eof in [false, true]) {
    test(
      'snapshot-only ${eof ? 'EOF' : 'lagged'} retries remain bounded',
      () async {
        final timers = _RetryTimers();
        await runZoned(() async {
          final transport = _RuntimeRetryTransport();
          final session = StudioThreadSession(
            'thread',
            transport: transport,
            directory: ThreadDirectoryStore(),
            budget: ResourceBudget(),
          );
          addTearDown(() async {
            await session.close();
            await transport.close();
          });
          session.start();
          final retries = const RetryPolicy().delays.length;
          for (var attempt = 0; attempt <= retries; attempt++) {
            final source = transport.sources.last;
            source.add(
              ThreadSnapshotFrame(
                workspace: _workspace(revision: 10 + attempt),
              ),
            );
            if (attempt == 0) await session.timeline.ready;
            if (eof) {
              await source.close();
            } else {
              source.add(
                const ThreadResyncRequiredFrame(
                  threadId: 'thread',
                  dropped: 512,
                  epoch: 2,
                ),
              );
            }
            if (attempt < retries) {
              expect(session.state.sync.phase, DomainSyncPhase.reconnecting);
              await timers.fireNext();
            } else {
              expect(session.state.sync.phase, DomainSyncPhase.failed);
              expect(timers.hasPending, isFalse);
            }
          }
          expect(transport.sources, hasLength(retries + 1));
        }, zoneSpecification: timers.specification);
      },
    );
  }

  test('a genuine runtime base gap keeps the last valid owner facts', () async {
    final timers = _RetryTimers();
    await runZoned(() async {
      final transport = _RuntimeRetryTransport();
      final session = StudioThreadSession(
        'thread',
        transport: transport,
        directory: ThreadDirectoryStore(),
        budget: ResourceBudget(),
      );
      addTearDown(() async {
        await session.close();
        await transport.close();
      });
      session.start();
      await session.timeline.ready;
      transport.sources.single.add(
        ThreadSnapshotFrame(workspace: _workspace(revision: 10)),
      );
      transport.sources.single.add(
        ThreadNotificationFrame(
          threadId: 'thread',
          epoch: 1,
          baseRevision: 10,
          revision: 11,
          update: ThreadRuntimeUpdate(runtime: _runtimeUsage(7), todo: null),
        ),
      );
      transport.sources.single.add(
        ThreadNotificationFrame(
          threadId: 'thread',
          epoch: 1,
          baseRevision: 12,
          revision: 13,
          update: ThreadRuntimeUpdate(runtime: _runtimeUsage(99), todo: null),
        ),
      );
      expect(session.state.sync.phase, DomainSyncPhase.reconnecting);
      expect(
        session.state.sync.errorMessage,
        allOf(
          contains('Thread state continuity gap'),
          contains('expected epoch=1, revision=11'),
          contains('received epoch=1, baseRevision=12, revision=13'),
        ),
      );
      expect(session.state.revision, 11);
      expect(session.state.runtime!.completionTokens, 7);
      await timers.fireNext();
      expect(transport.sources, hasLength(2));
    }, zoneSpecification: timers.specification);
  });

  test(
    'actual Client keeps the same draft and owned timeline across Settings',
    () async {
      final transport = _FakeTransport();
      final client = AnyworkClient(transport: transport, clientId: 'client');
      client.startDraft.updateDraft('project', 'draft before Settings');
      final draftOwner = client.startDraft;
      final draft = draftOwner.state;
      client.workspace.openNewSession(projectId: 'project');
      client.workspace.showSettings();
      client.workspace.hideSettings();
      client.workspace.showSettings();
      client.workspace.hideSettings();
      expect(identical(client.startDraft, draftOwner), isTrue);
      expect(identical(client.startDraft.state, draft), isTrue);
      expect(
        client.startDraft.state.forProject('project').text,
        'draft before Settings',
      );

      client.threadDirectory.applyBaseline(
        ThreadDirectoryPage(threads: [_workspace().thread], revision: 1),
        revision: 1,
      );
      client.workspace.selectThread('thread', projectId: 'project');
      final session = client.session('thread');
      await _deliverSnapshot(session, transport);
      await _deliverContent(transport, session, version: 3);
      client.workspace.showSettings();
      client.workspace.hideSettings();
      expect(identical(client.session('thread'), session), isTrue);
      expect(
        (session.timeline.lastDeliveredFrame! as StudioTimelineBaselineFrame)
            .baseline
            .version,
        3,
      );
      expect(transport.pendingOpens, hasLength(1));
      expect(session.isActive, isTrue);
      await client.close();
      await transport.close();
    },
  );

  test(
    'actual Clients never share same-id session, timeline or draft ownership',
    () async {
      final leftTransport = _FakeTransport();
      final rightTransport = _FakeTransport();
      final left = AnyworkClient(transport: leftTransport, clientId: 'left');
      final right = AnyworkClient(transport: rightTransport, clientId: 'right');
      final leftSession = left.session('thread');
      final rightSession = right.session('thread');
      await _deliverSnapshot(leftSession, leftTransport);
      await _deliverSnapshot(rightSession, rightTransport);
      await _deliverContent(leftTransport, leftSession, version: 1);
      await _deliverContent(rightTransport, rightSession, version: 6);
      left.startDraft.updateDraft('project', 'left draft');
      expect(right.startDraft.state.forProject('project').text, isEmpty);
      expect(identical(leftSession, rightSession), isFalse);
      expect(
        (leftSession.timeline.lastDeliveredFrame!
                as StudioTimelineBaselineFrame)
            .baseline
            .version,
        1,
      );
      expect(
        (rightSession.timeline.lastDeliveredFrame!
                as StudioTimelineBaselineFrame)
            .baseline
            .version,
        6,
      );
      await left.close();
      expect(leftSession.isActive, isFalse);
      expect(rightSession.isActive, isTrue);
      await right.close();
      await leftTransport.close();
      await rightTransport.close();
    },
  );

  test(
    'late open and first baseline failure close their own connection',
    () async {
      final transport = _FakeTransport();
      final session = _session(transport);
      await _deliverSnapshot(session, transport);
      final lateOpen = transport.pendingOpens.single;
      final retired = await session.retire(deadline: DateTime.utc(2000));
      expect(retired.unresolved, isNotEmpty);
      final late = TestTimelineConnection(initial: baseline(99));
      lateOpen.complete(late);
      await late.closeCompleted.future;
      expect(late.initialCalls, 0);
      expect(session.timeline.lastDeliveredFrame, isNull);

      session.start();
      final failed = TestTimelineConnection();
      transport.pendingOpens.last.complete(failed);
      await failed.initialStarted.future;
      failed.initialResult.completeError(StateError('initial failed'));
      await failed.closeCompleted.future;
      expect(session.timeline.lastDeliveredFrame, isNull);
      // 内容首帧失败不污染 Thread 状态同步：两路事实各自报告。
      expect(session.state.sync.phase, DomainSyncPhase.ready);
      // 首帧失败先进入有界重连（默认重试策略），仍然只影响内容连接。
      expect(
        session.timeline.state.value,
        isA<ChatReconnecting<StudioTimelineFrame>>(),
      );
      await session.close();
      await transport.close();
    },
  );

  test('retire then start A to B to A never reuses an old baseline', () async {
    final transport = _FakeTransport();
    final session = _session(transport);
    await _deliverSnapshot(session, transport);
    final first = TestTimelineConnection(
      initial: baseline(5, subscriptionId: 'first'),
    );
    transport.pendingOpens.single.complete(first);
    await session.timeline.ready;
    await session.retire();
    expect(first.closeCalls, 1);
    expect(session.timeline.lastDeliveredFrame, isNull);

    session.start();
    final second = TestTimelineConnection(
      initial: baseline(1, subscriptionId: 'second'),
    );
    transport.pendingOpens.last.complete(second);
    final reopened = await session.timeline.ready;
    expect(reopened.baseline.subscriptionId, 'second');
    expect(reopened.baseline.version, 1);
    // 新 attempt 的补丁必须从它自己的基线开始。
    await second.nextStarted.future;
    second.emit(patch(1, 2, subscriptionId: 'second'));
    final delivered = await session.timeline.state.waitFor(
      (state) => state.snapshot is StudioTimelinePatchFrame,
    );
    expect((delivered.snapshot! as StudioTimelinePatchFrame).patch.from, 1);
    await session.close();
    await transport.close();
  });

  test(
    'content demand belongs to the session, not the thread snapshot',
    () async {
      final transport = _FakeTransport();
      final session = _session(transport);
      // 没有 Thread 快照时内容连接同样建立：正文与状态流互相独立。
      session.start();
      expect(transport.pendingOpens, hasLength(1));
      final connection = TestTimelineConnection(initial: baseline(2));
      transport.pendingOpens.single.complete(connection);
      final ready = await session.timeline.ready;
      expect(ready.baseline.version, 2);
      expect(session.state.hasSnapshot, isFalse);
      expect(session.state.sync.phase, DomainSyncPhase.idle);
      await session.close();
      expect(connection.closeCalls, 1);
      await transport.close();
    },
  );
}
