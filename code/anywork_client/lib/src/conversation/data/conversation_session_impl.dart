import 'dart:async';

import '../../../models.dart';
import '../../../conversation_ports.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart';
import '../../observation/latest_value.dart';
import '../../studio/stores/thread_directory_store.dart';
import '../../studio/stores/domain_sync.dart';
import '../domain/conversation_repository.dart';
import '../domain/conversation_state.dart';
import 'conversation_content_impl.dart';
import 'state_reducer.dart';
import 'thread_stream_gate.dart';
import 'input_turn_facts.dart';
import '../domain/conversation_errors.dart';

/// One canonical state mirror and one combined feed owner. No public setter.
final class ConversationSessionImpl implements ConversationSession {
  ConversationSessionImpl(
    this.threadId, {
    required ConversationTransport transport,
    required this.directory,
    required ResourceBudget budget,
    required InputFactRegistry inputFacts,
  }) : _source = LatestValue(ThreadSessionState(threadId: threadId)) {
    _content = ConversationContentImpl(
      threadId: threadId,
      transport: transport,
      budget: budget,
      inputFacts: inputFacts,
      onState: _onState,
      onFailure: _onFailure,
      onAttempt: _onAttempt,
    );
    _directoryObservation = directory.source.watch((_) => _rebindDirectory());
  }
  @override
  final String threadId;
  final ThreadDirectoryStore directory;
  final LatestValue<ThreadSessionState> _source;
  late final ConversationContentImpl _content;
  late final Observation _directoryObservation;
  _RuntimeResync? _resync;
  bool _closed = false;
  Future<CloseReport>? _closing;

  @override
  ThreadSessionState get state => _source.value;
  @override
  ValueObservation<ThreadSessionState> get source => _source;
  @override
  ConversationContent get content => _content;
  @override
  bool get isActive => _content.hasDemand;
  @override
  bool get isClosed => _closed;

  void setVisible(bool visible) {
    if (!visible) {
      _cancelResync();
      _content.setDemand(false);
      _source.publish(state.copyWith(sync: const DomainSyncStatus()));
    } else {
      if (_closed) throw StateError('Conversation is closed');
      _content.setDemand(true);
    }
  }

  StudioThread? get _identity {
    for (final thread in [
      ...directory.state.window.threads,
      ...directory.state.overlayThreads,
    ]) {
      if (thread.id == threadId) return thread;
    }
    return null;
  }

  void _rebindDirectory() {
    if (_closed) return;
    final workspace = state.workspace;
    final identity = _identity;
    if (workspace == null ||
        identity == null ||
        identical(workspace.thread, identity))
      return;
    _source.publish(
      state.copyWith(workspace: workspace.copyWith(thread: identity)),
    );
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
          directoryThread: _identity,
        );
        final eligible = _eligibleResync(attemptId);
        _source.publish(candidate);
        if (eligible != null &&
            identical(_resync, eligible) &&
            eligible.expectedAttempt == attemptId &&
            _content.currentAttemptId == attemptId) {
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
            _source.publish(applyThreadNotificationState(state, frame));
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
        _content.currentAttemptId == attemptId) {
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
  void refresh() => _content.refresh();

  @override
  Future<ThreadWorkspace> resyncRuntime() {
    if (_closed || !isActive)
      return Future.error(ThreadStateResyncCancelled(threadId));
    final pending = _resync;
    if (pending != null) return pending.completer.future;
    final result = _RuntimeResync();
    _resync = result;
    _content.refresh();
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
    return _content.joinRetired(deadline: deadline);
  }

  Future<CloseReport> close({DateTime? deadline}) =>
      _closing ??= _close(deadline);
  Future<CloseReport> _close(DateTime? deadline) {
    _closed = true;
    _cancelResync();
    _directoryObservation.cancel();
    return _content.close(deadline: deadline);
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      _content.retryCleanup(deadline: deadline);

  void seedInputFacts(String inputId, void Function(InputTurnFact) onFact) =>
      _content.seedInputFacts(inputId, onFact);
}

final class _RuntimeResync {
  final Completer<ThreadWorkspace> completer = Completer<ThreadWorkspace>();
  AttemptId? expectedAttempt;
}
