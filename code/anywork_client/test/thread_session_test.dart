import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

final class _FakeTransport implements StudioTransport, ChatWindowReader {
  final StreamController<ThreadStreamFrame> frames =
      StreamController<ThreadStreamFrame>.broadcast();
  final List<Completer<StudioChatWindow>> pendingOpens = [];
  int subscriptions = 0;

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) {
    subscriptions++;
    return frames.stream;
  }

  @override
  Future<StudioChatWindow> openChatWindow(String threadId) {
    final completer = Completer<StudioChatWindow>();
    pendingOpens.add(completer);
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused fake transport capability: ${invocation.memberName}',
  );

  Future<void> close() => frames.close();
}

final class _FakeWindow implements StudioChatWindow {
  _FakeWindow({required this.initialSnapshot, this.failInitial});

  final StudioChatSnapshot initialSnapshot;
  final Object? failInitial;
  final List<Completer<StudioChatFrame?>> _nextReads = [];
  final Completer<StudioChatReceipt> loadResult = Completer();
  final focusEntered = Completer<void>();
  final List<String?> focusRequests = [];
  final Completer<void> closeCompleted = Completer();
  int nextCalls = 0;
  int closeCalls = 0;
  int requestCloseCalls = 0;
  bool closed = false;

  @override
  Future<StudioChatSnapshot> initial() async {
    if (failInitial case final error?) throw error;
    return initialSnapshot;
  }

  @override
  Future<StudioChatFrame?> next() {
    if (closed) return Future.value(null);
    if (_nextReads.isNotEmpty) throw StateError('Two pending next calls');
    nextCalls++;
    final read = Completer<StudioChatFrame?>();
    _nextReads.add(read);
    return read.future;
  }

  void emit(StudioChatFrame frame) {
    if (_nextReads.isEmpty) throw StateError('No pending content read');
    _nextReads.removeAt(0).complete(frame);
  }

  @override
  Future<StudioChatReceipt> load(TimelineDirection direction) =>
      loadResult.future;
  @override
  Future<StudioChatReceipt> extendLatest() => loadResult.future;
  @override
  Future<StudioChatReceipt> focus(String? itemId) {
    focusRequests.add(itemId);
    if (!focusEntered.isCompleted) focusEntered.complete();
    return loadResult.future;
  }

  @override
  Future<StudioChatReceipt> expandItem(String itemId) => loadResult.future;

  @override
  void requestClose() {
    requestCloseCalls++;
    closed = true;
    for (final read in _nextReads) {
      if (!read.isCompleted) read.complete(null);
    }
    _nextReads.clear();
    if (focusRequests.isNotEmpty && !loadResult.isCompleted) {
      loadResult.completeError(const StaleChatAttempt());
    }
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    if (!closeCompleted.isCompleted) closeCompleted.complete();
  }
}

