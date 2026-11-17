import 'dart:async';

import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/controlled_batch_consumer.dart';
import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 1, maxBytes: 16384);

ChatAtom _atom(
  String id, {
  ChatAtomKind kind = ChatAtomKind.toolCall,
  String? callId = 'call',
  bool background = false,
  bool terminal = false,
  ChatTerminalOutcome outcome = ChatTerminalOutcome.completed,
  ChatDeliveryKind delivery = ChatDeliveryKind.foreground,
}) => ChatAtom(
  id: id,
  attemptId: 'attempt',
  source: background
      ? const BackgroundResultChatSource(messageId: 'background-result')
      : const ForegroundTurnChatSource(turnId: 'turn'),
  sourceOrder: null,
  kind: kind,
  delivery: delivery,
  tool: callId == null
      ? null
      : ChatToolIdentity(callId: callId, name: 'same-name'),
  lifecycle: terminal
      ? TerminalChatAtom(started: null, ended: null, outcome: outcome)
      : const ActiveChatAtom(started: null, status: ChatActiveStatus.waiting),
  contents: [],
);

ActivitySnapshot _snapshot(
  int revision,
  int through,
  List<ActivityEntry> entries,
) => ActivitySnapshot(
  revision: revision,
  completedThrough: through,
  executionPresent: true,
  entries: entries,
);

ChatBatch _append(int from, int through, List<CompletedEntry> entries) =>
    ChatBatch(
      placement: ChatPlacement.append,
      fromSeq: from,
      throughSeq: through,
      entries: entries,
    );

Future<(ConversationFixture, ControlledBatchConsumer, TestConversationFeed)>
_open() async {
  final fixture = ConversationFixture();
  final consumer = ControlledBatchConsumer();
  fixture.session().content.attachConsumer(consumer, demand: _demand);
  fixture.repository.setVisibleThread('thread');
  await fixture.transport.opened(0);
  final feed = TestConversationFeed();
  fixture.transport.opens.single.result.complete(feed);
  await feed.deliver(ConversationChatEvent(batch: chatSet()));
  return (fixture, consumer, feed);
}

