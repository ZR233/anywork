import 'dart:async';

import '../../../operations_ports.dart';
import '../../../resources_ports.dart';
import '../../../workspace.dart';
import '../domain/stop_execution_result.dart';
import 'conversation_command_port.dart';

typedef _DirectoryMember = ({
  ProductProjectionStamp stamp,
  ProductEntityRef reference,
  AgentDirectoryEntry row,
});

/// Uses the original AgentDirectory capability, never a selected/lazy Session.
final class DirectoryExecutionStops {
  DirectoryExecutionStops(this.directory, this.commands, this.operations, ResourceBudget budget)
      : lifetime = ResourceLifetime(budget);
  final ReadonlyLatestValue<AgentDirectoryState> Function() directory;
  final ConversationCommandPort commands;
  final OperationRecorder operations;
  final ResourceLifetime lifetime;
  final Map<(Object, int, String), _DirectoryStop> _work = {};

  StopExecutionResult stop({
    required ProductProjectionStamp origin,
    required ProductEntityRef member,
    required String executionId,
  }) {
    lifetime.admit();
    final source = directory();
    final current = _member(source.value, origin, member)!;
    final row = current.row;
    if (executionId.isEmpty || row.execution != null && row.execution!.id != executionId) {
      throw const StudioFailure(code: StudioFailureCode.superseded,
        message: 'The original directory member now has a different execution.',
        retryable: false, correlationId: 'directory-stop-execution',
        details: StudioFailureDetails.reason(reason: 'staleExecution'));
    }
    _work.removeWhere((_, work) => work.released);
    final key = (source, member.entry, executionId);
    final previous = _work[key];
    if (previous != null && !previous.released) {
      if (previous.origin.origin != origin.origin) throw resourceProtocol('A pending directory stop cannot change owner.');
      return StopExecutionOperation(ticket: previous.writer.ticket);
    }
    if (row.execution == null) return StopNoExecution(row.threadId);
    if (!row.canStop ||
        row.state is ClosedAgentState || row.state is ClosingAgentState) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The original directory member has no matching stoppable execution.',
        retryable: false,
        correlationId: 'directory-stop-target',
      );
    }
    // A permitted forward read does not retarget an old work. Only a new work
    // captures this actually checked current source stamp/ref and immutable row.
    final work = _DirectoryStop(this, source, current.stamp, current.reference, row, executionId);
    lifetime.register(work);
    _work[key] = work;
    try {
      work.writer = operations.begin<Unit>(
        target: 'stop:${row.threadId}',
        requireIdentityObservation: true,
      );
      work.writerAssigned = true;
      work.start();
    } catch (_) {
      work.requestClose();
      work.notStarted();
      rethrow;
    }
    return StopExecutionOperation(ticket: work.writer.ticket);
  }

  static _DirectoryMember? _member(
    AgentDirectoryState state,
    ProductProjectionStamp original,
    ProductEntityRef member, {
    bool waitForRead = false,
  }) {
    final stamp = state.projection.stamp;
    final mirror = state.agents;
    if (stamp == null ||
        original.revision < 0 || member.entry < 0 || member.revision < 0 ||
        stamp.origin != original.origin ||
        stamp.revision < original.revision ||
        state.projection.sync.phase != ResourceSyncPhase.ready ||
        state.projection.sync.error != null ||
        state.projection.header?.reference == null ||
        state.projection.header?.source.brief is! ReadyObservedBrief ||
        mirror is! CurrentCollectionMirror<AgentDirectoryEntry> ||
        mirror.window.origin != stamp.origin ||
        mirror.window.error != null) {
      throw _superseded;
    }
    if (!mirror.window.complete || mirror.window.loading ||
        mirror.window.continuation is! EndCollectionContinuation ||
        mirror.window.entries.length != mirror.window.reference.total) {
      // A reliable change clears the ordered index before the reader rebuilds
      // it. Absence in this partial window cannot prove member replacement.
      if (waitForRead) return null;
      throw _superseded;
    }
    final reference = mirror.window.entries.where((ref) => ref.entry == member.entry).singleOrNull;
    // Native workspace/source.rs never reuses an entry within ProductReadOrigin:
    // a surviving member advances only its revision; removal/recreation gets a
    // fresh monotonic entry. Thread ID equality cannot substitute for this proof.
    if (reference == null || reference.revision < member.revision) throw _superseded;
    for (final ref in mirror.window.entries) {
      final ready = mirror.window.rows[ref.entry];
      if (ready is! ReadyReadValue<AgentDirectoryEntry, ProductEntityRef>) {
        // The same reader must publish current material for every member.
        if (waitForRead) {
          return null;
    }
        throw _superseded;
      }
      if (ready.current.origin != mirror.window.origin || ready.current.reference != ref) throw _superseded;
    }
    final row = mirror.window.rows[reference.entry] as ReadyReadValue<AgentDirectoryEntry, ProductEntityRef>;
    return (stamp: stamp, reference: reference, row: row.current.value);
  }

  static const _superseded = StudioFailure(
    code: StudioFailureCode.superseded,
    message: 'The original AgentDirectory source or member is no longer authoritative.',
    retryable: false,
    correlationId: 'directory-stop-source',
  );
}