/// Supplies Thread frames per binding; reduction and reconnection stay in the
/// actual StudioThreadSession. Timers are released separately by the test.
final class _RuntimeRetryTransport
    implements StudioTransport, ChatWindowReader {
  final List<StreamController<ThreadStreamFrame>> sources = [];
  final window = _FakeWindow(initialSnapshot: _snapshot(1));

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) {
    final controller = StreamController<ThreadStreamFrame>(sync: true);
    sources.add(controller);
    return controller.stream;
  }

  @override
  Future<StudioChatWindow> openChatWindow(String threadId) async => window;

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
    items: const [],
    interactions: const [],
    runtime:
        runtime ??
        const ThreadRuntimeView(
          model: 'model',
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
    model: 'model',
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
  model: 'model',
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

StudioChatSnapshot _snapshot(
  int version, {
  String? focusedItemId,
  List<StudioChatItem> items = const [],
}) => StudioChatSnapshot(
  focusedItemId: focusedItemId,
  version: version,
  items: items,
  hasOlder: true,
  hasNewer: false,
  canExtendLatest: false,
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

void main() {
  test('runtime snapshot and updates expose approved plan markdown', () async {
    final transport = _FakeTransport();
    final session = _session(transport);
    addTearDown(() async {
      for (final open in transport.pendingOpens) {
        if (!open.isCompleted) {
          open.complete(_FakeWindow(initialSnapshot: _snapshot(1)));
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
    'Chat capacity recovery keeps runtime synchronization independent',
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
            open.complete(_FakeWindow(initialSnapshot: _snapshot(1)));
          }
        }
        await session.close();
        await transport.close();
      });
      await _deliverSnapshot(session, transport);
      expect(session.chat.state.value, isA<ChatFailed<StudioChatSnapshot>>());
      expect(session.state.sync.phase, DomainSyncPhase.ready);
      expect(session.state.sync.errorMessage, isNull);

      retiring.release();
      final window = _FakeWindow(initialSnapshot: _snapshot(1));
      transport.pendingOpens.single.complete(window);
      await session.chat.ready;
      expect(session.state.sync.phase, DomainSyncPhase.ready);
      expect(session.state.sync.errorMessage, isNull);

      // Content progress also cannot clear a genuine Thread-state failure.
      session.markResync(StateError('runtime offline'), failed: true);
      window.emit(
        const StudioChatPatch(from: 1, to: 2, changes: [], hasNewer: false),
      );
      await session.source.waitFor((state) => state.chatVersion == 2);
      expect(session.state.sync.phase, DomainSyncPhase.failed);
      expect(session.state.sync.errorMessage, contains('runtime offline'));
    },
  );

  test('runtime progress renews retries and eventually observes terminal usage', () async {
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
      // More outages than the consecutive-failure limit, with actual owner
      // notification progress between them. A successful baseline alone is not
      // sufficient progress; the snapshot-only cases below retain that limit.
      for (var cycle = 0; cycle < 5; cycle++) {
        final baseline = 100 * (cycle + 1);
        transport.sources.last.add(
          ThreadSnapshotFrame(workspace: _workspace(revision: baseline)),
        );
        if (cycle == 0) await session.chat.ready;
        transport.sources.last.add(
          ThreadNotificationFrame(
            threadId: 'thread',
            epoch: 1,
            baseRevision: baseline,
            revision: baseline + 1,
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
      expect(session.state.chatVersion, 1);
    }, zoneSpecification: timers.specification);
  });

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
            if (attempt == 0) await session.chat.ready;
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
      transport.sources.single.add(
        ThreadSnapshotFrame(workspace: _workspace(revision: 10)),
      );
      await session.chat.ready;
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
    'actual Client keeps the same draft and owned view across Settings',
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
      final window = _FakeWindow(initialSnapshot: _snapshot(3));
      transport.pendingOpens.single.complete(window);
      await session.source.waitFor((value) => value.chatVersion == 3);
      final viewId = session.state.chatViewId;
      client.workspace.showSettings();
      client.workspace.hideSettings();
      expect(identical(client.session('thread'), session), isTrue);
      expect(session.state.chatViewId, viewId);
      expect(transport.pendingOpens, hasLength(1));
      expect(window.closeCalls, 0);
      expect(session.isActive, isTrue);
      await client.close();
      await transport.close();
    },
  );

  test(
    'actual Clients never share same-id session, view or draft ownership',
    () async {
      final leftTransport = _FakeTransport();
      final rightTransport = _FakeTransport();
      final left = AnyworkClient(transport: leftTransport, clientId: 'left');
      final right = AnyworkClient(transport: rightTransport, clientId: 'right');
      final leftSession = left.session('thread');
      final rightSession = right.session('thread');
      await _deliverSnapshot(leftSession, leftTransport);
      await _deliverSnapshot(rightSession, rightTransport);
      final leftWindow = _FakeWindow(initialSnapshot: _snapshot(1));
      final rightWindow = _FakeWindow(initialSnapshot: _snapshot(6));
      leftTransport.pendingOpens.single.complete(leftWindow);
      rightTransport.pendingOpens.single.complete(rightWindow);
      await leftSession.source.waitFor((value) => value.chatVersion == 1);
      await rightSession.source.waitFor((value) => value.chatVersion == 6);
      left.startDraft.updateDraft('project', 'left draft');
      expect(right.startDraft.state.forProject('project').text, isEmpty);
      expect(identical(leftSession, rightSession), isFalse);
      await left.close();
      expect(leftWindow.closeCalls, 1);
      expect(rightWindow.closeCalls, 0);
      expect(rightSession.state.chatVersion, 6);
      expect(rightSession.isActive, isTrue);
      await right.close();
      await leftTransport.close();
      await rightTransport.close();
    },
  );

  test('initial Reset and following Patch use the same session reducer and one next', () async {
    final transport = _FakeTransport();
    final session = _session(transport);
    await _deliverSnapshot(session, transport);
    final window = _FakeWindow(initialSnapshot: _snapshot(1));
    transport.pendingOpens.single.complete(window);
    await session.source.waitFor((value) => value.chatVersion == 1);
    expect(window.nextCalls, 1);
    expect(session.state.chatViewId, isNotNull);

    window.emit(
      StudioChatPatch(from: 1, to: 2, changes: const [], hasNewer: false),
    );
    await session.source.waitFor((value) => value.chatVersion == 2);
    expect(
      window.nextCalls,
      2,
      reason: 'next is requested only after the prior frame reduces',
    );
    await session.close();
    await transport.close();
  });

  for (final badRevision in [false, true]) {
    test(
      'mixed Patch failure commits no prior splice or field (${badRevision ? 'revision' : 'field'})',
      () async {
        final transport = _FakeTransport();
        final session = _session(transport);
        await _deliverSnapshot(session, transport);
        StudioChatItem item(String id) => StudioChatItem(
          ThreadItemView(
            id: id,
            threadId: 'thread',
            turnId: 'turn',
            ordinal: 1,
            revision: 1,
            saved: false,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            state: const ThreadTextItemStateView(
              channel: ThreadTextChannel.commentary,
              text: 'original',
              attachments: [],
              lifecycle: StreamingThreadContentView(),
            ),
          ),
          saved: false,
          lifecycle: StudioChatLifecycle.streaming,
        );
        final window = _FakeWindow(
          initialSnapshot: _snapshot(1, items: [item('original')]),
        );
        transport.pendingOpens.single.complete(window);
        await session.source.waitFor((state) => state.chatVersion == 1);
        final failed = session.chat.state.waitFor(
          (state) => state is ChatReconnecting<StudioChatSnapshot>,
        );
        window.emit(
          StudioChatPatch(
            from: 1,
            to: 2,
            hasNewer: true,
            changes: [
              StudioViewSplice(index: 0, remove: 0, items: [item('inserted')]),
              StudioViewItemUpdate(
                itemId: 'original',
                expectedRevision: badRevision ? 99 : 1,
                revision: 2,
                omittedUnits: 0,
                saved: true,
                fields: [
                  const StudioFieldUpdateView(
                    field: ThreadTextFieldView(),
                    change: AppendThreadFieldChangeView(' should roll back'),
                  ),
                  if (!badRevision)
                    const StudioFieldUpdateView(
                      field: ThreadToolResultFieldView(),
                      change: ReplaceThreadFieldChangeView('wrong field'),
                    ),
                ],
              ),
            ],
          ),
        );
        await failed;
        expect(session.state.chatVersion, 1);
        expect(session.state.items.map((item) => item.id), ['original']);
        expect(session.state.items.single.text, 'original');
        expect(session.state.items.single.revision, 1);
        expect(session.state.items.single.saved, isFalse);
        await session.close();
        await transport.close();
      },
    );
  }

  test('retire then start A to B to A never reuses an old baseline', () async {
    final transport = _FakeTransport();
    final session = _session(transport);
    await _deliverSnapshot(session, transport);
    final first = _FakeWindow(initialSnapshot: _snapshot(1));
    transport.pendingOpens.single.complete(first);
    await session.source.waitFor((value) => value.chatVersion == 1);
    final firstView = session.state.chatViewId;

    await session.retire();
    session.start();
    final second = _FakeWindow(initialSnapshot: _snapshot(8));
    transport.pendingOpens.last.complete(second);
    await session.source.waitFor((value) => value.chatVersion == 8);
    expect(session.state.chatViewId, isNot(firstView));
    await session.retire();
    session.start();
    final third = _FakeWindow(initialSnapshot: _snapshot(1));
    transport.pendingOpens.last.complete(third);
    await session.source.waitFor((value) => value.chatVersion == 1);
    expect(session.state.chatViewId, isNot(firstView));
    expect(session.state.chatViewId, isNotNull);
    // A patch from B is a continuity gap for the new A view and cannot alter it.
    third.emit(
      StudioChatPatch(from: 8, to: 9, changes: const [], hasNewer: false),
    );
    await session.chat.state.waitFor(
      (value) => value is ChatReconnecting<StudioChatSnapshot>,
    );
    expect(session.state.chatVersion, 1);
    await session.close();
    await transport.close();
  });

  test(
    'returning view Reset preserves the Client reading intent and offset',
    () async {
      final transport = _FakeTransport();
      final session = _session(transport);
      addTearDown(() async {
        await session.close();
        await transport.close();
      });
      await _deliverSnapshot(session, transport);
      final first = _FakeWindow(initialSnapshot: _snapshot(1));
      transport.pendingOpens.single.complete(first);
      await session.source.waitFor((value) => value.chatVersion == 1);
      const anchor = TimelineAnchor(
        'historical-item',
        -120,
        readingIntent: TimelineReadingIntent.browseHistory,
      );
      session.setTimelineAnchor(anchor);

      await session.retire();
      expect(first.closeCalls, 1);
      expect(session.state.items, isEmpty);
      expect(session.state.history.anchor, anchor);
      session.start();
      final returned = _FakeWindow(initialSnapshot: _snapshot(8));
      transport.pendingOpens.last.complete(returned);
      await session.source.waitFor((value) => value.chatVersion == 8);

      expect(session.state.history.anchor, anchor);
      expect(session.state.history.detached, isTrue);
      await returned.focusEntered.future;
      expect(returned.focusRequests, ['historical-item']);
      expect(session.state.history.isLoading, isTrue);
      final historical = StudioChatItem(
        ThreadItemView(
          id: 'historical-item',
          threadId: 'thread',
          turnId: 'turn',
          ordinal: 1,
          revision: 1,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          state: ThreadTextItemStateView(
            channel: ThreadTextChannel.user,
            text: 'historical body outside the initial latest window',
            attachments: const [],
            lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
          ),
        ),
        saved: true,
        lifecycle: StudioChatLifecycle.terminal,
      );
      returned.emit(
        StudioChatReset(
          _snapshot(9, focusedItemId: 'historical-item', items: [historical]),
        ),
      );
      await session.source.waitFor((value) => value.chatVersion == 9);
      // A frame may win the race with its receipt. It still cannot finish a
      // pending control or replace the Client's item + pixel offset intent.
      expect(session.state.history.isLoading, isTrue);
      returned.loadResult.complete(
        const StudioChatReceipt(
          operationId: 1,
          version: 9,
          retained: true,
          disposition: StudioChatDisposition.applied,
        ),
      );
      await session.source.waitFor((value) => !value.history.isLoading);
      expect(session.state.history.anchor, anchor);
      expect(session.state.items.single.id, 'historical-item');
      expect(session.confirmedViewFocus, 'historical-item');
    },
  );

  test('late focus replies cannot settle a newer same-item intent', () async {
    final transport = _FakeTransport();
    final session = _session(transport);
    addTearDown(() async {
      await session.close();
      await transport.close();
    });
    await _deliverSnapshot(session, transport);
    transport.pendingOpens.single.complete(
      _FakeWindow(initialSnapshot: _snapshot(1)),
    );
    await session.chat.ready;
    final firstA = session.requestViewFocus('A')!;
    final requestB = session.requestViewFocus('B')!;
    final newA = session.requestViewFocus('A')!;
    session.settleViewFocus(firstA, succeeded: true);
    session.settleViewFocus(requestB, succeeded: true);
    expect(session.viewFocusPending, isTrue);
    expect(session.confirmedViewFocus, isNull);
    expect(session.isViewFocusCurrent(newA), isTrue);
    session.settleViewFocus(newA, succeeded: true);
    expect(session.confirmedViewFocus, 'A');
    expect(session.viewFocusPending, isFalse);

    await session.retire();
    session.start();
    transport.pendingOpens.last.complete(
      _FakeWindow(initialSnapshot: _snapshot(1)),
    );
    await session.chat.ready;
    final reopenedA = session.requestViewFocus('A')!;
    session.settleViewFocus(newA, succeeded: true);
    expect(session.confirmedViewFocus, isNull);
    expect(session.isViewFocusCurrent(reopenedA), isTrue);
  });

  test(
    'closing a restore waiting for initial joins its attempt control',
    () async {
      final transport = _FakeTransport();
      final session = _session(transport);
      addTearDown(transport.close);
      await _deliverSnapshot(session, transport);
      transport.pendingOpens.single.complete(
        _FakeWindow(initialSnapshot: _snapshot(1)),
      );
      await session.chat.ready;
      session.setTimelineAnchor(
        const TimelineAnchor(
          'historical-item',
          -120,
          readingIntent: TimelineReadingIntent.browseHistory,
        ),
      );
      await session.retire();
      session.start();
      expect(session.budget.used(ResourceKind.pendingOperation), 1);
      final closing = session.close();
      final late = _FakeWindow(initialSnapshot: _snapshot(8));
      transport.pendingOpens.last.complete(late);
      final report = await closing;
      expect(report.unresolved, isEmpty);
      expect(late.closeCalls, 1);
      expect(late.focusRequests, isEmpty);
      expect(session.budget.used(ResourceKind.pendingOperation), 0);
    },
  );

  test('late open and initial failure close their own native window', () async {
    final transport = _FakeTransport();
    final session = _session(transport);
    await _deliverSnapshot(session, transport);
    final lateOpen = transport.pendingOpens.single;
    final retired = await session.retire(deadline: DateTime.utc(2000));
    expect(retired.unresolved, isNotEmpty);
    final late = _FakeWindow(initialSnapshot: _snapshot(99));
    lateOpen.complete(late);
    await late.closeCompleted.future;
    expect(session.state.chatVersion, isNull);

    session.start();
    final failed = _FakeWindow(
      initialSnapshot: _snapshot(2),
      failInitial: StateError('initial failed'),
    );
    transport.pendingOpens.last.complete(failed);
    await failed.closeCompleted.future;
    expect(session.state.chatVersion, isNull);
    await session.close();
    await transport.close();
  });

  test(
    'Applied equal-version receipt ends loading without becoming NoChange',
    () async {
      final transport = _FakeTransport();
      final session = _session(transport);
      await _deliverSnapshot(session, transport);
      final window = _FakeWindow(initialSnapshot: _snapshot(4));
      transport.pendingOpens.single.complete(window);
      await session.source.waitFor((value) => value.chatVersion == 4);

      final token = session.beginHistoryOp(TimelineDirection.older);
      expect(token, isNotNull);
      final operationToken = token!;
      final receipt = StudioChatReceipt(
        operationId: operationToken,
        version: 4,
        retained: true,
        disposition: StudioChatDisposition.applied,
      );
      session.observeHistoryOp(operationToken, receipt);
      expect(session.state.history.isLoading, isFalse);
      expect(
        session.historyOperation.value?.outcome,
        HistoryOperationOutcome.observed,
      );
      expect(
        session.historyOperation.value?.receipt?.disposition,
        StudioChatDisposition.applied,
      );
      await session.close();
      await transport.close();
    },
  );

  test(
    'NoChange ends loading without waiting for unrelated session progress',
    () async {
      final transport = _FakeTransport();
      final session = _session(transport);
      await _deliverSnapshot(session, transport);
      final window = _FakeWindow(initialSnapshot: _snapshot(4));
      transport.pendingOpens.single.complete(window);
      await session.source.waitFor((value) => value.chatVersion == 4);

      final token = session.beginHistoryOp(TimelineDirection.older)!;
      session.observeHistoryOp(
        token,
        StudioChatReceipt(
          operationId: token,
          version: 99,
          retained: true,
          disposition: StudioChatDisposition.noChange,
        ),
      );
      expect(session.state.history.isLoading, isFalse);
      expect(session.state.chatVersion, 4);
      expect(
        session.historyOperation.value?.outcome,
        HistoryOperationOutcome.noChange,
      );
      expect(session.historyOperation.value?.receipt?.version, 99);
      expect(
        window.nextCalls,
        1,
        reason: 'there is no control-owned content frame',
      );
      await session.close();
      await transport.close();
    },
  );
}
