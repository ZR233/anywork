import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 20, maxBytes: 65536);

ChatBatch _appendMessage(String id, {int from = 1}) => ChatBatch(
  placement: ChatPlacement.append,
  fromSeq: from,
  throughSeq: from + 1,
  entries: [chatMessage(id: id, seq: from + 1)],
);

void main() {
  for (final label in <String?>[
    'protocolVersionMismatch',
    null,
    'someFutureReason',
  ]) {
    test(
      'backend Protocol reason=$label controls version retry without parsing text',
      () async {
        final timers = _RetryTimers();
        await runZoned(() async {
          final fixture = ConversationFixture();
          final feed = await fixture.open(demand: _demand);
          await fixture.transport.productTopicOpened(
            const ThreadMcpTopic(threadId: 'thread'),
          );
          // Settle the unrelated MCP stability timer before inspecting retries.
          await timers.fireNext();
          final content = fixture.session().content;
          final failure = StudioFailure(
            code: StudioFailureCode.protocol,
            reason: StudioFailureReason.fromLabel(label),
            message: 'ProtocolVersionMismatch',
            retryable: false,
            correlationId: 'backend-content-version',
            detailsJson: label == null ? null : '{"reason":"$label"}',
          );
          final stopped = content.state.waitFor(
            (state) =>
                state is ChatFailed<bool> || state is ChatReconnecting<bool>,
          );
          feed.send(ConversationFailureEvent(failure: failure));
          final state = await stopped;
          expect((await content.joinRetired()).complete, isTrue);
          expect(feed.acknowledgements, [1]);
          if (label == 'protocolVersionMismatch') {
            expect((state as ChatFailed<bool>).error, same(failure));
            expect(timers.hasPending, isFalse);
            expect(fixture.transport.opens, hasLength(1));
          } else {
            expect((state as ChatReconnecting<bool>).error, same(failure));
            expect(timers.hasPending, isTrue);
            await timers.fireNext();
            await fixture.transport.opened(1);
            fixture.transport.opens[1].result.complete(
              TestConversationFeed(subscriptionId: 'protocol-retry'),
            );
          }
          expect((await fixture.close()).complete, isTrue);
        }, zoneSpecification: timers.specification);
      },
    );
  }

  test('Main and multiple independently expanded details read and close concurrently', () async {
    final fixture = ConversationFixture();
    final main = await fixture.open(demand: _demand);
    final details = <ConversationContent>[];
    final feeds = <TestConversationFeed>[];
    for (var index = 0; index < 4; index++) {
      final content = await fixture.repository.openRecords(
        threadId: 'thread',
        scope: ChatScope.conversation(parentId: 'parent-$index'),
        demand: _demand,
      );
      details.add(content);
      content.attachConsumer(TestCompletionConsumer(), demand: _demand);
      await fixture.transport.opened(index + 1);
      final opening = fixture.transport.opens[index + 1];
      final feed = TestConversationFeed(
        threadId: 'thread',
        subscriptionId: 'detail-$index',
      );
      feeds.add(feed);
      opening.result.complete(feed);
      await feed.deliver(ConversationChatEvent(batch: chatSet(messages: [])));
      expect(content.state.value, isA<ChatReady<bool>>());
    }
    expect(main.eventConsumers, 1);
    expect(feeds.every((feed) => feed.eventConsumers == 1), isTrue);
    feeds.first.closeGate = Completer<void>();
    final closing = details.first.close();
    await feeds.first.closeStarted.future;
    expect(details.first.ownedAttemptCount, 1);
    expect(feeds.first.closeCompleted.isCompleted, isFalse);
    expect(details.last.state.value, isA<ChatReady<bool>>());
    feeds.first.closeGate!.complete();
    expect((await closing).complete, isTrue);
    expect(details.first.ownedAttemptCount, 0);
    expect(main.eventConsumers, 1);
    expect((await fixture.close()).complete, isTrue);
    expect(main.closeCompleted.isCompleted, isTrue);
    expect(feeds.every((feed) => feed.closeCompleted.isCompleted), isTrue);
    expect(details.every((content) => content.ownedAttemptCount == 0), isTrue);
  });
  test('repository retryCleanup honors expired absolute deadline and preserves original native join', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    feed.closeGate = Completer<void>();
    fixture.repository.setVisibleThread(null);
    await feed.closeStarted.future;
    final expired = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final first = await fixture.repository.retryCleanup(deadline: expired);
    expect(first.complete, isFalse);
    expect(
      first.unresolved.map((entry) => entry.owner),
      contains('conversation:thread'),
    );
    expect(feed.closeCompleted.isCompleted, isFalse);
    expect(feed.closeCalls, 1);
    final again = await fixture.repository.retryCleanup(deadline: expired);
    expect(again.complete, isFalse);
    expect(
      feed.closeCalls,
      1,
      reason: 'An expired retry neither cancels nor replaces actual close',
    );
    feed.closeGate!.complete();
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(fixture.transport.opens, hasLength(1));
    await fixture.close();
  });

  test('retirement starts native close but joins the blocked ACK before releasing ownership', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    final content = fixture.session().content;
    feed.ackGate = Completer<void>();
    feed.closeGate = Completer<void>();
    feed.send(ConversationChatEvent(batch: _appendMessage('item-2')));
    await fixture.consumers['thread']!
        .waitForCount(2)
        .timeout(
          const Duration(seconds: 1),
          onTimeout: () => throw StateError('consumer did not accept batch'),
        );
    await feed.ackStarted(2);
    var completed = false;
    final closing = fixture.close().then((report) {
      completed = true;
      return report;
    });
    await feed.closeStarted.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () => throw StateError('native close did not start'),
    );
    expect(completed, isFalse);
    expect(feed.ackGate!.isCompleted, isFalse);
    feed.closeGate!.complete();
    await feed.closeCompleted.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () => throw StateError('native close did not finish'),
    );
    expect(completed, isFalse);
    expect(feed.ackGate!.isCompleted, isFalse);
    feed.ackGate!.complete();
    await feed
        .acknowledged(2)
        .timeout(
          const Duration(seconds: 1),
          onTimeout: () => throw StateError('ACK did not settle'),
        );
    expect((await closing).complete, isTrue);
    expect(content.state.value, isA<ChatClosed<bool>>());
  });

  test(
    'bounded automatic retries exhaust and explicit refresh owns a new attempt',
    () async {
      final timers = _RetryTimers();
      await runZoned(() async {
        final fixture = ConversationFixture();
        var feed = await fixture.open(demand: _demand);
        await fixture.transport.productTopicOpened(
          ThreadMcpTopic(threadId: fixture.repository.visibleThreadId.value!),
        );
        // Settle the independent MCP topic's stability timer before driving
        // the conversation retry timers below.
        await timers.fireNext();
        final content = fixture.session().content;
        for (var index = 0; index < 4; index++) {
          feed.send(const ConversationClosedEvent());
          await content.state.waitFor(
            (state) => index == 3
                ? state is ChatFailed<bool>
                : state is ChatReconnecting<bool>,
          );
          await feed.closeCompleted.future;
          if (index == 3) break;
          await timers.fireNext();
          await fixture.transport.opened(index + 1);
          feed = TestConversationFeed(subscriptionId: 'retry-${index + 1}');
          fixture.transport.opens[index + 1].result.complete(feed);
        }
        expect(fixture.transport.opens, hasLength(4));
        expect(timers.hasPending, isFalse);
        content.refresh();
        await fixture.transport.opened(4);
        final refreshed = TestConversationFeed(subscriptionId: 'explicit');
        fixture.transport.opens[4].result.complete(refreshed);
        await refreshed.deliver(
          ConversationChatEvent(
            batch: chatSet(messages: [chatMessage(id: 'item-20')]),
          ),
        );
        expect(content.state.value, isA<ChatReady<bool>>());
        await fixture.close();
      }, zoneSpecification: timers.specification);
    },
  );

  test(
    'new A opens while original A and B remain owned until their actual close',
    () async {
      final fixture = ConversationFixture();
      fixture.attach('A', demand: _demand);
      fixture.attach('B', demand: _demand);
      fixture.repository.setVisibleThread('A');
      fixture.repository.setVisibleThread('B');
      fixture.repository.setVisibleThread('A');
      expect(fixture.transport.opens.map((open) => open.threadId), [
        'A',
        'B',
        'A',
      ]);
      final oldA = TestConversationFeed(threadId: 'A')
        ..closeGate = Completer<void>();
      fixture.transport.opens[0].result.complete(oldA);
      await oldA.closeStarted.future;
      expect(fixture.transport.opens, hasLength(3));
      expect(oldA.closeCompleted.isCompleted, isFalse);
      await fixture.transport.opened(2);
      expect(fixture.transport.opens[2].threadId, 'A');
      final current = TestConversationFeed(
        threadId: 'A',
        subscriptionId: 'new-A',
      );
      fixture.transport.opens[2].result.complete(current);
      await current.deliver(
        ConversationChatEvent(batch: chatSet(messages: [chatMessage()])),
      );
      expect(oldA.closeCompleted.isCompleted, isFalse);
      oldA.closeGate!.complete();
      final oldB = TestConversationFeed(threadId: 'B');
      fixture.transport.opens[1].result.complete(oldB);
      await oldB.closeCompleted.future;
      expect(oldA.eventConsumers, 0);
      expect(oldB.eventConsumers, 0);
      expect(fixture.session('A').content.state.value, isA<ChatReady<bool>>());
      await fixture.close();
    },
  );

  for (final owner in ['repository', 'client']) {
    test(
      'closing $owner from the first opening publication joins its registered attempt',
      () async {
        final fixture = ConversationFixture();
        final session = fixture.session('A');
        fixture.attach('A', demand: _demand);
        Future<CloseReport>? closing;
        final observation = session.content.state.watch((state) {
          if (state is! ChatOpening<bool>) return;
          closing = owner == 'repository'
              ? fixture.repository.close()
              : fixture.close();
        });
        fixture.repository.setVisibleThread('A');
        expect(closing, isNotNull);
        expect(fixture.transport.opens, isEmpty);
        expect((await closing!).complete, isTrue);
        if (owner == 'repository') {
          // Closing the conversation repository cannot release the Client's MCP mirror.
        } else {}
        expect(session.content.state.value, isA<ChatClosed<bool>>());
        observation.cancel();
        // No retryCleanup is necessary, and the original close result stays clean.
        expect((await fixture.close()).complete, isTrue);
      },
    );
  }

  test('borrowing state and content never admits a native feed', () async {
    final fixture = ConversationFixture();
    final session = fixture.session();
    final observed = session.source.watch((_) {});
    final content = session.content.state.watch((_) {});
    expect(session.isActive, isFalse);
    expect(fixture.transport.opens, isEmpty);
    observed.cancel();
    content.cancel();
    expect((await fixture.close()).complete, isTrue);
  });

  test('visible mirror signal reentry retires old A and diagnostic join leaves new A active', () async {
    final fixture = ConversationFixture();
    final oldA = await fixture.open(
      threadId: 'A',
      initial: chatSet(messages: [chatMessage()]),
      demand: _demand,
    );
    oldA.closeGate = Completer<void>();
    final targets = <String?>[];
    final observation = fixture.repository.visibleThreadId.watch((target) {
      targets.add(target);
      if (target != null) {
        final owner = fixture.repository.existingSession(target);
        expect(owner, isNotNull, reason: 'Only assembled mirrors are signaled');
        if (target == 'B') {
          expect(owner!.isActive, isFalse);
          fixture.repository.setVisibleThread('A');
        }
      }
    }, fireImmediately: true);
    fixture.repository.setVisibleThread('B');
    expect(targets, ['A', null, 'B', null, 'A']);
    expect(oldA.requestCloseStarted.isCompleted, isTrue);
    expect(fixture.transport.opens.map((open) => open.threadId), ['A', 'A']);
    fixture.repository.setVisibleThread('A');
    expect(targets, ['A', null, 'B', null, 'A']);
    expect(fixture.transport.opens, hasLength(2));
    final newA = TestConversationFeed(threadId: 'A', subscriptionId: 'new-A');
    fixture.transport.opens[1].result.complete(newA);
    await newA.deliver(
      ConversationChatEvent(batch: chatSet(messages: [chatMessage()])),
    );
    final content = fixture.session('A').content;
    final expired = await content.joinRetired(
      deadline: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    expect(expired.complete, isFalse);
    var joined = false;
    final joining = content.joinRetired().then((report) {
      joined = true;
      return report;
    });
    await oldA.closeStarted.future;
    expect(joined, isFalse);
    expect(newA.requestCloseCalls, 0);
    oldA.closeGate!.complete();
    expect((await joining).complete, isTrue);
    expect(content.hasDemand, isTrue);
    expect(newA.requestCloseCalls, 0);
    expect(fixture.repository.visibleThreadId.value, 'A');
    final closing = fixture.close();
    expect(fixture.repository.visibleThreadId.value, isNull);
    expect(targets, ['A', null, 'B', null, 'A', null]);
    expect((await closing).complete, isTrue);
    observation.cancel();
  });

  test('close inside visible mirror signal prevents activation and later ready publication', () async {
    final fixture = ConversationFixture();
    final oldA = await fixture.open(
      threadId: 'A',
      initial: chatSet(messages: [chatMessage()]),
      demand: _demand,
    );
    Future<CloseReport>? closing;
    final targets = <String?>[];
    final observation = fixture.repository.visibleThreadId.watch((target) {
      targets.add(target);
      if (target == 'B') closing = fixture.close();
    });
    final secondTargets = <String?>[];
    final second = fixture.repository.visibleThreadId.watch(secondTargets.add);
    fixture.repository.setVisibleThread('B');
    expect(targets, [null, 'B', null]);
    expect(secondTargets, [null, null]);
    expect(fixture.repository.visibleThreadId.value, isNull);
    expect(fixture.transport.opens.map((open) => open.threadId), ['A']);
    expect(oldA.requestCloseStarted.isCompleted, isTrue);
    expect(closing, isNotNull);
    expect((await closing!).complete, isTrue);
    expect(targets, [null, 'B', null]);
    expect(secondTargets, [null, null]);
    observation.cancel();
    second.cancel();
  });

  test(
    'visible Thread MCP owns a page topic lease and releases it on navigation',
    () async {
      final fixture = ConversationFixture();
      await fixture.open(threadId: 'A', demand: _demand);
      expect(fixture.repository.visibleThreadId.value, 'A');
      expect(fixture.client.existingThreadMcp('A'), isNotNull);
      expect(
        fixture.client.channels.activeTopicRefCountViews()['threadMcp:A'],
        1,
      );
      expect(
        fixture.transport.productTopics,
        contains(const ThreadMcpTopic(threadId: 'A')),
      );

      fixture.repository.setVisibleThread(null);
      expect(
        fixture.client.channels.activeTopicRefCountViews()['threadMcp:A'] ?? 0,
        0,
      );
      expect(fixture.client.existingThreadMcp('A'), isNotNull);

      await fixture.open(threadId: 'B', index: 1, demand: _demand);
      expect(fixture.repository.visibleThreadId.value, 'B');
      expect(
        fixture.client.channels.activeTopicRefCountViews()['threadMcp:B'],
        1,
      );
      expect(
        fixture.client.channels.activeTopicRefCountViews()['threadMcp:A'] ?? 0,
        0,
      );
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test(
    'child visibility reentry retires old A before returning to a fresh A feed',
    () async {
      final fixture = ConversationFixture();
      final oldA = await fixture.open(
        threadId: 'A',
        initial: chatSet(messages: [chatMessage()]),
        demand: _demand,
      );
      oldA.closeGate = Completer<void>();
      oldA.ackGate = Completer<void>();
      final content = fixture.session('A').content;
      oldA.send(ConversationChatEvent(batch: _appendMessage('item-2')));
      await fixture.consumers['A']!.waitForCount(2);
      await oldA.ackStarted(2);
      // A following native frame may arrive after ACK starts, before Dart's
      // acknowledge Future settles; it still belongs to this original attempt.
      oldA.send(
        ConversationChatEvent(batch: _appendMessage('item-99', from: 2)),
      );
      await fixture.consumers['A']!.waitForCount(3);
      final scope = content.openScope(generation: 1);
      final pageReply = Completer<ChatBatch>();
      oldA.reader.onOlder = (_, __) => pageReply.future;
      final reading = expectLater(
        scope.loadOlder(before: 'opaque-before', demand: _demand),
        throwsA(isA<StaleConversationScope>()),
      );
      final visibleTargets = <String?>[];
      final observation = fixture.repository.visibleThreadId.watch((target) {
        visibleTargets.add(target);
        if (target != 'B') return;
        // B 的会话 demand 已建立、原生打开尚未发起：在同一导航 drain 内直接返回
        // A，B 不成为可见终点也不留下打开中的 feed。
        fixture.repository.setVisibleThread('A');
      });
      fixture.repository.setVisibleThread('B');
      expect(visibleTargets, [null, 'B', null, 'A']);
      expect(oldA.requestCloseStarted.isCompleted, isTrue);
      expect(scope.isActive, isFalse);
      expect(scope.pendingQueries, 1);
      expect(fixture.transport.opens.map((open) => open.threadId), ['A', 'A']);
      final newA = TestConversationFeed(threadId: 'A', subscriptionId: 'new-A');
      fixture.transport.opens[1].result.complete(newA);
      await newA.deliver(
        ConversationChatEvent(batch: chatSet(messages: [chatMessage()])),
      );
      oldA.ackGate!.complete();
      await oldA.acknowledged(2);
      expect(oldA.acknowledgements, [1, 2]);
      expect(
        fixture.consumers['A']!.batches.last,
        isA<ChatBatch>().having(
          (batch) => batch.placement,
          'placement',
          ChatPlacement.set,
        ),
      );
      expect(newA.requestCloseCalls, 0);
      observation.cancel();
      await oldA.closeStarted.future;
      var closed = false;
      final closing = fixture.close().then((report) {
        closed = true;
        return report;
      });
      await newA.closeCompleted.future;
      expect(closed, isFalse);
      oldA.closeGate!.complete();
      await oldA.closeCompleted.future;
      expect(scope.pendingQueries, 1);
      expect(
        closed,
        isFalse,
        reason: 'The retired query still owns its future',
      );
      pageReply.complete(
        ChatBatch(placement: ChatPlacement.prepend, throughSeq: 1, entries: []),
      );
      await reading;
      expect((await closing).complete, isTrue);
    },
  );

  test(
    'close from a child visibility callback seals the navigation drain',
    () async {
      final fixture = ConversationFixture();
      final oldA = await fixture.open(
        threadId: 'A',
        initial: chatSet(messages: [chatMessage()]),
        demand: _demand,
      );
      Future<CloseReport>? closing;
      final observation = fixture.repository.visibleThreadId.watch((target) {
        if (target != 'B') return;
        fixture.repository.setVisibleThread('A');
        closing = fixture.close();
      });
      fixture.repository.setVisibleThread('B');
      expect(fixture.session('A').isActive, isFalse);
      expect(fixture.transport.opens.map((open) => open.threadId), ['A']);
      expect(oldA.requestCloseStarted.isCompleted, isTrue);
      observation.cancel();
      expect(closing, isNotNull);
      expect((await closing!).complete, isTrue);
    },
  );

  for (final boundary in ['retirement', 'activation']) {
    test(
      'navigation from $boundary publication drains without recursive activation',
      () async {
        final fixture = ConversationFixture();
        final oldA = await fixture.open(
          threadId: 'A',
          initial: chatSet(messages: [chatMessage()]),
          demand: _demand,
        );
        fixture.attach('B', demand: _demand);
        final source = fixture
            .session(boundary == 'retirement' ? 'A' : 'B')
            .content
            .state;
        var redirected = false;
        final observation = source.watch((state) {
          if (redirected) return;
          final atBoundary = boundary == 'retirement'
              ? state is ChatIdle<bool>
              : state is ChatOpening<bool>;
          if (!atBoundary) return;
          redirected = true;
          fixture.repository.setVisibleThread('A');
        });
        fixture.repository.setVisibleThread('B');
        expect(redirected, isTrue);
        expect(oldA.requestCloseStarted.isCompleted, isTrue);
        // 新契约：重定向在调用返回前同步撤销不再是最新请求的 demand。
        // activation 边界上的 B attempt 在 transport open 之前退役，B 从未
        // 打开连接；两个边界都只有一次全新的 A 恢复。
        final expectedTargets = ['A', 'A'];
        expect(
          fixture.transport.opens.map((open) => open.threadId),
          expectedTargets,
        );
        final current = TestConversationFeed(
          threadId: 'A',
          subscriptionId: 'fresh-A',
        );
        fixture.transport.opens.last.result.complete(current);
        await current.deliver(
          ConversationChatEvent(batch: chatSet(messages: [chatMessage()])),
        );
        if (boundary == 'activation') {
          expect(
            fixture.transport.opens.map((open) => open.threadId),
            isNot(contains('B')),
            reason: '撤销后的 B 不再打开内容连接',
          );
        }
        expect(current.requestCloseCalls, 0);
        observation.cancel();
        expect((await fixture.close()).complete, isTrue);
      },
    );
  }

  test(
    'A -> B -> A invalidates synchronously and closes exact late feeds',
    () async {
      final fixture = ConversationFixture();
      final consumer = fixture.attach('A', demand: _demand);
      fixture.attach('B', demand: _demand);
      fixture.repository.setVisibleThread('A');
      fixture.repository.setVisibleThread('B');
      fixture.repository.setVisibleThread('A');
      expect(fixture.transport.opens.map((e) => e.threadId), ['A', 'B', 'A']);
      final oldA = TestConversationFeed(threadId: 'A', subscriptionId: 'old-A');
      final oldB = TestConversationFeed(threadId: 'B', subscriptionId: 'old-B');
      final newA = TestConversationFeed(threadId: 'A', subscriptionId: 'new-A');
      fixture.transport.opens[2].result.complete(newA);
      await newA.deliver(
        ConversationChatEvent(batch: chatSet(messages: [chatMessage()])),
      );
      fixture.transport.opens[0].result.complete(oldA);
      fixture.transport.opens[1].result.complete(oldB);
      await Future.wait([
        oldA.closeCompleted.future,
        oldB.closeCompleted.future,
      ]);
      expect(oldA.eventConsumers, 0);
      expect(oldB.eventConsumers, 0);
      expect(
        consumer.batches.last,
        isA<ChatBatch>().having(
          (batch) => batch.placement,
          'placement',
          ChatPlacement.set,
        ),
      );
      expect(newA.requestCloseCalls, 0);
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test('a pending native close of an older attempt never blocks retiring a fresh attempt of the same owner', () async {
    final fixture = ConversationFixture();
    fixture.attach('A', demand: _demand);
    fixture.attach('B', demand: _demand);
    // A opens first; its native close stays gated to simulate a slow worker.
    fixture.repository.setVisibleThread('A');
    await fixture.transport.opened(0);
    final oldA = TestConversationFeed(threadId: 'A', subscriptionId: 'old-A');
    oldA.closeGate = Completer<void>();
    fixture.transport.opens[0].result.complete(oldA);
    await oldA.deliver(
      ConversationChatEvent(batch: chatSet(messages: [chatMessage()])),
    );
    // Leaving A starts its retirement while its native close hangs.
    fixture.repository.setVisibleThread('B');
    await oldA.closeStarted.future;
    await fixture.transport.opened(1);
    final firstB = TestConversationFeed(threadId: 'B', subscriptionId: 'b-1');
    fixture.transport.opens[1].result.complete(firstB);
    await firstB.deliver(
      ConversationChatEvent(batch: chatSet(messages: [chatMessage()])),
    );
    // Returning to A must mint a fresh attempt, not resurrect the retired one.
    fixture.repository.setVisibleThread('A');
    await fixture.transport.opened(2);
    final newA = TestConversationFeed(threadId: 'A', subscriptionId: 'new-A');
    fixture.transport.opens[2].result.complete(newA);
    await newA.deliver(
      ConversationChatEvent(batch: chatSet(messages: [chatMessage()])),
    );
    final owner = fixture.repository.existingSession('A')!;
    expect(owner.isActive, isTrue);
    // Leaving A again retires the fresh attempt synchronously, even though
    // the same owner still has an older native close in flight.
    fixture.repository.setVisibleThread('B');
    expect(owner.isActive, isFalse);
    // The product signals requestClose once per retirement; the feed's own
    // close() may echo requestClose again. The native close itself runs once.
    expect(newA.requestCloseCalls, greaterThanOrEqualTo(1));
    await newA.closeStarted.future;
    expect(newA.closeCalls, 1);
    await newA.closeCompleted.future;
    expect(owner.content.currentAttemptId, isNull);
    await fixture.transport.opened(3);
    final secondB = TestConversationFeed(threadId: 'B', subscriptionId: 'b-2');
    fixture.transport.opens[3].result.complete(secondB);
    await secondB.deliver(
      ConversationChatEvent(batch: chatSet(messages: [chatMessage()])),
    );
    expect(fixture.transport.opens.map((e) => e.threadId), [
      'A',
      'B',
      'A',
      'B',
    ]);
    // Releasing the gated close lets every retirement settle to zero.
    oldA.closeGate!.complete();
    await oldA.closeCompleted.future;
    expect((await fixture.close()).complete, isTrue);
  });

  test('A -> B -> A synchronous cascade mints a new attempt id for the returning A', () async {
    final fixture = ConversationFixture();
    final attemptsPerThread = <String, List<Object?>>{};
    void record(String id) {
      final owner = fixture.repository.existingSession(id);
      if (owner != null) {
        attemptsPerThread
            .putIfAbsent(id, () => [])
            .add(owner.content.currentAttemptId!);
      }
    }

    void drain(String id) {
      fixture.attach(id, demand: _demand);
      fixture.repository.setVisibleThread(id);
      record(id);
    }

    drain('A');
    drain('B');
    drain('A');
    // The two A attempts are distinct generations: the cascade really
    // retired the first demand and minted a second one, not a reuse.
    expect(attemptsPerThread['A'], hasLength(2));
    expect(attemptsPerThread['A']![0], isNot(same(attemptsPerThread['A']![1])));
    expect(attemptsPerThread['B'], hasLength(1));
    expect(fixture.transport.opens.map((e) => e.threadId), ['A', 'B', 'A']);
    await Future.wait([
      fixture.transport.opened(0),
      fixture.transport.opened(1),
      fixture.transport.opened(2),
    ]);
    fixture.transport.opens[0].result.complete(
      TestConversationFeed(threadId: 'A', subscriptionId: 'a-1'),
    );
    fixture.transport.opens[1].result.complete(
      TestConversationFeed(threadId: 'B', subscriptionId: 'b-1'),
    );
    fixture.transport.opens[2].result.complete(
      TestConversationFeed(threadId: 'A', subscriptionId: 'a-2'),
    );
    expect((await fixture.close()).complete, isTrue);
  });

  test(
    'leaving settings cancels only GUI demand and returning opens new baseline',
    () async {
      final fixture = ConversationFixture();
      final visibleTargets = <String?>[];
      final observation = fixture.repository.visibleThreadId.watch((target) {
        visibleTargets.add(target);
        if (target != null) {
          final owner = fixture.repository.existingSession(target);
          expect(owner, isNotNull);
          expect(
            owner!.isActive,
            isFalse,
            reason: 'Signal precedes feed admission',
          );
        }
      }, fireImmediately: true);
      expect(visibleTargets, [null]);
      expect(fixture.repository.sessionStates, isEmpty);
      expect(fixture.transport.opens, isEmpty);
      // Selection and visible demand are independent; neither stops business work.
      fixture.client.selection.selectThread(
        threadId: 'thread',
        workspaceId: 'project',
      );
      expect(visibleTargets, [null]);
      final consumer = fixture.attach('thread', demand: _demand);
      fixture.repository.setVisibleThread('thread');
      expect(visibleTargets, [null, 'thread']);
      await fixture.transport.opened(0);
      final first = TestConversationFeed();
      fixture.transport.opens.first.result.complete(first);
      await first.deliver(
        ConversationChatEvent(
          batch: chatSet(messages: [chatMessage(id: 'item-1')]),
        ),
      );
      final draft = fixture.client.drafts.composer('thread')
        ..updateDraft('keep');
      fixture.repository.setVisibleThread(null);
      expect(fixture.repository.visibleThreadId.value, isNull);
      expect(visibleTargets, [null, 'thread', null]);
      expect(fixture.session().isActive, isFalse);
      expect(fixture.client.selection.state.selectedThreadId, 'thread');
      expect(draft.state.draft, 'keep');
      await first.closeCompleted.future;
      fixture.repository.setVisibleThread('thread');
      expect(fixture.client.selection.state.selectedThreadId, 'thread');
      expect(visibleTargets, [null, 'thread', null, 'thread']);
      await fixture.transport.opened(1);
      final second = TestConversationFeed(subscriptionId: 'new');
      fixture.transport.opens[1].result.complete(second);
      await second.deliver(
        ConversationChatEvent(
          batch: chatSet(messages: [chatMessage(id: 'item-9')]),
        ),
      );
      expect(
        consumer.batches.last,
        isA<ChatBatch>().having(
          (batch) => (batch.entries.single).recordId,
          'message identity',
          'item-9',
        ),
      );
      final closing = fixture.close();
      expect(fixture.repository.visibleThreadId.value, isNull);
      expect(visibleTargets, [null, 'thread', null, 'thread', null]);
      await closing;
      observation.cancel();
    },
  );

  test(
    'consumer acceptance precedes ACK and no second consumer is created',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open(demand: _demand);
      final consumer = fixture.consumers['thread']!;
      feed.ackGate = Completer<void>();
      feed.send(ConversationChatEvent(batch: _appendMessage('item-2')));
      await consumer.waitForCount(2);
      expect(consumer.batches.last.placement, ChatPlacement.append);
      expect(feed.acknowledgements, [1]);
      // No second consumer and no unbounded async-listen callback chain.
      expect(feed.eventConsumers, 1);
      feed.ackGate!.complete();
      await feed.acknowledged(2);
      expect(feed.acknowledgements, [1, 2]);
      await fixture.close();
    },
  );

  test(
    'close deadline keeps pending open and native close ownership until join',
    () async {
      final fixture = ConversationFixture();
      fixture.attach('thread', demand: _demand);
      fixture.repository.setVisibleThread('thread');
      final closing = fixture.close(deadline: DateTime.now());
      final report = await closing;
      expect(report.complete, isFalse);
      final feed = TestConversationFeed()..closeGate = Completer<void>();
      fixture.transport.opens.single.result.complete(feed);
      await feed.closeStarted.future;
      feed.closeGate!.complete();
      await feed.closeCompleted.future;
      expect((await fixture.client.retryCleanup()).complete, isTrue);
    },
  );

  test('failed native close retains ownership and explicit cleanup retries same owner', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open(demand: _demand);
    feed.closeFailure = StateError('native join failed');
    expect((await fixture.close()).complete, isFalse);
    feed.closeFailure = null;
    expect((await fixture.client.retryCleanup()).complete, isTrue);
    expect(feed.closeCalls, 2);
    expect(fixture.transport.opens, hasLength(1));
  });

  test(
    'late A1 retirement cannot erase A2 unresolved close ownership',
    () async {
      final fixture = ConversationFixture();
      fixture.attach('thread-main', demand: _demand);
      fixture.attach('thread-alt', demand: _demand);

      fixture.repository.setVisibleThread('thread-main');
      await fixture.transport.opened(0);
      final owner = fixture.repository.existingSession('thread-main')!;
      final firstAttempt = owner.content.currentAttemptId!;

      fixture.repository.setVisibleThread('thread-alt');
      await fixture.transport.opened(1);
      final alternate = TestConversationFeed(
        threadId: 'thread-alt',
        subscriptionId: 'alt',
      );
      fixture.transport.opens[1].result.complete(alternate);
      await alternate.deliver(ConversationChatEvent(batch: chatSet()));

      fixture.repository.setVisibleThread('thread-main');
      await fixture.transport.opened(2);
      final second = TestConversationFeed(
        threadId: 'thread-main',
        subscriptionId: 'a2',
      )..closeFailure = StateError('A2 close acknowledgement failed');
      fixture.transport.opens[2].result.complete(second);
      await second.deliver(ConversationChatEvent(batch: chatSet()));
      final secondAttempt = owner.content.currentAttemptId!;
      expect(secondAttempt, isNot(firstAttempt));

      fixture.repository.setVisibleThread(null);
      final report = await fixture.close(deadline: DateTime.utc(2000));
      expect(
        report.unresolved.any(
          (entry) =>
              entry.owner == 'conversation:thread-main' &&
              entry.attemptId == secondAttempt,
        ),
        isTrue,
      );

      final first = TestConversationFeed(
        threadId: 'thread-main',
        subscriptionId: 'a1',
      );
      fixture.transport.opens[0].result.complete(first);
      await first.closeCompleted.future;
      expect(first.closeCalls, greaterThanOrEqualTo(1));

      final retired = await fixture.client.retryCleanup();
      expect(retired.complete, isFalse);
      expect(
        fixture.client.unresolvedResources.any(
          (entry) =>
              entry.owner == 'conversation:thread-main' &&
              entry.attemptId == secondAttempt,
        ),
        isTrue,
        reason:
            'the old successful retirement must not replace A2 close evidence',
      );

      second.closeFailure = null;
      final recovered = await fixture.client.retryCleanup();
      expect(recovered.complete, isTrue);
      expect(
        fixture.transport.opens.where((open) => open.threadId == 'thread-main'),
        hasLength(2),
        reason: 'cleanup never reopens a timeline connection',
      );
    },
  );

  test(
    'terminal control frames use no credit and close does not await an ACK',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open(demand: _demand);
      // Revocation occurs before another ACK can be issued.
      fixture.repository.setVisibleThread(null);
      await feed.closeCompleted.future;
      expect(feed.acknowledgements, [1]);
      expect(fixture.session().content.state.value, isA<ChatIdle<bool>>());
      await fixture.close();
    },
  );
}

StudioThread testThread() => StudioThread(
  id: 'thread',
  workspaceId: 'project',
  workspacePath: '/workspace',
  title: 'Thread',
  mode: ThreadModeId.simple,
  delegationMode: DelegationMode.profile,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: DateTime.utc(2026),
);

/// Drives production retry timers without sleeping or changing SDK interfaces.
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
