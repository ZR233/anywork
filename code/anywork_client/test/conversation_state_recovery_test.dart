import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 1, maxBytes: 1024);

ThreadWorkspace _workspace(int revision) =>
    emptyCurrentWorkspace('thread').copyWith(revision: revision);

CurrentView _view(int revision) =>
    currentViewForWorkspace(_workspace(revision));

Future<TestCurrentReader> _open(ConversationFixture fixture) async {
  await fixture.open(demand: _demand);
  await fixture.transport.currentOpened(0);
  return fixture.currentReader();
}

Future<TestCurrentReader> _reopen(
  ConversationFixture fixture,
  int index,
) async {
  await fixture.transport
      .currentOpened(index)
      .timeout(const Duration(seconds: 4));
  return fixture.currentReader();
}

void main() {
  test('active interaction query is bounded, leaves State moving and rejects a late old page', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    final reader = await _open(fixture);
    const oldRef = CurrentCollectionRef(
      ownerId: 'owner',
      collection: 'interactions',
      revision: 1,
    );
    const nextRef = CurrentCollectionRef(
      ownerId: 'owner',
      collection: 'interactions',
      revision: 2,
    );
    final oldStarted = Completer<void>();
    final oldPage = Completer<CurrentCollectionPage>();
    final bytes = utf8.encode(
      jsonEncode(_questionRequest('new', '问题' * 18000)),
    );
    const body = CurrentContentRef(
      ownerId: 'owner',
      domain: 'collection',
      entityId: 'new',
      contentKey: 'entry',
      generation: '2',
    );
    var queries = 0;
    final offsets = <int>[];
    reader.onPage = (reference, continuation, demand) async {
      expect(demand.maxItems, 1);
      expect(demand.maxBytes, lessThanOrEqualTo(64 * 1024));
      expect(continuation, isNull);
      queries++;
      if (reference == oldRef) {
        oldStarted.complete();
        return oldPage.future;
      }
      expect(reference, nextRef);
      return CurrentCollectionPage(
        revision: nextRef.revision,
        entries: [
          CurrentCollectionEntry(
            id: 'new',
            position: 1,
            payload: DeferredCurrentPayload(
              reference: body,
              byteLength: bytes.length,
            ),
          ),
        ],
        continuation: 'unread-rest-of-collection',
      );
    };
    reader.onReadBody = (reference, range) async {
      expect(reference, body);
      expect(range.maxBytes, lessThanOrEqualTo(64 * 1024));
      offsets.add(range.offset);
      return ContentWindow(
        offset: range.offset,
        bytes: bytes.sublist(
          range.offset,
          (range.offset + range.maxBytes).clamp(0, bytes.length),
        ),
        generation: body.generation,
        availableThrough: bytes.length,
        sealed: true,
      );
    };
    await reader.deliver(ResetCurrentFrame(_interactionView(1, oldRef)));
    await oldStarted.future;
    expect(fixture.session().state.hasInteractionBaseline, isFalse);
    await reader.deliver(testCurrentEvent(frame: _progress(2)));
    expect(fixture.session().state.revision, 2);
    await reader.deliver(testCurrentEvent(frame: _interactionRefs(3, nextRef)));
    final ready = await fixture.session().source.waitFor(
      (value) => value.interactions.singleOrNull?.id == 'new',
    );
    expect(
      (ready.interactions.single.payload as UserInputInteractionPayload)
          .questions
          .single
          .question,
      '问题' * 18000,
    );
    expect(offsets.length, greaterThan(1));
    expect(ready.hasInteractionBaseline, isTrue);
    oldPage.complete(
      CurrentCollectionPage(
        revision: 1,
        entries: [
          CurrentCollectionEntry(
            id: 'old',
            position: 1,
            payload: InlineCurrentPayload(
              bytes: utf8.encode(
                jsonEncode(_questionRequest('old', 'old question')),
              ),
            ),
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(fixture.session().state.interactions.single.id, 'new');
    await reader.deliver(testCurrentEvent(frame: _interactionRefs(4, nextRef)));
    expect(fixture.session().state.interactions.single.id, 'new');
    expect(queries, 2);
    expect(fixture.transport.historyOpens, isEmpty);
    expect(reader.requested, isFalse);
  });

  test('interaction failure is visible and does not close or stall the State owner', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    final reader = await _open(fixture);
    const reference = CurrentCollectionRef(
      ownerId: 'owner',
      collection: 'interactions',
      revision: 1,
    );
    final failure = StateError('controlled interaction read failure');
    reader.onPage = (_, _, _) async => throw failure;
    await reader.deliver(ResetCurrentFrame(_interactionView(1, reference)));
    await fixture.session().source.waitFor(
      (value) => identical(value.interactionReadError, failure),
    );
    await reader.deliver(testCurrentEvent(frame: _progress(2)));
    expect(fixture.session().state.revision, 2);
    expect(fixture.session().state.interactionReadError, same(failure));
    expect(fixture.session().state.hasInteractionBaseline, isFalse);
    expect(reader.requested, isFalse);
    reader.onPage = (reference, _, _) async =>
        CurrentCollectionPage(revision: reference.revision, entries: const []);
    await reader.deliver(ResetCurrentFrame(_interactionView(3, reference)));
    await fixture.session().source.waitFor(
      (value) => value.revision == 3 && value.hasInteractionBaseline,
    );
    expect(fixture.session().state.interactions, isEmpty);
  });

  test('Current watch failures rebuild a fresh Reset baseline with bounded retries', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    var reader = await _open(fixture);
    for (var attempt = 0; attempt < 3; attempt++) {
      await reader.deliver(ResetCurrentFrame(_view(1)));
      reader.sendError(ConversationContinuityError('stream $attempt'));
      await reader.requestCloseStarted.future.timeout(
        const Duration(seconds: 2),
      );
      reader = await _reopen(fixture, attempt + 1);
    }
    await reader.deliver(ResetCurrentFrame(_view(9)));
    expect(fixture.session().state.workspace!.revision, 9);
    expect(fixture.transport.currentOpens, hasLength(4));
  });

  test(
    'late old Current reader cannot mutate the replacement generation',
    () async {
      final fixture = ConversationFixture();
      addTearDown(fixture.close);
      final old = await _open(fixture);
      await old.deliver(ResetCurrentFrame(_view(1)));
      old.sendError(ConversationContinuityError('old current broke'));
      await old.requestCloseStarted.future.timeout(const Duration(seconds: 2));
      final replacement = await _reopen(fixture, 1);
      await replacement.deliver(ResetCurrentFrame(_view(2)));
      old.send(testCurrentEvent(frame: _progress(99)));
      expect(fixture.session().state.workspace!.revision, 2);
    },
  );

  test('unsupported State schema fails without retry', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    fixture.transport.currentReaderFactory = (threadId, index) =>
        TestCurrentReader(
          threadId: threadId,
          initialView: currentViewForWorkspace(_workspace(1))
              .copyWithStateSchema(threadSchemaVersion + 1),
        );
    await fixture.open(demand: _demand);
    await fixture.transport.currentOpened(0);
    final failed = fixture.session().source.waitFor(
      (value) =>
          value.sync.phase == DomainSyncPhase.failed &&
          value.sync.retryExhausted,
    );
    await failed;
    expect(fixture.transport.currentOpens, hasLength(1));
    expect(fixture.session().state.hasSnapshot, isFalse);
  });

  test('New Current watch starts with Reset and preserves envelope order after Reset', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    final reader = await _open(fixture);
    await reader.deliver(ResetCurrentFrame(_view(1)));
    await reader.deliver(testCurrentEvent(frame: _progress(2)));
    await reader.deliver(testCurrentEvent(frame: _progress(3)));
    expect(fixture.session().state.revision, 3);
  });
}

