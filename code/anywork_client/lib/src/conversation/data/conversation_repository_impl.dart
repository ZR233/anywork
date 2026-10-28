import 'dart:async';

import '../../lifecycle/resource_budget.dart';
import '../../observation/latest_value.dart';
import '../../studio/stores/thread_directory_store.dart';
import '../../../conversation_ports.dart';
import '../domain/conversation_repository.dart';
import '../domain/conversation_state.dart';
import 'conversation_session_impl.dart';
import 'input_turn_facts.dart';

final class ConversationRepositoryImpl
    implements ConversationRepository, InputTurnFacts {
  ConversationRepositoryImpl({
    required this.transport,
    required this.directory,
    required this.budget,
    required this.onRevision,
    this.onVisibleThreadChanged,
  });
  final ConversationTransport transport;
  final ThreadDirectoryStore directory;
  final ResourceBudget budget;
  final void Function(String key, int revision) onRevision;
  final void Function(String?)? onVisibleThreadChanged;
  final Map<String, ConversationSessionImpl> _sessions = {};
  final Map<String, ResourcePermit> _permits = {};
  final Map<String, Observation> _observations = {};
  // Every exact retirement Future remains owned, including A -> B -> A.
  final Set<Future<CloseReport>> _retiring = {};
  final Map<String, CloseReport> _reports = {};
  final LatestValue<String?> _visibleThreadId = LatestValue(null);
  String? _visibleThread;
  String? _requestedVisibleThread;
  bool _drainingVisibility = false;
  bool _closed = false;
  Future<CloseReport>? _closing;
  late final InputFactRegistry _inputFacts = InputFactRegistry(
    budget,
    seed: (inputId, onFact) {
      for (final session in List.of(_sessions.values)) {
        session.seedInputFacts(inputId, onFact);
      }
    },
  );

  @override
  Observation watchInputFacts({
    required String inputId,
    String? expectedThreadId,
    required void Function(InputTurnFact) onFact,
  }) {
    if (_closed) throw StateError('Conversation repository is closed');
    return _inputFacts.watchInputFacts(
      inputId: inputId,
      expectedThreadId: expectedThreadId,
      onFact: onFact,
    );
  }

  @override
  ConversationSession session(String threadId) {
    final existing = _sessions[threadId];
    if (existing != null) return existing;
    if (_closed) throw StateError('Conversation repository is closed');
    final permit = budget.acquire(
      ResourceKind.readModel,
      owner: 'conversation:$threadId',
    );
    try {
      final owner = ConversationSessionImpl(
        threadId,
        transport: transport,
        directory: directory,
        budget: budget,
        inputFacts: _inputFacts,
      );
      _sessions[threadId] = owner;
      _permits[threadId] = permit;
      _observations[threadId] = owner.source.watch((value) {
        if (value.hasSnapshot)
          onRevision('thread-state:$threadId', value.revision);
        final route = value.runtime?.modelRoute;
        if (route != null) onRevision('thread-route:$threadId', route.revision);
      });
      return owner;
    } catch (_) {
      permit.release();
      rethrow;
    }
  }

  @override
  ConversationSession? existingSession(String threadId) => _sessions[threadId];
  @override
  ThreadSessionState? sessionState(String threadId) =>
      _sessions[threadId]?.state;
  @override
  Iterable<ThreadSessionState> get sessionStates =>
      List.unmodifiable(_sessions.values.map((owner) => owner.state));
  @override
  ValueObservation<String?> get visibleThreadId => _visibleThreadId;

  @override
  void setVisibleThread(String? threadId) {
    if (_closed) {
      if (threadId != null)
        throw StateError('Conversation repository is closed');
      return;
    }
    _requestedVisibleThread = threadId;
    if (_drainingVisibility) return;
    _drainingVisibility = true;
    try {
      while (!_closed && _visibleThread != _requestedVisibleThread) {
        final old = _visibleThread;
        final target = _requestedVisibleThread;
        _visibleThread = target;
        // Withdraw the previous ready mirror before any reentrant transition.
        if (_visibleThreadId.value != null) _visibleThreadId.publish(null);
        // Reentrant navigation only registers intent until this departure retires.
        if (!_closed) onVisibleThreadChanged?.call(target);
        if (old != null) {
          final owner = _sessions[old];
          if (owner != null) _retainRetirement(owner.retire());
        }
        if (!_closed && target != null && _requestedVisibleThread == target) {
          // Borrowing the mirror alone never admits a native feed.
          session(target);
          if (!_closed && _requestedVisibleThread == target) {
            _visibleThreadId.publish(target);
            if (!_closed && _requestedVisibleThread == target) {
              _sessions[target]!.setVisible(true);
            }
          }
        }
      }
    } finally {
      _drainingVisibility = false;
    }
  }

  void _retainRetirement(Future<CloseReport> task) {
    _retiring.add(task);
    unawaited(
      task.then(
        (_) {
          _retiring.remove(task);
        },
        onError: (Object _, StackTrace _) {
          // The session still owns the failed native cleanup and its permit.
          _retiring.remove(task);
        },
      ),
    );
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) =>
      _closing ??= _close(deadline);
  Future<CloseReport> _close(DateTime? deadline) async {
    _closed = true;
    _requestedVisibleThread = null;
    final hadVisibleThread = _visibleThread != null;
    _visibleThread = null;
    if (_visibleThreadId.value != null) _visibleThreadId.publish(null);
    if (hadVisibleThread) onVisibleThreadChanged?.call(null);
    final tasks = {
      for (final entry in _sessions.entries)
        entry.key: entry.value.close(deadline: deadline),
    };
    for (final entry in tasks.entries) _reports[entry.key] = await entry.value;
    _releaseResolved();
    return CloseReport(
      unresolved: [for (final r in _reports.values) ...r.unresolved],
    );
  }

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) async {
    final tasks = {
      for (final entry in _sessions.entries)
        entry.key: entry.value.retryCleanup(deadline: deadline),
    };
    for (final entry in tasks.entries) _reports[entry.key] = await entry.value;
    _releaseResolved();
    return CloseReport(
      unresolved: [for (final r in _reports.values) ...r.unresolved],
    );
  }

  void _releaseResolved() {
    if (!_closed) return;
    for (final id in _sessions.keys) {
      if (_reports[id]?.unresolved.isNotEmpty ?? true) continue;
      _observations.remove(id)?.cancel();
      _permits.remove(id)?.release();
    }
  }
}