final class _DirectoryStop implements ResourceOwner {
  _DirectoryStop(this.actions, this.source, this.origin, this.member, this.row, this.executionId)
      : attempt = actions.lifetime.nextAttempt();
  final DirectoryExecutionStops actions;
  final ReadonlyLatestValue<AgentDirectoryState> source;
  final ProductProjectionStamp origin;
  final ProductEntityRef member;
  final AgentDirectoryEntry row;
  final String executionId;
  late final OperationWriter<Unit> writer;
  bool writerAssigned = false;
  @override
  final int attempt;
  @override
  String get owner => 'directory-stop:${row.threadId}:$executionId';
  final _closing = Completer<void>();
  final _done = Completer<void>();
  bool _unknown = false;
  bool _confirmed = false;
  bool _observed = false;
  StudioFailure? _failure;
  ResourcePermit? _operationPermit;
  ResourcePermit? _observerPermit;
  Observation? _watch;

  void notStarted() {
    if (writerAssigned) writer.rejected(resourceCancelled);
    if (!_done.isCompleted) _done.complete();
  }

  void start() {
    unawaited(actions.lifetime.accepted(this, () async {
      var issued = false;
      CommitReceipt? receipt;
      final terminal = Completer<void>();
      void inspect(AgentDirectoryState state) {
        if (terminal.isCompleted) return;
        try {
          final current = DirectoryExecutionStops._member(state, origin, member, waitForRead: true);
          if (current == null) return;
          if (current.row.id != row.id || current.row.threadId != row.threadId ||
              current.row.rootThreadId != row.rootThreadId || current.row.path != row.path) throw DirectoryExecutionStops._superseded;
          if (issued && current.stamp.revision > origin.revision && current.row.execution?.id != executionId) terminal.complete();
        } catch (error, stack) {
          terminal.completeError(error, stack);
        }
      }
      // Avoid an unhandled read failure while the native command is still joining.
      terminal.future.ignore();
      try {
        _operationPermit = actions.lifetime.budget.acquire(ResourceKind.pendingOperation, owner: owner);
        _observerPermit = actions.lifetime.budget.acquire(ResourceKind.observer, owner: owner);
        final watching = source.watchLatest(inspect);
        _watch = watching.observation;
        final current = DirectoryExecutionStops._member(watching.value, origin, member)!;
        if (current.row.id != row.id || current.row.threadId != row.threadId ||
            current.row.rootThreadId != row.rootThreadId || current.row.path != row.path ||
            current.row.execution?.id != executionId || !current.row.canStop ||
            current.row.state is ClosedAgentState || current.row.state is ClosingAgentState ||
            _closing.isCompleted) throw resourceCancelled;
        issued = true;
        final reply = await actions.commands.stopExecution(row.threadId, executionId, operationId: writer.ticket.id);
        _confirmed = true;
        if (reply.threadId != row.threadId || reply.executionId != executionId ||
            !_validReceipt(reply.receipt) ||
            reply.receipt.disposition != (reply.stopped ? CommitDisposition.applied : CommitDisposition.noChange)) {
          throw resourceProtocol('Directory Stop returned another execution or receipt contract.');
        }
        receipt = reply.receipt;
        writer.accepted(const Unit(), receipt);
        inspect(source.value);
        await Future.any([terminal.future, _closing.future.then<void>((_) => throw resourceCancelled)]);
        writer.identityObserved();
        writer.effective();
        _observed = true;
      } catch (error, stack) {
        actions.lifetime.lastCause = error;
        actions.lifetime.lastStack = stack;
        final failure = error is CommandDispatchFailure ? error.failure : resourceFailure(error);
        _failure = failure;
        if (error is CommittedButUnobservedCommandDispatchFailure) {
          _confirmed = true;
          if (_validReceipt(error.receipt)) receipt = error.receipt;
        } else if (error is ConfirmedWithoutUsableReceiptCommandDispatchFailure) {
          _confirmed = true;
        }
        if (receipt != null) {
          writer.synchronizationFailed(failure, value: const Unit(), receipt: receipt);
        } else if (_confirmed) {
          writer.acknowledgedSynchronizationFailed(failure, value: const Unit());
        } else if (!issued || error is RejectedCommandDispatchFailure) {
          writer.rejected(failure);
        } else {
          _unknown = true;
          writer.unknownOutcome(failure);
        }
      } finally {
        _watch?.cancel();
        _watch = null;
        _observerPermit?.release();
        _operationPermit?.release();
        _done.complete();
      }
    }));
  }

  bool _validReceipt(CommitReceipt receipt) =>
      receipt.operationId == writer.ticket.id && receipt.requiresIdentityObservation &&
      receipt.effect == EffectPoint.immediate && !receipt.effective && !receipt.durable && receipt.targets.isEmpty;
  @override
  // Registry evidence survives independently. Sealing joins the original native
  // call and cancels only this observer; it never invents Observed/Effective.
  bool get released => _done.isCompleted &&
      (_closing.isCompleted || !_unknown && (!_confirmed || _observed));
  @override
  void requestClose() {
    if (!_closing.isCompleted) _closing.complete();
  }
  @override
  Future<void> cleanup({required bool retry}) => _done.future;
  @override
  List<FeedCloseIssue> get issues => released ? const [] : [
    resourceCleanupIssue(_failure ?? resourceCancelled,
        _done.isCompleted ? CleanupRecovery.terminal : CleanupRecovery.awaitCompletion),
  ];
}
