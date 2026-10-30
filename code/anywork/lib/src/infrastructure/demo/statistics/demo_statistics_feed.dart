import 'dart:async';

import 'package:anywork_client/statistics.dart';
import 'package:anywork_client/statistics_ports.dart';

/// Deterministic in-process statistics source for Demo and DriverDemo AppGraphs.
/// It implements the same scoped, paged port as the FRB adapter and does not use StudioTransport.
final class DemoStatisticsFeedPort implements StatisticsFeedPort {
  DemoStatisticsFeedPort({DateTime? now})
    : _ownerEpoch = 'demo-statistics:${DateTime.now().microsecondsSinceEpoch}',
      _snapshot = _demoSnapshot(now ?? DateTime.now());

  final String _ownerEpoch;
  final StatisticsSnapshot _snapshot;
  int _nextFeed = 0;

  @override
  Future<StatisticsFeedConnection> open() async {
    return _DemoStatisticsConnection(
      feedId: 'demo-statistics-feed-${++_nextFeed}',
      ownerEpoch: _ownerEpoch,
      snapshot: _snapshot,
    );
  }
}

final class _DemoStatisticsConnection implements StatisticsFeedConnection {
  _DemoStatisticsConnection({
    required this.feedId,
    required this.ownerEpoch,
    required this.snapshot,
  });

  final String feedId;
  final String ownerEpoch;
  final StatisticsSnapshot snapshot;
  final Set<_DemoStatisticsScope> _scopes = {};
  final Completer<void> _closed = Completer<void>();
  bool _baselineSent = false;
  bool _acknowledged = false;
  bool _closeRequested = false;

  StatisticsFeedIdentity get _identity => StatisticsFeedIdentity(
    ownerEpoch: ownerEpoch,
    feedId: feedId,
    deliverySequence: 1,
    publicationRevision: snapshot.publicationRevision,
    summariesRevision: snapshot.summariesRevision,
    historyRevision: snapshot.historyRevision,
    summaryCount: snapshot.summaries.length,
    historyCount: snapshot.history.length,
    statisticsPending: snapshot.statisticsPending,
    statisticsGap: snapshot.statisticsGap,
    readFailed: snapshot.readFailed,
  );

  @override
  Stream<StatisticsFeedEvent> events() async* {
    if (_closeRequested) return;
    if (!_baselineSent) {
      _baselineSent = true;
      yield StatisticsFeedBaseline(_identity);
    }
    await _closed.future;
    yield const StatisticsFeedClosed();
  }

  @override
  Future<StatisticsReadScope> openScope(
    StatisticsFeedIdentity publication,
  ) async {
    if (_closeRequested) {
      throw StatisticsFailure.local(
        category: StatisticsFailureCategory.closed,
        code: StudioFailureCode.runtimeStopped,
        message: 'Demo statistics feed is closed',
        retryable: false,
      );
    }
    if (publication.ownerEpoch != ownerEpoch ||
        publication.feedId != feedId ||
        publication.deliverySequence != 1 ||
        _acknowledged ||
        !_baselineSent) {
      throw StatisticsFailure.local(
        category: StatisticsFailureCategory.protocol,
        code: StudioFailureCode.protocol,
        message: 'Demo statistics scope reference is invalid',
        retryable: false,
      );
    }
    if (_scopes.length >= 2) {
      throw StatisticsFailure.local(
        category: StatisticsFailureCategory.capacity,
        code: StudioFailureCode.overloaded,
        message: 'Demo statistics feed scope capacity is exhausted',
        retryable: true,
      );
    }
    final scope = _DemoStatisticsScope(this, publication);
    _scopes.add(scope);
    return scope;
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    if (deliverySequence <= 1 && _acknowledged) return;
    if (_closeRequested || deliverySequence != 1 || !_baselineSent) {
      throw StatisticsFailure.local(
        category: StatisticsFailureCategory.acknowledgement,
        code: StudioFailureCode.protocol,
        message: 'Demo statistics delivery acknowledgement is invalid',
        retryable: false,
      );
    }
    _acknowledged = true;
  }

  @override
  void requestClose() {
    if (_closeRequested) return;
    _closeRequested = true;
    for (final scope in _scopes.toList()) {
      scope.requestClose();
    }
    if (!_closed.isCompleted) _closed.complete();
  }

  @override
  Future<void> close() async {
    requestClose();
    for (final scope in _scopes.toList()) {
      await scope.close();
    }
  }
}

final class _DemoStatisticsScope implements StatisticsReadScope {
  _DemoStatisticsScope(this.owner, this.publication)
    : scopeId = 'demo-statistics-scope-${++_nextScopeId}';

  static int _nextScopeId = 0;
  final _DemoStatisticsConnection owner;
  final StatisticsFeedIdentity publication;
  @override
  final String scopeId;
  bool _closed = false;

  @override
  String get ownerEpoch => publication.ownerEpoch;

  @override
  String get feedId => publication.feedId;

