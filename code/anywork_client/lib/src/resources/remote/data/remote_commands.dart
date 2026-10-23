import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';

import 'remote_observation.dart';

/// Local operation IDs are observations, never SSH idempotence credentials.
final class RemoteCommands {
  RemoteCommands(this.operations);
  final OperationRecorder operations;
  final Map<AttemptId, _RemoteWork> _work = {};
  final Map<String, Future<void>> _lanes = {};
  int _sequence = 0;
  bool _sealed = false;

  OperationTicket<T> run<T>({
    required String target,
    required Set<String> lanes,
    required Future<T> Function() dispatch,
    required void Function(T) onReturned,
  }) {
    if (_sealed) throw remoteCancelled();
    if (_work.values.any((work) => work.uncertain &&
        work.lanes.any(lanes.contains))) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'An earlier SSH action has an unresolved outcome for this target.',
        retryable: false,
        correlationId: '',
      );
    }
    final work = _FrozenRemoteWork<T>(
      AttemptId(++_sequence), Set.unmodifiable(lanes), dispatch,
    );
    final previous = {
      for (final lane in lanes)
        if (_lanes[lane] case final task?) task,
    };
    _work[work.id] = work;
    for (final lane in lanes) {
      _lanes[lane] = work.done.future;
    }
    final OperationWriter<T> writer;
    try {
      writer = operations.begin<T>(target: target);
    } catch (_) {
      _finish(work);
      rethrow;
    }
    // The typed frozen closure remains owned for UnknownOutcome, including
    // secret input; it is never logged or invoked a second time.
    unawaited(_drive(work, writer, previous, onReturned));
    return writer.ticket;
  }

  Future<void> _drive<T>(
    _FrozenRemoteWork<T> work,
    OperationWriter<T> writer,
    Set<Future<void>> previous,
    void Function(T) onReturned,
  ) async {
    var issued = false;
    var confirmed = false;
    T? value;
    try {
      await Future.wait(previous);
      if (_sealed) throw CommandDispatchFailure.rejected(failure: remoteCancelled());
      if (_work.values.any((other) => !identical(other, work) &&
          other.uncertain && other.lanes.any(work.lanes.contains))) {
        throw const CommandDispatchFailure.rejected(failure: StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'The preceding SSH action has an unresolved outcome.',
          retryable: false,
          correlationId: '',
        ));
      }
      issued = true;
      value = await work.dispatch();
      confirmed = true;
      onReturned(value);
      writer.acknowledged(value);
    } catch (error, stack) {
      work.causes.add((error, stack));
      final failure = error is CommandDispatchFailure ? error.failure
          : error is StudioFailure ? error : remoteProtocol('SSH action failed at its typed boundary');
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
            work.uncertain = true;
            work.failure = failure;
            writer.unknownOutcome(failure);
          default:
            if (issued) {
              work.uncertain = true;
              work.failure = failure;
              writer.unknownOutcome(failure);
            } else {
              writer.rejected(failure);
            }
        }
      }
    } finally {
      _finish(work);
    }
  }

  void _finish(_RemoteWork work) {
    if (!work.done.isCompleted) work.done.complete();
    for (final lane in work.lanes) {
      if (identical(_lanes[lane], work.done.future)) _lanes.remove(lane);
    }
    if (!work.uncertain) _work.remove(work.id);
  }

  void seal() => _sealed = true;

  Future<void> join() async {
    await Future.wait([
      for (final work in List.of(_work.values)) work.done.future,
    ]);
  }

  List<UnresolvedResource> get unresolved => [
    for (final work in _work.values)
      UnresolvedResource(
        owner: 'remote-command',
        attemptId: work.id,
        issues: [
          if (!work.done.isCompleted)
            const FeedCloseIssue(
              diagnostic: StudioShutdownIssue(
                stage: 'remote-command',
                code: 'awaitingCompletion',
                message: 'An accepted SSH action is still running.',
                retryable: true,
                correlationId: '',
              ),
              recovery: CleanupRecovery.awaitCompletion,
            ),
          if (work.uncertain)
            remoteIssue(work.failure!, 'remote-command-outcome', CleanupRecovery.terminal),
        ],
      ),
  ];
}

abstract class _RemoteWork {
  _RemoteWork(this.id, this.lanes);
  final AttemptId id;
  final Set<String> lanes;
  final Completer<void> done = Completer<void>();
  final List<(Object, StackTrace)> causes = [];
  bool uncertain = false;
  StudioFailure? failure;
}

final class _FrozenRemoteWork<T> extends _RemoteWork {
  _FrozenRemoteWork(super.id, super.lanes, this.dispatch);
  final Future<T> Function() dispatch;
}
