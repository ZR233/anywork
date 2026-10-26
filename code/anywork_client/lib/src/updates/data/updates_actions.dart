import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/update_values.dart';
import '../domain/updates_state.dart';
import 'update_task.dart';
import 'updates_mirror.dart';
import 'updates_port.dart';
import 'updates_reader.dart';
import 'updates_state_helpers.dart';
import 'updates_task_owner.dart';

/// Only command coordination lives here. Native owns preparation sharing;
/// neither the automatic Unit ticket nor a current feed value is its result.
final class UpdatesActions {
  UpdatesActions(
    this.port,
    this.mirror,
    this.reads,
    this.lifetime,
    this.operations,
    this.controls,
  );
  final UpdatesPort port;
  final UpdatesMirror mirror;
  final UpdatesReads reads;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;
  final UpdateControls controls;
  final Map<int, _UpdateWorkBase> _work = {};
  final Map<_UpdateWorkBase, _UpdateWork<Unit>> _cancels = Map.identity();
  _UpdateWork<Unit>? _check;
  _UpdateWork<UpdatePreparationResult>? _prepare;
  _UpdateWork<Unit>? _automatic;

  void _admit() {
    lifetime.admit();
    if (!controls.enabled)
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Updates are disabled for this application.',
        retryable: false,
        correlationId: 'updates',
      );
    _prune();
  }

  OperationTicket<T> _borrow<T>(_UpdateWork<T> work) {
    final writer = work.writer;
    if (writer == null) throw _busy;
    return writer.ticket;
  }

  OperationTicket<Unit> check() {
    _admit();
    if (_check case final active?) {
      if (!active.done.isCompleted) return _borrow(active);
      throw _busy;
    }
    if (_prepare != null) throw _busy;
    final work = _UpdateWork<Unit>(lifetime.nextAttempt(), 'updates-check');
    _check = work;
    return _launch(work, port.openUpdateCheck, (_) => const Unit());
  }

  OperationTicket<UpdatePreparationResult> prepare() {
    _admit();
    if (_prepare case final active?) {
      if (!active.done.isCompleted) return _borrow(active);
      throw _busy;
    }
    if (_check != null) throw _busy;
    final binding = mirror.current;
    if (binding == null) throw updatesUnavailable;
    final summary = mirror.summary(binding);
    if (summary == null) throw updatesNoSummary;
    if (binding.header.brief is! AvailableUpdatesBrief &&
        binding.header.brief is! DownloadingUpdatesBrief &&
        binding.header.brief is! VerifyingUpdatesBrief &&
        binding.header.brief is! ReadyUpdatesBrief &&
        binding.header.brief is! InstallFailedUpdatesBrief) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'The current update cannot be prepared.',
        retryable: false,
        correlationId: 'updates',
      );
    }
    // Capture the canonical business revision (not projection/ref revision),
    // exact version text and source before begin/any external callback.
    final revision = binding.header.brief.revision;
    final version = summary.version;
    final work = _UpdateWork<UpdatePreparationResult>(
      lifetime.nextAttempt(),
      'updates-prepare',
      original: binding,
      version: version,
    );
    _prepare = work;
    return _launch(
      work,
      (id) => port.openUpdatePreparation(
        id,
        expectedRevision: revision,
        version: version,
      ),
      (value) => UpdatePreparationResult(
        readyVersion:
            value is ReadyUpdatesValue && value.update.version == version
            ? version
            : null,
      ),
    );
  }

  OperationTicket<Unit> automaticOnce() {
    _admit();
    if (_automatic case final prior?) return _borrow(prior);
    final binding = mirror.current;
    final value = mirror.source.value.value;
    if (binding == null ||
        value is! ReadyReadValue<UpdatesValue, UpdatesReadRef> ||
        value.current.origin != binding.origin ||
        value.current.reference != binding.header.reference) {
      throw updatesUnavailable;
    }
    final work = _UpdateWork<Unit>(lifetime.nextAttempt(), 'updates-automatic');
    _automatic = work;
    return _launch(work, port.openAutomaticUpdate, (_) => const Unit());
  }

  OperationTicket<Unit> cancelPreparation() {
    _admit();
    // This object, including an opening without its handle, is the target.
    final manual = _prepare;
    final automatic = _automatic;
    final target =
        manual ??
        (automatic != null &&
                (!automatic.done.isCompleted ||
                    automatic.task != null && !automatic.task!.released)
            ? automatic
            : null);
    if (target != null) {
      if (_cancels[target] case final pending?) return _borrow(pending);
    }
    final work = _UpdateWork<Unit>(
      lifetime.nextAttempt(),
      'updates-cancel-preparation',
    );
    if (target != null) _cancels[target] = work;
    final ticket = _register(work, (writer) async {
      var notified = false;
      try {
        if (target != null) {
          notified = true;
          await target.done.future;
          final task = target.task;
          if (task != null && !task.released) throw _cleanupPending;
        } else {
          // No target: a local known no-op, with no native receipt/evidence.
          lifetime.admit();
        }
        writer.acknowledged(const Unit());
      } catch (error, stack) {
        _remember(work, error, stack);
        if (notified) {
          work.unknown = true;
          writer.unknownOutcome(_failure(error));
        } else
          writer.rejected(_failure(error));
      }
    });
    // Full work/ticket ownership precedes the synchronous native callback.
    if (target != null) {
      target.cancelRequested = true;
      target.task?.requestClose();
    }
    return ticket;
  }

  OperationTicket<T> _launch<T>(
    _UpdateWork<T> work,
    Future<UpdateTaskConnection> Function(OperationId) open,
    T Function(UpdatesValue) result,
  ) => _register(work, (writer) async {
    UpdatesReadTarget? completed;
    T? value;
    try {
      lifetime.admit();
      if (work.cancelRequested)
        throw const CommandDispatchFailure.rejected(failure: resourceCancelled);
      final task = UpdatesTaskOwner(
        lifetime: lifetime,
        owner: work.label,
        operationId: writer.ticket.id,
        open: () => open(writer.ticket.id),
        beforeStart: () {
          lifetime.admit();
          if (work.cancelRequested)
            throw const CommandDispatchFailure.rejected(
              failure: resourceCancelled,
            );
          if (work.original case final original?) mirror.check(original);
        },
      );
      work.task = task;
      if (work.cancelRequested) {
        task.requestClose();
        unawaited(task.cleanup(retry: false));
      }
      completed = await task.completion;
      if (completed.origin.ownerEpoch.isEmpty ||
          completed.origin.incarnation < 0 ||
          completed.reference.entry < 0 ||
          completed.reference.revision < 0 ||
          work.original != null && completed.origin != work.original!.origin) {
        final error = resourceProtocol(
          'The update completion has another original source or an invalid ref.',
        );
        task.terminal(error, StackTrace.current, 'finish-target');
        throw error;
      }
      // Do not replace completed with a later mirror target after either await.
      final body = await reads.at(completed);
      final returned = result(body);
      value = returned;
      mirror.offerTarget(completed, body);
      await mirror.synchronize(completed);
      writer.acknowledged(returned);
    } catch (error, stack) {
      _remember(work, error, stack);
      final failure = _failure(error);
      if (completed != null) {
        writer.acknowledgedSynchronizationFailed(failure, value: value);
      } else {
        switch (error) {
          case RejectedCommandDispatchFailure():
            writer.rejected(failure);
          case ConfirmedWithoutUsableReceiptCommandDispatchFailure() ||
              CommittedButUnobservedCommandDispatchFailure():
            // Updates have no receipt. Keep unexpected native evidence in the
            // original cause, never manufacture an Updates CommitReceipt.
            writer.acknowledgedSynchronizationFailed(failure);
          case UnknownOutcomeCommandDispatchFailure():
            _unknown(work, error, stack);
            writer.unknownOutcome(failure);
          default:
            final task = work.task;
            if (task == null || !task.startIssued && task.hasConnection)
              writer.rejected(failure);
            else {
              _unknown(work, error, stack);
              writer.unknownOutcome(failure);
            }
        }
      }
    }
  });

  OperationTicket<T> _register<T>(
    _UpdateWork<T> work,
    Future<void> Function(OperationWriter<T>) action,
  ) {
    final handoff = Completer<OperationWriter<T>>();
    unawaited(
      handoff.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    _work[work.attempt] = work;
    try {
      // Regular complete work, registered before begin's observers can seal.
      unawaited(
        lifetime
            .run(work.label, () async {
              try {
                final writer = await handoff.future;
                await action(writer);
              } catch (error, stack) {
                if (work.writer != null) {
                  final task = work.task;
                  if (task != null)
                    task.terminal(error, stack, 'operation-settlement');
                  else
                    work.terminal = resourceCleanupIssue(
                      _failure(error),
                      CleanupRecovery.terminal,
                    );
                }
                _remember(work, error, stack);
              } finally {
                final task = work.task;
                try {
                  if (task != null) {
                    task.decisionComplete();
                    await task.cleanup(retry: false);
                  }
                } catch (error, stack) {
                  _remember(work, error, stack);
                  if (task != null)
                    task.terminal(error, stack, 'action-cleanup');
                  else
                    work.terminal = resourceCleanupIssue(
                      _failure(error),
                      CleanupRecovery.terminal,
                    );
                } finally {
                  if (!work.done.isCompleted) work.done.complete();
                  _prune();
                }
              }
            })
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) {
                _remember(work, error, stack);
                work.terminal = resourceCleanupIssue(
                  _failure(error),
                  CleanupRecovery.terminal,
                );
              },
            ),
      );
      final writer = operations.begin<T>(target: work.label);
      work.writer = writer;
      final ticket = writer.ticket;
      handoff.complete(writer);
      return ticket;
    } catch (error, stack) {
      if (!handoff.isCompleted) handoff.completeError(error, stack);
      if (work.writer != null)
        work.terminal = resourceCleanupIssue(
          _failure(error),
          CleanupRecovery.terminal,
        );
      if (!work.done.isCompleted) work.done.complete();
      _prune();
      if (work.writer == null && identical(_automatic, work)) _automatic = null;
      rethrow;
    }
  }

  void _unknown(_UpdateWorkBase work, Object error, StackTrace stack) {
    work.unknown = true;
    final task = work.task;
    if (task != null)
      task.terminal(error, stack, 'unknown-outcome');
    else
      work.terminal = resourceCleanupIssue(
        _failure(error),
        CleanupRecovery.terminal,
      );
  }

  StudioFailure _failure(Object error) =>
      error is CommandDispatchFailure ? error.failure : resourceFailure(error);
  void _remember(_UpdateWorkBase work, Object error, StackTrace stack) {
    work.causes.add((error, stack));
    lifetime.lastCause = error;
    lifetime.lastStack = stack;
  }

  void _prune() {
    bool released(_UpdateWorkBase work) =>
        work.done.isCompleted &&
        !work.unknown &&
        work.terminal == null &&
        (work.task == null || work.task!.released);
    _work.removeWhere((_, work) => released(work));
    _cancels.removeWhere((_, work) => released(work));
    if (_check case final work?) {
      if (released(work)) _check = null;
    }
    if (_prepare case final work?) {
      if (released(work)) _prepare = null;
    }
    // _automatic is the once-ticket, even after its real owner is released.
  }

  /// Original cleanup can later prove an uncertain cancellation. Update only
  /// its original operation evidence, never send another business command.
  void reconcileCleanup() {
    for (final entry in List.of(_cancels.entries)) {
      final target = entry.key;
      final work = entry.value;
      if (!work.unknown ||
          work.terminal != null ||
          !target.done.isCompleted ||
          target.task != null && !target.task!.released)
        continue;
      try {
        work.writer!.acknowledged(const Unit());
        work.unknown = false;
      } catch (error, stack) {
        _remember(work, error, stack);
        work.terminal = resourceCleanupIssue(
          _failure(error),
          CleanupRecovery.terminal,
        );
      }
    }
    _prune();
  }

  List<UnresolvedResource> get unresolved => [
    // ResourceLifetime owns all native task diagnostics. Only settlement faults
    // without an actual task are domain-owned, not a duplicate owner registry.
    for (final work in _work.values)
      if (work.terminal case final issue?)
        UnresolvedResource(
          owner: work.label,
          attemptId: AttemptId(work.attempt),
          issues: [issue],
        ),
  ];

  static const _busy = StudioFailure(
    code: StudioFailureCode.conflict,
    message: 'A manual update operation is registering, running or retains unresolved work.',
    retryable: false,
    correlationId: 'updates',
  );
  static const _cleanupPending = StudioFailure(
    code: StudioFailureCode.busy,
    message: 'The original update task still owns unresolved cleanup.',
    retryable: true,
    correlationId: 'updates',
  );
}

sealed class _UpdateWorkBase {
  _UpdateWorkBase(this.attempt, this.label, this.original, this.version);
  final int attempt;
  final String label;
  final UpdatesBinding? original;
  final String? version;
  final Completer<void> done = Completer<void>();
  final List<(Object, StackTrace)> causes = [];
  UpdatesTaskOwner? task;
  bool cancelRequested = false;
  bool unknown = false;
  FeedCloseIssue? terminal;
}

final class _UpdateWork<T> extends _UpdateWorkBase {
  _UpdateWork(
    int attempt,
    String label, {
    UpdatesBinding? original,
    String? version,
  }) : super(attempt, label, original, version);
  OperationWriter<T>? writer;
}
