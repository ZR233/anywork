import 'dart:async';

import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/scripted_feed.dart';

const _retryIssue = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'native-read',
    code: 'readJoinPending',
    message: 'The original native join needs an explicit retry.',
    retryable: true,
    correlationId: 'snapshot-native-read',
  ),
  recovery: CleanupRecovery.retryClose,
);

void main() {
  test('snapshots retain live owners and work without starting close or preventing later admission and recovery', () async {
    final budget = ResourceBudget();
    final lifetime = ResourceLifetime(budget);
    final native = ScriptedFeed<int>(
      feedId: 'snapshot-read',
      sequenceOf: (value) => value,
      isTerminal: (_) => false,
    );
    final workEntered = Completer<void>();
    final workReply = Completer<int>();
    final readEntered = Completer<void>();
    final readReply = Completer<String>();
    var sealCalls = 0;
    lifetime.onSeal(() => sealCalls++);

    expect(lifetime.snapshotReport().complete, isTrue);
    final work = lifetime.run('snapshot:work', () {
      workEntered.complete();
      return workReply.future;
    });
    final pin = PinnedReadOwner<ScriptedFeed<int>>(
      lifetime: lifetime,
      owner: 'snapshot:pin',
      open: () async => native,
      request: (value) => value.requestClose(),
      closeNative: (value) => value.close(),
      retryNative: (value) => value.retryClose(),
    );
    final reading = pin.use((_) {
      readEntered.complete();
      return readReply.future;
    });
    try {
      await Future.wait([workEntered.future, readEntered.future]);
      final cause = Object();
      final stack = StackTrace.current;
      lifetime.lastCause = cause;
      lifetime.lastStack = stack;
      final attempt = lifetime.nextAttempt();
      final usage = List<ResourceUsage>.of(budget.usage);
      final snapshot = lifetime.snapshotReport();
      expect(lifetime.snapshotReport(), snapshot);
      expect(
        lifetime.nextAttempt(),
        attempt + 1,
        reason: 'Reading a report must not allocate another attempt',
      );
      final resource = snapshot.unresolved.singleWhere(
        (value) => value.attemptId == AttemptId(pin.attempt),
      );
      expect(resource.owner, 'snapshot:pin');
      expect(resource.issues.single.recovery, CleanupRecovery.awaitCompletion);
      expect(
        snapshot.unresolved.any((value) => value.owner == 'snapshot:work'),
        isTrue,
      );
      expect(
        snapshot.unresolved.any(
          (value) =>
              value.owner == 'snapshot:pin' &&
              value.attemptId != AttemptId(pin.attempt),
        ),
        isTrue,
        reason: 'The active use is distinct from its original read owner',
      );
      expect(lifetime.lastCause, same(cause));
      expect(lifetime.lastStack, same(stack));
      expect(lifetime.sealed, isFalse);
      expect(pin.accepting, isTrue);
      expect(sealCalls, 0);
      expect(
        (native.requestCloseCalls, native.closeCalls, native.retryCloseCalls),
        (0, 0, 0),
      );
      expect(budget.usage, usage);
      expect(await lifetime.run('snapshot:later-work', () async => 7), 7);
      expect(
        await pin.use((_) async => 'later read'),
        'later read',
        reason: 'Neither empty nor nonempty reports seal existing admission',
      );

      workReply.complete(11);
      readReply.complete('original read');
      expect(await work, 11);
      expect(await reading, 'original read');
      expect(
        snapshot.unresolved.any((value) => value.owner == 'snapshot:work'),
        isTrue,
        reason:
            'An earlier snapshot is not a lazy view of the changing work set',
      );
      expect(
        lifetime.snapshotReport().unresolved.any(
          (value) => value.owner == 'snapshot:work',
        ),
        isFalse,
      );
      expect(
        lifetime.snapshotReport().complete,
        isFalse,
        reason: 'The read pin is still owned until actual close',
      );
      expect(native.closeCalls, 0);

      native.outcome = FeedCloseOutcome.unresolved(issues: [_retryIssue]);
      final unresolved = await lifetime.close();
      expect(unresolved.complete, isFalse);
      final original = unresolved.unresolved.singleWhere(
        (value) => value.attemptId == AttemptId(pin.attempt),
      );
      expect(original.issues, [_retryIssue]);
      final calls = (
        native.requestCloseCalls,
        native.closeCalls,
        native.retryCloseCalls,
      );
      final unresolvedUsage = List<ResourceUsage>.of(budget.usage);
      final before = lifetime.nextAttempt();
      expect(lifetime.snapshotReport(), unresolved);
      expect(lifetime.snapshotReport(), unresolved);
      expect(lifetime.nextAttempt(), before + 1);
      expect((
        native.requestCloseCalls,
        native.closeCalls,
        native.retryCloseCalls,
      ), calls);
      expect(budget.usage, unresolvedUsage);
      expect(sealCalls, 1);
      native.outcome = const FeedCloseOutcome.clean();
      expect((await lifetime.close(retry: true)).complete, isTrue);
      expect(native.retryCloseCalls, 1);
      expect(lifetime.snapshotReport().complete, isTrue);
      expect(original.issues, [
        _retryIssue,
      ], reason: 'A later Clean must not mutate already captured typed issues');
      expect(budget.usage, isEmpty);
    } finally {
      if (!workReply.isCompleted) workReply.complete(11);
      if (!readReply.isCompleted) readReply.complete('original read');
      await work;
      await reading;
      native.outcome = const FeedCloseOutcome.clean();
      await lifetime.close(retry: true);
    }
  });

  test('a snapshot preserves terminal seal failure and pending work without replaying or clearing either responsibility', () async {
    final lifetime = ResourceLifetime(ResourceBudget());
    const failure = StudioFailure(
      code: StudioFailureCode.internal,
      message: 'The original seal callback failed.',
      retryable: false,
      correlationId: 'snapshot-seal',
    );
    var sealCalls = 0;
    lifetime.onSeal(() {
      sealCalls++;
      throw failure;
    });
    final entered = Completer<void>();
    final reply = Completer<void>();
    final work = lifetime.run('snapshot:pending-at-seal', () {
      entered.complete();
      return reply.future;
    });
    try {
      await entered.future;
      final closed = await lifetime.close(deadline: DateTime.utc(2000));
      final terminal = closed.unresolved.singleWhere(
        (value) => value.issues.any(
          (issue) => issue.recovery == CleanupRecovery.terminal,
        ),
      );
      expect(
        terminal.issues.single.diagnostic.code,
        StudioFailureCode.internal.name,
      );
      expect(
        terminal.issues.single.diagnostic.correlationId,
        failure.correlationId,
      );
      expect(
        closed.unresolved.any(
          (value) => value.owner == 'snapshot:pending-at-seal',
        ),
        isTrue,
      );
      final cause = lifetime.lastCause;
      final stack = lifetime.lastStack;
      final attempt = lifetime.nextAttempt();
      expect(lifetime.snapshotReport(), closed);
      expect(lifetime.snapshotReport(), closed);
      expect(lifetime.nextAttempt(), attempt + 1);
      expect(lifetime.lastCause, same(cause));
      expect(lifetime.lastStack, same(stack));
      expect(sealCalls, 1);
      reply.complete();
      await work;
      final settled = await lifetime.close(retry: true);
      expect(
        settled.unresolved,
        [terminal],
        reason: 'Joining pending work cannot erase the independent terminal failure',
      );
      expect(lifetime.snapshotReport(), settled);
      expect(
        closed.unresolved.any(
          (value) => value.owner == 'snapshot:pending-at-seal',
        ),
        isTrue,
      );
      expect(sealCalls, 1);
    } finally {
      if (!reply.isCompleted) reply.complete();
      await work;
      await lifetime.close(retry: true);
    }
  });
}