  @override
  int get publicationRevision => publication.publicationRevision;

  @override
  Future<StatisticsPage<StatisticsSummaryPageItem>> readSummaries(
    int offset,
    int limit,
  ) async {
    _ensureOpen();
    final summaries = owner.snapshot.summaries
        .map(
          (summary) => StatisticsSummaryPageItem(
            accountId: summary.accountId,
            accountDisplayName: summary.accountDisplayName,
            modelId: summary.modelId,
            sampleCount: summary.sampleCount,
            completionTokens: summary.completionTokens,
            totalTtftMillis: summary.totalTtftMillis,
            ttftSampleCount: summary.ttftSampleCount,
            totalResponseMillis: summary.totalResponseMillis,
            tokensPerSecond: summary.tokensPerSecond,
            averageTtftMillis: summary.averageTtftMillis,
            averageResponseMillis: summary.averageResponseMillis,
            effortCount: summary.effortBreakdowns.length,
          ),
        )
        .toList(growable: false);
    return _page(
      summaries,
      offset,
      limit,
      materialRevision: publication.summariesRevision,
    );
  }

  @override
  Future<StatisticsPage<StatisticsSample>> readHistory(
    int offset,
    int limit,
  ) async {
    _ensureOpen();
    return _page(
      owner.snapshot.history,
      offset,
      limit,
      materialRevision: publication.historyRevision,
    );
  }

  @override
  Future<StatisticsPage<StatisticsEffortSummary>> readEfforts(
    int summaryIndex,
    int offset,
    int limit,
  ) async {
    _ensureOpen();
    final summary = owner.snapshot.summaries[summaryIndex];
    return _page(
      summary.effortBreakdowns,
      offset,
      limit,
      materialRevision: publication.summariesRevision,
      summaryIndex: summaryIndex,
    );
  }

  StatisticsPage<T> _page<T>(
    List<T> values,
    int offset,
    int limit, {
    required int materialRevision,
    int? summaryIndex,
  }) {
    if (offset < 0 || limit < 1 || limit > 128 || offset > values.length) {
      throw RangeError('Demo statistics page request is invalid');
    }
    final end = (offset + limit) > values.length
        ? values.length
        : offset + limit;
    return StatisticsPage(
      ownerEpoch: publication.ownerEpoch,
      feedId: publication.feedId,
      scopeId: scopeId,
      publicationRevision: publication.publicationRevision,
      materialRevision: materialRevision,
      offset: offset,
      totalCount: values.length,
      nextOffset: end < values.length ? end : null,
      sourceBytes: 0,
      summaryIndex: summaryIndex,
      items: values.sublist(offset, end),
    );
  }

  void _ensureOpen() {
    if (_closed || owner._closeRequested) {
      throw StatisticsFailure.local(
        category: StatisticsFailureCategory.closed,
        code: StudioFailureCode.runtimeStopped,
        message: 'Demo statistics read scope is closed',
        retryable: false,
      );
    }
  }

  void requestClose() {
    if (_closed) return;
    _closed = true;
    owner._scopes.remove(this);
  }

  @override
  Future<void> close() async => requestClose();
}

