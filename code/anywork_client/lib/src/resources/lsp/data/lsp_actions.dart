import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/lsp_state.dart';
import 'lsp_port.dart';

/// The Repository injects its own target observer, never another domain's writer.
/// All four native LSP mutations share LspStateRuntime.command_lock. Read work
/// stays outside this lane. This owner does not create project-scoped facts.
final class LspActions {
  LspActions({required this.port, required this.lifetime, required this.operations,
    required this.synchronize});
  final LspPort port;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;
  final Future<void> Function(LspReadTarget) synchronize;
  final Map<int, _LspWork> _work = {};
  Future<void>? _tail;

  OperationTicket<LspReadTarget> probe(String projectId) =>
    _perform('lsp-probe:$projectId', () => port.probe(projectId));
  OperationTicket<LspReadTarget> repair(String projectId, String serverId) =>
    _perform('lsp-repair:$projectId:$serverId', () => port.repair(projectId, serverId));
  OperationTicket<LspReadTarget> resetServer(String projectId, String serverId) =>
    _perform('lsp-reset-server:$projectId:$serverId', () => port.resetServer(projectId, serverId));
  OperationTicket<LspReadTarget> resetWorkspace(String projectId) =>
    _perform('lsp-reset-workspace:$projectId', () => port.resetWorkspace(projectId));

  OperationTicket<LspReadTarget> _perform(String target, Future<LspReadTarget> Function() dispatch) {
    lifetime.admit();
    if (_work.values.any((work) => work.unknown || work.terminal != null)) throw _conflict;
    final prior = _tail;
    final work = _LspWork(lifetime.nextAttempt(), dispatch);
    _work[work.attempt] = work;
    _tail = work.done.future;
    final handoff = Completer<OperationWriter<LspReadTarget>>();
    try {
      lifetime.run('lsp-command', () async {
        final writer = await handoff.future;
        await _run(work, writer, prior);
      }).then<void>((_) {}, onError: (Object error, StackTrace stack) {
        lifetime.lastCause = error;
        lifetime.lastStack = stack;
      });
    } catch (_) { _finish(work); rethrow; }
    try {
      final writer = operations.begin<LspReadTarget>(target: target);
      final ticket = writer.ticket;
      handoff.complete(writer);
      return ticket;
    } catch (error, stack) {
      handoff.completeError(error, stack);
      _finish(work);
      rethrow;
    }
  }

  Future<void> _run(_LspWork work, OperationWriter<LspReadTarget> writer, Future<void>? prior) async {
    var dispatched = false;
    LspReadTarget? confirmed;
    try {
      if (prior != null) await prior;
      lifetime.admit();
      if (_work.values.any((other) => !identical(other, work) && (other.unknown || other.terminal != null))) {
        throw const CommandDispatchFailure.rejected(failure: _conflict);
      }
      dispatched = true;
      final target = await work.dispatch();
      confirmed = target;
      await synchronize(target);
      writer.acknowledged(target);
    } catch (error, stack) {
      work.causes.add((error, stack));
      lifetime.lastCause = error;
      lifetime.lastStack = stack;
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
              work.unknown = true;
              work.failure = failure;
              writer.unknownOutcome(failure);
            default:
              if (dispatched) {
                work.unknown = true;
                work.failure = failure;
                writer.unknownOutcome(failure);
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

  void _finish(_LspWork work) {
    if (!work.done.isCompleted) work.done.complete();
    if (identical(_tail, work.done.future)) _tail = null;
    if (!work.unknown && work.terminal == null) _work.remove(work.attempt);
  }

  /// Included by the Repository after joining its shared ResourceLifetime.
  List<UnresolvedResource> get unresolved => [
    for (final work in _work.values)
      if (work.unknown || work.terminal != null)
        UnresolvedResource(owner: 'lsp-command', attemptId: AttemptId(work.attempt), issues: [
          if (work.unknown) resourceCleanupIssue(work.failure!, CleanupRecovery.terminal),
          if (work.terminal case final issue?) issue,
        ]),
  ];

  static const _conflict = StudioFailure(code: StudioFailureCode.conflict,
    message: 'A prior LSP command retains an unknown or terminal native outcome.',
    retryable: false, correlationId: 'lsp');
}

final class _LspWork {
  _LspWork(this.attempt, this.dispatch);
  final int attempt;
  final Future<LspReadTarget> Function() dispatch;
  final Completer<void> done = Completer<void>();
  final List<(Object, StackTrace)> causes = [];
  bool unknown = false;
  StudioFailure? failure;
  FeedCloseIssue? terminal;
}
