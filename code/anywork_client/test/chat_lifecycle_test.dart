import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

void main() {
  test('repository retryCleanup honors expired absolute deadline and preserves original native join', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open();
    feed.closeGate = Completer<void>();
    fixture.repository.setVisibleThread(null);
    await feed.closeStarted.future;
    final expired = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final first = await fixture.repository.retryCleanup(deadline: expired);
    expect(first.complete, isFalse);
    expect(first.unresolved.map((entry) => entry.owner), contains('thread'));
    expect(fixture.client.budget.used(ResourceKind.chatHandle), 1);
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
    expect(fixture.client.budget.used(ResourceKind.chatHandle), 0);
    expect(fixture.transport.opens, hasLength(1));
    await fixture.close();
  });

  test('retirement starts and joins actual native close without waiting for blocked ACK', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open();
    final content = fixture.session().content;
    feed.ackGate = Completer<void>();
    feed.closeGate = Completer<void>();
    feed.send(ConversationUpdateEvent(update: patch(1, 2)));
    await content.state.waitFor(
      (state) => state.snapshot is ConversationPatchFrame,
    );
    var completed = false;
    final closing = fixture.close().then((report) {
      completed = true;
      return report;
    });
    await feed.closeStarted.future;
    expect(completed, isFalse);
    expect(fixture.client.budget.used(ResourceKind.chatHandle), 1);
    expect(feed.ackGate!.isCompleted, isFalse);
    feed.closeGate!.complete();
    expect((await closing).complete, isTrue);
    expect(feed.ackGate!.isCompleted, isFalse);
    expect(fixture.client.budget.usage, isEmpty);
    // The late control response has no publication or native-resource claim.
    feed.ackGate!.complete();
    await feed.acknowledged(2);
    expect(content.state.value, isA<ChatClosed<ConversationContentFrame>>());
  });

  test(
    'bounded automatic retries exhaust and explicit refresh owns a new attempt',
    () async {
      final timers = _RetryTimers();
      await runZoned(() async {
        final fixture = ConversationFixture();
        var feed = await fixture.open();
        final content = fixture.session().content;
        for (var index = 0; index < 4; index++) {
          feed.send(const ConversationClosedEvent());
          await content.state.waitFor(
            (state) => index == 3
                ? state is ChatFailed<ConversationContentFrame>
                : state is ChatReconnecting<ConversationContentFrame>,
          );
          await feed.closeCompleted.future;
          if (index == 3) break;
          await timers.fireNext();
          await fixture.transport.opened(index + 1);
          feed = TestConversationFeed(subscriptionId: 'retry-${index + 1}');
          fixture.transport.opens[index + 1].result.complete(feed);
          await feed.deliver(
            ConversationBaselineEvent(
              baseline: baseline(
                index + 2,
                subscriptionId: feed.subscriptionId,
              ),
            ),
          );
        }
        expect(fixture.transport.opens, hasLength(4));
        expect(timers.hasPending, isFalse);
        content.refresh();
        await fixture.transport.opened(4);
        final refreshed = TestConversationFeed(subscriptionId: 'explicit');
        fixture.transport.opens[4].result.complete(refreshed);
        await refreshed.deliver(
          ConversationBaselineEvent(
            baseline: baseline(20, subscriptionId: 'explicit'),
          ),
        );
        expect(content.state.value, isA<ChatReady<ConversationContentFrame>>());
        await fixture.close();
        expect(fixture.client.budget.usage, isEmpty);
      }, zoneSpecification: timers.specification);
    },
  );

  test(
    'default two-handle budget waits for actual old close before opening new A',
    () async {
      final budget = ResourceBudget();
      final fixture = ConversationFixture(budget: budget);
      fixture.repository.setVisibleThread('A');
      fixture.repository.setVisibleThread('B');
      fixture.repository.setVisibleThread('A');
      expect(fixture.transport.opens.map((open) => open.threadId), ['A', 'B']);
      final oldA = TestConversationFeed(threadId: 'A')
        ..closeGate = Completer<void>();
      fixture.transport.opens[0].result.complete(oldA);
      await oldA.closeStarted.future;
      expect(fixture.transport.opens, hasLength(2));
      expect(budget.used(ResourceKind.chatHandle), 2);
      oldA.closeGate!.complete();
      await fixture.transport.opened(2);
      expect(fixture.transport.opens[2].threadId, 'A');
      final current = TestConversationFeed(
        threadId: 'A',
        subscriptionId: 'new-A',
      );
      fixture.transport.opens[2].result.complete(current);
      await current.deliver(
        ConversationBaselineEvent(
          baseline: baseline(
            3,
            subscriptionId: 'new-A',
            items: [timelineItem(3, threadId: 'A')],
          ),
        ),
      );
      final oldB = TestConversationFeed(threadId: 'B');
      fixture.transport.opens[1].result.complete(oldB);
      await oldB.closeCompleted.future;
      expect(oldA.eventConsumers, 0);
      expect(oldB.eventConsumers, 0);
      expect(
        fixture.session('A').content.state.value,
        isA<ChatReady<ConversationContentFrame>>(),
      );
      await fixture.close();
      expect(budget.usage, isEmpty);
    },
  );

  for (final owner in ['repository', 'client']) {
    test(
      'closing $owner from the first opening publication joins its registered attempt',
      () async {
        final fixture = ConversationFixture();
        final session = fixture.session('A');
        Future<CloseReport>? closing;
        final observation = session.content.state.watch((state) {
          if (state is! ChatOpening<ConversationContentFrame>) return;
          closing = owner == 'repository'
              ? fixture.repository.close()
              : fixture.close();
        });
        fixture.repository.setVisibleThread('A');
        expect(closing, isNotNull);
        expect(fixture.transport.opens, isEmpty);
        expect(
          fixture.client.childInteractions.state.visibleHostThreadId,
          isNull,
        );
        expect((await closing!).complete, isTrue);
        expect(fixture.client.budget.usage, isEmpty);
        expect(
          session.content.state.value,
          isA<ChatClosed<ConversationContentFrame>>(),
        );
        observation.cancel();
        // No retryCleanup is necessary, and the original close result stays clean.
        expect((await fixture.close()).complete, isTrue);
        expect(fixture.client.budget.usage, isEmpty);
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
      initial: baseline(1, items: [timelineItem(1, threadId: 'A')]),
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
      ConversationBaselineEvent(
        baseline: baseline(
          7,
          subscriptionId: 'new-A',
          items: [timelineItem(7, threadId: 'A')],
        ),
      ),
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
    expect(fixture.client.budget.usage, isEmpty);
  });

  test('close inside visible mirror signal prevents activation and later ready publication', () async {
    final fixture = ConversationFixture();
    final oldA = await fixture.open(
      threadId: 'A',
      initial: baseline(1, items: [timelineItem(1, threadId: 'A')]),
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
    expect(fixture.client.budget.usage, isEmpty);
  });

  test('mirror admission failure withdraws visibility without signaling a missing owner', () async {
    final fixture = ConversationFixture(
      budget: ResourceBudget(
        capacities: {...ResourceBudget().capacities, ResourceKind.readModel: 1},
      ),
    );
    final feed = await fixture.open();
    final targets = <String?>[];
    final observation = fixture.repository.visibleThreadId.watch(targets.add);
    expect(
      () => fixture.repository.setVisibleThread('missing'),
      throwsA(isA<ResourceBudgetExceeded>()),
    );
    expect(targets, [null]);
    expect(fixture.repository.visibleThreadId.value, isNull);
    expect(fixture.repository.existingSession('missing'), isNull);
    expect(feed.requestCloseStarted.isCompleted, isTrue);
    expect(fixture.transport.opens, hasLength(1));
    expect((await fixture.close()).complete, isTrue);
    observation.cancel();
    expect(fixture.client.budget.usage, isEmpty);
  });

  test(
    'child visibility reentry retires old A before returning to a fresh A feed',
    () async {
      final fixture = ConversationFixture();
      final oldA = await fixture.open(
        threadId: 'A',
        initial: baseline(1, items: [timelineItem(1, threadId: 'A')]),
      );
      oldA.closeGate = Completer<void>();
      oldA.ackGate = Completer<void>();
      final content = fixture.session('A').content;
      oldA.send(ConversationUpdateEvent(update: patch(1, 2)));
      await content.state.waitFor(
        (state) => state.snapshot is ConversationPatchFrame,
      );
      // The second native credit is already queued behind the blocked ACK.
      oldA.send(ConversationUpdateEvent(update: patch(2, 99)));
      final scope = content.openScope(generation: 1)!;
      final pageReply = Completer<ConversationPage>();
      oldA.onPage = (_, _) => pageReply.future;
      final reading = expectLater(
        scope.page(),
        throwsA(isA<StaleConversationScope>()),
      );
      final generation =
          fixture.client.childInteractions.state.displayGeneration;
      final visibleTargets = <String?>[];
      final observation = fixture.client.childInteractions.source.watch((
        state,
      ) {
        visibleTargets.add(state.visibleHostThreadId);
        if (state.visibleHostThreadId == 'B') {
          fixture.repository.setVisibleThread('A');
        }
      });
      fixture.repository.setVisibleThread('B');
      expect(visibleTargets, ['B', 'A']);
      expect(
        fixture.client.childInteractions.state.displayGeneration,
        generation + 2,
      );
      expect(oldA.requestCloseStarted.isCompleted, isTrue);
      expect(scope.isActive, isFalse);
      expect(scope.pendingQueries, 1);
      expect(fixture.transport.opens.map((open) => open.threadId), ['A', 'A']);
      final newA = TestConversationFeed(threadId: 'A', subscriptionId: 'new-A');
      fixture.transport.opens[1].result.complete(newA);
      await newA.deliver(
        ConversationBaselineEvent(
          baseline: baseline(
            7,
            subscriptionId: 'new-A',
            items: [timelineItem(7, threadId: 'A')],
          ),
        ),
      );
      oldA.ackGate!.complete();
      await oldA.acknowledged(2);
      expect(oldA.acknowledgements, [1, 2]);
      expect(
        content.lastDeliveredFrame,
        isA<ConversationBaselineFrame>().having(
          (frame) => frame.baseline.version,
          'version',
          7,
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
      expect(fixture.client.budget.used(ResourceKind.pendingOperation), 1);
      oldA.closeGate!.complete();
      await oldA.closeCompleted.future;
      expect(scope.pendingQueries, 1);
      expect(
        closed,
        isFalse,
        reason: 'The retired query still owns its future',
      );
      pageReply.complete(
        const ConversationPage(items: [], before: null, hasOlder: false),
      );
      await reading;
      expect((await closing).complete, isTrue);
      expect(fixture.client.budget.usage, isEmpty);
    },
  );

  test(
    'close from a child visibility callback seals the navigation drain',
    () async {
      final fixture = ConversationFixture();
      final oldA = await fixture.open(
        threadId: 'A',
        initial: baseline(1, items: [timelineItem(1, threadId: 'A')]),
      );
      Future<CloseReport>? closing;
      final observation = fixture.client.childInteractions.source.watch((
        state,
      ) {
        if (state.visibleHostThreadId != 'B') return;
        fixture.repository.setVisibleThread('A');
        closing = fixture.close();
      });
      fixture.repository.setVisibleThread('B');
      expect(
        fixture.client.childInteractions.state.visibleHostThreadId,
        isNull,
      );
      expect(fixture.session('A').isActive, isFalse);
      expect(fixture.transport.opens.map((open) => open.threadId), ['A']);
      expect(oldA.requestCloseStarted.isCompleted, isTrue);
      observation.cancel();
      expect(closing, isNotNull);
      expect((await closing!).complete, isTrue);
      expect(fixture.client.budget.usage, isEmpty);
    },
  );

  for (final boundary in ['retirement', 'activation']) {
    test(
      'navigation from $boundary publication drains without recursive activation',
      () async {
        final fixture = ConversationFixture(
          budget: ResourceBudget(
            capacities: {
              ...ResourceBudget().capacities,
              ResourceKind.chatHandle: 3,
            },
          ),
        );
        final oldA = await fixture.open(
          threadId: 'A',
          initial: baseline(1, items: [timelineItem(1, threadId: 'A')]),
        );
        final source = fixture
            .session(boundary == 'retirement' ? 'A' : 'B')
            .content
            .state;
        var redirected = false;
        final observation = source.watch((state) {
          if (redirected) return;
          final atBoundary = boundary == 'retirement'
              ? state is ChatIdle<ConversationContentFrame>
              : state is ChatOpening<ConversationContentFrame>;
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
          ConversationBaselineEvent(
            baseline: baseline(
              7,
              subscriptionId: 'fresh-A',
              items: [timelineItem(7, threadId: 'A')],
            ),
          ),
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
        expect(fixture.client.budget.usage, isEmpty);
      },
    );
  }

  test(
    'A -> B -> A invalidates synchronously and closes exact late feeds',
    () async {
      final budget = ResourceBudget(
        capacities: {
          ...ResourceBudget().capacities,
          ResourceKind.chatHandle: 3,
        },
      );
      final fixture = ConversationFixture(budget: budget);
      fixture.repository.setVisibleThread('A');
      fixture.repository.setVisibleThread('B');
      fixture.repository.setVisibleThread('A');
      expect(fixture.transport.opens.map((e) => e.threadId), ['A', 'B', 'A']);
      final oldA = TestConversationFeed(threadId: 'A', subscriptionId: 'old-A');
      final oldB = TestConversationFeed(threadId: 'B', subscriptionId: 'old-B');
      final newA = TestConversationFeed(threadId: 'A', subscriptionId: 'new-A');
      fixture.transport.opens[2].result.complete(newA);
      await newA.deliver(
        ConversationBaselineEvent(
          baseline: baseline(
            7,
            subscriptionId: 'new-A',
            items: [timelineItem(7, threadId: 'A')],
          ),
        ),
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
        fixture.session('A').content.lastDeliveredFrame,
        isA<ConversationBaselineFrame>().having(
          (f) => f.baseline.version,
          'version',
          7,
        ),
      );
      expect(newA.requestCloseCalls, 0);
      expect((await fixture.close()).complete, isTrue);
      expect(budget.usage, isEmpty);
    },
  );

  test('a pending native close of an older attempt never blocks retiring a fresh attempt of the same owner', () async {
    final budget = ResourceBudget(
      // The gated close of the first A holds its permit until the end;
      // B1/A2 cleanups release asynchronously, so transient demand peaks
      // above four live attempts even though only one is truly pending.
      capacities: {...ResourceBudget().capacities, ResourceKind.chatHandle: 8},
    );
    final fixture = ConversationFixture(budget: budget);
    // A opens first; its native close stays gated to simulate a slow worker.
    fixture.repository.setVisibleThread('A');
    await fixture.transport.opened(0);
    final oldA = TestConversationFeed(threadId: 'A', subscriptionId: 'old-A');
    oldA.closeGate = Completer<void>();
    fixture.transport.opens[0].result.complete(oldA);
    await oldA.deliver(
      ConversationBaselineEvent(
        baseline: baseline(
          1,
          subscriptionId: 'old-A',
          items: [timelineItem(1, threadId: 'A')],
        ),
      ),
    );
    // Leaving A starts its retirement while its native close hangs.
    fixture.repository.setVisibleThread('B');
    await oldA.closeStarted.future;
    await fixture.transport.opened(1);
    final firstB = TestConversationFeed(threadId: 'B', subscriptionId: 'b-1');
    fixture.transport.opens[1].result.complete(firstB);
    await firstB.deliver(
      ConversationBaselineEvent(
        baseline: baseline(
          2,
          subscriptionId: 'b-1',
          items: [timelineItem(2, threadId: 'B')],
        ),
      ),
    );
    // Returning to A must mint a fresh attempt, not resurrect the retired one.
    fixture.repository.setVisibleThread('A');
    await fixture.transport.opened(2);
    final newA = TestConversationFeed(threadId: 'A', subscriptionId: 'new-A');
    fixture.transport.opens[2].result.complete(newA);
    await newA.deliver(
      ConversationBaselineEvent(
        baseline: baseline(
          3,
          subscriptionId: 'new-A',
          items: [timelineItem(3, threadId: 'A')],
        ),
      ),
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
    expect(newA.closeCalls, 1);
    await newA.closeCompleted.future;
    expect(owner.content.currentAttemptId, isNull);
    await fixture.transport.opened(3);
    final secondB = TestConversationFeed(threadId: 'B', subscriptionId: 'b-2');
    fixture.transport.opens[3].result.complete(secondB);
    await secondB.deliver(
      ConversationBaselineEvent(
        baseline: baseline(
          4,
          subscriptionId: 'b-2',
          items: [timelineItem(4, threadId: 'B')],
        ),
      ),
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
    expect(budget.usage, isEmpty);
  });

  test('A -> B -> A synchronous cascade mints a new attempt id for the returning A', () async {
    final budget = ResourceBudget(
      // The cascade runs without awaiting cleanups: both retired permits are
      // still held when the returning A mints its fresh attempt.
      capacities: {...ResourceBudget().capacities, ResourceKind.chatHandle: 4},
    );
    final fixture = ConversationFixture(budget: budget);
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
    expect(budget.usage, isEmpty);
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
      fixture.client.threadDirectory.applyBaseline(
        ThreadDirectoryPage(
          threads: [testThread()],
          nextCursor: null,
          revision: 1,
        ),
        revision: 1,
      );
      fixture.client.selection.selectThread(
        threadId: 'thread',
        workspaceId: 'project',
      );
      expect(visibleTargets, [null]);
      fixture.repository.setVisibleThread('thread');
      expect(visibleTargets, [null, 'thread']);
      await fixture.transport.opened(0);
      final first = TestConversationFeed();
      fixture.transport.opens.first.result.complete(first);
      await first.deliver(ConversationBaselineEvent(baseline: baseline(1)));
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
        ConversationBaselineEvent(baseline: baseline(9, subscriptionId: 'new')),
      );
      expect(
        fixture.session().content.lastDeliveredFrame,
        isA<ConversationBaselineFrame>().having(
          (f) => f.baseline.version,
          'version',
          9,
        ),
      );
      final closing = fixture.close();
      expect(fixture.repository.visibleThreadId.value, isNull);
      expect(visibleTargets, [null, 'thread', null, 'thread', null]);
      await closing;
      observation.cancel();
    },
  );

  test('data delivery is serial: listener completion precedes ACK and next reduction', () async {
    final fixture = ConversationFixture();
    final feed = await fixture.open();
    final content = fixture.session().content;
    final phases = <String>[];
    final observation = content.state.watch((value) {
      if (value.snapshot is ConversationPatchFrame) {
        phases.add('publish');
        expect(feed.acknowledgements, [1]);
      }
    });
    feed.ackGate = Completer<void>();
    feed.send(ConversationUpdateEvent(update: patch(1, 2)));
    await content.state.waitFor(
      (value) => value.snapshot is ConversationPatchFrame,
    );
    expect(phases, ['publish']);
    expect(feed.acknowledgements, [1]);
    // No second consumer and no unbounded async-listen callback chain.
    expect(feed.eventConsumers, 1);
    feed.ackGate!.complete();
    await feed.acknowledged(2);
    expect(feed.acknowledgements, [1, 2]);
    observation.cancel();
    await fixture.close();
  });

  test(
    'close deadline keeps pending open and native close ownership until join',
    () async {
      final budget = ResourceBudget();
      final fixture = ConversationFixture(budget: budget);
      fixture.repository.setVisibleThread('thread');
      final closing = fixture.close(deadline: DateTime.now());
      final report = await closing;
      expect(report.complete, isFalse);
      expect(budget.usage, isNotEmpty);
      final feed = TestConversationFeed()..closeGate = Completer<void>();
      fixture.transport.opens.single.result.complete(feed);
      await feed.closeStarted.future;
      expect(budget.usage, isNotEmpty);
      feed.closeGate!.complete();
      await feed.closeCompleted.future;
      expect((await fixture.client.retryCleanup()).complete, isTrue);
      expect(budget.usage, isEmpty);
    },
  );

  test('failed native close retains permit and explicit cleanup retries same owner', () async {
    final budget = ResourceBudget();
    final fixture = ConversationFixture(budget: budget);
    final feed = await fixture.open();
    feed.closeFailure = StateError('native join failed');
    expect((await fixture.close()).complete, isFalse);
    expect(budget.usage, isNotEmpty);
    feed.closeFailure = null;
    expect((await fixture.client.retryCleanup()).complete, isTrue);
    expect(feed.closeCalls, 2);
    expect(fixture.transport.opens, hasLength(1));
    expect(budget.usage, isEmpty);
  });

  test(
    'terminal control frames use no credit and close does not await an ACK',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open();
      // Revocation occurs before another ACK can be issued.
      fixture.repository.setVisibleThread(null);
      await feed.closeCompleted.future;
      expect(feed.acknowledgements, [1]);
      expect(
        fixture.session().content.state.value,
        isA<ChatIdle<ConversationContentFrame>>(),
      );
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
