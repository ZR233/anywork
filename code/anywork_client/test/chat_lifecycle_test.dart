import 'dart:async';

import 'package:anywork_client/anywork_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

void main() {
  for (final pendingOpen in [false, true]) {
    test(
      'A B A waits for real capacity after ${pendingOpen ? 'late open' : 'slow close'}',
      () async {
        final budget = ResourceBudget();
        final firstTransport = TestTimelineTransport();
        final secondTransport = TestTimelineTransport();
        final first = timelineChannel(firstTransport, budget: budget);
        final second = timelineChannel(secondTransport, budget: budget);
        first.start();
        final oldOpen = firstTransport.opens.single;
        final old = TestTimelineConnection(
          initial: baseline(8, subscriptionId: 'old'),
        )..closeGate = Completer<void>();
        if (!pendingOpen) {
          oldOpen.complete(old);
          await first.ready;
        }
        first.setDemand(false);
        second.start();
        final middle = TestTimelineConnection(
          initial: baseline(1, subscriptionId: 'middle'),
        )..closeGate = Completer<void>();
        secondTransport.opens.single.complete(middle);
        await second.ready;
        second.setDemand(false);
        first.start();
        expect(first.state.value, isA<ChatFailed<StudioTimelineFrame>>());
        expect(budget.used(ResourceKind.chatHandle), 2);
        expect(firstTransport.opens, hasLength(1));
        final reopening = first.state.waitFor(
          (state) => state is ChatOpening<StudioTimelineFrame>,
        );
        if (pendingOpen) oldOpen.complete(old);
        await old.closeStarted.future;
        expect(firstTransport.opens, hasLength(1));
        old.closeGate!.complete();
        await reopening.timeout(const Duration(seconds: 2));
        expect(firstTransport.opens, hasLength(2));
        final current = TestTimelineConnection(
          initial: baseline(1, subscriptionId: 'returned'),
        );
        firstTransport.opens.last.complete(current);
        expect((await first.ready).baseline.subscriptionId, 'returned');
        expect(budget.used(ResourceKind.chatHandle), 2);
        middle.closeGate!.complete();
        await second.joinRetired();
        final delivered = first.state.value.snapshot;
        expect(
          (delivered as StudioTimelineBaselineFrame).baseline.subscriptionId,
          'returned',
        );
        expect((await first.close()).complete, isTrue);
        expect((await second.close()).complete, isTrue);
        expect(budget.usage, isEmpty);
      },
    );
  }

  test(
    'closing a capacity-blocked channel cancels its observation demand',
    () async {
      final budget = ResourceBudget(capacities: {ResourceKind.chatHandle: 1});
      final firstTransport = TestTimelineTransport();
      final secondTransport = TestTimelineTransport();
      final first = timelineChannel(firstTransport, budget: budget);
      final second = timelineChannel(secondTransport, budget: budget);
      first.start();
      final connection = TestTimelineConnection(initial: baseline(1));
      firstTransport.opens.single.complete(connection);
      await first.ready;
      second.start();
      expect(second.state.value, isA<ChatFailed<StudioTimelineFrame>>());
      expect((await second.close()).complete, isTrue);
      await first.close();
      expect(secondTransport.opens, isEmpty);
      expect(second.state.value, isA<ChatClosed<StudioTimelineFrame>>());
      expect(budget.usage, isEmpty);
    },
  );

  test(
    'close joins the pending next without publishing another Ready',
    () async {
      final transport = TestTimelineTransport();
      final budget = ResourceBudget();
      final owner = timelineChannel(transport, budget: budget);
      owner.start();
      final connection = TestTimelineConnection(initial: baseline(1));
      transport.opens.single.complete(connection);
      await owner.ready;
      await connection.nextStarted.future;
      final states = <ChatUiState<StudioTimelineFrame>>[];
      final observation = owner.state.watch(states.add);
      expect((await owner.close()).complete, isTrue);
      expect(states.whereType<ChatReady<StudioTimelineFrame>>(), isEmpty);
      expect(owner.ownedAttemptCount, 0);
      expect(connection.nextCalls, 1);
      expect(connection.closeCalls, 1);
      expect(budget.usage, isEmpty);
      observation.cancel();
    },
  );

  test(
    'repeated EOF exhausts observation retries and retirement never reopens',
    () async {
      final transport = TestTimelineTransport();
      final owner = StudioTimelineChannel(
        threadId: 'thread',
        transport: transport,
        retryPolicy: const RetryPolicy(delays: [Duration.zero, Duration.zero]),
      );
      owner.start();
      for (var index = 0; index < 3; index++) {
        final connection = TestTimelineConnection(initial: baseline(1));
        transport.opens[index].complete(connection);
        await owner.ready;
        await connection.nextStarted.future;
        final attempt = owner.currentAttemptId;
        final next = owner.state.waitFor(
          (value) => index < 2
              ? value is ChatOpening<StudioTimelineFrame> &&
                    owner.currentAttemptId != attempt
              : value is ChatFailed<StudioTimelineFrame>,
        );
        // EOF 是显式错误，不是“正常结束”：它必须走重试/失败路径。
        connection.emit(null);
        await next;
        await connection.closeCompleted.future;
      }
      expect(transport.opens, hasLength(3));
      owner.setDemand(false);
      expect((await owner.close()).complete, isTrue);
      expect(transport.opens, hasLength(3));
    },
  );

  test(
    'late open is closed by its retired attempt without replacing new view',
    () async {
      final transport = TestTimelineTransport();
      final owner = timelineChannel(transport);
      owner.start();
      final oldOpen = transport.opens.single;
      owner.setDemand(false);
      owner.start();
      final active = TestTimelineConnection(
        initial: baseline(1, subscriptionId: 'new'),
      );
      transport.opens.last.complete(active);
      expect((await owner.ready).baseline.subscriptionId, 'new');

      final old = TestTimelineConnection(
        initial: baseline(40, subscriptionId: 'old'),
      );
      oldOpen.complete(old);
      await old.closeCompleted.future;
      expect(old.initialCalls, 0);
      final delivered =
          owner.state.value.snapshot! as StudioTimelineBaselineFrame;
      expect(delivered.baseline.subscriptionId, 'new');
      expect((await owner.close()).complete, isTrue);
    },
  );

  test(
    'first baseline failure closes created handle and remains an error',
    () async {
      final transport = TestTimelineTransport();
      final owner = timelineChannel(transport);
      owner.start();
      final connection = TestTimelineConnection();
      transport.opens.single.complete(connection);
      await connection.initialStarted.future;
      final failed = owner.state.waitFor(
        (state) => state is ChatFailed<StudioTimelineFrame>,
      );
      connection.initialResult.completeError(
        StateError('missing first baseline'),
      );

      final state = await failed;
      expect(state.snapshot, isNull);
      expect((state as ChatFailed<StudioTimelineFrame>).error, isStateError);
      await connection.closeCompleted.future;
      expect((await owner.close()).complete, isTrue);
    },
  );

  test(
    'patch gap retains last good frame and closes only that attempt',
    () async {
      final transport = TestTimelineTransport();
      final owner = timelineChannel(transport);
      owner.start();
      final connection = TestTimelineConnection(initial: baseline(3));
      transport.opens.single.complete(connection);
      await owner.ready;
      await connection.nextStarted.future;
      final failed = owner.state.waitFor(
        (state) => state is ChatFailed<StudioTimelineFrame>,
      );
      // from 既不等于已交付版本：连续性无法证明，必须显式失败而不是猜测删除。
      connection.emit(patch(8, 9));
      final state = await failed;
      final lastGood = state.snapshot! as StudioTimelineBaselineFrame;
      expect(lastGood.baseline.version, 3);
      expect(
        (state as ChatFailed<StudioTimelineFrame>).error,
        isA<TimelineContinuityError>(),
      );
      await connection.closeCompleted.future;
      expect(connection.nextCalls, 1);
      await owner.close();
    },
  );

  test(
    'close during initial cancels the connection without publishing Ready',
    () async {
      final transport = TestTimelineTransport();
      final owner = timelineChannel(transport);
      owner.start();
      final connection = TestTimelineConnection();
      transport.opens.single.complete(connection);
      await connection.initialStarted.future;
      final states = <ChatUiState<StudioTimelineFrame>>[];
      final observation = owner.state.watch(states.add);

      expect((await owner.close()).complete, isTrue);
      expect(states.whereType<ChatReady<StudioTimelineFrame>>(), isEmpty);
      expect(owner.state.value, isA<ChatClosed<StudioTimelineFrame>>());
      expect(connection.closeCalls, 1);
      observation.cancel();
    },
  );

  test(
    'deadline keeps late open owned and a repeated close joins same result',
    () async {
      final transport = TestTimelineTransport();
      final budget = ResourceBudget();
      final owner = timelineChannel(transport, budget: budget);
      owner.start();
      final closing = owner.close(deadline: DateTime.utc(2000));
      expect(
        identical(closing, owner.close(deadline: DateTime.utc(2100))),
        isTrue,
      );
      final report = await closing;
      expect(report.unresolved, hasLength(1));
      expect(budget.used(ResourceKind.chatHandle), 1);

      final late = TestTimelineConnection(initial: baseline(1));
      transport.opens.single.complete(late);
      await late.closeCompleted.future;
      expect(late.initialCalls, 0);
      expect((await owner.retryCleanup()).complete, isTrue);
      expect(budget.used(ResourceKind.chatHandle), 0);
    },
  );

  test(
    'close failure holds a permit until explicit cleanup succeeds',
    () async {
      final transport = TestTimelineTransport();
      final budget = ResourceBudget();
      final owner = timelineChannel(transport, budget: budget);
      owner.start();
      final connection = TestTimelineConnection(initial: baseline(1));
      transport.opens.single.complete(connection);
      await owner.ready;
      connection.closeFailure = StateError('native close failed');

      final report = await owner.close();
      expect(report.complete, isFalse);
      expect(budget.used(ResourceKind.chatHandle), 1);
      expect(budget.usage.single.phase, ResourcePhase.unresolved);
      connection.closeFailure = null;
      expect((await owner.retryCleanup()).complete, isTrue);
      expect(budget.used(ResourceKind.chatHandle), 0);
    },
  );

  test('old cleanup failure cannot replace a newer Ready attempt', () async {
    final transport = TestTimelineTransport();
    final owner = timelineChannel(transport);
    owner.start();
    final old =
        TestTimelineConnection(initial: baseline(3, subscriptionId: 'old'))
          ..closeGate = Completer<void>()
          ..closeFailure = StateError('old native cleanup failed');
    transport.opens.single.complete(old);
    await owner.ready;
    old.emit(null);
    await old.closeStarted.future;
    owner.refresh();
    final replacement = TestTimelineConnection(
      initial: baseline(1, subscriptionId: 'new'),
    );
    transport.opens.last.complete(replacement);
    await owner.ready;
    old.closeGate!.complete();
    await owner.joinRetired();
    expect(owner.state.value, isA<ChatReady<StudioTimelineFrame>>());
    final delivered =
        owner.state.value.snapshot! as StudioTimelineBaselineFrame;
    expect(delivered.baseline.subscriptionId, 'new');
    old.closeFailure = null;
    await owner.retryCleanup();
    await owner.close();
  });

  test(
    'a new subscription identity cannot adopt the delivered baseline',
    () async {
      final transport = TestTimelineTransport();
      final owner = timelineChannel(transport);
      owner.start();
      final connection = TestTimelineConnection(initial: baseline(1));
      transport.opens.single.complete(connection);
      await owner.ready;
      await connection.nextStarted.future;
      final failed = owner.state.waitFor(
        (state) => state is ChatFailed<StudioTimelineFrame>,
      );
      connection.emit(
        StudioTimelineResync(
          subscriptionId: 'other',
          reason: StudioTimelineResyncReason.lagging,
          baseline: baseline(4, subscriptionId: 'other'),
        ),
      );
      final state = await failed;
      expect(
        (state as ChatFailed<StudioTimelineFrame>).error,
        isA<TimelineContinuityError>(),
      );
      await connection.closeCompleted.future;
      await owner.close();
    },
  );
}
