import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/persistence_state.dart';
import '../domain/persistence_values.dart';
import 'persistence_mirror.dart';
import 'persistence_port.dart';

/// Global retry affects the process writer; history retry/resume freeze one
/// Thread and generation. Different Threads do not wait on each other's lane.
final class PersistenceActions {
  PersistenceActions(this.port, this.mirror, this.lifetime, this.operations);
  final PersistencePort port;
  final PersistenceMirror mirror;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;
  final Map<int, _PersistenceWork> _work = {};

  OperationTicket<PersistenceReadTarget> retry() {
    lifetime.admit();
    final work = _RetryWork(lifetime.nextAttempt(), port.retry);
    return _perform(work, work.dispatch, synchronize: (target) async {
      if (target.reference.entry < 0 || target.reference.revision < 0) {
        throw resourceProtocol('Persistence retry returned an invalid target.');
      }
      await mirror.synchronize(target);
    });
  }

  OperationTicket<PersistenceQueueSnapshot> history(String threadId, int faultGeneration, {required bool resume}) {
    lifetime.admit();
    if (faultGeneration < 0) throw const StudioFailure(code: StudioFailureCode.invalidArgument,
      message: 'A persistence fault generation cannot be negative.', retryable: false, correlationId: 'persistence');
    final work = _ThreadWork(lifetime.nextAttempt(), threadId, faultGeneration, resume,
      resume ? () => port.resumeThreadHistory(threadId, faultGeneration)
          : () => port.retryThreadHistory(threadId, faultGeneration));
    // This raw reply has no publication clock. Acknowledging it cannot update
    // the queue mirror, infer durability, or substitute retry for explicit resume.
    return _perform(work, work.dispatch);
  }

  OperationTicket<T> _perform<T>(_PersistenceWork work, Future<T> Function() dispatch,
      {Future<void> Function(T)? synchronize}) {
    lifetime.admit();
    final prior = [for (final other in _work.values) if (work.conflicts(other)) other];
    if (prior.any((other) => other.unknown || other.terminal != null)) throw _conflict;
    _work[work.attempt] = work;
    final handoff = Completer<OperationWriter<T>>();
    try {
      lifetime.run(work.target, () async {
        final writer = await handoff.future;
        await _run(work, writer, dispatch, prior, synchronize);
      }).then<void>((_) {}, onError: (Object error, StackTrace stack) {
        lifetime.lastCause = error; lifetime.lastStack = stack;
      });
    } catch (_) { _finish(work); rethrow; }
    try {
      final writer = operations.begin<T>(target: work.target);
      final ticket = writer.ticket;
      handoff.complete(writer);
      return ticket;
    } catch (error, stack) {
      handoff.completeError(error, stack);
      _finish(work);
      rethrow;
    }
  }

  Future<void> _run<T>(_PersistenceWork work, OperationWriter<T> writer,
      Future<T> Function() dispatch, List<_PersistenceWork> prior,
      Future<void> Function(T)? synchronize) async {
    var dispatched = false;
    T? confirmed;
    try {
      await Future.wait([for (final other in prior) other.done.future]);
      lifetime.admit();
      if (_work.values.any((other) => !identical(work, other) && work.conflicts(other) &&
          (other.unknown || other.terminal != null))) {
        throw const CommandDispatchFailure.rejected(failure: _conflict);
      }
      dispatched = true;
      final value = await dispatch();
      confirmed = value;
      if (synchronize != null) await synchronize(value);
      writer.acknowledged(value);
    } catch (error, stack) {
      work.causes.add((error, stack));
      lifetime.lastCause = error; lifetime.lastStack = stack;
      final failure = error is CommandDispatchFailure ? error.failure : resourceFailure(error);
      try {
        if (confirmed != null) {
          writer.acknowledgedSynchronizationFailed(failure, value: confirmed);
        } else {
          switch (error) {
            case RejectedCommandDispatchFailure(): writer.rejected(failure);
            case ConfirmedWithoutUsableReceiptCommandDispatchFailure():
              writer.acknowledgedSynchronizationFailed(failure);
            case CommittedButUnobservedCommandDispatchFailure(:final receipt):
              writer.synchronizationFailed(failure, receipt: receipt);
            case UnknownOutcomeCommandDispatchFailure():
              work.unknown = true; work.failure = failure; writer.unknownOutcome(failure);
            default:
              if (dispatched) {
                work.unknown = true; work.failure = failure; writer.unknownOutcome(failure);
              } else { writer.rejected(failure); }
          }
        }
      } catch (ownerError, ownerStack) {
        work.causes.add((ownerError, ownerStack));
        work.terminal = resourceCleanupIssue(ownerError, CleanupRecovery.terminal);
        rethrow;
      }
    } finally { _finish(work); }
  }

  void _finish(_PersistenceWork work) {
    if (!work.done.isCompleted) work.done.complete();
    if (!work.unknown && work.terminal == null) _work.remove(work.attempt);
  }

  List<UnresolvedResource> get unresolved => [
    for (final work in _work.values)
      if (work.unknown || work.terminal != null)
        UnresolvedResource(owner: work.target, attemptId: AttemptId(work.attempt), issues: [
          if (work.unknown) resourceCleanupIssue(work.failure!, CleanupRecovery.terminal),
          if (work.terminal case final issue?) issue,
        ]),
  ];

  static const _conflict = StudioFailure(code: StudioFailureCode.conflict,
    message: 'A conflicting persistence operation retains an unknown or terminal outcome.',
    retryable: false, correlationId: 'persistence');
}

sealed class _PersistenceWork {
  _PersistenceWork(this.attempt, this.target, this.threadId);
  final int attempt;
  final String target;
  final String? threadId;
  final Completer<void> done = Completer<void>();
  final List<(Object, StackTrace)> causes = [];
  bool unknown = false;
  StudioFailure? failure;
  FeedCloseIssue? terminal;
  bool conflicts(_PersistenceWork other) => threadId == null || other.threadId == null || threadId == other.threadId;
}

final class _RetryWork extends _PersistenceWork {
  _RetryWork(int attempt, this.dispatch) : super(attempt, 'persistence-retry', null);
  final Future<PersistenceReadTarget> Function() dispatch;
}

final class _ThreadWork extends _PersistenceWork {
  _ThreadWork(int attempt, String threadId, this.faultGeneration, this.resume, this.dispatch)
      : super(attempt, 'persistence-history-${resume ? 'resume' : 'retry'}:$threadId', threadId);
  final int faultGeneration;
  final bool resume;
  final Future<PersistenceQueueSnapshot> Function() dispatch;
}