void main() {
  test(
    'I17 History readEvent does not wait for content acceptance or feed credit',
    () async {
      final (fixture, consumer, feed) = await _open();
      final history = await fixture.repository.openHistoryReader(
        'thread',
      ) as TestHistoryReader;
      addTearDown(history.close);
      final acceptance = Completer<void>();
      consumer.onApply = (_) => acceptance.future;
      final entry = completedFixture('next', seq: 2);
      feed.send(ConversationChatEvent(batch: _append(1, 2, [entry])));
      await consumer.waitForCount(2);
      final response = Completer<HistoryEventDetail>();
      final entered = Completer<void>();
      history.onEvent = (String eventId, HistoryDemand demand) {
        expect(eventId, 'detail');
        expect(demand.maxRows, 1);
        expect(demand.maxBytes, 16384);
        entered.complete();
        return response.future;
      };
      final reading = history.readEvent(
        eventId: 'detail',
        demand: const HistoryDemand(maxRows: 1, maxBytes: 16384),
      );
      await entered.future;
      final detail = HistoryEventDetail(
        header: HistoryEventHeader(
          seq: 1,
          eventId: 'detail',
          kind: 'entity_ended',
          recordedAt: 0,
        ),
      );
      response.complete(detail);
      expect(await reading, same(detail));
      expect(feed.acknowledgements, [1]);
      expect(consumer.batches, hasLength(2));
      acceptance.complete();
      await feed.acknowledged(2);
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test('I18/I21 split handoff and background result retire precise activity after acceptance', () async {
    final (fixture, consumer, feed) = await _open();
    final foreground = ActivityEntry(
      identity: const ForegroundToolActivityIdentity(callId: 'call'),
      atom: _atom('fg'),
    );
    final background = ActivityEntry(
      identity: const BackgroundToolActivityIdentity(callId: 'call'),
      atom: _atom('bg', background: true),
    );
    final initial = _snapshot(1, 1, [foreground, background]);
    await feed.deliver(ConversationActivityEvent(snapshot: initial));
    final gate = Completer<void>();
    consumer.onApply = (_) => gate.future;
    final handoff = completedFixture(
      'handoff',
      seq: 2,
      atom: _atom(
        'fg',
        terminal: true,
        delivery: ChatDeliveryKind.backgroundHandoff,
        outcome: ChatTerminalOutcome.transferred,
      ),
    );
    feed.send(ConversationChatEvent(batch: _append(1, 2, [handoff])));
    await consumer.waitForCount(2);
    expect(fixture.session().activity.value, same(initial));
    expect(feed.acknowledgements, [1, 2]);
    gate.complete();
    await feed.acknowledged(3);
    expect(fixture.session().activity.value!.entries, [background]);
    // A delayed snapshot from before completion cannot restore the foreground call.
    await feed.deliver(
      ConversationActivityEvent(
        snapshot: _snapshot(2, 1, [foreground, background]),
      ),
    );
    expect(fixture.session().activity.value!.entries, [background]);
    consumer.onApply = null;
    final result = completedFixture(
      'result',
      seq: 3,
      atom: _atom('bg', terminal: true, background: true),
    );
    await feed.deliver(ConversationChatEvent(batch: _append(2, 3, [result])));
    expect(fixture.session().activity.value!.entries, isEmpty);
    expect(consumer.batches.skip(1).expand((batch) => batch.entries), [
      handoff,
      result,
    ]);
    await feed.deliver(
      ConversationActivityEvent(snapshot: _snapshot(3, 3, [])),
    );
    expect(fixture.session().activity.value!.revision, 3);
    expect((await fixture.close()).complete, isTrue);
  });

  test('empty Append advances the barrier without inserting or changing query cursor', () async {
    final (fixture, consumer, feed) = await _open();
    final gate = Completer<void>();
    consumer.onActivity = (_) => gate.future;
    await feed.deliver(ConversationChatEvent(batch: _append(1, 9, [])));
    expect(consumer.batches, hasLength(1));
    final snapshot = _snapshot(1, 9, []);
    final entered = Completer<void>();
    consumer.onActivity = (_) {
      entered.complete();
      return gate.future;
    };
    feed.send(ConversationActivityEvent(snapshot: snapshot));
    await entered.future;
    expect(feed.acknowledgements, [1, 2]);
    expect(fixture.session().activity.value, isNull);
    gate.complete();
    await feed.acknowledged(3);
    expect(fixture.session().activity.value, same(snapshot));
    expect((await fixture.close()).complete, isTrue);
  });

  test('I19 activity-only updates leave the accepted history window untouched and reject revision rollback', () async {
    final (fixture, consumer, feed) = await _open();
    for (var revision = 1; revision <= 30; revision++) {
      await feed.deliver(
        ConversationActivityEvent(snapshot: _snapshot(revision, 1, [])),
      );
    }
    final latest = fixture.session().activity.value;
    await feed.deliver(
      ConversationActivityEvent(snapshot: _snapshot(29, 1, [])),
    );
    expect(fixture.session().activity.value, same(latest));
    expect(consumer.batches, hasLength(1));
    expect(consumer.activities, hasLength(30));
    expect((await fixture.close()).complete, isTrue);
  });

  test('future activity barrier fails without compensation query or premature activity acceptance', () async {
    final (fixture, consumer, feed) = await _open();
    feed.send(ConversationActivityEvent(snapshot: _snapshot(1, 2, [])));
    await feed.requestCloseStarted.future;
    expect(consumer.activities, isEmpty);
    expect(feed.acknowledgements, [1]);
    expect((await fixture.close()).complete, isTrue);
  });

  test('I20 retiring a History scope rejects its late read without closing the History owner', () async {
    final (fixture, _, feed) = await _open();
    final history = await fixture.repository.openHistoryReader(
      'thread',
    ) as TestHistoryReader;
    addTearDown(history.close);
    final scope = HistoryReadScope(
      threadId: 'thread',
      generation: 1,
      reader: history,
      isEligible: () => true,
    );
    final response = Completer<HistoryEventDetail>();
    history.onEvent = (String _, HistoryDemand _) => response.future;
    final reading = scope.readEvent(
      eventId: 'detail',
      demand: const HistoryDemand(maxRows: 1, maxBytes: 16384),
    );
    final rejected = expectLater(
      reading,
      throwsA(isA<StaleConversationScope>()),
    );
    final partial = await scope.close(budget: ClientCloseBudget(Duration.zero));
    expect(partial.complete, isFalse);
    response.complete(
      HistoryEventDetail(
        header: HistoryEventHeader(
          seq: 1,
          eventId: 'detail',
          kind: 'entity_ended',
          recordedAt: 0,
        ),
      ),
    );
    await rejected;
    expect((await scope.close()).complete, isTrue);
    expect(history.requestCloseCalls, 0);
    expect(feed.requestCloseCalls, 0);
    expect((await fixture.close()).complete, isTrue);
  });

  test(
    'I20 late Activity acceptance from A1 cannot overwrite or ACK A2',
    () async {
      final (fixture, consumer, old) = await _open();
      final content = fixture.session().content;
      final gate = Completer<void>();
      final entered = Completer<void>();
      consumer.onActivity = (_) {
        entered.complete();
        return gate.future;
      };
      old.send(ConversationActivityEvent(snapshot: _snapshot(90, 1, [])));
      await entered.future;
      fixture.repository.setVisibleThread('other');
      fixture.repository.setVisibleThread('thread');
      await fixture.transport.opened(1);
      final fresh = TestConversationFeed(subscriptionId: 'A2');
      fixture.transport.opens[1].result.complete(fresh);
      await fresh.deliver(ConversationChatEvent(batch: chatSet()));
      consumer.onActivity = null;
      final current = _snapshot(1, 1, []);
      await fresh.deliver(ConversationActivityEvent(snapshot: current));
      gate.complete();
      expect((await content.joinRetired()).complete, isTrue);
      expect(content.activity.value, same(current));
      expect(old.acknowledgements, [1]);
      expect(fresh.acknowledgements, [1, 2]);
      expect((await fixture.close()).complete, isTrue);
    },
  );

  for (final kind in [ChatAtomKind.plan, ChatAtomKind.interaction]) {
    for (final outcome in [
      ChatTerminalOutcome.failed,
      ChatTerminalOutcome.cancelled,
    ]) {
      test(
        'I22 $kind $outcome retains typed call identity without executing business commands',
        () async {
          final (fixture, _, feed) = await _open();
          final pending = ActivityEntry(
            identity: const ForegroundToolActivityIdentity(callId: 'call'),
            atom: _atom('pending', kind: kind),
          );
          await feed.deliver(
            ConversationActivityEvent(snapshot: _snapshot(1, 1, [pending])),
          );
          final completion = completedFixture(
            'finished',
            seq: 2,
            atom: _atom(
              'pending',
              kind: kind,
              terminal: true,
              outcome: outcome,
            ),
          );
          await feed.deliver(
            ConversationChatEvent(batch: _append(1, 2, [completion])),
          );
          expect(fixture.session().activity.value!.entries, isEmpty);
          expect((await fixture.close()).complete, isTrue);
        },
      );
    }
  }
}
