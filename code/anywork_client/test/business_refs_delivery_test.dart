import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/conversation_encoding.dart';
import 'package:test/test.dart';

import 'support/controlled_batch_consumer.dart';
import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 2, maxBytes: 4096);
const _range = ContentRange(offset: 0, maxBytes: 100);
const _none = ThreadBusinessRefs(plan: null, interactions: null);

ContentRef _document(int revision) => ContentRef(
  databaseId: 'db',
  target: BodyContentTarget(
    owner: CurrentContentOwner(domain: 'plan', id: 'plan', revision: revision),
    key: 'document',
  ),
);
CurrentCollectionRef _interactions(int revision) => CurrentCollectionRef(
  databaseId: 'db',
  collection: 'interactions',
  revision: revision,
);
ThreadBusinessRefs _refs({int? plan = 3, int? interactions = 1}) =>
    ThreadBusinessRefs(
      plan: plan == null
          ? null
          : CurrentPlanHead(
              revision: plan,
              phase: PlanRuntimePhase.values.first,
              document: _document(plan),
            ),
      interactions: interactions == null ? null : _interactions(interactions),
    );
ContentWindow _window(String content) => ContentWindow(
  offset: 0,
  bytes: content.codeUnits,
  generation: 'sealed',
  availableThrough: content.length,
  sealed: true,
);
Matcher get _stale => isA<StudioFailure>().having(
  (error) => error.reason,
  'reason',
  StudioFailureReason.staleContent,
);

Future<void> _baseline(ConversationFixture fixture, ThreadBusinessRefs refs) =>
    fixture.stateFeed().deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: completedHistoryVersion,
          workspace: _workspace(refs),
        ),
      ),
    );
Future<void> _update(
  ConversationFixture fixture,
  int revision,
  ThreadBusinessRefs refs,
) => fixture.stateFeed().deliver(
  ConversationStateEvent(
    frame: ThreadNotificationFrame(
      threadId: 'thread',
      epoch: 1,
      baseRevision: revision - 1,
      revision: revision,
      update: ThreadBusinessRefsUpdate(references: refs),
    ),
  ),
);

