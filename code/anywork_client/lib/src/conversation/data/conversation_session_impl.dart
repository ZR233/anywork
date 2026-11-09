import 'dart:async';

import '../../../models.dart';
import '../../../conversation_ports.dart';
import '../../../directory_ports.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/close_report.dart';
import '../../observation/latest_value.dart';
import '../../studio/stores/thread_directory_store.dart';
import '../../studio/stores/domain_sync.dart';
import '../domain/conversation_repository.dart';
import '../domain/conversation_state.dart';
import 'conversation_content_impl.dart';
import 'conversation_state_owner.dart';
import 'state_reducer.dart';
import 'thread_stream_gate.dart';
import 'input_turn_facts.dart';
import '../domain/conversation_errors.dart';

/// One canonical state mirror, one independent state feed owner and one content
/// feed owner. No public setter.
final class ConversationSessionImpl implements ConversationSession {
  ConversationSessionImpl(
    this.threadId, {
    required ConversationTransport transport,
    required this.directory,
    required InputFactRegistry inputFacts,
  }) : _inputFacts = inputFacts,
       _source = LatestValue(ThreadSessionState(threadId: threadId)) {
    _state = ConversationStateOwner(
      threadId: threadId,
      transport: transport,
      onState: _onState,
      onFailure: _onFailure,
      onAttempt: _onAttempt,
    );
    _content = ConversationContentImpl(
      threadId: threadId,
      transport: transport,
    );
    _directoryDemand = directory.observeThread(threadId);
    _directoryObservation = _directoryDemand.state.watch(
      (_) => _rebindDirectory(),
      fireImmediately: true,
    );
  }
  @override
  final String threadId;
  final ThreadDirectoryStore directory;
  final InputFactRegistry _inputFacts;
  final LatestValue<ThreadSessionState> _source;
  late final ConversationStateOwner _state;
  late final ConversationContentImpl _content;
  late final DirectoryObservation<ThreadMetadataFrame> _directoryDemand;
  late final Observation _directoryObservation;
  _RuntimeResync? _resync;
  bool _closed = false;
  Future<CloseReport>? _closing;
  int _visibilityGeneration = 0;

  @override
  ThreadSessionState get state => _source.value;
  @override
  ValueObservation<ThreadSessionState> get source => _source;
  @override
  ConversationContent get content => _content;
  @override
  ValueObservation<ActivitySnapshot?> get activity => _content.activity;
  @override
  // The session's real visible demand: the state owner turns on first, so
  // this must already read true during that synchronous window, or a
  // reentrant visibility switch cannot revoke the stale stack.
  bool get isActive => _state.hasDemand || _content.hasDemand;
  @override
  bool get isClosed => _closed;

  void setVisible(bool visible) {
    final generation = ++_visibilityGeneration;
    if (!visible) {
      _cancelResync();
      _state.setDemand(false);
      _content.setDemand(false);
      _source.publish(state.copyWith(sync: const DomainSyncStatus()));
      return;
    }
    if (_closed) throw StateError('Conversation is closed');
    // State opens first: its synchronous connecting publication may reenter
    // visibility switching. A reentrant revoke (or an A -> B -> A cascade)
    // bumps the generation, so this stale stack can never resurrect content
    // demand; only the newest stack owns the recovery. A synchronous close
    // from that publication seals this session, so it must also stop here
    // instead of demanding from a closed content owner.
    _state.setDemand(true);
    if (_closed || generation != _visibilityGeneration) return;
    _content.setDemand(true);
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
        sync: const DomainSyncStatus(phase: DomainSyncPhase.connecting),
      ),
    );
  }

  void _onState(AttemptId attemptId, ThreadStreamFrame frame) {
    final id = switch (frame) {
      ThreadSnapshotFrame(:final workspace) => workspace.thread.id,
      ThreadNotificationFrame(:final threadId) => threadId,
      ThreadResyncRequiredFrame(:final threadId) => threadId,
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
        final previousRefs = state.businessRefs;
        _source.publish(candidate);
        if (identical(state, candidate)) {
          _content.businessRefsChanged(previousRefs, candidate.businessRefs!);
        }
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
      case ThreadResyncRequiredFrame(:final dropped, :final epoch):
        throw ThreadStateLagged(
          threadId: threadId,
          dropped: dropped,
          epoch: epoch,
        );
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
            final previousRefs = state.businessRefs;
            _source.publish(candidate);
            if (identical(state, candidate)) {
              _content.businessRefsChanged(
                previousRefs,
                candidate.businessRefs!,
              );
            }
            if (identical(state, candidate))
              _publishCurrentInputFacts(candidate);
        }
    }
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
    _content.refresh();
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

  Future<CloseReport> retire({DateTime? deadline}) {
    setVisible(false);
    return Future.wait([
      _state.joinRetired(deadline: deadline),
      _content.joinRetired(deadline: deadline),
    ]).then(
      (reports) => CloseReport(
        unresolved: [for (final report in reports) ...report.unresolved],
      ),
    );
  }

  Future<CloseReport> close({DateTime? deadline}) =>
      _closing ??= _close(deadline);
  Future<CloseReport> _close(DateTime? deadline) async {
    _closed = true;
    _cancelResync();
    _directoryObservation.cancel();
    final unresolved = <UnresolvedResource>[];
    final directoryWork = _directoryDemand.release().then<void>(
      (_) {},
      onError: (Object error, StackTrace _) {
        unresolved.add(
          UnresolvedResource(
            owner: 'conversation-directory:$threadId',
            attemptId: const AttemptId(0),
            reason: error,
          ),
        );
      },
    );
    // Seal both owners synchronously before joining either: a blocked state
    // join must not leave content admitting or ACKing until the deadline.
    // Either side failing never skips the other side's close.
    final stateClosing = _state.close(deadline: deadline);
    final contentClosing = _content.close(deadline: deadline);
    Object? closeError;
    StackTrace? closeStack;
    CloseReport? stateFeed;
    CloseReport? content;
    try {
      stateFeed = await stateClosing;
    } catch (error, stack) {
      closeError = error;
      closeStack = stack;
    }
    try {
      content = await contentClosing;
    } catch (error, stack) {
      closeError ??= error;
      closeStack ??= stack;
    }
    await directoryWork;
    if (closeError != null) {
      Error.throwWithStackTrace(closeError, closeStack!);
    }
    return CloseReport(
      unresolved: [
        ...?stateFeed?.unresolved,
        ...?content?.unresolved,
        ...unresolved,
      ],
    );
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      Future.wait([
        _state.retryCleanup(deadline: deadline),
        _content.retryCleanup(deadline: deadline),
      ]).then(
        (reports) => CloseReport(
          unresolved: [for (final report in reports) ...report.unresolved],
        ),
      );

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

final class _RuntimeResync {
  final Completer<ThreadWorkspace> completer = Completer<ThreadWorkspace>();
  AttemptId? expectedAttempt;
}
