import '../../models/failure_models.dart' show StudioFailureCode;
import '../domain/statistics_failure.dart';
import '../domain/statistics_models.dart';
import '../statistics_ports.dart';

const _pageSize = 128;
const _maximumSourcePageBytes = 256 * 1024;

/// Complete materialized materials from one immutable owner publication.
final class StatisticsMaterializedMaterials {
  const StatisticsMaterializedMaterials({
    required this.summaries,
    required this.history,
  });

  final List<StatisticsSummary> summaries;
  final List<StatisticsSample> history;
}

/// Reads and validates all changed bounded materials before the repository ACKs a delivery.
final class StatisticsMaterializer {
  static Future<StatisticsMaterializedMaterials> read({
    required StatisticsReadScope scope,
    required StatisticsFeedIdentity publication,
    required StatisticsSnapshot? previous,
    required bool readSummaries,
    required bool readHistory,
  }) async {
    _validateScope(scope, publication);
    final summaries = readSummaries
        ? await _readSummaries(scope, publication)
        : previous?.summaries ?? const <StatisticsSummary>[];
    final history = readHistory
        ? await _readHistory(scope, publication)
        : previous?.history ?? const <StatisticsSample>[];
    return StatisticsMaterializedMaterials(
      summaries: summaries,
      history: history,
    );
  }

  static Future<List<StatisticsSummary>> _readSummaries(
    StatisticsReadScope scope,
    StatisticsFeedIdentity publication,
  ) async {
    final summaries = <StatisticsSummary>[];
    var offset = 0;
    while (true) {
      final page = await scope.readSummaries(offset, _pageSize);
      _validatePage(
        page,
        publication,
        scope: scope,
        materialRevision: publication.summariesRevision,
        expectedOffset: offset,
        expectedCount: publication.summaryCount,
      );
      for (var index = 0; index < page.items.length; index++) {
        final item = page.items[index];
        final summaryIndex = offset + index;
        final efforts = await _readEfforts(
          scope,
          publication,
          summaryIndex: summaryIndex,
          expectedCount: item.effortCount,
        );
        summaries.add(
          StatisticsSummary(
            accountId: item.accountId,
            accountDisplayName: item.accountDisplayName,
            modelId: item.modelId,
            sampleCount: item.sampleCount,
            completionTokens: item.completionTokens,
            totalTtftMillis: item.totalTtftMillis,
            ttftSampleCount: item.ttftSampleCount,
            totalResponseMillis: item.totalResponseMillis,
            tokensPerSecond: item.tokensPerSecond,
            averageTtftMillis: item.averageTtftMillis,
            averageResponseMillis: item.averageResponseMillis,
            effortBreakdowns: efforts,
          ),
        );
      }
      final next = page.nextOffset;
      if (next == null) break;
      offset = next;
    }
    return StatisticsMaterial.freeze(summaries);
  }

  static Future<List<StatisticsEffortSummary>> _readEfforts(
    StatisticsReadScope scope,
    StatisticsFeedIdentity publication, {
    required int summaryIndex,
    required int expectedCount,
  }) async {
    final efforts = <StatisticsEffortSummary>[];
    var offset = 0;
    while (true) {
      final page = await scope.readEfforts(summaryIndex, offset, _pageSize);
      _validatePage(
        page,
        publication,
        scope: scope,
        materialRevision: publication.summariesRevision,
        expectedOffset: offset,
        expectedCount: expectedCount,
        expectedSummaryIndex: summaryIndex,
      );
      efforts.addAll(
        page.items.map(
          (item) => StatisticsEffortSummary(
            effort: item.effort,
            sampleCount: item.sampleCount,
            completionTokens: item.completionTokens,
            totalTtftMillis: item.totalTtftMillis,
            ttftSampleCount: item.ttftSampleCount,
            totalResponseMillis: item.totalResponseMillis,
            tokensPerSecond: item.tokensPerSecond,
            averageTtftMillis: item.averageTtftMillis,
            averageResponseMillis: item.averageResponseMillis,
          ),
        ),
      );
      final next = page.nextOffset;
      if (next == null) break;
      offset = next;
    }
    return List.unmodifiable(efforts);
  }

  static Future<List<StatisticsSample>> _readHistory(
    StatisticsReadScope scope,
    StatisticsFeedIdentity publication,
  ) async {
    final history = <StatisticsSample>[];
    var offset = 0;
    while (true) {
      final page = await scope.readHistory(offset, _pageSize);
      _validatePage(
        page,
        publication,
        scope: scope,
        materialRevision: publication.historyRevision,
        expectedOffset: offset,
        expectedCount: publication.historyCount,
      );
      history.addAll(page.items);
      final next = page.nextOffset;
      if (next == null) break;
      offset = next;
    }
    return StatisticsMaterial.freeze(history);
  }

  static void _validatePage<T>(
    StatisticsPage<T> page,
    StatisticsFeedIdentity publication, {
    required StatisticsReadScope scope,
    required int materialRevision,
    required int expectedOffset,
    required int expectedCount,
    int? expectedSummaryIndex,
  }) {
    if (page.items.length > _pageSize ||
        page.sourceBytes < 0 ||
        page.sourceBytes > _maximumSourcePageBytes) {
      throw StatisticsFailure.local(
        category: StatisticsFailureCategory.capacity,
        code: StudioFailureCode.overloaded,
        message: 'Statistics page exceeds its supported capacity',
        retryable: true,
      );
    }
    if (page.ownerEpoch != scope.ownerEpoch ||
        page.ownerEpoch != publication.ownerEpoch ||
        page.feedId != scope.feedId ||
        page.feedId != publication.feedId ||
        page.scopeId != scope.scopeId ||
        page.publicationRevision != scope.publicationRevision ||
        page.publicationRevision != publication.publicationRevision ||
        page.materialRevision != materialRevision ||
        page.summaryIndex != expectedSummaryIndex ||
        page.offset != expectedOffset ||
        page.totalCount != expectedCount) {
      throw _protocolFailure(
        'statistics page identity did not match its scope',
      );
    }
    final pageEnd = expectedOffset + page.items.length;
    final next = page.nextOffset;
    if (pageEnd < expectedCount) {
      if (next == null || next != pageEnd || next <= expectedOffset) {
        throw _protocolFailure(
          'statistics continuation disagreed with total count',
        );
      }
    } else if (pageEnd != expectedCount || next != null) {
      throw _protocolFailure('statistics page end disagreed with total count');
    }
  }

  static void _validateScope(
    StatisticsReadScope scope,
    StatisticsFeedIdentity publication,
  ) {
    if (scope.ownerEpoch != publication.ownerEpoch ||
        scope.feedId != publication.feedId ||
        scope.publicationRevision != publication.publicationRevision ||
        scope.scopeId.isEmpty) {
      throw _protocolFailure(
        'statistics scope identity did not match its publication',
      );
    }
  }

  static StatisticsFailure _protocolFailure(String diagnostic) =>
      StatisticsFailure.local(
        category: StatisticsFailureCategory.protocol,
        code: StudioFailureCode.protocol,
        message: 'Statistics source returned invalid data',
        retryable: false,
        details: {'diagnostic': diagnostic},
      );
}
