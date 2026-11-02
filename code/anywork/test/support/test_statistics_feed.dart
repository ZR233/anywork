import 'dart:async';

import 'package:anywork_client/statistics.dart';
import 'package:anywork_client/statistics_ports.dart';

/// Explicit unused AppGraph fixture. Repository behavior tests use richer controlled sources.
final class TestStatisticsFeedPort implements StatisticsFeedPort {
  const TestStatisticsFeedPort();

  @override
  Future<StatisticsFeedConnection> open() async => _TestStatisticsConnection();
}

final class _TestStatisticsConnection implements StatisticsFeedConnection {
  final Completer<void> _closed = Completer<void>();
  final StreamController<StatisticsFeedEvent> _events =
      StreamController<StatisticsFeedEvent>();
  bool _first = true;
  bool _closeRequested = false;
  bool _acknowledged = false;

  final _identity = const StatisticsFeedIdentity(
    ownerEpoch: 'test-statistics-owner',
    feedId: 'test-statistics-feed',
    deliverySequence: 1,
    publicationRevision: 0,
    summariesRevision: 0,
    historyRevision: 0,
    summaryCount: 0,
    historyCount: 0,
    statisticsPending: false,
    statisticsGap: false,
    readFailed: false,
  );

  @override
  Stream<StatisticsFeedEvent> events() {
    if (_first) {
      _first = false;
      _events.add(StatisticsFeedBaseline(_identity));
    }
    return _events.stream;
  }

  @override
  Future<StatisticsReadScope> openScope(
    StatisticsFeedIdentity publication,
  ) async {
    if (_closeRequested ||
        _acknowledged ||
        publication.feedId != _identity.feedId) {
      throw StateError('test statistics source closed');
    }
    return _TestStatisticsScope(_identity);
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    if (deliverySequence != 1 || _closeRequested) {
      throw StateError('test statistics ACK identity mismatch');
    }
    _acknowledged = true;
  }

  @override
  void requestClose() {
    if (_closeRequested) return;
    _closeRequested = true;
    _events.add(const StatisticsFeedClosed());
    unawaited(_events.close());
    if (!_closed.isCompleted) _closed.complete();
  }

  @override
  Future<void> close() async {
    requestClose();
  }
}

final class _TestStatisticsScope implements StatisticsReadScope {
  _TestStatisticsScope(this._identity);

  final StatisticsFeedIdentity _identity;
  bool _closed = false;

  @override
  String get ownerEpoch => _identity.ownerEpoch;
  @override
  String get feedId => _identity.feedId;
  @override
  String get scopeId => 'test-statistics-scope';
  @override
  int get publicationRevision => _identity.publicationRevision;

  void _ensureOpen() {
    if (_closed) throw StateError('test statistics scope closed');
  }

  StatisticsPage<T> _emptyPage<T>(int offset, int revision) {
    _ensureOpen();
    return StatisticsPage<T>(
      ownerEpoch: ownerEpoch,
      feedId: feedId,
      scopeId: scopeId,
      publicationRevision: publicationRevision,
      materialRevision: revision,
      offset: offset,
      totalCount: 0,
      nextOffset: null,
      sourceBytes: 0,
      items: const [],
    );
  }

  @override
  Future<StatisticsPage<StatisticsSummaryPageItem>> readSummaries(
    int offset,
    int limit,
  ) async => _emptyPage(offset, _identity.summariesRevision);

  @override
  Future<StatisticsPage<StatisticsSample>> readHistory(
    int offset,
    int limit,
  ) async => _emptyPage(offset, _identity.historyRevision);

  @override
  Future<StatisticsPage<StatisticsEffortSummary>> readEfforts(
    int summaryIndex,
    int offset,
    int limit,
  ) async => _emptyPage(offset, _identity.summariesRevision);

  @override
  Future<void> close() async {
    _closed = true;
  }
}
