import 'dart:async';

import '../../../lifecycle.dart'
    show ClientCloseBudget, ClientResourceId, ClientScope, ClientLease;
import '../../../models.dart';
import '../../../conversation_ports.dart';
import '../../../directory_ports.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/close_report.dart';
import '../../observation/latest_value.dart';
import '../../studio/stores/thread_directory_store.dart';
import '../../studio/stores/domain_sync.dart';
import '../../studio/thread_frames.dart';
import '../domain/conversation_repository.dart';
import '../domain/conversation_state.dart';
import 'conversation_state_owner.dart';
import 'state_reducer.dart';
import 'thread_stream_gate.dart';
import 'input_turn_facts.dart';
import '../domain/conversation_errors.dart';

/// One canonical Current state mirror and its independent observation owner.
final class ConversationSessionImpl implements ConversationSession {
  ConversationSessionImpl(
    this.threadId, {
    required CurrentTransport currentTransport,
    required ReadDemand stateDemand,
    required this.directory,
    required InputFactRegistry inputFacts,
    required ClientScope scope,
  }) : _scope = scope,
       _inputFacts = inputFacts,
       _source = LatestValue(ThreadSessionState(threadId: threadId)) {
    _state = ConversationStateOwner(
      threadId: threadId,
      transport: currentTransport,
      demand: stateDemand,
      onState: _onState,
      onFailure: _onFailure,
      onAttempt: _onAttempt,
      onInteractions: _onInteractions,
    );
    _directoryLease = _scope.acquireLease(
      'conversation-directory',
      () => _SessionDirectoryLease(directory.observeThread(threadId)),
    );
    _directoryDemand = _directoryLease.observation;
    _directoryObservation = _directoryDemand.state.watch(
      (_) => _rebindDirectory(),
      fireImmediately: true,
    );
  }
  @override
  final String threadId;
  final ThreadDirectoryStore directory;
  final ClientScope _scope;
  final InputFactRegistry _inputFacts;
  final LatestValue<ThreadSessionState> _source;
  late final ConversationStateOwner _state;
  late final DirectoryObservation<ThreadMetadataFrame> _directoryDemand;
  late final _SessionDirectoryLease _directoryLease;
  late final Observation _directoryObservation;
  _RuntimeResync? _resync;
  bool _closed = false;
  Future<CloseReport>? _closing;

  @override
  ThreadSessionState get state => _source.value;
  @override
  ValueObservation<ThreadSessionState> get source => _source;
  @override
  // The session's real visible demand: the state owner turns on first, so
  // this must already read true during that synchronous window, or a
  // reentrant visibility switch cannot revoke the stale stack.
  bool get isActive => _state.hasDemand;
  @override
  bool get isClosed => _closed;

  void setVisible(bool visible) {
    if (!visible) {
      _cancelResync();
      _state.setDemand(false);
      _source.publish(state.copyWith(sync: const DomainSyncStatus()));
      return;
    }
    if (_closed) throw StateError('Conversation is closed');
    // State opens first: its synchronous connecting publication may reenter
    // visibility switching. A reentrant revoke (or an A -> B -> A cascade)
    // bumps the generation, so this stale stack can never resurrect demand.
    _state.setDemand(true);
  }

  SessionDirectoryRow? get _identity => _directoryDemand.state.value.frame?.row;

  void _rebindDirectory() {
    if (_closed) return;
    final row = _identity;
    if (identical(state.directoryRow, row)) return;
    _source.publish(state.copyWith(directoryRow: row));
  }

  void _onAttempt(AttemptId attemptId) {
    final pending = _resync;
    if (pending != null) {
      final expected = pending.expectedAttempt;
      if (expected == null) {
        pending.expectedAttempt = attemptId;
      } else if (expected != attemptId) {
        if (identical(_resync, pending)) _resync = null;
        if (!pending.completer.isCompleted) {
          pending.completer.completeError(ThreadStateResyncCancelled(threadId));
        }
      }
    }
    _source.publish(
      state.copyWith(
        streamEpoch: null,
        // A replacement reader is still reconnecting until it delivers a
        // baseline. Starting each attempt must not hide the recovery state.
        sync: state.sync.phase == DomainSyncPhase.reconnecting
            ? state.sync
            : const DomainSyncStatus(phase: DomainSyncPhase.connecting),
      ),
    );
  }

