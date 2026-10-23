import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/controlled_timers.dart';
import 'support/conversation_fixture.dart';
import 'support/timeline_transport.dart';

Future<({ConversationSession session, TimelineConnectionProbe connection})>
_openReady(ConversationFixture fixture, {
  String threadId = 'thread',
  TestTimelineConnection? native,
  TimelineFrameConsumer? consume,
}) async {
  final index = fixture.timeline.requests.length;
  final session = fixture.select(threadId);
  session.timeline.attachConsumer(consume ?? (_) {});
  final request = await fixture.timeline.opened(index);
  final connection = TimelineConnectionProbe(
    native ?? TestTimelineConnection(initial: baseline(1)),
  );
  request.result.complete(connection);
  await session.timeline.ready;
  await connection.acknowledged(1);
  return (session: session, connection: connection);
}

Matcher _failure(StudioFailureCode code) => isA<StudioFailure>().having(
  (error) => error.code, 'code', code,
);

void main() {
  for (final pendingOpen in [false, true]) {
    test(
      'A B A replaces the concrete Session and waits for ${pendingOpen ? 'late open' : 'slow close'} capacity',
      () async {
        final fixture = ConversationFixture();
        final first = fixture.select('A');
        first.timeline.attachConsumer((_) {});
        final oldOpen = await fixture.timeline.opened(0);
        final old = TimelineConnectionProbe(TestTimelineConnection(
          initial: baseline(8, subscriptionId: 'old',
            items: [timelineItem(8, threadId: 'A')]),
        )..closeGate = Completer<void>());
        if (!pendingOpen) {
          oldOpen.result.complete(old);
          await first.timeline.ready;
          await old.acknowledged(1);
        }

        final middleSession = fixture.select('B');
        middleSession.timeline.attachConsumer((_) {});
        final middleOpen = await fixture.timeline.opened(1);
        final middle = TimelineConnectionProbe(TestTimelineConnection(
          initial: baseline(1, subscriptionId: 'middle',
            items: [timelineItem(1, threadId: 'B')]),
        )..closeGate = Completer<void>());
        middleOpen.result.complete(middle);
        await middleSession.timeline.ready;
        await middle.acknowledged(1);

        final currentSession = fixture.select('A');
        expect(currentSession, isNot(same(first)),
          reason: 'A same-ID Session cannot borrow the retiring A owner');
        currentSession.timeline.attachConsumer((_) {});
        final blocked = await currentSession.timeline.state.waitFor(
          (state) => state.phase == TimelineConnectionPhase.failed,
        );
        expect(blocked.error, _failure(StudioFailureCode.overloaded));
        expect(fixture.budget.used(ResourceKind.chatHandle), 2);
        expect(fixture.timeline.requests, hasLength(2));
        final reopening = fixture.timeline.opened(2);
        if (pendingOpen) oldOpen.result.complete(old);
        await old.native.closeStarted.future;
        expect(fixture.timeline.requests, hasLength(2));
        old.native.closeGate!.complete();

        final reopened = await reopening;
        expect(reopened.threadId, 'A');
        final current = TimelineConnectionProbe(TestTimelineConnection(
          initial: baseline(1, subscriptionId: 'returned',
            items: [timelineItem(1, threadId: 'A')]),
        ));
        reopened.result.complete(current);
        expect((await currentSession.timeline.ready).baseline.subscriptionId, 'returned');
        await current.acknowledged(1);
        expect(fixture.budget.used(ResourceKind.chatHandle), 2);
        middle.native.closeGate!.complete();
        await middle.native.closeCompleted.future;
        expect(fixture.repository.active.value, same(currentSession));
        expect(currentSession.timeline.state.value.lastStamp!.viewId, 'returned');
        expect((await fixture.repository.close()).complete, isTrue);
        expect(old.native.disposeCalls, 1);
        expect(middle.native.disposeCalls, 1);
        expect(current.native.disposeCalls, 1);
        expect(fixture.budget.usage, isEmpty);
      },
    );
  }

  test('closing a capacity-blocked Session cancels its availability observation', () async {
    final budget = ResourceBudget(capacities: {
      ...ResourceBudget().capacities,
      ResourceKind.chatHandle: 1,
    });
    final first = ConversationFixture(budget: budget);
    final second = ConversationFixture(budget: budget);
    await _openReady(first);
    final blocked = second.select('other');
    blocked.timeline.attachConsumer((_) {});
    final failed = await blocked.timeline.state.waitFor(
      (state) => state.phase == TimelineConnectionPhase.failed,
    );
    expect(failed.error, _failure(StudioFailureCode.overloaded));
    expect((await second.repository.close()).complete, isTrue);
    expect((await first.repository.close()).complete, isTrue);
    expect(second.timeline.requests, isEmpty);
    expect(blocked.timeline.state.value.phase, TimelineConnectionPhase.closed);
    expect(budget.usage, isEmpty);
  });

  test('close joins the pending feed without publishing another Ready', () async {
    final fixture = ConversationFixture();
    final frames = <StudioTimelineFrame>[];
    final ready = await _openReady(fixture, consume: frames.add);
    final states = <TimelineConnectionState>[];
    final observation = ready.session.timeline.state.watch(states.add);
    expect((await fixture.repository.close()).complete, isTrue);
    expect(states.where((state) => state.phase == TimelineConnectionPhase.ready), isEmpty);
    expect(frames, hasLength(1));
    expect(ready.connection.native.acks, [1]);
    expect(ready.connection.native.disposeCalls, 1);
    expect(observation.isCancelled, isTrue);
    expect(fixture.budget.usage, isEmpty);
  });

  test('repeated EOF exhausts real observation retries and retirement never reopens', () async {
    final timers = ControlledTimers();
    await runZoned(() async {
      final fixture = ConversationFixture();
      final session = fixture.select('thread');
      session.timeline.attachConsumer((_) {});
      for (var index = 0; index < 4; index++) {
        if (index > 0) await timers.fireNext();
        final request = await fixture.timeline.opened(index);
        final connection = TimelineConnectionProbe(TestTimelineConnection(
          initial: baseline(1, subscriptionId: 'eof-$index'),
        ));
        request.result.complete(connection);
        await session.timeline.ready;
        await connection.acknowledged(1);
        final attempt = session.timeline.state.value.attemptId;
        final failure = session.timeline.state.waitFor((state) =>
          state.attemptId == attempt && state.phase == TimelineConnectionPhase.failed);
        connection.native.emitClosed();
        final state = await failure;
        expect(state.error, _failure(StudioFailureCode.unavailable));
        expect(state.retryExhausted, index == 3);
        await connection.native.closeCompleted.future;
      }
      expect(fixture.timeline.requests, hasLength(4));
      fixture.deselect();
      expect((await fixture.repository.close()).complete, isTrue);
      expect(timers.hasPending, isFalse);
      expect(fixture.timeline.requests, hasLength(4));
      expect(fixture.budget.usage, isEmpty);
    }, zoneSpecification: timers.specification);
  });

  test('late open closes its retired Session without replacing the new view', () async {
    final fixture = ConversationFixture();
    final oldSession = fixture.select('thread');
    oldSession.timeline.attachConsumer((_) {});
    final oldOpen = await fixture.timeline.opened(0);
    fixture.deselect();
    final currentSession = fixture.select('thread');
    expect(currentSession, isNot(same(oldSession)));
    currentSession.timeline.attachConsumer((_) {});
    final active = TimelineConnectionProbe(TestTimelineConnection(
      initial: baseline(1, subscriptionId: 'new'),
    ));
    (await fixture.timeline.opened(1)).result.complete(active);
    expect((await currentSession.timeline.ready).baseline.subscriptionId, 'new');
    await active.acknowledged(1);

    final old = TestTimelineConnection(initial: baseline(40, subscriptionId: 'old'));
    oldOpen.result.complete(old);
    await old.closeCompleted.future;
    expect(old.wasSubscribed, isFalse);
    expect(old.disposeCalls, 1);
    expect(fixture.repository.active.value, same(currentSession));
    expect(currentSession.timeline.state.value.lastStamp!.viewId, 'new');
    expect((await fixture.repository.close()).complete, isTrue);
    expect(fixture.budget.usage, isEmpty);
  });

  test('first baseline failure keeps its typed error and closes the created handle', () async {
    final fixture = ConversationFixture();
    final session = fixture.select('thread');
    final frames = <StudioTimelineFrame>[];
    session.timeline.attachConsumer(frames.add);
    final states = <TimelineConnectionState>[];
    final observation = session.timeline.state.watch(states.add);
    final request = await fixture.timeline.opened(0);
    final connection = TestTimelineConnection();
    request.result.complete(connection);
    const error = StudioFailure(code: StudioFailureCode.storage,
      message: 'The first baseline could not be read', retryable: false,
      correlationId: 'first-baseline-failed');
    final readyFailure = expectLater(session.timeline.ready, throwsA(same(error)));
    await connection.subscribed.future;
    final failed = session.timeline.state.waitFor(
      (state) => state.phase == TimelineConnectionPhase.failed,
    );
    connection.emitStreamError(error);
    final state = await failed;
    expect(state.lastStamp, isNull);
    expect(state.error, same(error));
    expect(frames, isEmpty);
    expect(states.where((state) => state.phase == TimelineConnectionPhase.ready), isEmpty);
    await readyFailure;
    await connection.closeCompleted.future;
    observation.cancel();
    expect((await fixture.repository.close()).complete, isTrue);
  });

  test('patch gap retains last-good provenance and does not ACK the broken frame', () async {
    final fixture = ConversationFixture();
    final frames = <StudioTimelineFrame>[];
    final ready = await _openReady(fixture,
      native: TestTimelineConnection(initial: baseline(3)), consume: frames.add);
    final failed = ready.session.timeline.state.waitFor(
      (state) => state.phase == TimelineConnectionPhase.failed,
    );
    ready.connection.native.emit(patch(8, 9));
    final state = await failed;
    expect(state.lastStamp!.version, 3);
    expect(state.error, _failure(StudioFailureCode.protocol));
    expect((frames.single as StudioTimelineBaselineFrame).baseline.version, 3);
    await ready.connection.native.closeCompleted.future;
    expect(ready.connection.native.acks, [1]);
    expect((await fixture.repository.close()).complete, isTrue);
  });

  test('close before the initial baseline never publishes Ready', () async {
    final fixture = ConversationFixture();
    final session = fixture.select('thread');
    session.timeline.attachConsumer((_) {});
    final request = await fixture.timeline.opened(0);
    final connection = TestTimelineConnection();
    request.result.complete(connection);
    await connection.subscribed.future;
    final states = <TimelineConnectionState>[];
    final observation = session.timeline.state.watch(states.add);
    final ready = expectLater(session.timeline.ready,
      throwsA(_failure(StudioFailureCode.cancelled)));
    expect((await fixture.repository.close()).complete, isTrue);
    await ready;
    expect(states.where((state) => state.phase == TimelineConnectionPhase.ready), isEmpty);
    expect(session.timeline.state.value.phase, TimelineConnectionPhase.closed);
    expect(connection.acks, isEmpty);
    expect(connection.disposeCalls, 1);
    expect(observation.isCancelled, isTrue);
  });

  test('deadline retains the late open and repeated close reports the same owner', () async {
    final fixture = ConversationFixture();
    final session = fixture.select('thread');
    session.timeline.attachConsumer((_) {});
    final request = await fixture.timeline.opened(0);
    final report = await fixture.repository.close(deadline: DateTime.utc(2000));
    final timeline = report.unresolved.where((owner) => owner.owner == 'timeline:thread').single;
    expect(timeline.issues.any((issue) => issue.recovery == CleanupRecovery.awaitCompletion), isTrue);
    expect(fixture.budget.used(ResourceKind.chatHandle), 1);
    final again = await fixture.repository.close(deadline: DateTime.utc(2000));
    expect(again.unresolved.where((owner) => owner.owner == 'timeline:thread').single.attemptId,
      timeline.attemptId);

    final late = TestTimelineConnection(initial: baseline(1));
    request.result.complete(late);
    await late.closeCompleted.future;
    expect(late.wasSubscribed, isFalse);
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(fixture.budget.usage, isEmpty);
  });

  test('close failure retains its diagnostic and permit until explicit cleanup', () async {
    final fixture = ConversationFixture();
    final ready = await _openReady(fixture);
    ready.connection.native.closeFailure = const StudioFailure(
      code: StudioFailureCode.unavailable, message: 'Native close failed',
      retryable: false, correlationId: 'native-close-failed');
    final report = await fixture.repository.close();
    expect(report.complete, isFalse);
    expect(report.unresolved.expand((owner) => owner.issues).any((issue) =>
      issue.diagnostic.correlationId == 'native-close-failed' &&
      issue.recovery == CleanupRecovery.retryClose), isTrue);
    expect(fixture.budget.used(ResourceKind.chatHandle), 1);
    expect(fixture.budget.usage.where((use) => use.kind == ResourceKind.chatHandle)
      .single.phase, ResourcePhase.unresolved);
    ready.connection.native.closeFailure = null;
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(ready.connection.native.retryCloseCalls, 1);
    expect(fixture.budget.usage, isEmpty);
  });

  test('old cleanup failure cannot replace a newer Ready attempt', () async {
    final fixture = ConversationFixture();
    final old = TestTimelineConnection(initial: baseline(3, subscriptionId: 'old'))
      ..closeGate = Completer<void>()
      ..closeFailure = const StudioFailure(code: StudioFailureCode.unavailable,
        message: 'Old native cleanup failed', retryable: true,
        correlationId: 'old-cleanup-failed');
    final ready = await _openReady(fixture, native: old);
    old.emitClosed();
    await old.closeStarted.future;
    ready.session.timeline.refresh();
    final replacement = TimelineConnectionProbe(TestTimelineConnection(
      initial: baseline(1, subscriptionId: 'new'),
    ));
    (await fixture.timeline.opened(1)).result.complete(replacement);
    await ready.session.timeline.ready;
    await replacement.acknowledged(1);
    old.closeGate!.complete();
    await old.closeCompleted.future;
    expect(ready.session.timeline.state.value.phase, TimelineConnectionPhase.ready);
    expect(ready.session.timeline.state.value.lastStamp!.viewId, 'new');
    old.closeFailure = null;
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(fixture.budget.usage, isEmpty);
  });

  test('a different subscription identity cannot adopt the delivered baseline', () async {
    final fixture = ConversationFixture();
    final ready = await _openReady(fixture);
    final failed = ready.session.timeline.state.waitFor(
      (state) => state.phase == TimelineConnectionPhase.failed,
    );
    ready.connection.native.emit(StudioTimelineResync(
      subscriptionId: 'other', reason: StudioTimelineResyncReason.lagging,
      baseline: baseline(4, subscriptionId: 'other'),
    ));
    expect((await failed).error, _failure(StudioFailureCode.protocol));
    await ready.connection.native.closeCompleted.future;
    expect(ready.connection.native.acks, [1]);
    expect((await fixture.repository.close()).complete, isTrue);
  });

  test('unresolved close retains all typed issues and recovers only on the original handle', () async {
    final fixture = ConversationFixture();
    final ready = await _openReady(fixture);
    final issue = FeedCloseIssue(diagnostic: const StudioShutdownIssue(
      stage: 'delivery', code: 'cancelled',
      message: 'A delivery call is still in flight', retryable: true,
      correlationId: 'issue-1'), recovery: CleanupRecovery.awaitCompletion);
    ready.connection.native.closeReport = FeedCloseReport(feedId: 'sub',
      outcome: FeedCloseOutcome.unresolved(issues: [issue]));
    final report = await fixture.repository.close();
    expect(report.complete, isFalse);
    expect(report.unresolved.expand((owner) => owner.issues), contains(issue));
    expect(fixture.budget.used(ResourceKind.chatHandle), 1);
    final closeCalls = ready.connection.native.closeCalls;
    expect((await fixture.repository.close()).complete, isFalse);
    expect(ready.connection.native.closeCalls, closeCalls,
      reason: 'Ordinary close never replays completed cleanup');
    final waiting = await fixture.repository.retryCleanup();
    expect(waiting.complete, isFalse);
    expect(waiting.unresolved.expand((owner) => owner.issues), contains(issue));
    expect(ready.connection.native.retryCloseCalls, 1);
    expect(ready.connection.native.disposeCalls, 0);
    ready.connection.native.closeReport = FeedCloseReport(feedId: 'sub',
      outcome: const FeedCloseOutcome.clean());
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(ready.connection.native.retryCloseCalls, 2);
    expect(ready.connection.native.disposeCalls, 1);
    expect(fixture.timeline.requests, hasLength(1));
    expect(fixture.budget.usage, isEmpty);
  });

  test('close joins an entered body consumer and never ACKs it after sealing', () async {
    final fixture = ConversationFixture();
    final session = fixture.select('thread');
    final entered = Completer<void>();
    final receipt = Completer<void>();
    final consumer = session.timeline.attachConsumer((_) {
      entered.complete();
      return receipt.future;
    });
    final connection = TimelineConnectionProbe(TestTimelineConnection(initial: baseline(1)));
    (await fixture.timeline.opened(0)).result.complete(connection);
    await session.timeline.ready;
    await entered.future;
    final report = await fixture.repository.close(deadline: DateTime.utc(2000));
    expect(report.complete, isFalse);
    expect(report.unresolved.expand((owner) => owner.issues).any((issue) =>
      issue.diagnostic.code == 'handoffPending' &&
      issue.recovery == CleanupRecovery.awaitCompletion), isTrue);
    expect(connection.native.acks, isEmpty);
    expect(fixture.budget.used(ResourceKind.chatHandle), 1);
    var joined = false;
    final closingConsumer = consumer.close().then((_) => joined = true);
    expect(joined, isFalse);
    receipt.complete();
    await closingConsumer;
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(connection.native.acks, isEmpty);
    expect(fixture.budget.usage, isEmpty);
  });

  test('an admitted consumer failure after sealing remains on its actual owner', () async {
    final fixture = ConversationFixture();
    final session = fixture.select('thread');
    final entered = Completer<void>();
    final receipt = Completer<void>();
    final consumer = session.timeline.attachConsumer((_) {
      entered.complete();
      return receipt.future;
    });
    final connection = TimelineConnectionProbe(TestTimelineConnection(initial: baseline(1)));
    (await fixture.timeline.opened(0)).result.complete(connection);
    await session.timeline.ready;
    await entered.future;
    expect((await fixture.repository.close(deadline: DateTime.utc(2000))).complete, isFalse);
    const error = StudioFailure(code: StudioFailureCode.storage,
      message: 'The accepted display handoff failed', retryable: true,
      correlationId: 'consumer-after-seal');
    receipt.completeError(error);
    await consumer.close();
    final report = await fixture.repository.retryCleanup();
    expect(report.complete, isFalse,
      reason: 'Sealing admission cannot erase a failure from an entered callback');
    final issue = report.unresolved.expand((owner) => owner.issues).singleWhere(
      (issue) => issue.diagnostic.correlationId == error.correlationId);
    expect(issue.diagnostic.code, 'storage');
    expect(issue.diagnostic.retryable, isTrue);
    expect(issue.recovery, CleanupRecovery.terminal,
      reason: 'The failed consumer callback has no independent replay capability');
    expect(connection.native.acks, isEmpty);
    expect(fixture.budget.used(ResourceKind.chatHandle), 1);
  });
}
