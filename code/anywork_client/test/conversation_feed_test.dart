import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/src/conversation/data/conversation_repository_impl.dart';
import 'package:anywork_client/src/studio/stores/thread_directory_store.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const body = BodyRef(
  databaseId: 'db',
  bodyId: 'body',
  ownerEventId: 'event',
  bodyKey: 'output',
  role: 'toolOutput',
  byteLength: 140,
  mediaType: 'text/plain',
);

final class _QueryFeed extends TestConversationFeed {
  _QueryFeed() : super();
  final older = TimelinePrependOlder(
    items: [],
    hasMoreOlder: true,
    olderCursor: 'opaque-next',
  );
  final members = <WorkGroupMember>[
    const WorkGroupReasoning(
      id: 'reasoning:1',
      seq: 3,
      text: 'reason',
      summary: 'summary',
      bodyRef: body,
      outcome: 'completed',
    ),
  ];
  final window = const BodyWindow(
    offset: 4,
    bytesBase64: 'AQI=',
    totalBytes: 140,
    eof: false,
  );
  (String, int)? olderArgs;
  (int?, int?)? memberArgs;
  (BodyRef, int, int)? bodyArgs;
  @override
  Future<TimelinePatch> loadOlder({
    required String cursor,
    int limit = 50,
  }) async {
    olderArgs = (cursor, limit);
    return older;
  }

  @override
  Future<List<WorkGroupMember>> loadWorkGroupMembers({
    int? afterSeq,
    int? beforeSeq,
  }) async {
    memberArgs = (afterSeq, beforeSeq);
    return members;
  }

  @override
  Future<BodyWindow> readBodyWindow({
    required BodyRef reference,
    required int offset,
    required int maxBytes,
  }) async {
    bodyArgs = (reference, offset, maxBytes);
    return window;
  }
}

final class _ReentrantFeed extends TestConversationFeed {
  void Function()? onRequestClose;
  @override
  void requestClose() {
    super.requestClose();
    final callback = onRequestClose;
    onRequestClose = null;
    callback?.call();
  }
}

final class _Fixture {
  _Fixture() {
    directory = ThreadDirectoryStore(
      feed: transport,
      scope: scope.child('directory'),
    );
    repository = ConversationRepositoryImpl(
      transport: transport,
      directory: directory,
      scope: scope.child('conversation'),
      onRevision: (_, _) {},
    );
    addTearDown(() async {
      final budget = ClientCloseBudget(const Duration(seconds: 2));
      final report = await repository.close(budget: budget);
      final settled = report.complete
          ? report
          : await repository.retryCleanup(budget: budget);
      expect(settled.complete, isTrue);
      await scope.close(budget: budget);
      await transport.lifecycleScope.close(budget: budget);
    });
  }
  final scope = ClientScope(owner: 'test');
  final transport = TestConversationTransport();
  late final ThreadDirectoryStore directory;
  late final ConversationRepositoryImpl repository;
}

