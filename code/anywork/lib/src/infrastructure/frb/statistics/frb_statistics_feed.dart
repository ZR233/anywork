import 'package:anywork_client/statistics.dart';
import 'package:anywork_client/statistics_ports.dart';

import '../../../rust/api/studio/statistics/feed.dart' as frb_statistics;
import '../../../rust/api/studio/statistics/types.dart' as frb_types;
import '../../../rust/api/studio/types/error.dart' as frb_error;
import '../usage_diagnostics.dart';

/// Native statistics adapter. It speaks only to the dedicated typed feed/scope API.
final class FrbStatisticsFeedPort implements StatisticsFeedPort {
  const FrbStatisticsFeedPort();

  @override
  Future<StatisticsFeedConnection> open() async {
    final feed = await _statisticsBridgeCall(frb_statistics.openStatisticsFeed);
    return _FrbStatisticsFeedConnection(feed);
  }
}

final class _FrbStatisticsFeedConnection implements StatisticsFeedConnection {
  _FrbStatisticsFeedConnection(this._feed);

  frb_statistics.BridgeStatisticsFeed? _feed;
  bool _closeRequested = false;
  Future<void>? _closeRequest;
  Future<void>? _closing;

  @override
  Stream<StatisticsFeedEvent> events() async* {
    final feed = _requireFeed();
    try {
      await for (final event in feed.events()) {
        switch (event) {
          case frb_types.BridgeStatisticsFeedEvent_Baseline(:final publication):
            yield StatisticsFeedBaseline(_identityFromFrb(publication));
          case frb_types.BridgeStatisticsFeedEvent_Data(:final publication):
            yield StatisticsFeedData(_identityFromFrb(publication));
          case frb_types.BridgeStatisticsFeedEvent_Failure(:final error):
            yield StatisticsFeedFailure(_statisticsFailureFromBridge(error));
            return;
          case frb_types.BridgeStatisticsFeedEvent_Closed():
            yield const StatisticsFeedClosed();
            return;
        }
      }
    } on frb_error.BridgeError catch (error) {
      yield StatisticsFeedFailure(_statisticsFailureFromBridge(error));
      return;
    } on Object catch (error) {
      yield StatisticsFeedFailure(
        StatisticsFailure.fromObject(
          error,
          category: StatisticsFailureCategory.stream,
        ),
      );
      return;
    }
    yield const StatisticsFeedClosed();
  }

  @override
  Future<StatisticsReadScope> openScope(
    StatisticsFeedIdentity publication,
  ) async {
    final feed = _requireFeed();
    final header = frb_types.BridgeStatisticsFeedHeader(
      ownerEpoch: publication.ownerEpoch,
      feedId: publication.feedId,
      deliverySequence: BigInt.from(publication.deliverySequence),
      publicationRevision: BigInt.from(publication.publicationRevision),
      summariesRevision: BigInt.from(publication.summariesRevision),
      historyRevision: BigInt.from(publication.historyRevision),
      summaryCount: BigInt.from(publication.summaryCount),
      historyCount: BigInt.from(publication.historyCount),
      statisticsPending: publication.statisticsPending,
      statisticsGap: publication.statisticsGap,
      readFailed: publication.readFailed,
    );
    final scope = await _statisticsBridgeCall(
      () => feed.openScope(header: header),
    );
    final identity = await _statisticsBridgeCall(scope.identity);
    return _FrbStatisticsReadScope(
      scope,
      ownerEpoch: identity.ownerEpoch,
      feedId: identity.feedId,
      scopeId: identity.scopeId,
      publicationRevision: identity.publicationRevision.toInt(),
    );
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    await _statisticsBridgeCall(
      () => _requireFeed().acknowledge(
        deliverySequence: BigInt.from(deliverySequence),
      ),
    );
  }

  @override
  void requestClose() {
    final feed = _feed;
    if (feed == null || _closeRequested) return;
    _closeRequested = true;
    _closeRequest = _statisticsBridgeCall(feed.requestClose);
  }

  @override
  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing;
    final next = _close();
    _closing = next;
    return next;
  }

  Future<void> _close() async {
    final feed = _feed;
    if (feed == null) return;
    requestClose();
    try {
      final closeRequest = _closeRequest;
      if (closeRequest != null) await closeRequest;
    } on Object {
      _closeRequest = null;
      _closing = null;
      rethrow;
    }
    try {
      await _statisticsBridgeCall(feed.close);
      _feed = null;
      feed.dispose();
    } on Object {
      // Keep the same opaque owner and make this close attempt explicitly retryable.
      _closing = null;
      rethrow;
    }
  }

  frb_statistics.BridgeStatisticsFeed _requireFeed() {
    final feed = _feed;
    if (feed == null || _closeRequested) {
      throw StatisticsFailure.local(
        category: StatisticsFailureCategory.closed,
        code: StudioFailureCode.runtimeStopped,
        message: 'Statistics feed is closing',
        retryable: false,
      );
    }
    return feed;
  }
}

