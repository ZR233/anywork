import 'dart:async';

import 'package:anywork_client/anywork_client.dart';
import 'package:test/test.dart';

import 'support/chat_transport.dart';

void main() {
  for (final pendingOpen in [false, true]) {
    test(
      'A B A waits for real capacity after ${pendingOpen ? 'late open' : 'slow close'}',
      () async {
        final budget = ResourceBudget();
        final firstTransport = TestTransport();
        final secondTransport = TestTransport();
        final first = channel(firstTransport, budget: budget);
        final second = channel(secondTransport, budget: budget);
        first.start();
        final oldOpen = firstTransport.opens.single;
        final old = TestHandle(initial: snapshot(8, viewId: 'old'))
          ..closeGate = Completer<void>();
        if (!pendingOpen) {
          oldOpen.complete(old);
          await first.ready;
        }
        first.setDemand(false);
        second.start();
        final middle = TestHandle(initial: snapshot(1, viewId: 'middle'))
          ..closeGate = Completer<void>();
        secondTransport.opens.single.complete(middle);
        await second.ready;
        second.setDemand(false);
        first.start();
        expect(first.state.value, isA<ChatFailed<TestSnapshot>>());
        expect(budget.used(ResourceKind.chatHandle), 2);
        expect(firstTransport.opens, hasLength(1));
        final reopening = first.state.waitFor(
          (state) => state is ChatOpening<TestSnapshot>,
        );
        if (pendingOpen) oldOpen.complete(old);
        await old.closeStarted.future;
        expect(firstTransport.opens, hasLength(1));
        old.closeGate!.complete();
        await reopening.timeout(const Duration(seconds: 2));
        expect(firstTransport.opens, hasLength(2));
        final current = TestHandle(initial: snapshot(1, viewId: 'returned'));
        firstTransport.opens.last.complete(current);
        expect((await first.ready).stamp.viewId, 'returned');
        expect(budget.used(ResourceKind.chatHandle), 2);
        middle.closeGate!.complete();
        await second.joinRetired();
        expect(first.state.value.snapshot?.stamp.viewId, 'returned');
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
      final firstTransport = TestTransport();
      final secondTransport = TestTransport();
      final first = channel(firstTransport, budget: budget);
      final second = channel(secondTransport, budget: budget);
      first.start();
      final handle = TestHandle(initial: snapshot(1));
      firstTransport.opens.single.complete(handle);
      await first.ready;
      second.start();
      expect(second.state.value, isA<ChatFailed<TestSnapshot>>());
      expect((await second.close()).complete, isTrue);
      await first.close();
      expect(secondTransport.opens, isEmpty);
      expect(second.state.value, isA<ChatClosed<TestSnapshot>>());
      expect(budget.usage, isEmpty);
    },
  );

  test(
    'close joins the pending next without publishing another Ready',
    () async {
      final transport = TestTransport();
      final budget = ResourceBudget();
      final owner = channel(transport, budget: budget);
      owner.start();
      final handle = TestHandle(initial: snapshot(1));
      transport.opens.single.complete(handle);
      await owner.ready;
      await handle.nextStarted.future;
      final states = <ChatUiState<TestSnapshot>>[];
      final observation = owner.state.watch(states.add);
      expect((await owner.close()).complete, isTrue);
      expect(states.whereType<ChatReady<TestSnapshot>>(), isEmpty);
      expect(owner.ownedAttemptCount, 0);
      expect(handle.nextCalls, 1);
      expect(handle.closeCalls, 1);
      expect(budget.usage, isEmpty);
      observation.cancel();
    },
  );

  test(
    'repeated EOF exhausts observation retries and retirement never reopens',
    () async {
      final transport = TestTransport();
      final owner = ChatChannel<TestSnapshot, TestFrame, int>(
        threadId: 'thread',
        transport: transport,
        reducer: const ChatSnapshotReducer<String>(),
        retryPolicy: const RetryPolicy(delays: [Duration.zero, Duration.zero]),
      );
      owner.start();
      for (var index = 0; index < 3; index++) {
        final handle = TestHandle(initial: snapshot(1));
        transport.opens[index].complete(handle);
        await owner.ready;
        await handle.nextStarted.future;
        final attempt = owner.currentAttemptId;
        final next = owner.state.waitFor(
          (value) => index < 2
              ? value is ChatOpening<TestSnapshot> &&
                    owner.currentAttemptId != attempt
              : value is ChatFailed<TestSnapshot>,
        );
        handle.emit(null);
        await next;
        await handle.closeCompleted.future;
      }
      expect(transport.opens, hasLength(3));
      owner.setDemand(false);
      expect((await owner.close()).complete, isTrue);
      expect(transport.opens, hasLength(3));
    },
  );

  test(
    'retired control keeps its handle and operation budget until it joins',
    () async {
      final transport = TestTransport();
      final budget = ResourceBudget();
      final owner = channel(transport, budget: budget);
      owner.start();
      final handle = TestHandle(initial: snapshot(1));
      transport.opens.single.complete(handle);
      await owner.ready;
      final command = owner.control((view) => view.focus('item'));
      final rejected = expectLater(command, throwsA(isA<StaleChatAttempt>()));
      await handle.controlStarted.future;
      expect(budget.used(ResourceKind.pendingOperation), 1);
      final report = await owner.close(deadline: DateTime.utc(2000));
      expect(report.complete, isFalse);
      await handle.closeCompleted.future;
      expect(budget.used(ResourceKind.chatHandle), 1);
      handle.controlResult.complete(4);
      await rejected;
      expect((await owner.retryCleanup()).complete, isTrue);
      expect(budget.used(ResourceKind.chatHandle), 0);
      expect(budget.used(ResourceKind.pendingOperation), 0);
    },
  );

  test(
    'late open is closed by its retired attempt without replacing new view',
    () async {
      final transport = TestTransport();
      final owner = channel(transport);
      owner.start();
      final oldOpen = transport.opens.single;
      owner.setDemand(false);
      owner.start();
      final active = TestHandle(initial: snapshot(1, viewId: 'new'));
      transport.opens.last.complete(active);
      expect((await owner.ready).stamp.viewId, 'new');

      final old = TestHandle(initial: snapshot(40, viewId: 'old'));
      oldOpen.complete(old);
      await old.closeCompleted.future;
      expect(old.initialCalls, 0);
      expect(owner.state.value.snapshot?.stamp.viewId, 'new');
      expect((await owner.close()).complete, isTrue);
    },
  );

  test(
    'first Reset failure closes created handle and remains an error',
    () async {
      final transport = TestTransport();
      final owner = channel(transport);
      owner.start();
      final handle = TestHandle();
      transport.opens.single.complete(handle);
      await handle.initialStarted.future;
      final failed = owner.state.waitFor(
        (state) => state is ChatFailed<TestSnapshot>,
      );
      handle.initialResult.completeError(StateError('missing first Reset'));

      final state = await failed;
      expect(state.snapshot, isNull);
      expect((state as ChatFailed<TestSnapshot>).error, isStateError);
      await handle.closeCompleted.future;
      expect((await owner.close()).complete, isTrue);
    },
  );

  test(
    'Patch gap retains last good snapshot and closes only that attempt',
    () async {
      final transport = TestTransport();
      final owner = channel(transport);
      owner.start();
      final handle = TestHandle(initial: snapshot(3));
      transport.opens.single.complete(handle);
      await owner.ready;
      await handle.nextStarted.future;
      final failed = owner.state.waitFor(
        (state) => state is ChatFailed<TestSnapshot>,
      );
      handle.emit(
        ChatPatch(
          from: snapshot(8).stamp,
          to: snapshot(9).stamp,
          changes: const [],
          hasNewer: false,
        ),
      );
      final state = await failed;
      expect(state.snapshot?.stamp.version, 3);
      expect(
        (state as ChatFailed<TestSnapshot>).error,
        isA<ChatProtocolError>(),
      );
      await handle.closeCompleted.future;
      expect(handle.nextCalls, 1);
      await owner.close();
    },
  );

  test(
    'close during initial cancels the view without publishing Ready',
    () async {
      final transport = TestTransport();
      final owner = channel(transport);
      owner.start();
      final handle = TestHandle();
      transport.opens.single.complete(handle);
      await handle.initialStarted.future;
      final states = <ChatUiState<TestSnapshot>>[];
      final observation = owner.state.watch(states.add);

      expect((await owner.close()).complete, isTrue);
      expect(states.whereType<ChatReady<TestSnapshot>>(), isEmpty);
      expect(owner.state.value, isA<ChatClosed<TestSnapshot>>());
      expect(handle.closeCalls, 1);
      observation.cancel();
    },
  );

  test(
    'deadline keeps late open owned and a repeated close joins same result',
    () async {
      final transport = TestTransport();
      final budget = ResourceBudget();
      final owner = channel(transport, budget: budget);
      owner.start();
      final closing = owner.close(deadline: DateTime.utc(2000));
      expect(
        identical(closing, owner.close(deadline: DateTime.utc(2100))),
        isTrue,
      );
      final report = await closing;
      expect(report.unresolved, hasLength(1));
      expect(budget.used(ResourceKind.chatHandle), 1);

      final late = TestHandle(initial: snapshot(1));
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
      final transport = TestTransport();
      final budget = ResourceBudget();
      final owner = channel(transport, budget: budget);
      owner.start();
      final handle = TestHandle(initial: snapshot(1));
      transport.opens.single.complete(handle);
      await owner.ready;
      handle.closeFailure = StateError('native close failed');

      final report = await owner.close();
      expect(report.complete, isFalse);
      expect(budget.used(ResourceKind.chatHandle), 1);
      expect(budget.usage.single.phase, ResourcePhase.unresolved);
      handle.closeFailure = null;
      expect((await owner.retryCleanup()).complete, isTrue);
      expect(budget.used(ResourceKind.chatHandle), 0);
    },
  );

  test('late control reply cannot complete a replacement attempt', () async {
    final transport = TestTransport();
    final owner = channel(transport);
    owner.start();
    final handle = TestHandle(initial: snapshot(1));
    transport.opens.single.complete(handle);
    await owner.ready;
    final command = owner.control((view) => view.focus('item'));
    final assertion = expectLater(command, throwsA(isA<StaleChatAttempt>()));
    await handle.controlStarted.future;
    owner.setDemand(false);
    handle.controlResult.complete(4);
    await assertion;
    expect(owner.state.value, isA<ChatIdle<TestSnapshot>>());
    await owner.close();
  });

  test('old cleanup failure cannot replace a newer Ready attempt', () async {
    final transport = TestTransport();
    final owner = channel(transport);
    owner.start();
    final old = TestHandle(initial: snapshot(3, viewId: 'old'))
      ..closeGate = Completer<void>()
      ..closeFailure = StateError('old native cleanup failed');
    transport.opens.single.complete(old);
    await owner.ready;
    old.emit(null);
    await old.closeStarted.future;
    owner.retry();
    final replacement = TestHandle(initial: snapshot(1, viewId: 'new'));
    transport.opens.last.complete(replacement);
    await owner.ready;
    old.closeGate!.complete();
    await owner.joinRetired();
    expect(owner.state.value, isA<ChatReady<TestSnapshot>>());
    expect(owner.state.value.snapshot?.stamp.viewId, 'new');
    old.closeFailure = null;
    await owner.retryCleanup();
    await owner.close();
  });
}
