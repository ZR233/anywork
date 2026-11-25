import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 1, maxBytes: 4096);
const _historyDemand = HistoryDemand(maxRows: 2, maxBytes: 8192);
const _range = ContentRange(offset: 3, maxBytes: 11);
const _content = CurrentContentRef(
  ownerId: 'owner',
  domain: 'entity',
  entityId: 'entity-1',
  contentKey: 'body',
  generation: '7',
);
const _collection = CurrentCollectionRef(
  ownerId: 'owner',
  collection: 'atoms',
  revision: 7,
);

void main() {
  test(
    'Current and History handshakes reject their own unsupported versions',
    () async {
      final fixture = ConversationFixture();
      addTearDown(fixture.close);
      final current = TestCurrentReader(protocolVersion: 0);
      final history = TestHistoryReader(protocolVersion: 0);
      fixture.transport.currentReaderFactory = (_, _) => current;
      fixture.transport.historyReaderFactory = (_, _) => history;

      await expectLater(
        fixture.repository.openCurrentReader('thread', demand: _demand),
        throwsA(
          isA<ProtocolVersionMismatch>()
              .having((error) => error.field, 'field', 'currentProtocolVersion')
              .having((error) => error.received, 'received', 0),
        ),
      );
      await expectLater(
        fixture.repository.openHistoryReader('thread'),
        throwsA(
          isA<ProtocolVersionMismatch>()
              .having((error) => error.field, 'field', 'historyProtocolVersion')
              .having((error) => error.received, 'received', 0),
        ),
      );
      expect(current.closeCalls, 1);
      expect(history.closeCalls, 1);
    },
  );

  test('Current scope forwards typed page/body identities and close joins pending work', () async {
    final reader = TestCurrentReader(
      initialView: currentViewForWorkspace(emptyCurrentWorkspace('thread')),
    );
    final pageReply = Completer<CurrentCollectionPage>();
    final page = CurrentCollectionPage(
      revision: 7,
      entries: const [],
      continuation: 'next',
    );
    reader.onPage = (reference, continuation, demand) {
      expect(reference, _collection);
      expect(continuation, null);
      expect(demand, same(_demand));
      return pageReply.future;
    };
    final body = ContentWindow(
      offset: 3,
      bytes: Uint8List.fromList([1, 2, 3]),
      generation: '7',
      availableThrough: 14,
      sealed: true,
    );
    reader.onReadBody = (reference, range) async {
      expect(reference, _content);
      expect(range, _range);
      return body;
    };
    final scope = CurrentReadScope(
      threadId: 'thread',
      generation: 4,
      reader: reader,
      isEligible: () => !reader.requested,
    );
    final opening = scope.pageCollection(
      reference: _collection,
      demand: _demand,
    );
    final rejected = expectLater(
      opening,
      throwsA(isA<StaleConversationScope>()),
    );
    expect((await scope.readBody(reference: _content, range: _range)).bytes, [
      1,
      2,
      3,
    ]);
    final timed = await scope.close(budget: ClientCloseBudget(Duration.zero));
    expect(timed.complete, isFalse);
    pageReply.complete(page);
    await rejected;
    expect((await scope.close()).complete, isTrue);
  });

  test(
    'Current body watch preserves generation and closes its own handle',
    () async {
      final frames = StreamController<ContentWindow>();
      final reader = TestCurrentReader();
      reader.onWatchBody = (reference, range) {
        expect(reference, _content);
        expect(range, _range);
        return frames.stream;
      };
      final scope = CurrentReadScope(
        threadId: 'thread',
        generation: 1,
        reader: reader,
        isEligible: () => !reader.requested,
      );
      final watch = scope.watchBody(reference: _content, range: _range);
      final received = watch.windows.first;
      final window = ContentWindow(
        offset: 3,
        bytes: Uint8List.fromList([4, 5]),
        generation: '7',
        availableThrough: 5,
        sealed: true,
      );
      frames.add(window);
      expect((await received).generation, '7');
      await watch.close();
      await frames.close();
      expect((await scope.close()).complete, isTrue);
    },
  );

  for (final duringOpen in [true, false]) {
    test(
      'Current body ${duringOpen ? "opening" : "stream"} failure is delivered without blocking cleanup',
      () async {
        const failure = StudioFailure(
          code: StudioFailureCode.staleRevision,
          reason: StudioFailureReason.staleCurrentReference,
          message: 'Current reference expired',
          retryable: false,
          correlationId: 'expired-body',
        );
        final reader = TestCurrentReader();
        reader.onWatchBody = (_, _) {
          if (duringOpen) throw failure;
          return Stream.error(failure);
        };
        final scope = CurrentReadScope(
          threadId: 'thread',
          generation: 1,
          reader: reader,
          isEligible: () => true,
        );
        final watch = scope.watchBody(reference: _content, range: _range);
        await expectLater(watch.windows, emitsError(same(failure)));
        expect((await scope.close()).complete, isTrue);
      },
    );
  }

  test(
    'Closing a Current body watch does not require an output listener',
    () async {
      final source = StreamController<ContentWindow>();
      final reader = TestCurrentReader()..onWatchBody = (_, _) => source.stream;
      final scope = CurrentReadScope(
        threadId: 'thread',
        generation: 1,
        reader: reader,
        isEligible: () => true,
      );
      scope.watchBody(reference: _content, range: _range);
      expect((await scope.close()).complete, isTrue);
      await source.close();
    },
  );

  test(
    'History scope returns pure pages and does not mutate a presenter',
    () async {
      final reader = TestHistoryReader();
      final cut = HistoryCut('cut-7');
      final item = BoundaryTimelineItem(
        HistoryEventRecord(
          seq: 7,
          eventId: 'event-1',
          kind: 'text_completed',
          timelineRole: HistoryTimelineRole.boundary,
          recordedAt: 100,
          turnId: 'turn',
          entityId: 'entity-1',
          source: const ForegroundTurnChatSource(turnId: 'turn'),
          payloadSchema: 'anywork.chat/1',
          payloadJson: '{"version":1}',
        ),
      );
      final page = HistoryTimelinePage(cut: cut, items: [item], next: 'older');
      var reads = 0;
      reader.onTimeline = (actualCut, cursor, demand) async {
        reads++;
        expect(actualCut, same(cut));
        expect(cursor, 'cursor');
        expect(demand.maxRows, 2);
        return page;
      };
      final scope = HistoryReadScope(
        threadId: 'thread',
        generation: 2,
        reader: reader,
        isEligible: () => !reader.requested,
      );
      expect(
        await scope.timelinePage(
          cut: cut,
          cursor: 'cursor',
          demand: _historyDemand,
        ),
        same(page),
      );
      expect(reads, 1);
      expect((await scope.close()).complete, isTrue);
    },
  );

  test('History and Current reader lifetimes are independent', () async {
    final current = TestCurrentReader();
    final history = TestHistoryReader();
    final currentScope = CurrentReadScope(
      threadId: 'thread',
      generation: 1,
      reader: current,
      isEligible: () => !current.requested,
    );
    final historyScope = HistoryReadScope(
      threadId: 'thread',
      generation: 1,
      reader: history,
      isEligible: () => !history.requested,
    );
    currentScope.retire();
    await currentScope.close();
    expect(current.requestCloseCalls, 0);
    expect(history.requested, isFalse);
    await historyScope.close();
  });

  test(
    'Current pages and body windows reject retired owner or generation',
    () async {
      final current = TestCurrentReader();
      var pages = 0;
      current.onPage = (reference, continuation, demand) async {
        pages++;
        return CurrentCollectionPage(
          revision: reference.revision + 1,
          entries: const [],
        );
      };
      current.onReadBody = (reference, range) async => ContentWindow(
        offset: range.offset,
        bytes: const [1],
        generation: 'retired-generation',
        availableThrough: 1,
        sealed: true,
      );
      final scope = CurrentReadScope(
        threadId: 'thread',
        generation: 1,
        reader: current,
        isEligible: () => !current.requested,
      );

      await expectLater(
        scope.pageCollection(reference: _collection, demand: _demand),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.reason,
            'reason',
            StudioFailureReason.staleCurrentReference,
          ),
        ),
      );
      await expectLater(
        scope.readBody(reference: _content, range: _range),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.reason,
            'reason',
            StudioFailureReason.staleCurrentReference,
          ),
        ),
      );
      expect(pages, 1);
      expect((await scope.close()).complete, isTrue);
    },
  );
}
