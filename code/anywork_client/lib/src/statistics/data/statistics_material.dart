import '../../../resources.dart';
import '../domain/statistics_state.dart';
import '../domain/statistics_values.dart';
import 'statistics_read_fields.dart';
import 'statistics_reader.dart';

typedef SummariesRow = ({PerformanceSummary value, SummaryIdentityRefs refs});
typedef HistoryRow = ({PerformanceSample value, SampleIdentityRefs refs});

/// One side's complete, validated material for exactly one captured
/// projection. It exists only inside the reader attempt that captured it.
final class StatisticsSummariesMaterial {
  StatisticsSummariesMaterial({
    required this.origin,
    required this.reference,
    required this.collection,
    required this.header,
    required List<PerformanceSummary> values,
    required this.rows,
  }) : values = List.unmodifiable(values) {
    if (values.length != collection.total)
      throw statisticsProtocol(
        'A summary material disagrees with its own collection length.',
      );
  }

  final ProductReadOrigin origin;
  final PerformanceSummariesReadRef reference;
  final ProductCollectionRef collection;
  final PerformanceSummariesHeader header;
  final List<PerformanceSummary> values;

  /// Row identity references reused by a later material of this attempt.
  /// Null when the values were reused from an already complete publication and
  /// no page was read again.
  final List<SummariesRow>? rows;
}

final class StatisticsHistoryMaterial {
  StatisticsHistoryMaterial({
    required this.origin,
    required this.reference,
    required this.collection,
    required this.header,
    required List<PerformanceSample> values,
    required this.rows,
  }) : values = List.unmodifiable(values) {
    if (values.length != collection.total)
      throw statisticsProtocol(
        'A history material disagrees with its own collection length.',
      );
  }

  final ProductReadOrigin origin;
  final PerformanceHistoryReadRef reference;
  final ProductCollectionRef collection;
  final PerformanceHistoryHeader header;
  final List<PerformanceSample> values;
  final List<HistoryRow>? rows;
}
