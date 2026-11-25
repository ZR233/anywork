import 'package:anywork_client/statistics.dart';

enum StatisticsSection { summaries, history }

/// Immutable presentation projection. It contains no provider, transport, or mutable domain state.
final class StatisticsViewState {
  StatisticsViewState({
    required this.repository,
    required this.modelFilter,
    required this.effortFilter,
    this.serviceTierFilter,
    required this.mismatchesOnly,
    required Iterable<StatisticsSample> filteredHistory,
    this.section = StatisticsSection.summaries,
    this.summaryPageIndex = 0,
    this.historyPageIndex = 0,
  }) : filteredHistory = StatisticsMaterial.freeze(filteredHistory);

  final StatisticsRepositoryState repository;
  final String? modelFilter;
  final String? effortFilter;
  final String? serviceTierFilter;
  final bool mismatchesOnly;
  final List<StatisticsSample> filteredHistory;
  final StatisticsSection section;
  final int summaryPageIndex;
  final int historyPageIndex;

  static const pageSize = 50;

  bool get isRefreshing => switch (connection.phase) {
    StatisticsConnectionPhase.connecting ||
    StatisticsConnectionPhase.reconnecting ||
    StatisticsConnectionPhase.closing => true,
    _ => false,
  };

  int get itemCount => section == StatisticsSection.summaries
      ? snapshot?.summaries.length ?? 0
      : filteredHistory.length;
  int get pageCount => pagesFor(itemCount);
  int get pageIndex => section == StatisticsSection.summaries
      ? summaryPageIndex
      : historyPageIndex;
  int get firstItem => itemCount == 0 ? 0 : pageIndex * pageSize + 1;
  int get lastItem => ((pageIndex + 1) * pageSize).clamp(0, itemCount);
  List<StatisticsSummary> get pageSummaries =>
      snapshot?.summaries
          .skip(summaryPageIndex * pageSize)
          .take(pageSize)
          .toList(growable: false) ??
      const [];
  List<StatisticsSample> get pageHistory => filteredHistory
      .skip(historyPageIndex * pageSize)
      .take(pageSize)
      .toList(growable: false);

  static int pagesFor(int count) =>
      count == 0 ? 1 : (count + pageSize - 1) ~/ pageSize;

  StatisticsSnapshot? get snapshot => repository.snapshot;
  StatisticsConnectionState get connection => repository.connection;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatisticsViewState &&
          repository == other.repository &&
          modelFilter == other.modelFilter &&
          effortFilter == other.effortFilter &&
          serviceTierFilter == other.serviceTierFilter &&
          mismatchesOnly == other.mismatchesOnly &&
          section == other.section &&
          summaryPageIndex == other.summaryPageIndex &&
          historyPageIndex == other.historyPageIndex &&
          _listEquals(filteredHistory, other.filteredHistory);

  @override
  int get hashCode => Object.hash(
    repository,
    modelFilter,
    effortFilter,
    serviceTierFilter,
    mismatchesOnly,
    section,
    summaryPageIndex,
    historyPageIndex,
    Object.hashAll(filteredHistory),
  );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
