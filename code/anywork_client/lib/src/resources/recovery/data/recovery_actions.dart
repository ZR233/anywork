import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/recovery_state.dart';
import '../domain/recovery_values.dart';
import 'recovery_pages.dart';
import 'recovery_port.dart';

final class RecoveryActions {
  RecoveryActions(this.port, this.pages, this.lifetime, this.operations);
  final RecoveryPort port;
  final RecoveryPages pages;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;
  final Map<int, _RecoveryWork> _work = {};
  Future<void>? _tail;

  OperationTicket<RecoveryReadTarget> retry() => _perform(
    target: 'recovery-audit', dispatch: port.retry, observe: pages.synchronize,
  );

  OperationTicket<Unit> cleanupWorktree(
      WorktreeOwner ownerKind, String ownerThreadId, int expectedLeaseRevision) {
    lifetime.admit();
    if (expectedLeaseRevision < 0) throw const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'A worktree lease revision must be nonnegative.',
      retryable: false, correlationId: 'recovery',
    );
    return _perform<Unit>(
      target: 'worktree:${ownerKind.name}:$ownerThreadId',
      dispatch: () async {
        await port.cleanupWorktree(ownerKind, ownerThreadId, expectedLeaseRevision);
        return const Unit();
      },
      observe: (_) async {},
    );
  }

  bool get _unknown => _work.values.any((work) => work.unknown || work.terminalIssue != null);

  OperationTicket<T> _perform<T>({required String target,
      required Future<T> Function() dispatch,
      required Future<void> Function(T) observe}) {
    lifetime.admit();
    if (_unknown) throw _conflict;
    final prior = _tail;
    final work = _FrozenRecoveryWork<T>(lifetime.nextAttempt(), dispatch, observe);
    _work[work.attempt] = work;
    _tail = work.done.future;
    final handoff = Completer<OperationWriter<T>>();
    try {
      // Register the whole command before begin can publish to external
      // observers. Late writer handoff stays inside this original Future.
      lifetime.run('recovery-action', () async {
        final writer = await handoff.future;
        await _run(work, writer, prior);
      }).then<void>((_) {}, onError: (Object error, StackTrace stack) {
        lifetime.lastCause = error;
        lifetime.lastStack = stack;
      });
    } catch (_) {
      _finish(work);
      rethrow;
    }
    try {
      final writer = operations.begin<T>(target: target);
      handoff.complete(writer);
    return writer.ticket;
    } catch (error, stack) {
      handoff.completeError(error, stack);
      _finish(work);
      rethrow;
    }
  }

  Future<void> _run<T>(_FrozenRecoveryWork<T> work,
      OperationWriter<T> writer, Future<void>? prior) async {
    var issued = false;
    var confirmed = false;
    T? value;
    try {
      await prior;
      lifetime.admit();
      if (_work.values.any((other) => !identical(other, work) &&
          (other.unknown || other.terminalIssue != null))) {
        throw const CommandDispatchFailure.rejected(failure: _conflict);
      }
      issued = true;
      value = await work.dispatch();
      confirmed = true;
      await work.observe(value);
      writer.acknowledged(value);
    } catch (error, stack) {
      lifetime.lastCause = error;
      lifetime.lastStack = stack;
      work.causes.add((error, stack));
      final failure = error is CommandDispatchFailure ? error.failure : resourceFailure(error);
      try {
      if (confirmed) {
        writer.acknowledgedSynchronizationFailed(failure, value: value);
      } else {
        switch (error) {
          case RejectedCommandDispatchFailure():
            writer.rejected(failure);
          case ConfirmedWithoutUsableReceiptCommandDispatchFailure():
            writer.acknowledgedSynchronizationFailed(failure);
          case CommittedButUnobservedCommandDispatchFailure(:final receipt):
            writer.synchronizationFailed(failure, receipt: receipt);
          case UnknownOutcomeCommandDispatchFailure():
            work.unknown = true;
            work.failure = failure;
            writer.unknownOutcome(failure);
          default:
            if (issued) {
              work.unknown = true;
              work.failure = failure;
              writer.unknownOutcome(failure);
            } else {
              writer.rejected(failure);
            }
        }
      }
      } catch (ownerError, ownerStack) {
        work.causes.add((ownerError, ownerStack));
        work.terminalIssue = resourceCleanupIssue(ownerError, CleanupRecovery.terminal);
        rethrow;
      }
    } finally {
      _finish(work);
    }
  }

  void _finish(_RecoveryWork work) {
    if (!work.done.isCompleted) work.done.complete();
    if (identical(_tail, work.done.future)) _tail = null;
    if (!work.unknown && work.terminalIssue == null) _work.remove(work.attempt);
  }

  List<UnresolvedResource> get unresolved => [
    for (final work in _work.values)
      if (work.unknown || work.terminalIssue != null)
        UnresolvedResource(owner: 'recovery-action', attemptId: AttemptId(work.attempt),
          issues: [
            if (work.unknown) resourceCleanupIssue(work.failure!, CleanupRecovery.terminal),
            if (work.terminalIssue case final issue?) issue,
          ]),
  ];

  static const _conflict = StudioFailure(
    code: StudioFailureCode.conflict,
    message: 'A prior recovery action retains an unknown native outcome.',
    retryable: false, correlationId: 'recovery',
  );
}

abstract class _RecoveryWork {
  _RecoveryWork(this.attempt);
  final int attempt;
  final Completer<void> done = Completer<void>();
  bool unknown = false;
  StudioFailure? failure;
  final List<(Object, StackTrace)> causes = [];
  FeedCloseIssue? terminalIssue;
}

/// Retains the original typed inputs/lease CAS without a heterogeneous result API.
final class _FrozenRecoveryWork<T> extends _RecoveryWork {
  _FrozenRecoveryWork(super.attempt, this.dispatch, this.observe);
  final Future<T> Function() dispatch;
  final Future<void> Function(T) observe;
}
