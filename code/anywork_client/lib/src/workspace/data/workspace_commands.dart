import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/selection.dart';
import 'workspace_command_cleanup.dart';

enum WorkspaceWriteKind { project, thread, localPath, remotePath }

typedef WorkspaceWriteKey = ({
  WorkspaceWriteKind kind,
  String id,
  String? path,
});

/// Dispatch evidence and optional archive responsibility for this exact work.
final class WorkspaceCommandScope<T> {
  WorkspaceCommandScope(this.lifetime, this.operationId);
  final ResourceLifetime lifetime;
  final OperationId operationId;
  bool dispatched = false;

  /// The dispatched native call answered before the current failure. A failure
  /// raised by the call itself is a known rejection; a later failure leaves the
  /// applied target unproven.
  bool answered = false;
  bool confirmed = false;
  T? value;
  CommitReceipt? receipt;
  CommitReceipt? unusableReceipt;
  WorkspaceCommandCleanup? cleanup;

  Future<R> invoke<R>(Future<R> Function() action) {
    lifetime.admit();
    dispatched = true;
    return Future<R>.sync(action).then((value) {
      answered = true;
      return value;
    });
  }

  void confirm({T? value, CommitReceipt? receipt}) {
    confirmed = true;
    if (value != null) this.value = value;
    if (receipt != null && receipt.operationId != operationId) {
      unusableReceipt = receipt;
      throw resourceProtocol(
        'The directory receipt belongs to another operation.',
      );
    }
    if (receipt != null) this.receipt = receipt;
  }
}

/// All short writes and retained archive cleanup belong to this original map.
/// Navigation reads and stop controls never join an unrelated write FIFO.
final class WorkspaceCommands {
  WorkspaceCommands(this.lifetime, this.operations);
  final ResourceLifetime lifetime;
  final OperationRecorder operations;
  final Map<int, _WorkspaceWorkBase> _work = {};

  bool get selectionPending => _work.values.any(
    (work) =>
        work.selection &&
        (!work.done.isCompleted ||
            work.unknown ||
            work.terminal != null ||
            work.cleanup?.report.complete == false),
  );
  bool holdsRemoval(WorkspaceState state) =>
      _work.values.any((work) => work.cleanup?.holdsRemoval(state) ?? false);