final class _FrbStatisticsReadScope implements StatisticsReadScope {
  _FrbStatisticsReadScope(
    this._scope, {
    required this.ownerEpoch,
    required this.feedId,
    required this.scopeId,
    required this.publicationRevision,
  });

  frb_statistics.BridgeStatisticsReadScope? _scope;
  Future<void>? _closing;

  @override
  final String ownerEpoch;
  @override
  final String feedId;
  @override
  final String scopeId;
  @override
  final int publicationRevision;

  @override
  Future<StatisticsPage<StatisticsSummaryPageItem>> readSummaries(
    int offset,
    int limit,
  ) async {
    final page = await _statisticsBridgeCall(
      () => _requireScope().readSummaries(
        offset: BigInt.from(offset),
        limit: limit,
      ),
    );
    return StatisticsPage(
      ownerEpoch: page.ownerEpoch,
      feedId: page.feedId,
      scopeId: page.scopeId,
      publicationRevision: page.publicationRevision.toInt(),
      materialRevision: page.materialRevision.toInt(),
      offset: page.offset.toInt(),
      totalCount: page.totalCount.toInt(),
      nextOffset: page.nextOffset?.toInt(),
      sourceBytes: page.sourceBytes.toInt(),
      items: [
        for (final item in page.items)
          StatisticsSummaryPageItem(
            accountId: item.accountId,
            accountDisplayName: item.accountDisplayName,
            modelId: item.modelId,
            sampleCount: item.sampleCount.toInt(),
            completionTokens: item.completionTokens.toInt(),
            totalTtftMillis: item.totalTtftMillis.toInt(),
            ttftSampleCount: item.ttftSampleCount.toInt(),
            totalResponseMillis: item.totalResponseMillis.toInt(),
            tokensPerSecond: item.tokensPerSecond,
            averageTtftMillis: item.averageTtftMillis,
            averageResponseMillis: item.averageResponseMillis,
            effortCount: item.effortCount.toInt(),
          ),
      ],
    );
  }

  @override
  Future<StatisticsPage<StatisticsSample>> readHistory(
    int offset,
    int limit,
  ) async {
    final page = await _statisticsBridgeCall(
      () => _requireScope().readHistory(
        offset: BigInt.from(offset),
        limit: limit,
      ),
    );
    return StatisticsPage(
      ownerEpoch: page.ownerEpoch,
      feedId: page.feedId,
      scopeId: page.scopeId,
      publicationRevision: page.publicationRevision.toInt(),
      materialRevision: page.materialRevision.toInt(),
      offset: page.offset.toInt(),
      totalCount: page.totalCount.toInt(),
      nextOffset: page.nextOffset?.toInt(),
      sourceBytes: page.sourceBytes.toInt(),
      items: [for (final item in page.items) _sampleFromFrb(item)],
    );
  }

  @override
  Future<StatisticsPage<StatisticsEffortSummary>> readEfforts(
    int summaryIndex,
    int offset,
    int limit,
  ) async {
    final page = await _statisticsBridgeCall(
      () => _requireScope().readEfforts(
        summaryIndex: BigInt.from(summaryIndex),
        offset: BigInt.from(offset),
        limit: limit,
      ),
    );
    return StatisticsPage(
      ownerEpoch: page.ownerEpoch,
      feedId: page.feedId,
      scopeId: page.scopeId,
      publicationRevision: page.publicationRevision.toInt(),
      materialRevision: page.materialRevision.toInt(),
      offset: page.offset.toInt(),
      totalCount: page.totalCount.toInt(),
      nextOffset: page.nextOffset?.toInt(),
      sourceBytes: page.sourceBytes.toInt(),
      summaryIndex: page.summaryIndex.toInt(),
      items: [
        for (final item in page.items)
          StatisticsEffortSummary(
            effort: item.effort,
            sampleCount: item.sampleCount.toInt(),
            completionTokens: item.completionTokens.toInt(),
            totalTtftMillis: item.totalTtftMillis.toInt(),
            ttftSampleCount: item.ttftSampleCount.toInt(),
            totalResponseMillis: item.totalResponseMillis.toInt(),
            tokensPerSecond: item.tokensPerSecond,
            averageTtftMillis: item.averageTtftMillis,
            averageResponseMillis: item.averageResponseMillis,
          ),
      ],
    );
  }

  @override
  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing;
    final next = _close();
    _closing = next;
    return next;
  }

  Future<void> _close() async {
    final scope = _scope;
    if (scope == null) return;
    try {
      await _statisticsBridgeCall(scope.close);
      _scope = null;
      scope.dispose();
    } on Object {
      // Do not discard the handle when close is unconfirmed; callers can retry it.
      _closing = null;
      rethrow;
    }
  }

  frb_statistics.BridgeStatisticsReadScope _requireScope() {
    final scope = _scope;
    if (scope == null) {
      throw StatisticsFailure.local(
        category: StatisticsFailureCategory.closed,
        code: StudioFailureCode.runtimeStopped,
        message: 'Statistics read scope is closed',
        retryable: false,
      );
    }
    return scope;
  }
}

