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

final class _GatedOwner implements ResourceOwner {
  _GatedOwner(this.lifetime) : attempt = lifetime.nextAttempt() {
    lifetime.register(this);
  }
  final ResourceLifetime lifetime;
  @override
  final int attempt;
  @override
  final String owner = 'retry:gated';
  final List<bool> cleanups = [];
  final firstEntered = Completer<void>();
  final firstGate = Completer<void>();
  final retryEntered = Completer<void>();
  final retryGate = Completer<void>();
  bool _released = false;

  @override
  bool get released => _released;
  @override
  void requestClose() {}
  @override
  List<FeedCloseIssue> get issues => _released ? const [] : const [_retryIssue];

  @override
  Future<void> cleanup({required bool retry}) async {
    cleanups.add(retry);
    if (!retry) {
      if (!firstEntered.isCompleted) firstEntered.complete();
      await firstGate.future;
      return;
    }
    if (!retryEntered.isCompleted) retryEntered.complete();
    await retryGate.future;
    _released = true;
  }
}

void main() {
  test('a retry accepted while the first pass is in flight runs once after it', () async {
    final lifetime = ResourceLifetime(ResourceBudget());
    final owner = _GatedOwner(lifetime);

    // The first pass is genuinely in flight inside the owner.
    expect(
      (await lifetime.close(deadline: DateTime.utc(2000))).complete,
      isFalse,
    );
    await owner.firstEntered.future;
    expect(owner.cleanups, [false]);

    // Overlapping explicit retries are accepted while that pass runs: each only
    // observes a bounded snapshot, and both share one retained retry instead of
    // queueing passes or folding into the running one.
    expect(
      (await lifetime.close(
        retry: true,
        deadline: DateTime.utc(2000),
      )).complete,
      isFalse,
    );
    expect(
      (await lifetime.close(
        retry: true,
        deadline: DateTime.utc(2000),
      )).complete,
      isFalse,
    );
    expect(owner.cleanups, [
      false,
    ], reason: 'The original pass owns the only running cleanup');

    // The unbounded close joins the whole responsibility, retry included.
    final closing = lifetime.close();
    owner.firstGate.complete();
    await owner.retryEntered.future;
    expect(owner.cleanups, [
      false,
      true,
    ], reason: 'The retained retry advances once without another public call');
    owner.retryGate.complete();

    final report = await closing;
    expect(report.complete, isTrue);
    expect(owner.cleanups, [false, true]);
    expect(lifetime.snapshotReport().complete, isTrue);
  });

  test('one explicit retry reaches each owner once even when another owner releases first', () async {
    final budget = ResourceBudget();
    final lifetime = ResourceLifetime(budget);
    final released = ScriptedFeed<int>(
      feedId: 'retry-released',
      sequenceOf: (value) => value,
      isTerminal: (_) => false,
    )..outcome = const FeedCloseOutcome.clean();
    final unresolved = ScriptedFeed<int>(
      feedId: 'retry-unresolved',
      sequenceOf: (value) => value,
      isTerminal: (_) => false,
    )..outcome = FeedCloseOutcome.unresolved(issues: [_retryIssue]);
    final cleanPin = PinnedReadOwner<ScriptedFeed<int>>(
      lifetime: lifetime,
      owner: 'retry:clean',
      open: () async => released,
      request: (value) => value.requestClose(),
      closeNative: (value) => value.close(),
      retryNative: (value) => value.retryClose(),
    );
    final pendingPin = PinnedReadOwner<ScriptedFeed<int>>(
      lifetime: lifetime,
      owner: 'retry:pending',
      open: () async => unresolved,
      request: (value) => value.requestClose(),
      closeNative: (value) => value.close(),
      retryNative: (value) => value.retryClose(),
    );
    try {
      await cleanPin.opened;
      await pendingPin.opened;

      final report = await lifetime.close(retry: true);
      expect(report.complete, isFalse);
      // The first owner really released, so the convergence pass ran.
      expect(
        budget.usage.any((use) => use.owner == 'retry:clean'),
        isFalse,
        reason: 'A Clean owner was released and removed in the first pass',
      );
      expect(
        (released.retryCloseCalls, released.closeCalls),
        (1, 0),
        reason: 'The caller asked for exactly one explicit retry per owner',
      );
      expect(
        (unresolved.retryCloseCalls, unresolved.closeCalls),
        (1, 0),
        reason: 'A later pass only exists because another owner was removed; it must not retry the same original handle again',
      );
      // The unresolved owner keeps its identity, issue and permit.
      expect(budget.used(ResourceKind.readModel), 1);
      expect(
        budget.usage.where((use) => use.owner == 'retry:pending').single.phase,
        ResourcePhase.unresolved,
      );
      expect(
        lifetime
            .snapshotReport()
            .unresolved
            .singleWhere((value) => value.owner == 'retry:pending')
            .issues,
        [_retryIssue],
      );

      // A second explicit retry is a new caller decision and advances once more.
      unresolved.outcome = const FeedCloseOutcome.clean();
      expect((await lifetime.close(retry: true)).complete, isTrue);
      expect(unresolved.retryCloseCalls, 2);
      expect(budget.usage, isEmpty);
    } finally {
      released.outcome = const FeedCloseOutcome.clean();
      unresolved.outcome = const FeedCloseOutcome.clean();
      await lifetime.close(retry: true);
    }
  });

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
