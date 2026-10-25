import '../../../resources.dart';
import 'statistics_state.dart';

abstract interface class StatisticsRepository {
  ReadonlyLatestValue<StatisticsSummaryState> get summaries;
  ReadonlyLatestValue<StatisticsHistoryState> get history;
  Future<void> loadSummariesPage({int limit = 32});
  Future<void> loadHistoryPage({int limit = 32});
  SessionCostsQuery costs(String rootThreadId);
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

abstract interface class SessionCostsQuery {
  String get rootThreadId;
  ReadonlyLatestValue<SessionCostsState> get state;
  Future<void> load();
  void requestClose();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