StatisticsSample _sampleFromFrb(frb_types.BridgeStatisticsSample value) =>
    StatisticsSample(
      threadId: value.threadId,
      callId: value.callId,
      purpose: value.purpose,
      firstOutputSource: firstOutputSourceFromFrb(value.firstOutputSource),
      usageStatus: usageReportStatusFromFrb(value.usageStatus),
      ttftAvailability: metricAvailabilityFromFrb(value.ttftAvailability),
      throughputAvailability: metricAvailabilityFromFrb(
        value.throughputAvailability,
      ),
      completedAt: DateTime.fromMillisecondsSinceEpoch(
        value.completedAt.toInt() * 1000,
      ),
      accountId: value.accountId,
      accountDisplayName: value.accountDisplayName,
      modelId: value.modelId,
      sentModel: value.sentModel,
      reportedModel: value.reportedModel,
      modelMatchState: switch (value.modelMatchState) {
        frb_types.BridgeStatisticsModelMatchState.matched =>
          StatisticsModelMatchState.matched,
        frb_types.BridgeStatisticsModelMatchState.mismatched =>
          StatisticsModelMatchState.mismatched,
        frb_types.BridgeStatisticsModelMatchState.unreported =>
          StatisticsModelMatchState.unreported,
        frb_types.BridgeStatisticsModelMatchState.legacyUnknown =>
          StatisticsModelMatchState.legacyUnknown,
      },
      effort: value.effort,
      completionTokens: value.completionTokens?.toInt(),
      ttftMillis: value.ttftMillis?.toInt(),
      decodeMillis: value.decodeMillis?.toInt(),
      totalResponseMillis: value.totalResponseMillis?.toInt(),
      tokensPerSecond: value.tokensPerSecond,
    );

StatisticsFeedIdentity _identityFromFrb(
  frb_types.BridgeStatisticsFeedHeader value,
) => StatisticsFeedIdentity(
  ownerEpoch: value.ownerEpoch,
  feedId: value.feedId,
  deliverySequence: value.deliverySequence.toInt(),
  publicationRevision: value.publicationRevision.toInt(),
  summariesRevision: value.summariesRevision.toInt(),
  historyRevision: value.historyRevision.toInt(),
  summaryCount: value.summaryCount.toInt(),
  historyCount: value.historyCount.toInt(),
  statisticsPending: value.statisticsPending,
  statisticsGap: value.statisticsGap,
  readFailed: value.readFailed,
);

StatisticsFailure _statisticsFailureFromBridge(frb_error.BridgeError error) {
  final category = switch (error.code) {
    frb_error.BridgeErrorCode.protocol => StatisticsFailureCategory.protocol,
    frb_error.BridgeErrorCode.overloaded => StatisticsFailureCategory.capacity,
    frb_error.BridgeErrorCode.busy => StatisticsFailureCategory.busy,
    frb_error.BridgeErrorCode.cancelled => StatisticsFailureCategory.cancelled,
    frb_error.BridgeErrorCode.runtimeStopped =>
      StatisticsFailureCategory.closed,
    _ => StatisticsFailureCategory.stream,
  };
  return StatisticsFailure.fromStudioFailure(
    StudioFailure(
      code: switch (error.code) {
        frb_error.BridgeErrorCode.notInitialized =>
          StudioFailureCode.notInitialized,
        frb_error.BridgeErrorCode.runtimeStopped =>
          StudioFailureCode.runtimeStopped,
        frb_error.BridgeErrorCode.instanceBusy =>
          StudioFailureCode.instanceBusy,
        frb_error.BridgeErrorCode.invalidArgument =>
          StudioFailureCode.invalidArgument,
        frb_error.BridgeErrorCode.notFound => StudioFailureCode.notFound,
        frb_error.BridgeErrorCode.busy => StudioFailureCode.busy,
        frb_error.BridgeErrorCode.conflict => StudioFailureCode.conflict,
        frb_error.BridgeErrorCode.staleRevision =>
          StudioFailureCode.staleRevision,
        frb_error.BridgeErrorCode.permissionDenied =>
          StudioFailureCode.permissionDenied,
        frb_error.BridgeErrorCode.cancelled => StudioFailureCode.cancelled,
        frb_error.BridgeErrorCode.cancellationTooLate =>
          StudioFailureCode.cancellationTooLate,
        frb_error.BridgeErrorCode.overloaded => StudioFailureCode.overloaded,
        frb_error.BridgeErrorCode.unavailable => StudioFailureCode.unavailable,
        frb_error.BridgeErrorCode.protocol => StudioFailureCode.protocol,
        frb_error.BridgeErrorCode.storage => StudioFailureCode.storage,
        frb_error.BridgeErrorCode.update => StudioFailureCode.update,
        frb_error.BridgeErrorCode.internal => StudioFailureCode.internal,
      },
      message: error.message,
      retryable: error.retryable,
      correlationId: error.correlationId,
      detailsJson: error.detailsJson,
    ),
    category: category,
    cause: error,
  );
}

Future<T> _statisticsBridgeCall<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on frb_error.BridgeError catch (error) {
    throw _statisticsFailureFromBridge(error);
  }
}