void main() {
  test(
    'DTO collections capture immutable values including nested attachment JSON',
    () {
      final map = <String, Object?>{
        'name': 'asset',
        'sizes': <Object?>[1, 2],
      };
      final attachments = <Object?>[map];
      final item = TimelineUserMessage(
        id: 'msg:1',
        seq: 1,
        channel: 'user',
        text: 'hello',
        attachments: attachments,
      );
      final items = <TimelineItem>[item];
      final patch = TimelineReset(
        items: items,
        hasMoreOlder: true,
        olderCursor: 'opaque',
        revision: 8,
      );
      map['name'] = 'changed';
      (map['sizes'] as List<Object?>).add(3);
      attachments.clear();
      items.clear();
      expect(patch.items, [item]);
      expect(item.attachments, [
        {
          'name': 'asset',
          'sizes': [1, 2],
        },
      ]);
      expect(() => patch.items.clear(), throwsUnsupportedError);
      expect(
        () =>
            (item.attachments.single as Map<String, Object?>)['name'] = 'edit',
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((item.attachments.single as Map<String, Object?>)['sizes']
                    as List<Object?>)
                .clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'independently received equivalent attachment values compare equally',
    () {
      TimelineUserMessage make(Map<String, Object?> attachment) =>
          TimelineUserMessage(
            id: 'msg:1',
            seq: 1,
            channel: 'user',
            text: 'hello',
            attachments: [attachment],
          );
      final first = make({
        'name': 'asset',
        'sizes': [1, 2],
      });
      final second = make({
        'sizes': [1, 2],
        'name': 'asset',
      });
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(
          make({
            'name': 'asset',
            'sizes': [2, 1],
          }),
        ),
      );
    },
  );

  test('work groups use lastSeq for ordering and preserve the exact query boundaries', () {
    const group = TimelineWorkGroup(
      id: 'work:4',
      firstSeq: 4,
      lastSeq: 19,
      afterBoundarySeq: 3,
      beforeBoundarySeq: 20,
      memberCount: 8,
      summary: 'work',
      status: WorkGroupStatus.failed,
    );
    expect(group.seq, 19);
    expect(group.afterBoundarySeq, 3);
    expect(group.beforeBoundarySeq, 20);
  });

  test('runtime snapshot retains optional metadata and owns its todo and health collections', () {
    final todoItems = <TimelineTodoItem>[
      const TimelineTodoItem(step: 'review', status: 'pending'),
    ];
    final skills = <String>['skill'];
    final servers = <ConversationMcpAvailabilityDescriptor>[
      const ConversationMcpAvailabilityDescriptor(
        server: ConversationMcpServerDescriptor(
          id: 'server',
          source: 'workspace',
          transport: 'stdio',
          endpoint: 'command',
          builtIn: false,
        ),
        availability: 'available',
        toolCount: 2,
      ),
    ];
    final snapshot = ConversationRuntimeSnapshot(
      threadId: 'thread',
      deferred: [],
      usage: usageForRuntime(emptyConversationWorkspace('thread').runtime),
      turnCompletionTokens: 7,
      turnResponseMillis: 9,
      todo: TimelineTodoListUpdate(callId: 'todo-call', items: todoItems),
      activeSkills: skills,
      activeMcpServers: ['server'],
      activeLspServers: [],
      progress: 'processing',
      mcpHealth: ConversationMcpHealthSnapshot(generation: 4, servers: servers),
      updatedAt: 123,
    );
    todoItems.clear();
    skills.clear();
    servers.clear();
    expect(snapshot.todo!.items.single.step, 'review');
    expect(snapshot.activeSkills, ['skill']);
    expect(snapshot.progress, 'processing');
    expect(snapshot.updatedAt, 123);
    expect(snapshot.mcpHealth!.servers.single.toolCount, 2);
    expect(() => snapshot.todo!.items.clear(), throwsUnsupportedError);
    expect(() => snapshot.mcpHealth!.servers.clear(), throwsUnsupportedError);
  });

  test(
    'opening through the repository uses one feed and forwards initialLimit',
    () async {
      final fixture = _Fixture();
      fixture.transport.feedFactory = (_, _) => TestConversationFeed();
      final ConversationFeedPort port = fixture.repository;
      final first = await port.openConversationFeed('thread', initialLimit: 17);
      final second = await fixture.repository.openConversationFeed('thread');
      expect(identical(first, second), isTrue);
      expect(fixture.transport.feedOpens, hasLength(1));
      expect(fixture.transport.feedOpens.single.initialLimit, 17);
      expect(
        fixture.repository.sessionState('thread')!.meta,
        same(first.sessionMetaSnapshot),
      );
      expect(first.liveStatusSnapshot.phase, isA<LiveStatusIdle>());
    },
  );

  test(
    'events preserve every typed patch and metadata event without regrouping',
    () async {
      final fixture = _Fixture();
      final raw = TestConversationFeed();
      fixture.transport.feedFactory = (_, _) => raw;
      final handle = await fixture.repository.openConversationFeed('thread');
      final received = <ConversationFeedEvent>[];
      final done = Completer<void>();
      final subscription = handle.events.listen((event) {
        received.add(event);
        if (received.length == 8) done.complete();
      });
      addTearDown(subscription.cancel);
      final meta = sessionMetaForWorkspace(
        emptyConversationWorkspace('thread').copyWith(revision: 5),
      );
      final status = LiveStatusSnapshot(
        revision: 6,
        phase: const LiveStatusStreamingText(
          attemptId: 'attempt',
          itemId: 'msg:7',
          text: 'stream',
        ),
        attentions: [],
        suppressedByInteraction: true,
      );
      final events = <ConversationFeedEvent>[
        ConversationTimeline(
          patch: TimelineReset(items: [], hasMoreOlder: false, revision: 1),
        ),
        ConversationTimeline(patch: TimelineAppend(items: [])),
        const ConversationTimeline(
          patch: TimelineUpdate(
            item: TimelineFallback(
              id: 'fallback:1',
              seq: 1,
              eventId: 'event',
              eventKind: 'new-kind',
              reason: 'unknown',
            ),
          ),
        ),
        const ConversationTimeline(patch: TimelineRemove(itemId: 'fallback:1')),
        ConversationLiveStatus(snapshot: status),
        ConversationSessionMeta(snapshot: meta),
        const ConversationInputPresented(inputId: 'input', itemId: 'msg:1'),
        const ConversationResyncRequired(reason: 'lagged'),
      ];
      for (final event in events) raw.send(event);
      await done.future;
      for (var i = 0; i < events.length; i++)
        expect(received[i], same(events[i]));
      expect(fixture.repository.sessionState('thread')!.meta, same(meta));
      expect(handle.liveStatusSnapshot, same(status));
      expect(
        fixture.transport.feedOpens,
        hasLength(1),
        reason: 'Resync is an explicit caller decision',
      );
    },
  );

  test('queries forward opaque identities, bounds and byte windows without applying results', () async {
    final fixture = _Fixture();
    final raw = _QueryFeed();
    fixture.transport.feedFactory = (_, _) => raw;
    final handle = await fixture.repository.openConversationFeed('thread');
    final before = fixture.repository.sessionState('thread')!.meta;
    expect(
      await handle.loadOlder(cursor: 'opaque-before', limit: 9),
      same(raw.older),
    );
    expect(
      await handle.loadWorkGroupMembers(afterSeq: 3, beforeSeq: 20),
      same(raw.members),
    );
    expect(
      await handle.readBodyWindow(reference: body, offset: 4, maxBytes: 2),
      same(raw.window),
    );
    expect(raw.olderArgs, ('opaque-before', 9));
    expect(raw.memberArgs, (3, 20));
    expect(raw.bodyArgs, (body, 4, 2));
    expect(fixture.repository.sessionState('thread')!.meta, same(before));
  });

  test('session details stay on the same feed, propagate failures and reject retirement', () async {
    final fixture = _Fixture();
    fixture.repository.setVisibleThread('thread');
    final session = fixture.repository.session('thread');
    await expectLater(
      session.readSessionDetail(
        kind: SessionDetailKind.plan,
        offset: 0,
        maxBytes: 2,
      ),
      throwsA(isA<ThreadStateResyncCancelled>()),
    );
    expect(fixture.transport.feedOpens, isEmpty);

    final bytes = <int>[1, 2];
    final window = SessionDetailWindow(
      ownerEpoch: 'detail-owner',
      revision: 9,
      offset: 4,
      totalBytes: 12,
      bytes: bytes,
    );
    bytes[0] = 99;
    expect(window.bytes, [1, 2]);
    expect(() => window.bytes[0] = 0, throwsUnsupportedError);
    final raw = TestConversationFeed();
    final freshRaw = TestConversationFeed();
    fixture.transport.feedFactory = (_, index) => index == 0 ? raw : freshRaw;
    final calls = <(SessionDetailKind, int, int)>[];
    raw.onReadSessionDetail =
        ({required kind, required offset, required maxBytes}) async {
          calls.add((kind, offset, maxBytes));
          return window;
        };
    final handle = await fixture.repository.openConversationFeed('thread');
    expect(
      await session.readSessionDetail(
        kind: SessionDetailKind.plan,
        offset: 4,
        maxBytes: 2,
      ),
      same(window),
    );
    expect(
      await handle.readSessionDetail(
        kind: SessionDetailKind.activeSkills,
        offset: 4,
        maxBytes: 2,
      ),
      same(window),
    );
    expect(calls, [
      (SessionDetailKind.plan, 4, 2),
      (SessionDetailKind.activeSkills, 4, 2),
    ]);
    expect(fixture.transport.feedOpens, hasLength(1));

    final failure = StateError('detail read failed');
    raw.onReadSessionDetail = ({
      required kind,
      required offset,
      required maxBytes,
    }) => Future.error(failure);
    await expectLater(
      session.readSessionDetail(
        kind: SessionDetailKind.todo,
        offset: 0,
        maxBytes: 16,
      ),
      throwsA(same(failure)),
    );
    await expectLater(
      handle.readSessionDetail(
        kind: SessionDetailKind.interactions,
        offset: 0,
        maxBytes: 16,
      ),
      throwsA(same(failure)),
    );

    final entered = Completer<void>();
    final pending = Completer<SessionDetailWindow>();
    var pendingCalls = 0;
    raw.onReadSessionDetail =
        ({required kind, required offset, required maxBytes}) {
          pendingCalls++;
          if (!entered.isCompleted) entered.complete();
          return pending.future;
        };
    final sessionRead = session.readSessionDetail(
      kind: SessionDetailKind.workflow,
      offset: 4,
      maxBytes: 2,
    );
    await entered.future;
    final handleRead = handle.readSessionDetail(
      kind: SessionDetailKind.activeMcpServers,
      offset: 4,
      maxBytes: 2,
    );
    final sessionRejected = expectLater(
      sessionRead,
      throwsA(isA<ClientResourceClosed>()),
    );
    final handleRejected = expectLater(
      handleRead,
      throwsA(isA<ClientResourceClosed>()),
    );
    handle.requestClose();
    final fresh = await fixture.repository.openConversationFeed('thread');
    expect(fresh, isNot(same(handle)));
    pending.complete(window);
    await Future.wait([sessionRejected, handleRejected]);
    expect(pendingCalls, 2);
    await expectLater(
      handle.readSessionDetail(
        kind: SessionDetailKind.plan,
        offset: 0,
        maxBytes: 2,
      ),
      throwsA(isA<ClientResourceClosed>()),
    );
    expect(
      pendingCalls,
      2,
      reason: 'A retired handle cannot start native work',
    );

    freshRaw.onReadSessionDetail = ({
      required kind,
      required offset,
      required maxBytes,
    }) async => window;
    expect(
      await session.readSessionDetail(
        kind: SessionDetailKind.activeLspServers,
        offset: 4,
        maxBytes: 2,
      ),
      same(window),
    );
    expect(fixture.transport.feedOpens, hasLength(2));
    fixture.repository.setVisibleThread(null);
    await expectLater(
      session.readSessionDetail(
        kind: SessionDetailKind.plan,
        offset: 0,
        maxBytes: 2,
      ),
      throwsA(isA<ThreadStateResyncCancelled>()),
    );
    expect(fixture.transport.feedOpens, hasLength(2));
  });

  test('reset is returned and emitted exactly as supplied by Rust', () async {
    final fixture = _Fixture();
    final raw = TestConversationFeed();
    fixture.transport.feedFactory = (_, _) => raw;
    final handle = await fixture.repository.openConversationFeed('thread');
    final event = handle.events.first;
    final patch = await handle.resetToLatest(limit: 12);
    expect((await event as ConversationTimeline).patch, same(patch));
  });

  test('transport stream errors remain errors', () async {
    final fixture = _Fixture();
    final raw = TestConversationFeed();
    fixture.transport.feedFactory = (_, _) => raw;
    final handle = await fixture.repository.openConversationFeed('thread');
    final failure = StateError('transport failed');
    final result = expectLater(handle.events.first, throwsA(same(failure)));
    raw.sendError(failure);
    await result;
    expect(
      fixture.repository.sessionState('thread')!.sync.errorMessage,
      failure.toString(),
    );
  });

  test(
    'late open after repository close remains owned until actual cleanup',
    () async {
      final fixture = _Fixture();
      final opening = fixture.repository.openConversationFeed('thread');
      final rejected = expectLater(opening, throwsA(anything));
      await fixture.transport.feedOpened(0);
      final report = await fixture.repository.close(
        budget: ClientCloseBudget(Duration.zero),
      );
      expect(report.complete, isFalse);
      final raw = TestConversationFeed();
      fixture.transport.feedOpens.single.result.complete(raw);
      await rejected;
      await raw.closeCompleted.future;
      expect(raw.requestCloseCalls, greaterThan(0));
      expect(raw.closeCalls, 1);
      final complete = await fixture.repository.retryCleanup(
        budget: ClientCloseBudget(const Duration(seconds: 2)),
      );
      expect(complete.complete, isTrue);
    },
  );

  test('feed close errors remain tracked and management cleanup retries the original handle', () async {
    final fixture = _Fixture();
    final raw = TestConversationFeed()
      ..closeFailure = StateError('close failed');
    fixture.transport.feedFactory = (_, _) => raw;
    await fixture.repository.openConversationFeed('thread');
    final report = await fixture.repository.close(
      budget: ClientCloseBudget(const Duration(seconds: 2)),
    );
    expect(report.complete, isFalse);
    expect(raw.closeCalls, 1);
    raw.closeFailure = null;
    final retried = await fixture.repository.retryCleanup(
      budget: ClientCloseBudget(const Duration(seconds: 2)),
    );
    expect(retried.complete, isTrue);
    expect(raw.closeCalls, 2);
  });
  for (final requestFirst in [false, true]) {
    test(
      'closed visible feed reopens the same thread while old cleanup is pending (requestFirst=$requestFirst)',
      () async {
        final fixture = _Fixture();
        final raws = <TestConversationFeed>[];
        fixture.transport.feedFactory = (threadId, _) {
          final raw = TestConversationFeed(threadId: threadId);
          raws.add(raw);
          return raw;
        };
        fixture.repository.setVisibleThread('thread');
        final old = await fixture.repository.openConversationFeed('thread');
        final gate = raws.first.closeGate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final lateDelivered = Completer<void>();
        final oldEvents = old.events.listen((_) => lateDelivered.complete());
        addTearDown(oldEvents.cancel);
        if (requestFirst) old.requestClose();
        final closing = old.close();
        expect(old.close(), same(closing));
        final reopened = await fixture.repository.openConversationFeed(
          'thread',
          initialLimit: 7,
        );
        expect(reopened, isNot(same(old)));
        expect(raws, hasLength(2));
        expect(fixture.transport.feedOpens.last.initialLimit, 7);
        expect(raws.first.closeCalls, 1);
        expect(raws.first.closeCompleted.isCompleted, isFalse);
        final freshEvent = reopened.events.first;
        const presented = ConversationInputPresented(
          inputId: 'fresh-input',
          itemId: 'msg:2',
        );
        raws.last.send(presented);
        expect(await freshEvent, same(presented));
        // A packet already in transit cannot overwrite the replacement mirror.
        raws.first.controller.add(
          ConversationSessionMeta(
            snapshot: sessionMetaForWorkspace(
              emptyConversationWorkspace('thread').copyWith(revision: 99),
            ),
          ),
        );
        await lateDelivered.future;
        expect(fixture.repository.sessionState('thread')!.revision, 0);
        gate.complete();
        await closing;
        expect(raws.first.closeCalls, 1);
      },
    );
  }

  test('public close failure stays owned after reopening and retries only the old resource', () async {
    final fixture = _Fixture();
    final failure = StateError('old close failed');
    final oldRaw = TestConversationFeed()..closeFailure = failure;
    final freshRaw = TestConversationFeed();
    fixture.transport.feedFactory = (_, index) =>
        index == 0 ? oldRaw : freshRaw;
    fixture.repository.setVisibleThread('thread');
    final old = await fixture.repository.openConversationFeed('thread');
    await expectLater(old.close(), throwsA(same(failure)));
    final fresh = await fixture.repository.openConversationFeed('thread');
    expect(fresh, isNot(same(old)));
    final report = await fixture.repository.close(
      budget: ClientCloseBudget(const Duration(seconds: 2)),
    );
    expect(report.complete, isFalse);
    expect(
      report.unresolved.any(
        (resource) =>
            resource.stages.any((stage) => identical(stage.error, failure)),
      ),
      isTrue,
    );
    expect(oldRaw.closeCalls, 1);
    expect(freshRaw.closeCalls, 1);
    oldRaw.closeFailure = null;
    final retried = await fixture.repository.retryCleanup(
      budget: ClientCloseBudget(const Duration(seconds: 2)),
    );
    expect(retried.complete, isTrue);
    expect(oldRaw.closeCalls, 2);
    expect(freshRaw.closeCalls, 1);
  });

  test('native close reentry shares the old close future and opens a fresh visible feed', () async {
    final fixture = _Fixture();
    final oldRaw = _ReentrantFeed();
    final freshRaw = TestConversationFeed();
    fixture.transport.feedFactory = (_, index) =>
        index == 0 ? oldRaw : freshRaw;
    fixture.repository.setVisibleThread('thread');
    final old = await fixture.repository.openConversationFeed('thread');
    final gate = oldRaw.closeGate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    Future<void>? nestedClose;
    Future<ConversationFeedHandle>? reentrantOpen;
    oldRaw.onRequestClose = () {
      nestedClose = old.close();
      reentrantOpen = fixture.repository.openConversationFeed('thread');
    };
    final closing = old.close();
    expect(nestedClose, same(closing));
    final fresh = await reentrantOpen!;
    expect(fresh, isNot(same(old)));
    expect(oldRaw.closeCalls, 1);
    gate.complete();
    await closing;
    expect(freshRaw.requestCloseCalls, 0);
  });

  test(
    'root scope retirement cannot hand out the closed cached feed',
    () async {
      final fixture = _Fixture();
      final raw = TestConversationFeed();
      fixture.transport.feedFactory = (_, _) => raw;
      await fixture.repository.openConversationFeed('thread');
      final gate = raw.closeGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      fixture.scope.requestClose();
      await expectLater(
        Future.sync(() => fixture.repository.openConversationFeed('thread')),
        throwsA(isA<ClientResourceClosed>()),
      );
      expect(fixture.transport.feedOpens, hasLength(1));
      gate.complete();
      await raw.closeCompleted.future;
    },
  );

  test('A to B to A retains old cleanup without letting an old handle retire the new A', () async {
    final fixture = _Fixture();
    final raws = <TestConversationFeed>[];
    fixture.transport.feedFactory = (threadId, _) {
      final raw = TestConversationFeed(threadId: threadId);
      raws.add(raw);
      return raw;
    };
    fixture.repository.setVisibleThread('a');
    final firstA = await fixture.repository.openConversationFeed('a');
    final gate = raws.first.closeGate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    fixture.repository.setVisibleThread('b');
    await fixture.repository.openConversationFeed('b');
    fixture.repository.setVisibleThread('a');
    final newA = await fixture.repository.openConversationFeed('a');
    final oldClosing = firstA.close();
    firstA.requestClose();
    expect(newA, isNot(same(firstA)));
    expect(fixture.transport.feedOpens.map((open) => open.threadId), [
      'a',
      'b',
      'a',
    ]);
    expect(raws.last.requestCloseCalls, 0);
    final freshEvent = newA.events.first;
    const presented = ConversationInputPresented(
      inputId: 'new-a',
      itemId: 'msg:3',
    );
    raws.last.send(presented);
    expect(await freshEvent, same(presented));
    gate.complete();
    await oldClosing;
    expect(raws.first.closeCalls, 1);
  });
}
