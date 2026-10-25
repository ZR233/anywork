import 'package:anywork_client/statistics.dart';

/// Immutable presentation projection. It contains no provider, transport, or mutable domain state.
final class StatisticsViewState {
  StatisticsViewState({
    required this.repository,
    required this.modelFilter,
    required this.effortFilter,
    required this.mismatchesOnly,
    required Iterable<StatisticsSample> filteredHistory,
  }) : filteredHistory = List.unmodifiable(filteredHistory);

  final StatisticsRepositoryState repository;
  final String? modelFilter;
  final String? effortFilter;
  final bool mismatchesOnly;
  final List<StatisticsSample> filteredHistory;

  StatisticsSnapshot? get snapshot => repository.snapshot;
  StatisticsConnectionState get connection => repository.connection;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatisticsViewState &&
          repository == other.repository &&
          modelFilter == other.modelFilter &&
          effortFilter == other.effortFilter &&
          mismatchesOnly == other.mismatchesOnly &&
          _listEquals(filteredHistory, other.filteredHistory);

  @override
  int get hashCode => Object.hash(
    repository,
    modelFilter,
    effortFilter,
    mismatchesOnly,
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