  void _onState(AttemptId attemptId, ThreadStreamFrame frame) {
    final id = switch (frame) {
      ThreadSnapshotFrame(:final workspace) => workspace.thread.id,
      ThreadNotificationFrame(:final threadId) => threadId,
    };
    if (id != threadId)
      throw StateError('State frame thread identity mismatch');
    switch (frame) {
      case ThreadSnapshotFrame(:final workspace):
        final candidate = applyThreadSnapshotState(
          state,
          workspace,
          directoryRow: _identity,
        );
        final eligible = _eligibleResync(attemptId);
        _source.publish(candidate);
        if (identical(state, candidate)) _publishCurrentInputFacts(candidate);
        if (eligible != null &&
            identical(_resync, eligible) &&
            eligible.expectedAttempt == attemptId &&
            _state.currentAttemptId == attemptId) {
          _resync = null;
          if (!eligible.completer.isCompleted) {
            eligible.completer.complete(candidate.workspace!);
          }
        }
      case ThreadNotificationFrame():
        switch (classifyThreadFrame(state.watermark, frame)) {
          case ThreadFrameDecision.drop:
            return;
          case ThreadFrameDecision.resync:
            throw ThreadStateContinuityError(
              threadId: threadId,
              expected: state.watermark,
              revision: frame.revision,
              epoch: frame.epoch,
              baseRevision: frame.baseRevision,
            );
          case ThreadFrameDecision.apply:
            final candidate = applyThreadNotificationState(state, frame);
            _source.publish(candidate);
            if (identical(state, candidate))
              _publishCurrentInputFacts(candidate);
        }
    }
  }

  void _onInteractions(
    AttemptId attemptId,
    CurrentCollectionRef reference,
    List<PendingInteraction> interactions,
    bool complete,
    Object? error,
  ) {
    final workspace = state.workspace;
    if (_closed ||
        _state.currentAttemptId != attemptId ||
        workspace == null ||
        workspace.businessRefs.interactions != reference)
      return;
    _source.publish(
      state.copyWith(
        workspace: complete
            ? workspace.copyWith(interactions: List.unmodifiable(interactions))
            : workspace,
        interactionReadReference: complete ? reference : null,
        interactionReadError: error,
      ),
    );
  }

  void _onFailure(AttemptId attemptId, Object error, bool exhausted) {
    final eligible = _eligibleResync(attemptId);
    _source.publish(
      state.copyWith(
        sync: DomainSyncStatus(
          phase: exhausted
              ? DomainSyncPhase.failed
              : DomainSyncPhase.reconnecting,
          errorMessage: error.toString(),
          retryExhausted: exhausted,
        ),
      ),
    );
    if (eligible != null &&
        identical(_resync, eligible) &&
        eligible.expectedAttempt == attemptId &&
        _state.currentAttemptId == attemptId) {
      _resync = null;
      if (!eligible.completer.isCompleted) {
        eligible.completer.completeError(error);
      }
    }
  }

  _RuntimeResync? _eligibleResync(AttemptId attemptId) {
    final pending = _resync;
    return pending?.expectedAttempt == attemptId ? pending : null;
  }

  @override
  void refresh() {
    _state.refresh();
  }

  @override
  Future<ThreadWorkspace> resyncRuntime() {
    if (_closed || !isActive)
      return Future.error(ThreadStateResyncCancelled(threadId));
    final pending = _resync;
    if (pending != null) return pending.completer.future;
    final result = _RuntimeResync();
    _resync = result;
    // A state resync rebuilds only the state baseline; valid content and
    // drafts keep their live owner.
    _state.refresh();
    return result.completer.future;
  }

