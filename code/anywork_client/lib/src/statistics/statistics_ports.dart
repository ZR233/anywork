import '../lifecycle/resource_budget.dart';
import 'data/statistics_repository_impl.dart';
import 'domain/statistics_failure.dart';
import 'domain/statistics_models.dart';
import 'domain/statistics_repository.dart';

/// Opaque native or demo statistics feed source. It is independent of StudioTransport.
abstract interface class StatisticsFeedPort {
  Future<StatisticsFeedConnection> open();
}

abstract interface class StatisticsFeedConnection {
  /// One ordered typed stream. Consumers await each envelope before requesting more work.
  Stream<StatisticsFeedEvent> events();

  Future<StatisticsReadScope> openScope(StatisticsFeedIdentity publication);
  Future<void> acknowledge(int deliverySequence);

  /// Synchronously seals local admission before asynchronous native close/join begins.
  void requestClose();

  Future<void> close();
}

sealed class StatisticsFeedEvent {
  const StatisticsFeedEvent();
}

final class StatisticsFeedBaseline extends StatisticsFeedEvent {
  const StatisticsFeedBaseline(this.publication);

  final StatisticsFeedIdentity publication;
}

final class StatisticsFeedData extends StatisticsFeedEvent {
  const StatisticsFeedData(this.publication);

  final StatisticsFeedIdentity publication;
}

final class StatisticsFeedFailure extends StatisticsFeedEvent {
  const StatisticsFeedFailure(this.failure);

  final StatisticsFailure failure;
}

final class StatisticsFeedClosed extends StatisticsFeedEvent {
  const StatisticsFeedClosed();
}

abstract interface class StatisticsReadScope {
  String get ownerEpoch;
  String get feedId;
  String get scopeId;
  int get publicationRevision;

  Future<StatisticsPage<StatisticsSummaryPageItem>> readSummaries(
    int offset,
    int limit,
  );

  Future<StatisticsPage<StatisticsSample>> readHistory(int offset, int limit);

  Future<StatisticsPage<StatisticsEffortSummary>> readEfforts(
    int summaryIndex,
    int offset,
    int limit,
  );

  Future<void> close();
}

/// Summary material without its independently paged effort breakdowns.
final class StatisticsSummaryPageItem {
  const StatisticsSummaryPageItem({
    required this.accountId,
    required this.accountDisplayName,
    required this.modelId,
    required this.sampleCount,
    required this.completionTokens,
    required this.totalTtftMillis,
    required this.ttftSampleCount,
    required this.totalResponseMillis,
    required this.tokensPerSecond,
    required this.averageTtftMillis,
    required this.averageResponseMillis,
    required this.effortCount,
  });

  final String accountId;
  final String accountDisplayName;
  final String modelId;
  final int sampleCount;
  final int completionTokens;
  final int totalTtftMillis;
  final int ttftSampleCount;
  final int totalResponseMillis;
  final double tokensPerSecond;
  final double? averageTtftMillis;
  final double averageResponseMillis;
  final int effortCount;
}

/// Typed page metadata shared by all statistics materials.
final class StatisticsPage<T> {
  StatisticsPage({
    required this.ownerEpoch,
    required this.feedId,
    required this.scopeId,
    required this.publicationRevision,
    required this.materialRevision,
    required this.offset,
    required this.totalCount,
    required this.nextOffset,
    required this.sourceBytes,
    this.summaryIndex,
    required Iterable<T> items,
  }) : items = List.unmodifiable(items);

  final String ownerEpoch;
  final String feedId;
  final String scopeId;
  final int publicationRevision;
  final int materialRevision;
  final int offset;
  final int totalCount;
  final int? nextOffset;
  final int sourceBytes;
  final int? summaryIndex;
  final List<T> items;
}

/// AppGraph composition entry: one SDK-only repository per application instance.
StatisticsRepository createStatisticsRepository({
  required StatisticsFeedPort feed,
  required ResourceBudget budget,
  required String owner,
}) => StatisticsRepositoryImpl(feed: feed, budget: budget, owner: owner);
