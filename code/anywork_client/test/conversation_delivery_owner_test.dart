import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/controlled_batch_consumer.dart';
import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 7, maxBytes: 16384);

Future<TestConversationFeed> _open(
  ConversationFixture fixture,
  ControlledBatchConsumer consumer, {
  int index = 0,
}) async {
  fixture.session().content.attachConsumer(consumer, demand: _demand);
  fixture.repository.setVisibleThread('thread');
  await fixture.transport.opened(index);
  final feed = TestConversationFeed(subscriptionId: 'sub-$index');
  fixture.transport.opens[index].result.complete(feed);
  return feed;
}

ChatBatch _append(String id) => ChatBatch(
  placement: ChatPlacement.append,
  fromSeq: 1,
  throughSeq: 2,
  entries: [chatMessage(id: id, seq: 2)],
);

void main() {
  test(
    'first Set is ready and ACKed only after actual component acceptance',
    () async {
      final fixture = ConversationFixture();
      final consumer = ControlledBatchConsumer();
      final gate = Completer<void>();
      consumer.onApply = (_) => gate.future;
      final feed = await _open(fixture, consumer);
      final content = fixture.session().content;
      final initial = chatSet();
      var ready = false;
      final readiness = content.ready.then((_) => ready = true);
      feed.send(ConversationChatEvent(batch: initial));
      await consumer.waitForCount(1);
      expect(consumer.batches.single, same(initial));
      expect(ready, isFalse);
      expect(feed.acknowledgements, isEmpty);
      gate.complete();
      await readiness;
      await feed.acknowledged(1);
      expect(content.state.value, isA<ChatReady<bool>>());
      expect(feed.eventConsumers, 1);
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test('an unaccepted Chat cannot release credit for a following State', () async {
    final fixture = ConversationFixture();
    final consumer = ControlledBatchConsumer();
    final gate = Completer<void>();
    consumer.onApply = (_) => gate.future;
    final feed = await _open(fixture, consumer);
    feed.send(ConversationChatEvent(batch: chatSet()));
    await consumer.waitForCount(1);
    // A producer violating its one-unacknowledged-frame allowance is rejected,
    // rather than queued or allowed to publish state ahead of the component.
    feed.send(
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: _workspace(),
        ),
      ),
    );
    await feed.requestCloseStarted.future;
    expect(fixture.session().state.hasSnapshot, isFalse);
    expect(feed.acknowledgements, isEmpty);
    gate.complete();
    expect((await fixture.close()).complete, isTrue);
  });

  test(
    'older IO proceeds during apply but Prepend joins the same serial consumer',
    () async {
      final fixture = ConversationFixture();
      final consumer = ControlledBatchConsumer();
      final feed = await _open(fixture, consumer);
      await feed.deliver(
        ConversationChatEvent(batch: chatSet(before: 'opaque')),
      );
      final content = fixture.session().content;
      final scope = content.openScope(generation: 2);
      final gate = Completer<void>();
      final incoming = _append('live');
      consumer.onApply = (batch) =>
          identical(batch, incoming) ? gate.future : Future.value();
      feed.send(ConversationChatEvent(batch: incoming));
      await consumer.waitForCount(2);
      final ioStarted = Completer<void>();
      final older = ChatBatch(
        placement: ChatPlacement.prepend,
        throughSeq: 1,
        entries: [chatMessage(id: 'older')],
      );
      feed.reader.onOlder = (before, demand) async {
        expect(before, 'opaque');
        expect(demand, same(_demand));
        ioStarted.complete();
        return older;
      };
      var finished = false;
      final loading = scope.loadOlder(before: 'opaque', demand: _demand).then((
        batch,
      ) {
        finished = true;
        return batch;
      });
      await ioStarted.future;
      expect(consumer.batches, hasLength(2));
      expect(finished, isFalse);
      expect(feed.acknowledgements, [1]);
      gate.complete();
      expect(await loading, same(older));
      expect(consumer.batches, [consumer.batches.first, incoming, older]);
      await feed.acknowledged(2);
      expect(feed.acknowledgements, [1, 2], reason: 'Queries do not ACK');
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test('queued older page is rejected before consumer admission when its original scope retires', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    final consumer = ControlledBatchConsumer();
    final feed = await _open(fixture, consumer);
    final initial = chatSet(before: 'opaque-before');
    await feed.deliver(ConversationChatEvent(batch: initial));
    final content = fixture.session().content;
    final scope = content.openScope(generation: 1);
    final attempt = content.currentAttemptId;
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final streamed = _append('live');
    consumer.onApply = (batch) =>
        identical(batch, streamed) ? gate.future : Future.value();
    feed.send(ConversationChatEvent(batch: streamed));
    await consumer.waitForCount(2);

    final reply = Completer<ChatBatch>();
    var reads = 0;
    feed.reader.onOlder = (before, demand) {
      expect(before, 'opaque-before');
      expect(demand, same(_demand));
      reads++;
      return reply.future;
    };
    final pageResult = expectLater(
      scope.loadOlder(before: 'opaque-before', demand: _demand),
      throwsA(isA<StaleConversationScope>()),
    );
    final older = ChatBatch(
      placement: ChatPlacement.prepend,
      throughSeq: 1,
      entries: [chatMessage(id: 'retired-page')],
    );
    reply.complete(older);
    // The SDK reader's await was registered first on this very Future. Its
    // continuation enqueues Prepend before this later completion waiter resumes;
    // the component gate keeps that admission queued, not its IO in flight.
    await reply.future;
    expect(reads, 1);
    expect(scope.isActive, isTrue);
    expect(scope.pendingQueries, 1);
    expect(consumer.batches, [initial, streamed]);

    scope.retire();
    expect(scope.isActive, isFalse);
    expect(content.currentAttemptId, attempt);
    expect(content.hasDemand, isTrue);
    expect(feed.requestCloseCalls, 0);
    gate.complete();
    await pageResult;
    await feed.acknowledged(2);
    expect(
      consumer.batches,
      [initial, streamed],
      reason: 'Stale after applying Prepend is too late: no consumer write is allowed',
    );
    expect(feed.acknowledgements, [1, 2]);
    expect(content.currentAttemptId, attempt);
    expect(feed.requestCloseCalls, 0);
    expect((await scope.close()).complete, isTrue);
    expect((await fixture.close()).complete, isTrue);
  });

  test('loadOlder Future includes Prepend component acceptance', () async {
    final fixture = ConversationFixture();
    final consumer = ControlledBatchConsumer();
    final feed = await _open(fixture, consumer);
    await feed.deliver(ConversationChatEvent(batch: chatSet()));
    final scope = fixture.session().content.openScope(generation: 1);
    final older = ChatBatch(
      placement: ChatPlacement.prepend,
      throughSeq: 1,
      entries: [],
    );
    feed.reader.onOlder = (_, __) async => older;
    final gate = Completer<void>();
    consumer.onApply = (_) => gate.future;
    var finished = false;
    final loading = scope.loadOlder(before: 'before', demand: _demand).then((
      batch,
    ) {
      finished = true;
      return batch;
    });
    await consumer.waitForCount(2);
    expect(finished, isFalse);
    expect(scope.pendingQueries, 1);
    gate.complete();
    expect(await loading, same(older));
    expect(feed.acknowledgements, [1]);
    expect((await fixture.close()).complete, isTrue);
  });

  for (final terminal in <ConversationEvent>[
    const ConversationClosedEvent(),
    const ConversationFailureEvent(
      failure: StudioFailure(
        code: StudioFailureCode.internal,
        message: 'producer failed',
        retryable: false,
        correlationId: 'terminal',
      ),
    ),
  ]) {
    for (final beforeData in [true, false]) {
      test(
        '${terminal.runtimeType} accepts ${beforeData ? 'zero' : 'last sent'} sequence without ACK',
        () async {
          final fixture = ConversationFixture();
          final consumer = ControlledBatchConsumer();
          final feed = await _open(fixture, consumer);
          if (!beforeData) {
            await feed.deliver(ConversationChatEvent(batch: chatSet()));
          }
          feed.send(terminal);
          await feed.requestCloseStarted.future;
          expect(feed.acknowledgements, beforeData ? isEmpty : [1]);
          expect(
            fixture.session().content.state.value,
            isA<ChatReconnecting<bool>>(),
          );
          expect((await fixture.close()).complete, isTrue);
        },
      );
    }

    test(
      '${terminal.runtimeType} revokes in-flight acceptance before current and ACK',
      () async {
        final fixture = ConversationFixture();
        final consumer = ControlledBatchConsumer();
        final gate = Completer<void>();
        consumer.onApply = (_) => gate.future;
        final feed = await _open(fixture, consumer);
        feed.send(ConversationChatEvent(batch: chatSet()));
        await consumer.waitForCount(1);
        feed.send(terminal);
        await feed.requestCloseStarted.future;
        final closing = fixture.close(deadline: DateTime.now());
        expect((await closing).complete, isFalse);
        gate.complete();
        expect((await fixture.client.retryCleanup()).complete, isTrue);
        expect(feed.acknowledgements, isEmpty);
      },
    );
  }

  test('detached pending consumer is joined and never ACKs or publishes into its replacement', () async {
    final fixture = ConversationFixture();
    final content = fixture.session().content;
    final old = ControlledBatchConsumer();
    final oldGate = Completer<void>();
    old.onApply = (_) => oldGate.future;
    final lease = content.attachConsumer(old, demand: _demand);
    fixture.repository.setVisibleThread('thread');
    await fixture.transport.opened(0);
    final first = TestConversationFeed();
    fixture.transport.opens[0].result.complete(first);
    first.send(ConversationChatEvent(batch: chatSet()));
    await old.waitForCount(1);
    lease.cancel();
    final next = ControlledBatchConsumer();
    content.attachConsumer(next, demand: _demand);
    await fixture.transport.opened(1);
    final second = TestConversationFeed(subscriptionId: 'replacement');
    fixture.transport.opens[1].result.complete(second);
    final replacement = chatSet(messages: [chatMessage(id: 'replacement')]);
    await second.deliver(ConversationChatEvent(batch: replacement));
    final report = await content.joinRetired(deadline: DateTime.now());
    expect(report.complete, isFalse);
    oldGate.complete();
    expect((await content.joinRetired()).complete, isTrue);
    expect(first.acknowledgements, isEmpty);
    expect(next.batches, [replacement]);
    expect(second.requestCloseCalls, 0);
    expect((await fixture.close()).complete, isTrue);
  });

  test('detach does not reopen until a new real consumer attaches', () async {
    final fixture = ConversationFixture();
    final content = fixture.session().content;
    final consumer = ControlledBatchConsumer();
    final lease = content.attachConsumer(consumer, demand: _demand);
    fixture.repository.setVisibleThread('thread');
    await fixture.transport.opened(0);
    final feed = TestConversationFeed();
    fixture.transport.opens[0].result.complete(feed);
    await feed.deliver(ConversationChatEvent(batch: chatSet()));
    lease.cancel();
    await feed.closeCompleted.future;
    expect((await content.joinRetired()).complete, isTrue);
    expect(fixture.transport.opens, hasLength(1));
    expect(content.state.value, isA<ChatIdle<bool>>());
    content.attachConsumer(ControlledBatchConsumer(), demand: _demand);
    await fixture.transport.opened(1);
    fixture.transport.opens[1].result.complete(
      TestConversationFeed(subscriptionId: 'next'),
    );
    expect((await fixture.close()).complete, isTrue);
  });

  test(
    'consumer rejection propagates and cannot publish current or ACK',
    () async {
      final fixture = ConversationFixture();
      final consumer = ControlledBatchConsumer();
      final failure = StateError('component rejected');
      consumer.onApply = (_) => Future.error(failure);
      final feed = await _open(fixture, consumer);
      final failed = fixture.session().content.state.waitFor(
        (state) => state is ChatReconnecting<bool>,
      );
      feed.send(ConversationChatEvent(batch: chatSet()));
      expect((await failed as ChatReconnecting<bool>).error, same(failure));
      expect(feed.acknowledgements, isEmpty);
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test('ACK error retires the accepted feed and leaves native cleanup responsibility', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    final error = StateError('ACK failed');
    feed.ackFailure = error;
    feed.closeFailure = StateError('join failed');
    feed.send(ConversationChatEvent(batch: _append('accepted')));
    await feed.requestCloseStarted.future;
    expect(
      (fixture.consumers['thread']!.batches.last.entries.single).recordId,
      'accepted',
    );
    expect(feed.acknowledgements, [1]);
    expect((await fixture.close()).complete, isFalse);
    feed.closeFailure = null;
    expect((await fixture.client.retryCleanup()).complete, isTrue);
    expect(feed.closeCalls, 2);
    expect(fixture.transport.opens, hasLength(1));
  });

  test('private reader close failure retains original facade responsibility for retry', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    final failure = StateError('reader join failed');
    feed.reader.closeFailure = failure;
    final report = await fixture.close();
    expect(report.complete, isFalse);
    expect(
      report.unresolved.any((entry) => identical(entry.reason, failure)),
      isTrue,
    );
    expect(feed.closeCompleted.isCompleted, isFalse);
    expect(feed.reader.closeCalls, 1);
    feed.reader.closeFailure = null;
    expect((await fixture.client.retryCleanup()).complete, isTrue);
    expect(feed.reader.closeCalls, 2);
    expect(feed.closeCompleted.isCompleted, isTrue);
    expect(fixture.transport.opens, hasLength(1));
  });

  test('cleanup retries retired facade but excludes healthy active feed and reader', () async {
    final fixture = ConversationFixture();
    final first = await fixture.open(demand: _demand);
    first.closeFailure = StateError('old native close failed');
    fixture.repository.setVisibleThread(null);
    expect((await fixture.session().content.joinRetired()).complete, isFalse);
    fixture.repository.setVisibleThread('thread');
    await fixture.transport.opened(1);
    final second = TestConversationFeed(subscriptionId: 'healthy');
    fixture.transport.opens[1].result.complete(second);
    await second.deliver(ConversationChatEvent(batch: chatSet()));
    expect((await fixture.repository.retryCleanup()).complete, isFalse);
    expect(second.requestCloseCalls, 0);
    expect(second.reader.closeCalls, 0);
    first.closeFailure = null;
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(second.requestCloseCalls, 0);
    expect(second.reader.closeCalls, 0);
    expect(fixture.session().content.state.value, isA<ChatReady<bool>>());
    expect((await fixture.close()).complete, isTrue);
  });
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