Map<String, Object?> _questionRequest(String id, String question) => {
  'interactionId': id,
  'scope': {'threadId': 'thread', 'turnId': 'turn'},
  'revision': 7,
  'createdAt': 1,
  'updatedAt': 1,
  'content': {
    'kind': 'userInput',
    'data': {
      'questions': [
        {
          'id': 'answer',
          'header': 'Choice',
          'question': question,
          'isOther': true,
          'isSecret': false,
          'options': <Object?>[],
        },
      ],
      'state': {'kind': 'pending', 'operationId': id},
    },
  },
};

CurrentView _interactionView(int revision, CurrentCollectionRef reference) =>
    currentViewForWorkspace(
      _workspace(revision).copyWith(
        businessRefs: ThreadBusinessRefs(plan: null, interactions: reference),
      ),
      projection: CurrentProjection(
        logicalStatus: ThreadStatusView.waitingInteraction,
        executionPresent: true,
        sources: const [],
        atoms: const [],
        previews: const [],
        collections: const [],
        interactions: reference,
      ),
    );

ThreadNotificationFrame _interactionRefs(
  int revision,
  CurrentCollectionRef reference,
) => ThreadNotificationFrame(
  threadId: 'thread',
  revision: revision,
  baseRevision: revision - 1,
  epoch: 7,
  update: ThreadBusinessRefsUpdate(
    references: ThreadBusinessRefs(plan: null, interactions: reference),
  ),
);

ThreadNotificationFrame _progress(int revision) => ThreadNotificationFrame(
  threadId: 'thread',
  revision: revision,
  baseRevision: revision - 1,
  epoch: 7,
  update: const ThreadActivityUpdate(activity: null),
);

extension on CurrentView {
  CurrentView copyWithStateSchema(int schemaVersion) => CurrentView(
    revision: revision,
    state: ThreadSnapshotFrame(
      workspace: state.workspace,
      schemaVersion: schemaVersion,
    ),
    projection: projection,
  );
}
