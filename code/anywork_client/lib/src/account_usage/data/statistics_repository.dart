import '../../../resources_ports.dart';
import '../domain/statistics_repository.dart';
import '../domain/statistics_state.dart';
import 'session_costs_query.dart';
import 'statistics_mirrors.dart';
import 'statistics_port.dart';
import 'statistics_reader.dart';

/// Read-only statistics has no dependency on the operations registry.
StatisticsRepository createStatisticsRepository({
  required StatisticsPort port,
  required ResourceBudget budget,
}) => _StatisticsRepository(port, budget);

final class _StatisticsRepository implements StatisticsRepository {
  _StatisticsRepository(this.port, this.budget)
    : lifetime = ResourceLifetime(budget) {
    final reader = StatisticsReader(port, lifetime);
    summaryMirror = StatisticsSummariesMirror(port, lifetime, reader);
    historyMirror = StatisticsHistoryMirror(port, lifetime, reader);
  }
  final StatisticsPort port;
  final ResourceBudget budget;
  final ResourceLifetime lifetime;
  late final StatisticsSummariesMirror summaryMirror;
  late final StatisticsHistoryMirror historyMirror;
  final Set<StatisticsCostsQuery> _costs = Set.identity();
  bool _sealed = false;
  bool _sourcesClosed = false;
  void _admit() {
    if (_sealed) throw resourceCancelled;
    lifetime.admit();
  }

  @override
  ReadonlyLatestValue<StatisticsSummaryState> get summaries =>
      summaryMirror.source.readonly;
  @override
  ReadonlyLatestValue<StatisticsHistoryState> get history =>
      historyMirror.source.readonly;
  @override
  Future<void> loadSummariesPage({int limit = 32}) {
    _admit();
    return summaryMirror.pages.page(limit: limit);
  }

  @override
  Future<void> loadHistoryPage({int limit = 32}) {
    _admit();
    return historyMirror.pages.page(limit: limit);
  }

  @override
  SessionCostsQuery costs(String rootThreadId) {
    _admit();
    if (rootThreadId.trim().isEmpty)
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'A SessionCosts query requires a non-empty root thread ID.',
        retryable: false,
        correlationId: 'statistics',
      );
    final query = StatisticsCostsQuery(
      port,
      budget,
      rootThreadId,
      _costs.remove,
    );
    _costs.add(query);
    return query;
  }

  @override
  void seal() {
    _sealed = true;
    lifetime.seal();
    for (final query in List.of(_costs)) {
      query.requestClose();
    }
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      _close(deadline, true);
  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    seal();
    final queries = List.of(_costs);
    final reports = await Future.wait([
      lifetime.close(deadline: deadline, retry: retry),
      for (final query in queries)
        retry
            ? query.retryCleanup(deadline: deadline)
            : query.close(deadline: deadline),
    ]);
    if (reports.first.complete && !_sourcesClosed) {
      _sourcesClosed = true;
      summaryMirror.markClosed();
      historyMirror.markClosed();
      summaryMirror.source.close();
      historyMirror.source.close();
    }
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }
}