  void _cancelResync() {
    final pending = _resync;
    _resync = null;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(ThreadStateResyncCancelled(threadId));
    }
  }

  Future<CloseReport> retire({ClientCloseBudget? budget}) {
    setVisible(false);
    return Future.wait([_state.joinRetired(budget: budget)]).then(
      (reports) => CloseReport(
        unresolved: [for (final report in reports) ...report.unresolved],
      ),
    );
  }

  Future<CloseReport> close({ClientCloseBudget? budget}) {
    final existing = _closing;
    if (existing != null) return existing;
    final completion = Completer<CloseReport>();
    _closing = completion.future;
    completion.complete(Future<CloseReport>.sync(() => _close(budget)));
    return completion.future;
  }

  Future<CloseReport> _close(ClientCloseBudget? budget) async {
    _closed = true;
    _cancelResync();
    _directoryObservation.cancel();
    _scope.requestClose();
    final directoryClosing = budget == null
        ? _joinDirectoryRelease()
        : _scope.close(budget: budget);
    final stateClosing = _state.close(budget: budget);
    Object? closeError;
    StackTrace? closeStack;
    CloseReport? stateFeed;
    try {
      stateFeed = await stateClosing;
    } catch (error, stack) {
      closeError = error;
      closeStack = stack;
    }
    final directory = await directoryClosing;
    if (closeError != null) {
      Error.throwWithStackTrace(closeError, closeStack!);
    }
    return CloseReport(
      unresolved: [...?stateFeed?.unresolved, ...directory.unresolved],
    );
  }

  Future<CloseReport> retryCleanup({required ClientCloseBudget budget}) =>
      Future.wait([
        _scope.retryCleanup(budget: budget),
        _state.retryCleanup(budget: budget),
      ]).then(
        (reports) => CloseReport(
          unresolved: [for (final report in reports) ...report.unresolved],
        ),
      );

  Future<CloseReport> _joinDirectoryRelease() async {
    try {
      await _directoryLease.latestRelease;
    } catch (_) {
      // The scope retains the original failure and its resource identity.
    }
    // A release may synchronously reenter this join before the scope installs
    // its result listener. Let that listener settle the entry before reading
    // the report; this is bookkeeping, not a timer or a new cleanup wait.
    await Future<void>.value();
    // Cleanup has reached a real terminal result. This zero-budget call only
    // reads the scope report; it never grants cleanup another waiting period.
    return _scope.close(budget: ClientCloseBudget(Duration.zero));
  }

  void seedInputFacts(String inputId, void Function(InputTurnFact) onFact) {
    final seen = <String>{};
    for (final turn in [state.activeTurn, state.lastTurn]) {
      if (turn?.inputId == inputId && seen.add(turn!.turnId)) {
        onFact(_turnFact(turn));
      }
    }
  }

  void _publishCurrentInputFacts(ThreadSessionState candidate) {
    if (_closed || !_inputFacts.hasObservers) return;
    final seen = <(String, String)>{};
    for (final turn in [candidate.activeTurn, candidate.lastTurn]) {
      final input = turn?.inputId;
      if (turn == null || input == null || !seen.add((input, turn.turnId))) {
        continue;
      }
      if (_inputFacts.isWatching(input)) _inputFacts.publish(_turnFact(turn));
    }
  }

  InputTurnFact _turnFact(StudioTurnView turn) => InputTurnFact(
    threadId: turn.threadId,
    inputId: turn.inputId!,
    itemId: null,
    turnId: turn.turnId,
    status: turn.state.status,
    saved: null,
  );
}

final class _SessionDirectoryLease implements ClientLease {
  _SessionDirectoryLease(this.observation);

  final DirectoryObservation<ThreadMetadataFrame> observation;
  Completer<void> _release = Completer<void>();

  Future<void> get latestRelease => _release.future;

  @override
  List<ClientResourceId> get retirementResourceIds =>
      observation.retirementResourceIds;

  // Only the scope calls this method, including management-side retries. The
  // session passively joins latestRelease and never calls the raw lease again.
  @override
  Future<void> release() {
    final completion = _release.isCompleted ? Completer<void>() : _release;
    _release = completion;
    // Publish the exact join Future before invoking reentrant external code.
    // Future.sync preserves synchronous failures for the scope's normal path.
    completion.complete(Future<void>.sync(observation.release));
    return completion.future;
  }
}

final class _RuntimeResync {
  final Completer<ThreadWorkspace> completer = Completer<ThreadWorkspace>();
  AttemptId? expectedAttempt;
}