  OperationTicket<T> run<T>({
    required String label,
    WorkspaceWriteKey? key,
    bool selection = false,
    void Function()? registered,
    void Function()? finished,
    OperationWriter<T>? existing,
    void Function(WorkspaceCommandScope<T>)? capture,
    required Future<T> Function(WorkspaceCommandScope<T>) action,
  }) {
    lifetime.admit();
    final prior = [
      for (final other in _work.values)
        if (key != null && other.key == key) other,
    ];
    final work = _WorkspaceWork<T>(
      lifetime.nextAttempt(),
      label,
      key,
      selection,
      action,
    );
    final handoff =
        Completer<
          ({OperationWriter<T> writer, WorkspaceCommandScope<T> scope})
        >();
    unawaited(
      handoff.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    _work[work.attempt] = work;
    try {
      unawaited(
        lifetime
            .run(label, () async {
              try {
                final accepted = await handoff.future;
                await _execute(work, accepted.writer, accepted.scope, prior);
              } catch (error, stack) {
                _remember(work, error, stack);
                if (work.writer != null)
                  work.terminal = resourceCleanupIssue(
                    error,
                    CleanupRecovery.terminal,
                  );
              } finally {
                if (!work.done.isCompleted) work.done.complete();
                _release(work);
                finished?.call();
              }
            })
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) {
                _remember(work, error, stack);
                work.terminal = resourceCleanupIssue(
                  error,
                  CleanupRecovery.terminal,
                );
                _work[work.attempt] = work;
              },
            ),
      );
      registered?.call();
      final writer = existing ?? operations.begin<T>(target: label);
      work.writer = writer;
      final scope = WorkspaceCommandScope<T>(lifetime, writer.ticket.id);
      work.scope = scope;
      // The original map entry, complete work and writer precede external
      // capture. It runs synchronously before the first await or lane wait.
      try {
        capture?.call(scope);
      } catch (error, stack) {
        work.admissionError = (error, stack);
      }
      handoff.complete((writer: writer, scope: scope));
      return writer.ticket;
    } catch (error, stack) {
      if (!handoff.isCompleted) handoff.completeError(error, stack);
      if (work.writer != null)
        work.terminal = resourceCleanupIssue(error, CleanupRecovery.terminal);
      rethrow;
    }
  }

  Future<void> _execute<T>(
    _WorkspaceWork<T> work,
    OperationWriter<T> writer,
    WorkspaceCommandScope<T> scope,
    List<_WorkspaceWorkBase> prior,
  ) async {
    StudioFailure? failure;
    late T value;
    try {
      if (work.admissionError case (final error, final stack)?)
        Error.throwWithStackTrace(error, stack);
      await Future.wait([for (final other in prior) other.done.future]);
      lifetime.admit();
      if (prior.any(
        (other) =>
            other.unknown ||
            other.terminal != null ||
            other.cleanup?.report.complete == false,
      )) {
        throw const CommandDispatchFailure.rejected(failure: _conflict);
      }
      value = await work.action(scope);
      scope.confirm(value: value);
    } catch (error, stack) {
      _remember(work, error, stack);
      failure = error is CommandDispatchFailure
          ? error.failure
          : resourceFailure(error);
      if (!scope.confirmed) {
        switch (error) {
          case RejectedCommandDispatchFailure():
            break;
          case CommittedButUnobservedCommandDispatchFailure(:final receipt):
            try {
              scope.confirm(receipt: receipt);
            } catch (mismatch, mismatchStack) {
              _remember(work, mismatch, mismatchStack);
              failure = resourceFailure(mismatch);
            }
          case ConfirmedWithoutUsableReceiptCommandDispatchFailure():
            scope.confirmed = true;
          case UnknownOutcomeCommandDispatchFailure():
            work.unknown = true;
          default:
            // The dispatched call itself answered with this error: the write is
            // known not to have been applied. Only a failure after a successful
            // dispatch leaves the applied target unproven.
            if (scope.answered) work.unknown = true;
        }
      }
    }
    final cleanup = scope.cleanup;
    if (cleanup != null) {
      try {
        final report = await cleanup.finish(
          confirmed: scope.confirmed,
          unknown: work.unknown,
        );
        if (!report.complete) failure ??= _cleanupFailure;
      } catch (error, stack) {
        _remember(work, error, stack);
        work.terminal = resourceCleanupIssue(error, CleanupRecovery.terminal);
        failure ??= resourceFailure(error);
      }
    }
    if (failure == null) {
      if (scope.receipt case final receipt?)
        writer.accepted(value, receipt);
      else
        writer.acknowledged(value);
    } else if (scope.confirmed) {
      if (scope.receipt case final receipt?)
        writer.synchronizationFailed(
          failure,
          value: scope.value,
          receipt: receipt,
        );
      else
        writer.acknowledgedSynchronizationFailed(failure, value: scope.value);
    } else if (work.unknown) {
      writer.unknownOutcome(failure);
    } else {
      writer.rejected(failure);
    }
  }

  void _release(_WorkspaceWorkBase work) {
    if (work.done.isCompleted &&
        !work.unknown &&
        work.terminal == null &&
        work.cleanup?.report.complete != false) {
      _work.remove(work.attempt);
    }
  }

  void _remember(_WorkspaceWorkBase work, Object error, StackTrace stack) {
    work.causes.add((error, stack));
    lifetime.lastCause = error;
    lifetime.lastStack = stack;
    work.failure ??= error is CommandDispatchFailure
        ? error.failure
        : resourceFailure(error);
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    final original = List.of(_work.values);
    await Future.wait([
      for (final work in original)
        if (work.cleanup case final cleanup?)
          Future<CloseReport>.sync(
            () => cleanup.close(deadline: deadline, retry: retry),
          ).then<void>(
            (report) {
              // Late diagnostics remain attached to the original work/cleanup. Never
              // rewrite an already settled ticket or allocate a replacement ticket.
              if (!report.complete)
                _remember(work, _cleanupFailure, StackTrace.current);
              _release(work);
            },
            onError: (Object error, StackTrace stack) {
              _remember(work, error, stack);
              work.terminal = resourceCleanupIssue(
                error,
                CleanupRecovery.terminal,
              );
            },
          ),
    ]);
    return CloseReport(unresolved: unresolved);
  }

  List<UnresolvedResource> get unresolved => [
    for (final work in _work.values) ...[
      if (work.unknown || work.terminal != null)
        UnresolvedResource(
          owner: work.label,
          attemptId: AttemptId(work.attempt),
          issues: [
            if (work.unknown)
              resourceCleanupIssue(work.failure!, CleanupRecovery.terminal),
            if (work.terminal case final issue?) issue,
          ],
        ),
      if (work.cleanup case final cleanup?) ...cleanup.report.unresolved,
    ],
  ];

  static const _conflict = StudioFailure(
    code: StudioFailureCode.conflict,
    message: 'The original directory write retains an unknown or unresolved outcome.',
    retryable: false,
    correlationId: 'workspace',
  );
  static const _cleanupFailure = StudioFailure(
    code: StudioFailureCode.unavailable,
    message: 'The original Workspace archive retains unresolved cleanup.',
    retryable: true,
    correlationId: 'workspace',
  );
}

sealed class _WorkspaceWorkBase {
  _WorkspaceWorkBase(this.attempt, this.label, this.key, this.selection);
  final int attempt;
  final String label;
  final WorkspaceWriteKey? key;
  final bool selection;
  final Completer<void> done = Completer<void>();
  final List<(Object, StackTrace)> causes = [];
  WorkspaceCommandCleanup? get cleanup;
  bool unknown = false;
  StudioFailure? failure;
  FeedCloseIssue? terminal;
}

final class _WorkspaceWork<T> extends _WorkspaceWorkBase {
  _WorkspaceWork(
    super.attempt,
    super.label,
    super.key,
    super.selection,
    this.action,
  );
  final Future<T> Function(WorkspaceCommandScope<T>) action;
  OperationWriter<T>? writer;
  WorkspaceCommandScope<T>? scope;
  (Object, StackTrace)? admissionError;
  @override
  WorkspaceCommandCleanup? get cleanup => scope?.cleanup;
}
