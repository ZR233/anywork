import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/mcp_state.dart';
import 'mcp_mirror.dart';
import 'mcp_port.dart';

/// Native MCP has one command lock. Unknown work therefore blocks all resets,
/// while independent field/page reads never wait in this reset lane.
final class McpActions {
  McpActions(this.port, this.mirror, this.lifetime, this.operations);
  final McpPort port;
  final McpMirror mirror;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;
  final Map<int, _ResetWork> _work = {};
  Future<void>? _tail;

  OperationTicket<McpReadTarget> resetServer(String serverId) =>
    _reset('mcp-server:$serverId', () => port.resetServer(serverId));
  OperationTicket<McpReadTarget> resetAll() => _reset('mcp-all', port.resetAll);

  OperationTicket<McpReadTarget> _reset(String target, Future<McpReadTarget> Function() dispatch) {
    lifetime.admit();
    if (_work.values.any((work) => work.unknown || work.terminal != null)) throw _conflict;
    final prior = _tail;
    final work = _ResetWork(lifetime.nextAttempt(), dispatch);
    _work[work.attempt] = work;
    _tail = work.done.future;
    final handoff = Completer<OperationWriter<McpReadTarget>>();
    try {
      lifetime.run('mcp-reset', () async {
        final writer = await handoff.future;
        await _run(work, writer, prior);
      }).then<void>((_) {}, onError: (Object error, StackTrace stack) {
        lifetime.lastCause = error;
        lifetime.lastStack = stack;
      });
    } catch (_) { _finish(work); rethrow; }
    try {
      final writer = operations.begin<McpReadTarget>(target: target);
      final ticket = writer.ticket;
      handoff.complete(writer);
      return ticket;
    } catch (error, stack) {
      handoff.completeError(error, stack);
      _finish(work);
      rethrow;
    }
  }

  Future<void> _run(_ResetWork work, OperationWriter<McpReadTarget> writer, Future<void>? prior) async {
    var dispatched = false;
    McpReadTarget? acknowledged;
    try {
      if (prior != null) await prior;
      lifetime.admit();
      if (_work.values.any((other) => !identical(other, work) && (other.unknown || other.terminal != null))) {
        throw const CommandDispatchFailure.rejected(failure: _conflict);
      }
      dispatched = true;
      final target = await work.dispatch();
      acknowledged = target;
      await mirror.synchronize(target);
      writer.acknowledged(target);
    } catch (error, stack) {
      work.causes.add((error, stack));
      lifetime.lastCause = error;
      lifetime.lastStack = stack;
      final failure = error is CommandDispatchFailure ? error.failure : resourceFailure(error);
      try {
        if (acknowledged != null) {
          writer.acknowledgedSynchronizationFailed(failure, value: acknowledged);
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

  void _finish(_ResetWork work) {
    if (!work.done.isCompleted) work.done.complete();
    if (identical(_tail, work.done.future)) _tail = null;
    if (!work.unknown && work.terminal == null) _work.remove(work.attempt);
  }

  List<UnresolvedResource> get unresolved => [
    for (final work in _work.values)
      if (work.unknown || work.terminal != null)
        UnresolvedResource(owner: 'mcp-reset', attemptId: AttemptId(work.attempt), issues: [
          if (work.unknown) resourceCleanupIssue(work.failure!, CleanupRecovery.terminal),
          if (work.terminal case final issue?) issue,
        ]),
  ];

  static const _conflict = StudioFailure(code: StudioFailureCode.conflict,
    message: 'A prior MCP reset retains an unknown or terminal native outcome.',
    retryable: false, correlationId: 'mcp');
}

final class _ResetWork {
  _ResetWork(this.attempt, this.dispatch);
  final int attempt;
  final Future<McpReadTarget> Function() dispatch;
  final Completer<void> done = Completer<void>();
  final List<(Object, StackTrace)> causes = [];
  bool unknown = false;
  StudioFailure? failure;
  FeedCloseIssue? terminal;
}
