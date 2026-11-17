import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 2, maxBytes: 4096);
const _range = ContentRange(offset: 0, maxBytes: 100);

ThreadWorkspace _workspace(int revision, ThreadBusinessRefs refs) =>
    emptyCurrentWorkspace('thread')
        .copyWith(revision: revision, businessRefs: refs);

ThreadBusinessRefs _refs({int plan = 3, int interactions = 1}) =>
    ThreadBusinessRefs(
      plan: CurrentPlanHead(
        revision: plan,
        phase: PlanRuntimePhase.drafting,
        document: CurrentContentRef(
          ownerId: 'owner',
          domain: 'plan',
          entityId: 'thread',
          contentKey: 'plan.document',
          generation: '$plan',
        ),
      ),
      interactions: CurrentCollectionRef(
        ownerId: 'owner',
        collection: 'interactions',
        revision: interactions,
      ),
    );

CurrentProjection _projection(ThreadBusinessRefs refs) => CurrentProjection(
  logicalStatus: ThreadStatusView.idle,
  executionPresent: false,
  sources: const [],
  atoms: const [],
  plan: refs.plan,
  interactions: refs.interactions,
  previews: const [],
  collections: [if (refs.interactions case final interactions?) interactions],
);

ContentWindow _window(String content, {String generation = 'sealed'}) =>
    ContentWindow(
      offset: 0,
      bytes: utf8.encode(content),
      generation: generation,
      availableThrough: utf8.encode(content).length,
      sealed: true,
    );

CurrentView _view(int revision, ThreadBusinessRefs refs) {
  final workspace = _workspace(revision, refs);
  return currentViewForWorkspace(workspace, projection: _projection(refs));
}

void main() {
  test('Current State owns refs while Plan and interaction pages use typed Current bodies', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    await fixture.open(demand: _demand);
    final refs = _refs();
    final current = fixture.currentReader();
    await current.deliver(ResetCurrentFrame(_view(1, refs)));
    expect(fixture.session().state.businessRefs, same(refs));

    final body = Completer<ContentWindow>();
    final page = Completer<CurrentCollectionPage>();
    current.onReadBody = (reference, range) {
      expect(reference, refs.plan!.document);
      expect(range, _range);
      return body.future;
    };
    current.onPage = (reference, continuation, demand) {
      expect(reference, refs.interactions);
      expect(continuation, 'page-2');
      expect(demand, same(_demand));
      return page.future;
    };
    final scope = CurrentReadScope(
      threadId: 'thread',
      generation: 1,
      reader: current,
      isEligible: () => true,
    );
    final reading = scope.readBody(
      reference: refs.plan!.document!,
      range: _range,
    );
    final paging = scope.pageCollection(
      reference: refs.interactions!,
      continuation: 'page-2',
      demand: _demand,
    );
    body.complete(_window('plan v3', generation: '3'));
    page.complete(
      CurrentCollectionPage(
        revision: 1,
        entries: const [],
        continuation: 'page-3',
      ),
    );
    expect(utf8.decode((await reading).bytes), 'plan v3');
    expect((await paging).continuation, 'page-3');
    expect(fixture.transport.opens, hasLength(1));
  });

  test('retired Current scope rejects late body and page results while content feed stays open', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    final feed = await fixture.open(demand: _demand);
    final refs = _refs();
    final current = fixture.currentReader();
    await current.deliver(ResetCurrentFrame(_view(1, refs)));
    final body = Completer<ContentWindow>();
    final page = Completer<CurrentCollectionPage>();
    current.onReadBody = (_, _) => body.future;
    current.onPage = (_, _, _) => page.future;
    final scope = CurrentReadScope(
      threadId: 'thread',
      generation: 1,
      reader: current,
      isEligible: () => true,
    );
    final reading = expectLater(
      scope.readBody(reference: refs.plan!.document!, range: _range),
      throwsA(isA<StaleConversationScope>()),
    );
    final paging = expectLater(
      scope.pageCollection(reference: refs.interactions!, demand: _demand),
      throwsA(isA<StaleConversationScope>()),
    );
    scope.retire();
    body.complete(_window('late plan'));
    page.complete(CurrentCollectionPage(revision: 1, entries: const []));
    await Future.wait([reading, paging]);
    expect(feed.requestCloseCalls, 0);
    expect(fixture.session().state.businessRefs, same(refs));
  });

  test(
    'Current collection body reads keep collection owner and generation',
    () async {
      final fixture = ConversationFixture();
      addTearDown(fixture.close);
      await fixture.open(demand: _demand);
      final refs = _refs();
      final current = fixture.currentReader();
      await current.deliver(ResetCurrentFrame(_view(1, refs)));
      const reference = CurrentContentRef(
        ownerId: 'owner',
        domain: 'collection:interactions',
        entityId: 'interaction-1',
        contentKey: 'entry',
        generation: '1',
      );
      current.onReadBody = (actual, range) async {
        expect(actual, reference);
        return _window(
          '{"interactionId":"interaction-1"}',
          generation: reference.generation,
        );
      };
      final scope = CurrentReadScope(
        threadId: 'thread',
        generation: 1,
        reader: current,
        isEligible: () => !current.requested,
      );
      final window = await scope.readBody(reference: reference, range: _range);
      expect(utf8.decode(window.bytes), contains('interaction-1'));
      expect(window.generation, reference.generation);
    },
  );

  test('new Current baseline replaces business refs without touching content reader', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    final feed = await fixture.open(demand: _demand);
    final current = fixture.currentReader();
    await current.deliver(ResetCurrentFrame(_view(1, _refs())));
    final next = _refs(plan: 4, interactions: 2);
    await current.deliver(
      NotificationCurrentFrame(
        revision: const CurrentRevision(ownerId: 'owner', revision: 2),
        notification: ThreadNotificationFrame(
          threadId: 'thread',
          epoch: 1,
          baseRevision: 1,
          revision: 2,
          update: ThreadBusinessRefsUpdate(references: next),
        ),
      ),
    );
    expect(fixture.session().state.businessRefs, same(next));
    expect(feed.requestCloseCalls, 0);
    expect(fixture.transport.opens, hasLength(1));
  });

  test(
    'unsupported Current protocol is rejected without publishing State',
    () async {
      final fixture = ConversationFixture();
      addTearDown(fixture.close);
      final feed = await fixture.open(demand: _demand);
      final failed = fixture.session().source.waitFor(
        (value) =>
            value.sync.phase == DomainSyncPhase.failed &&
            value.sync.retryExhausted,
      );
      final current = fixture.currentReader();
      final before = fixture.session().state.businessRefs;
      final view = _view(1, _refs());
      current.sendError(
        const ProtocolVersionMismatch(
          received: 0,
          supported: currentProtocolVersion,
          field: 'currentProtocolVersion',
        ),
      );
      await failed;
      expect(fixture.session().state.businessRefs, same(before));
      expect(feed.requestCloseCalls, 0);
      expect(view.state.schemaVersion, threadSchemaVersion);
    },
  );
}
