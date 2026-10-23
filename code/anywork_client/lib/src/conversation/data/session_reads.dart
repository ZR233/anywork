import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../domain/read_scopes.dart';
import '../domain/thread_identity.dart';
import 'connection_owner.dart';
import 'read_connections.dart';
import 'read_scope_owners.dart';
import 'session_ui_demand.dart';

/// Opening, unreturned and borrowed detail scopes all remain owned by this Session.
final class ConversationSessionReads {
  ConversationSessionReads({required this.threadId, required this.budget, required this.nextAttempt});
  final String threadId;
  final ResourceBudget budget;
  final AttemptId Function() nextAttempt;
  final Map<ConversationReadScope, ({ThreadFacetStamp origin, ConversationUiDemand demand,
    bool Function() released, CloseReport Function() report})> _scopes = {};
  bool _sealed = false;

  Future<S> open<C extends ConversationReadConnection, S extends PinnedConversationScope<C>>({
    required ThreadFacetStamp origin, required ConversationUiDemand demand, required Future<C> Function() open,
    required S Function(ConversationConnectionOwner<C>) build,
  }) {
    if (_sealed || demand.retired) throw conversationCancelled;
    _scopes.removeWhere((_, entry) => entry.released());
    if (_scopes.length >= 8) throw const StudioFailure(code: StudioFailureCode.overloaded,
      message: 'The Thread already has eight owned detail scopes.', retryable: true,
      correlationId: 'thread-read-scopes', details: StudioFailureDetails.resourceLimit(resource: 'threadReadScope', capacity: 8));
    final ConversationConnectionOwner<C> owner;
    try {
      owner = ConversationConnectionOwner<C>(label: 'thread-read:$threadId', attemptId: nextAttempt(),
      budget: budget, kind: ResourceKind.readModel, requestClose: (c) => c.requestClose(),
      close: (c) => c.close(), retryClose: (c) => c.retryClose());
    } on ResourceBudgetExceeded catch (error) { throw error.failure; }
    final S scope;
    try { scope = build(owner); } catch (error, stack) {
      owner.start(() => Future.error(error, stack));
      owner.close().ignore();
      rethrow;
    }
    _scopes[scope] = (origin: origin, demand: demand, released: () => owner.released, report: owner.report);
    owner.start(() async {
      if (_sealed || demand.retired) throw conversationCancelled;
      final permit = budget.acquire(ResourceKind.pendingOperation, owner: 'thread-read-open:$threadId');
      try {
        if (_sealed || demand.retired) throw conversationCancelled;
        return await open();
      } finally { permit.release(); }
    });
    if (_sealed || demand.retired) { owner.requestClose(); owner.close().ignore(); }
    return owner.opened.then((_) => scope, onError: (Object error, StackTrace stack) {
      owner.requestClose();
      owner.close().ignore();
      Error.throwWithStackTrace(conversationFailure(error), stack);
    });
  }

  void retireOrigin(ThreadFacetStamp previous) {
    for (final entry in List.of(_scopes.entries)) {
      final origin = entry.value.origin;
      if (origin.runtimeEpoch == previous.runtimeEpoch && origin.incarnation == previous.incarnation) {
        entry.key.requestClose();
        entry.key.close().ignore();
      }
    }
  }

  void seal() {
    if (_sealed) return;
    _sealed = true;
    for (final scope in List.of(_scopes.keys)) { scope.requestClose(); }
  }

  Future<CloseReport> closeUi(ConversationUiDemand demand, {DateTime? deadline, bool retry = false}) async {
    demand.retired = true;
    final scopes = [for (final entry in _scopes.entries) if (identical(entry.value.demand, demand)) entry.key];
    await Future.wait([for (final scope in scopes)
      retry ? scope.retryCleanup(deadline: deadline) : scope.close(deadline: deadline)]);
    _scopes.removeWhere((_, entry) => entry.released());
    // A synchronous admission which was reentered by retirement still registers
    // its cancelled open in this same map. Include its actual current report.
    return conversationCloseReport([for (final entry in _scopes.values)
      if (identical(entry.demand, demand)) ...entry.report().unresolved]);
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    seal();
    final reports = await Future.wait([for (final scope in List.of(_scopes.keys))
      retry ? scope.retryCleanup(deadline: deadline) : scope.close(deadline: deadline)]);
    _scopes.removeWhere((_, entry) => entry.released());
    return CloseReport(unresolved: [for (final report in reports) ...report.unresolved]);
  }
}