void main() {
  test('B08/B09 State baseline exposes business refs independently of Activity or Chat.current', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    final refs = _refs();
    await _baseline(fixture, refs);
    expect(fixture.session().state.businessRefs, same(refs));
    expect(fixture.session().activity.value, isNull);
    final scope = fixture.session().content.openScope(generation: 1);
    feed.reader.onContent = (reference, range) async {
      expect(reference, refs.plan!.document);
      return _window('plan v3');
    };
    feed.reader.onCurrent = (reference, continuation, demand) async {
      expect(reference, refs.interactions);
      return CurrentCollectionPage(
        revision: reference.revision,
        entries: [],
        continuation: 'page-2',
      );
    };
    expect(
      String.fromCharCodes(
        (await scope.readContent(
          reference: refs.plan!.document!,
          range: _range,
        )).bytes,
      ),
      'plan v3',
    );
    expect(
      (await scope.pageCurrent(
        reference: refs.interactions!,
        demand: _demand,
      )).continuation,
      'page-2',
    );
    expect(fixture.transport.opens, hasLength(1));
    expect((await fixture.close()).complete, isTrue);
  });

  test('B10/B11 refs replace as one value and invalidate only the changed resource in flight', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    final initial = _refs();
    await _baseline(fixture, initial);
    final scope = fixture.session().content.openScope(generation: 1);
    final plan = Completer<ContentWindow>();
    final page = Completer<CurrentCollectionPage>();
    feed.reader.onContent = (_, _) => plan.future;
    feed.reader.onCurrent = (_, _, _) => page.future;
    final oldPlan = scope.readContent(
      reference: initial.plan!.document!,
      range: _range,
    );
    final oldPage = scope.pageCurrent(
      reference: initial.interactions!,
      continuation: 'page-2',
      demand: _demand,
    );
    final rejectedPlan = expectLater(oldPlan, throwsA(_stale));
    await _update(fixture, 2, _refs(plan: 4));
    plan.complete(_window('v3'));
    page.complete(CurrentCollectionPage(revision: 1, entries: []));
    await rejectedPlan;
    expect((await oldPage).revision, 1);
    expect(scope.isActive, isTrue);
    expect(fixture.consumers['thread']!.batches, hasLength(1));
    expect(fixture.session().state.businessRefs!.plan!.revision, 4);
    final secondPage = Completer<CurrentCollectionPage>();
    feed.reader.onCurrent = (_, _, _) => secondPage.future;
    final stalePage = expectLater(
      scope.pageCurrent(
        reference: _interactions(1),
        continuation: 'page-2',
        demand: _demand,
      ),
      throwsA(_stale),
    );
    await _update(fixture, 3, _refs(plan: 4, interactions: 2));
    secondPage.complete(CurrentCollectionPage(revision: 1, entries: []));
    await stalePage;
    expect(scope.isActive, isTrue);
    expect(feed.requestCloseCalls, 0);
    expect(fixture.transport.opens, hasLength(1));
    expect((await fixture.close()).complete, isTrue);
  });

  test('B10 identical refs and activity tokens do not invalidate a Plan read; explicit old version reads stay legal', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    await _baseline(fixture, _refs());
    final scope = fixture.session().content.openScope(generation: 1);
    final reply = Completer<ContentWindow>();
    feed.reader.onContent = (_, _) => reply.future;
    final reading = scope.readContent(reference: _document(3), range: _range);
    await _update(fixture, 2, _refs());
    await feed.deliver(
      ConversationActivityEvent(
        snapshot: ActivitySnapshot(
          revision: 1,
          completedThrough: 1,
          executionPresent: true,
          entries: [],
        ),
      ),
    );
    reply.complete(_window('v3'));
    expect(String.fromCharCodes((await reading).bytes), 'v3');
    await _update(fixture, 3, _refs(plan: 4));
    feed.reader.onContent = (reference, _) async {
      expect(reference, _document(3));
      return _window('original v3');
    };
    expect(
      String.fromCharCodes(
        (await scope.readContent(reference: _document(3), range: _range)).bytes,
      ),
      'original v3',
    );
    expect((await fixture.close()).complete, isTrue);
  });

  test('B10 Plan replacement closes only its original content watch and retains unrelated body watch', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    await _baseline(fixture, _refs());
    final scope = fixture.session().content.openScope(generation: 1);
    final planSource = StreamController<ContentWindow>();
    final bodySource = StreamController<ContentWindow>();
    final planHandle = TestContentWatch(source: planSource.stream);
    final bodyHandle = TestContentWatch(source: bodySource.stream);
    feed.reader.onWatchHandle = (ref, _) =>
        ref == _document(3) ? planHandle : bodyHandle;
    final errors = <Object>[];
    final ended = Completer<void>();
    final plan = scope
        .watchContent(reference: _document(3), range: _range)
        .listen((_) {}, onError: errors.add, onDone: ended.complete);
    const bodyRef = ContentRef(
      databaseId: 'db',
      target: ItemPayloadTarget(itemId: 'unrelated'),
    );
    final body = scope
        .watchContent(reference: bodyRef, range: _range)
        .listen((_) {});
    await _update(fixture, 2, _refs(plan: 4));
    await ended.future;
    expect(errors.single, _stale);
    expect(planHandle.closeCalls, 1);
    expect(bodyHandle.closeCalls, 0);
    expect(scope.isActive, isTrue);
    await plan.cancel();
    await body.cancel();
    await planSource.close();
    await bodySource.close();
    expect((await fixture.close()).complete, isTrue);
  });

  test('B15 resource failures preserve their exact typed error without clearing State or history', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    final refs = _refs();
    await _baseline(fixture, refs);
    final scope = fixture.session().content.openScope(generation: 1);
    const failure = StudioFailure(
      code: StudioFailureCode.storage,
      message: 'missing plan chunk',
      retryable: false,
      correlationId: 'missing-plan',
    );
    feed.reader.onContent = (_, _) => Future.error(failure);
    await expectLater(
      scope.readContent(reference: refs.plan!.document!, range: _range),
      throwsA(same(failure)),
    );
    feed.reader.onCurrent = (_, _, _) async =>
        CurrentCollectionPage(revision: 2, entries: []);
    await expectLater(
      scope.pageCurrent(reference: refs.interactions!, demand: _demand),
      throwsA(_stale),
    );
    expect(fixture.session().state.businessRefs, same(refs));
    expect(fixture.consumers['thread']!.batches, hasLength(1));
    expect(feed.requestCloseCalls, 0);
    expect((await fixture.close()).complete, isTrue);
  });

  test(
    'B16 business queries proceed while Chat acceptance holds credit',
    () async {
      final fixture = ConversationFixture();
      final consumer = ControlledBatchConsumer();
      fixture.session().content.attachConsumer(consumer, demand: _demand);
      fixture.repository.setVisibleThread('thread');
      await fixture.transport.opened(0);
      final feed = TestConversationFeed();
      fixture.transport.opens.single.result.complete(feed);
      await feed.deliver(ConversationChatEvent(batch: chatSet()));
      await _baseline(fixture, _refs());
      final scope = fixture.session().content.openScope(generation: 1);
      final gate = Completer<void>();
      consumer.onApply = (_) => gate.future;
      feed.send(
        ConversationChatEvent(
          batch: ChatBatch(
            placement: ChatPlacement.append,
            entries: [completedFixture('next', seq: 2)],
            fromSeq: 1,
            throughSeq: 2,
          ),
        ),
      );
      await consumer.waitForCount(2);
      feed.reader.onContent = (_, _) async => _window('plan');
      feed.reader.onCurrent = (ref, _, _) async =>
          CurrentCollectionPage(revision: ref.revision, entries: []);
      await Future.wait([
        scope.readContent(reference: _document(3), range: _range),
        scope.pageCurrent(reference: _interactions(1), demand: _demand),
      ]);
      expect(feed.acknowledgements, [
        1,
      ], reason: 'the gated Chat still owns the sole content credit');
      expect(fixture.stateFeed().acknowledgements, [
        1,
      ], reason: 'the state snapshot was already ACKed independently');
      gate.complete();
      await feed.acknowledged(2);
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test(
    'B17 late business read from A1 cannot replace A2 refs or close its feed',
    () async {
      final fixture = ConversationFixture();
      final old = await fixture.open(demand: _demand);
      await _baseline(fixture, _refs());
      final content = fixture.session().content;
      final scope = content.openScope(generation: 1);
      final reply = Completer<ThreadBusinessRefs>();
      old.reader.onBusinessRefs = () => reply.future;
      final rejected = expectLater(
        scope.readBusinessRefs(),
        throwsA(isA<StaleConversationScope>()),
      );
      fixture.repository.setVisibleThread('other');
      fixture.repository.setVisibleThread('thread');
      await fixture.transport.opened(1);
      final fresh = TestConversationFeed(subscriptionId: 'A2');
      fixture.transport.opens[1].result.complete(fresh);
      await fresh.deliver(ConversationChatEvent(batch: chatSet()));
      final current = _refs(plan: 4, interactions: 2);
      await _baseline(fixture, current);
      reply.complete(_refs(plan: 99, interactions: 99));
      await rejected;
      expect((await content.joinRetired()).complete, isTrue);
      expect(fixture.session().state.businessRefs, same(current));
      expect(fresh.requestCloseCalls, 0);
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test('B12/B13 refs and collection pages do not rewrite the actionable interaction owner or storage state', () async {
    final fixture = ConversationFixture();
    await fixture.open(demand: _demand);
    const pending = PendingInteraction(
      id: 'question',
      threadId: 'thread',
      turnId: 'turn',
      kind: InteractionKind.userInput,
      title: 'question',
      body: 'original',
    );
    await fixture.stateFeed().deliver(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: completedHistoryVersion,
          workspace: _workspace(_refs()).copyWith(interactions: [pending]),
        ),
      ),
    );
    await _update(fixture, 2, _none);
    expect(fixture.session().state.interactions.single, same(pending));
    await fixture.stateFeed().deliver(
      ConversationStateEvent(
        frame: const ThreadNotificationFrame(
          threadId: 'thread',
          epoch: 1,
          baseRevision: 2,
          revision: 3,
          update: ThreadStorageUpdate(
            storage: ThreadStorageStateView(durableSequence: 1),
          ),
        ),
      ),
    );
    expect(fixture.session().state.businessRefs, _none);
    expect(fixture.session().state.interactions.single, same(pending));
    expect(fixture.consumers['thread']!.batches, hasLength(1));
    expect(fixture.transport.opens, hasLength(1));
    expect((await fixture.close()).complete, isTrue);
  });

  test('B18 readBusinessRefs is an explicit read, never an automatic State repair or second writer', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    await _baseline(fixture, _none);
    var calls = 0;
    final refs = _refs();
    feed.reader.onBusinessRefs = () async {
      calls++;
      return refs;
    };
    final scope = fixture.session().content.openScope(generation: 1);
    expect(await scope.readBusinessRefs(), same(refs));
    expect(calls, 1);
    expect(fixture.session().state.businessRefs, _none);
    expect((await fixture.close()).complete, isTrue);
  });

  for (final version in <int?>[null, 16, 18]) {
    test(
      'State schemaVersion=$version is rejected before baseline publication',
      () async {
        final fixture = ConversationFixture();
        final feed = await fixture.open(demand: _demand);
        final state = fixture.stateFeed();
        final failed = fixture.session().source.waitFor(
          (value) =>
              value.sync.phase == DomainSyncPhase.failed &&
              value.sync.retryExhausted,
        );
        state.send(
          ConversationStateEvent(
            frame: ThreadSnapshotFrame(
              schemaVersion: version,
              completedHistoryVersion: completedHistoryVersion,
              workspace: _workspace(_refs()),
            ),
          ),
        );
        await failed;
        expect(
          fixture.session().state.sync.errorMessage,
          allOf(
            contains('ProtocolVersionMismatch'),
            contains('threadSchemaVersion=$version'),
          ),
        );
        expect(fixture.session().state.businessRefs, isNull);
        expect(state.acknowledgements, isEmpty);
        expect(feed.acknowledgements, [1]);
        expect(
          feed.requestCloseCalls,
          0,
          reason: 'a state rejection never retires the content owner',
        );
        expect((await fixture.close()).complete, isTrue);
      },
    );
  }

  test('Inbox source preserves both original identities without reinterpreting content or authority', () {
    const source = InboxMessageChatSource(
      sourceId: 'platform/account/chat',
      messageId: 'event',
    );
    expect(chatSourceIdToJson(source), {
      'kind': 'inboxMessage',
      'sourceId': 'platform/account/chat',
      'messageId': 'event',
    });
    expect(
      source,
      const InboxMessageChatSource(
        sourceId: 'platform/account/chat',
        messageId: 'event',
      ),
    );
    expect(
      source,
      isNot(
        const InboxMessageChatSource(
          sourceId: 'other-account',
          messageId: 'event',
        ),
      ),
    );
  });
}

ThreadWorkspace _workspace(ThreadBusinessRefs refs) => ThreadWorkspace(
  businessRefs: refs,
  thread: StudioThread(
    id: 'thread',
    workspaceId: 'workspace',
    title: 'Thread',
    mode: ThreadModeId.simple,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    updatedAt: DateTime.utc(2026),
    workspacePath: '/workspace',
  ),
  revision: 1,
  interactions: [],
  runtime: const ThreadRuntimeView(
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