StatisticsSnapshot _demoSnapshot(DateTime now) {
  final deepseek = StatisticsSummary(
    accountId: 'deepseek-primary',
    accountDisplayName: 'DeepSeek',
    modelId: 'deepseek-flash',
    sampleCount: 2,
    completionTokens: 300,
    totalTtftMillis: 760,
    ttftSampleCount: 2,
    totalResponseMillis: 2760,
    tokensPerSecond: 300 * 1000 / 2760,
    averageTtftMillis: 380,
    averageResponseMillis: 1380,
  );
  final deepseekSummary = StatisticsSummary(
    accountId: deepseek.accountId,
    accountDisplayName: deepseek.accountDisplayName,
    modelId: deepseek.modelId,
    sampleCount: deepseek.sampleCount,
    completionTokens: deepseek.completionTokens,
    totalTtftMillis: deepseek.totalTtftMillis,
    ttftSampleCount: deepseek.ttftSampleCount,
    totalResponseMillis: deepseek.totalResponseMillis,
    tokensPerSecond: deepseek.tokensPerSecond,
    averageTtftMillis: deepseek.averageTtftMillis,
    averageResponseMillis: deepseek.averageResponseMillis,
    effortBreakdowns: const [
      StatisticsEffortSummary(
        effort: 'high',
        sampleCount: 1,
        completionTokens: 150,
        totalTtftMillis: 410,
        ttftSampleCount: 1,
        totalResponseMillis: 1410,
        tokensPerSecond: 150 * 1000 / 1410,
        averageTtftMillis: 410,
        averageResponseMillis: 1410,
      ),
      StatisticsEffortSummary(
        effort: 'none',
        sampleCount: 1,
        completionTokens: 150,
        totalTtftMillis: 350,
        ttftSampleCount: 1,
        totalResponseMillis: 1350,
        tokensPerSecond: 150 * 1000 / 1350,
        averageTtftMillis: 350,
        averageResponseMillis: 1350,
      ),
    ],
  );
  final openaiSummary = StatisticsSummary(
    accountId: 'openai-work',
    accountDisplayName: 'OpenAI Work',
    modelId: 'gpt-5.6-codex',
    sampleCount: 1,
    completionTokens: 216,
    totalTtftMillis: 620,
    ttftSampleCount: 1,
    totalResponseMillis: 3120,
    tokensPerSecond: 216 * 1000 / 3120,
    averageTtftMillis: 620,
    averageResponseMillis: 3120,
    effortBreakdowns: const [
      StatisticsEffortSummary(
        effort: null,
        sampleCount: 1,
        completionTokens: 216,
        totalTtftMillis: 620,
        ttftSampleCount: 1,
        totalResponseMillis: 3120,
        tokensPerSecond: 216 * 1000 / 3120,
        averageTtftMillis: 620,
        averageResponseMillis: 3120,
      ),
    ],
  );
  return StatisticsSnapshot(
    ownerEpoch: 'demo-statistics-owner',
    feedId: 'demo-statistics-feed',
    publicationRevision: 3,
    summariesRevision: 1,
    historyRevision: 1,
    summaries: [deepseekSummary, openaiSummary],
    history: [
      StatisticsSample(
        threadId: 'thread-statistics',
        callId: 'call-1',
        purpose: 'primary',
        firstOutputSource: FirstOutputSource.incremental,
        usageStatus: UsageReportStatus.reported,
        ttftAvailability: MetricAvailability.available,
        throughputAvailability: MetricAvailability.available,
        completedAt: now.subtract(const Duration(seconds: 12)),
        accountId: openaiSummary.accountId,
        accountDisplayName: openaiSummary.accountDisplayName,
        modelId: openaiSummary.modelId,
        sentModel: openaiSummary.modelId,
        reportedModel: openaiSummary.modelId,
        modelMatchState: StatisticsModelMatchState.matched,
        effort: null,
        completionTokens: 216,
        ttftMillis: 620,
        decodeMillis: 2500,
        totalResponseMillis: 3120,
        tokensPerSecond: 216 * 1000 / 3120,
      ),
      StatisticsSample(
        threadId: 'thread-statistics',
        callId: 'call-2',
        purpose: 'primary',
        firstOutputSource: FirstOutputSource.incremental,
        usageStatus: UsageReportStatus.reported,
        ttftAvailability: MetricAvailability.available,
        throughputAvailability: MetricAvailability.available,
        completedAt: now.subtract(const Duration(seconds: 34)),
        accountId: deepseekSummary.accountId,
        accountDisplayName: deepseekSummary.accountDisplayName,
        modelId: deepseekSummary.modelId,
        sentModel: 'deepseek-flash-0724',
        reportedModel: 'deepseek-flash',
        modelMatchState: StatisticsModelMatchState.mismatched,
        effort: 'high',
        completionTokens: 150,
        ttftMillis: 410,
        decodeMillis: 1000,
        totalResponseMillis: 1410,
        tokensPerSecond: 150 * 1000 / 1410,
      ),
      StatisticsSample(
        threadId: 'thread-statistics',
        callId: 'call-3',
        purpose: 'primary',
        firstOutputSource: FirstOutputSource.incremental,
        usageStatus: UsageReportStatus.reported,
        ttftAvailability: MetricAvailability.available,
        throughputAvailability: MetricAvailability.available,
        completedAt: now.subtract(const Duration(minutes: 2)),
        accountId: deepseekSummary.accountId,
        accountDisplayName: deepseekSummary.accountDisplayName,
        modelId: deepseekSummary.modelId,
        sentModel: deepseekSummary.modelId,
        reportedModel: null,
        modelMatchState: StatisticsModelMatchState.unreported,
        effort: 'none',
        completionTokens: 150,
        ttftMillis: 350,
        decodeMillis: 1000,
        totalResponseMillis: 1350,
        tokensPerSecond: 150 * 1000 / 1350,
      ),
      StatisticsSample(
        threadId: 'thread-statistics',
        callId: 'call-4',
        purpose: null,
        firstOutputSource: FirstOutputSource.legacyUnknown,
        usageStatus: UsageReportStatus.legacyUnknown,
        ttftAvailability: MetricAvailability.legacyUnknown,
        throughputAvailability: MetricAvailability.legacyUnknown,
        completedAt: now.subtract(const Duration(minutes: 8)),
        accountId: 'legacy-account',
        accountDisplayName: 'Legacy account',
        modelId: null,
        sentModel: 'legacy-alias-model',
        reportedModel: null,
        modelMatchState: StatisticsModelMatchState.legacyUnknown,
        effort: null,
        completionTokens: 90,
        ttftMillis: null,
        decodeMillis: null,
        totalResponseMillis: null,
        tokensPerSecond: null,
      ),
    ],
    statisticsPending: false,
    statisticsGap: false,
    readFailed: false,
  );
}
