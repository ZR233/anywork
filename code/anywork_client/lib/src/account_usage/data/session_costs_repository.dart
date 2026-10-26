import '../../../resources_ports.dart';
import '../domain/session_costs_repository.dart';
import 'session_costs_port.dart';
import 'session_costs_query.dart';

/// Root-session costs keep their own repository, budget accounting and close
/// rights inside the account-usage domain.
SessionCostsRepository createSessionCostsRepository({
  required SessionCostsPort port,
  required ResourceBudget budget,
}) => _SessionCostsRepository(port, budget);

final class _SessionCostsRepository implements SessionCostsRepository {
  _SessionCostsRepository(this.port, this.budget)
    : lifetime = ResourceLifetime(budget);

  final SessionCostsPort port;
  final ResourceBudget budget;
  final ResourceLifetime lifetime;
  final Set<SessionCostsBorrow> _queries = Set.identity();
  bool _sealed = false;

  void _admit() {
    if (_sealed) throw resourceCancelled;
    lifetime.admit();
  }

  @override
  SessionCostsQuery costs(String rootThreadId) {
    _admit();
    if (rootThreadId.trim().isEmpty)
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'A SessionCosts query requires a non-empty root thread ID.',
        retryable: false,
        correlationId: 'session-costs',
      );
    final query = SessionCostsBorrow(port, budget, rootThreadId, _remove);
    _queries.add(query);
    return query;
  }

  void _remove(SessionCostsBorrow query) => _queries.remove(query);

  @override
  void seal() {
    if (_sealed) return;
    _sealed = true;
    lifetime.seal();
    for (final query in List.of(_queries)) query.requestClose();
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      _close(deadline, true);

  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    seal();
    final queries = List.of(_queries);
    final reports = await Future.wait([
      lifetime.close(deadline: deadline, retry: retry),
      for (final query in queries)
        retry
            ? query.retryCleanup(deadline: deadline)
            : query.close(deadline: deadline),
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }
}
