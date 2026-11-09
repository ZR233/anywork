import 'dart:async';

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
    'I17 readCompleted does not wait for consumer acceptance or feed credit',
    () async {
      final (fixture, consumer, feed) = await _open();
      final scope = fixture.session().content.openScope(generation: 1);
      final acceptance = Completer<void>();
      consumer.onApply = (_) => acceptance.future;
      final entry = completedFixture('next', seq: 2);
      feed.send(ConversationChatEvent(batch: _append(1, 2, [entry])));
      await consumer.waitForCount(2);
      final response = Completer<CompletedEntry>();
      final entered = Completer<void>();
      feed.reader.onCompleted = (recordId, demand) {
        expect(recordId, 'detail');
        expect(demand, same(_demand));
        entered.complete();
        return response.future;
      };
      final reading = scope.readCompleted(recordId: 'detail', demand: _demand);
      await entered.future;
      final detail = completedFixture('detail');
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

  test('I20 retiring a scope joins readCompleted and rejects the late original result', () async {
    final (fixture, _, feed) = await _open();
    final content = fixture.session().content;
    final scope = content.openScope(generation: 1);
    final response = Completer<CompletedEntry>();
    feed.reader.onCompleted = (_, _) => response.future;
    final reading = scope.readCompleted(recordId: 'detail', demand: _demand);
    final rejected = expectLater(
      reading,
      throwsA(isA<StaleConversationScope>()),
    );
    fixture.repository.setVisibleThread(null);
    final partial = await content.joinRetired(deadline: DateTime.now());
    expect(partial.complete, isFalse);
    response.complete(completedFixture('detail'));
    await rejected;
    expect((await content.joinRetired()).complete, isTrue);
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

  for (final version in <int?>[null, 0, 2]) {
    test(
      'missing or unsupported completedHistoryVersion=$version fails without decoder fallback or retry',
      () async {
        final (fixture, _, feed) = await _open();
        final state = fixture.stateFeed();
        final failed = fixture.session().source.waitFor(
          (value) =>
              value.sync.phase == DomainSyncPhase.failed &&
              value.sync.retryExhausted,
        );
        state.send(
          ConversationStateEvent(
            frame: ThreadSnapshotFrame(
              schemaVersion: 17,
              completedHistoryVersion: version,
              workspace: _workspace(),
            ),
          ),
        );
        await failed;
        expect(
          fixture.session().state.sync.errorMessage,
          allOf(
            contains('ProtocolVersionMismatch'),
            contains('completedHistoryVersion=$version'),
          ),
        );
        expect(fixture.session().state.hasSnapshot, isFalse);
        expect(state.acknowledgements, isEmpty);
        expect(feed.acknowledgements, [1]);
        expect(
          feed.requestCloseCalls,
          0,
          reason: 'a state rejection never retires the content owner',
        );
        expect((await fixture.close()).complete, isTrue);
        expect(fixture.transport.opens, hasLength(1));
      },
    );
  }
}

ThreadWorkspace _workspace() => ThreadWorkspace(
  businessRefs: const ThreadBusinessRefs(plan: null, interactions: null),
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
