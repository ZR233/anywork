import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/statistics_ports.dart';

import 'history_read_connection.dart';
import 'identity_read_connections.dart';
import 'performance_history_feed.dart';
import 'performance_summaries_feed.dart';
import 'summaries_read_connection.dart';

StatisticsPort createStatisticsPort() => const FrbStatisticsPort();

/// No secondary statistics cache or model selection. Every read opens the
/// exact reference/origin supplied by the Repository, including identity reads.
/// Root-session costs are not part of this domain.
final class FrbStatisticsPort implements StatisticsPort {
  const FrbStatisticsPort();

  @override
  Future<FeedConnection<PerformanceSummariesFrame>>
  openPerformanceSummaries() async {
    final connection = FrbPerformanceSummariesConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<FeedConnection<PerformanceHistoryFrame>>
  openPerformanceHistory() async {
    final connection = FrbPerformanceHistoryConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<PerformanceSummariesReadConnection> openPerformanceSummariesRead(
    PerformanceSummariesReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbPerformanceSummariesReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<PerformanceHistoryReadConnection> openPerformanceHistoryRead(
    PerformanceHistoryReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbPerformanceHistoryReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<PerformanceSummaryIdentityReadConnection> openSummaryIdentity(
    PerformanceSummaryIdentityRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbPerformanceSummaryIdentityReadConnection(
      reference,
      origin,
    );
    await connection.opened;
    return connection;
  }

  @override
  Future<PerformanceEffortIdentityReadConnection> openEffortIdentity(
    PerformanceEffortIdentityRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbPerformanceEffortIdentityReadConnection(
      reference,
      origin,
    );
    await connection.opened;
    return connection;
  }

  @override
  Future<PerformanceSampleIdentityReadConnection> openSampleIdentity(
    PerformanceSampleIdentityRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbPerformanceSampleIdentityReadConnection(
      reference,
      origin,
    );
    await connection.opened;
    return connection;
  }
}
