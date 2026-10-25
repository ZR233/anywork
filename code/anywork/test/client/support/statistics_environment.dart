import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../anywork_client/test/support/profile_native_pin.dart';
import '../../../../anywork_client/test/support/scripted_feed.dart';

/// Immutable native read material. Grouping, identity materialization and
/// filtering remain production Repository/VM behavior, not a fixture reducer.
final class StatisticsTestPort implements StatisticsPort {
  static const origin = ProductReadOrigin(
    ownerEpoch: 'statistics-native',
    incarnation: 1,
  );
  static const summaryRef = PerformanceSummariesReadRef(entry: 1, revision: 1);
  static const historyRef = PerformanceHistoryReadRef(entry: 2, revision: 1);
  static const summaryCollection = ProductCollectionRef(
    entry: 3,
    revision: 1,
    total: 1,
  );
  static const historyCollection = ProductCollectionRef(
    entry: 4,
    revision: 1,
    total: 3,
  );
  final summaries = ScriptedFeed<PerformanceSummariesFrame>(
    feedId: 'statistics-summaries',
    sequenceOf: (frame) =>
        frame is PerformanceSummariesData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! PerformanceSummariesData,
  );
  final history = ScriptedFeed<PerformanceHistoryFrame>(
    feedId: 'statistics-history',
    sequenceOf: (frame) =>
        frame is PerformanceHistoryData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! PerformanceHistoryData,
  );

  Future<void> establish() async {
    await summaries.listened.future;
    await history.listened.future;
    summaries.emit(
      PerformanceSummariesFrame.data(
        deliverySequence: 1,
        event: PerformanceSummariesEvent.baseline(
          identity: profileIdentity(
            summaries.feedId,
            origin,
            ProductResource.performanceSummaries,
          ),
          stamp: profileStamp(origin, 1),
          value: const PerformanceSummariesBaseline(
            header: PerformanceSummariesHeader(
              revision: 1,
              updatedAt: 1769904000,
              statisticsPending: false,
              statisticsGap: false,
              readFailed: false,
              reference: summaryRef,
            ),
            collection: summaryCollection,
          ),
        ),
      ),
    );
    history.emit(
      PerformanceHistoryFrame.data(
        deliverySequence: 1,
        event: PerformanceHistoryEvent.baseline(
          identity: profileIdentity(
            history.feedId,
            origin,
            ProductResource.performanceHistory,
          ),
          stamp: profileStamp(origin, 1),
          value: const PerformanceHistoryBaseline(
            header: PerformanceHistoryHeader(
              revision: 1,
              updatedAt: 1769904000,
              statisticsPending: false,
              statisticsGap: false,
              readFailed: false,
              reference: historyRef,
            ),
            collection: historyCollection,
          ),
        ),
      ),
    );
    await summaries.acknowledged(1);
    await history.acknowledged(1);
  }

  @override
  Future<FeedConnection<PerformanceSummariesFrame>>
  openPerformanceSummaries() async => summaries;
  @override
  Future<FeedConnection<PerformanceHistoryFrame>>
  openPerformanceHistory() async => history;
  @override
  Future<PerformanceSummariesReadConnection> openPerformanceSummariesRead(
    PerformanceSummariesReadRef reference, {
    required ProductReadOrigin origin,
  }) async => _SummaryRead();
  @override
  Future<PerformanceHistoryReadConnection> openPerformanceHistoryRead(
    PerformanceHistoryReadRef reference, {
    required ProductReadOrigin origin,
  }) async => _HistoryRead();
  @override
  Future<PerformanceSummaryIdentityReadConnection> openSummaryIdentity(
    PerformanceSummaryIdentityRef reference, {
    required ProductReadOrigin origin,
  }) async => _SummaryIdentity();
  @override
  Future<PerformanceEffortIdentityReadConnection> openEffortIdentity(
    PerformanceEffortIdentityRef reference, {
    required ProductReadOrigin origin,
  }) async => _EffortIdentity(reference.entry);
  @override
  Future<PerformanceSampleIdentityReadConnection> openSampleIdentity(
    PerformanceSampleIdentityRef reference, {
    required ProductReadOrigin origin,
  }) async => _SampleIdentity(reference.entry);
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Statistics native capability: ${invocation.memberName}',
  );
}

const _one = PerformanceCounters(
  sampleCount: 1,
  completionTokens: 100,
  totalTtftMillis: 300,
  ttftSampleCount: 1,
  totalResponseMillis: 1300,
  tokensPerSecond: 100,
  averageTtftMillis: 300,
  averageResponseMillis: 1300,
);

final class _SummaryRead extends ProfileNativePin
    implements PerformanceSummariesReadConnection {
  _SummaryRead() : super('summary-material');
  @override
  Future<PerformanceSummariesReadHeader> header() async =>
      const PerformanceSummariesReadHeader(
        summaries: TypedListRef(listId: 1, total: 1),
      );
  @override
  Future<PerformanceSummariesEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async => PerformanceSummariesEntryPage(
    collection: StatisticsTestPort.summaryCollection,
    offset: offset,
    items: const [ProductEntityRef(entry: 10, revision: 1)],
    nextOffset: null,
  );
  @override
  Future<PerformanceSummariesEntityRead> entity(
    ProductEntityRef reference,
  ) async => PerformanceSummariesEntityRead(
    reference: reference,
    value: PerformanceSummaryRead(
      identity: const PerformanceSummaryIdentityRef(entry: 10, revision: 1),
      counters: _one.copyWith(
        sampleCount: 2,
        completionTokens: 200,
        totalTtftMillis: 600,
        ttftSampleCount: 2,
        totalResponseMillis: 2600,
      ),
      effortBreakdowns: const TypedListRef(listId: 2, total: 2),
    ),
  );
  @override
  Future<PerformanceEffortReadPage> effortBreakdowns(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async => PerformanceEffortReadPage(
    listId: listId,
    offset: offset,
    total: 2,
    nextOffset: null,
    items: const [
      PerformanceEffortRead(
        identity: PerformanceEffortIdentityRef(entry: 20, revision: 1),
        counters: _one,
      ),
      PerformanceEffortRead(
        identity: PerformanceEffortIdentityRef(entry: 21, revision: 1),
        counters: _one,
      ),
    ],
  );
}

final class _SummaryIdentity extends ProfileNativePin
    implements PerformanceSummaryIdentityReadConnection {
  _SummaryIdentity() : super('summary-identity');
  @override
  Future<PerformanceSummaryIdentityRead> header() async =>
      const PerformanceSummaryIdentityRead(
        accountId: ReadText.inline(text: 'account-a'),
        accountDisplayName: ReadText.inline(text: 'Alpha'),
        modelId: ReadText.inline(text: 'shared-model'),
      );
}

final class _EffortIdentity extends ProfileNativePin
    implements PerformanceEffortIdentityReadConnection {
  _EffortIdentity(this.entry) : super('effort-$entry');
  final int entry;
  @override
  Future<PerformanceEffortIdentityRead> header() async =>
      PerformanceEffortIdentityRead(
        effort: entry == 20 ? const ReadText.inline(text: 'high') : null,
      );
}

final class _HistoryRead extends ProfileNativePin
    implements PerformanceHistoryReadConnection {
  _HistoryRead() : super('history-material');
  @override
  Future<PerformanceHistoryReadHeader> header() async =>
      const PerformanceHistoryReadHeader(
        samples: TypedListRef(listId: 3, total: 3),
      );
  @override
  Future<PerformanceHistoryEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async => PerformanceHistoryEntryPage(
    collection: StatisticsTestPort.historyCollection,
    offset: offset,
    nextOffset: null,
    items: const [
      ProductEntityRef(entry: 30, revision: 1),
      ProductEntityRef(entry: 31, revision: 1),
      ProductEntityRef(entry: 32, revision: 1),
    ],
  );
  @override
  Future<PerformanceHistoryEntityRead> entity(
    ProductEntityRef reference,
  ) async => PerformanceHistoryEntityRead(
    reference: reference,
    value: PerformanceSampleRead(
      identity: PerformanceSampleIdentityRef(
        entry: reference.entry,
        revision: 1,
      ),
      counters: PerformanceSampleCounters(
        completedAt: 1769904000 - (reference.entry - 30) * 60,
        completionTokens: reference.entry == 32 ? 10 : 100,
        ttftMillis: reference.entry == 32 ? null : 300,
        decodeMillis: reference.entry == 32 ? null : 1000,
        totalResponseMillis: reference.entry == 32 ? null : 1300,
        tokensPerSecond: reference.entry == 32 ? null : 100,
      ),
    ),
  );
}

final class _SampleIdentity extends ProfileNativePin
    implements PerformanceSampleIdentityReadConnection {
  _SampleIdentity(this.entry) : super('sample-$entry');
  final int entry;
  @override
  Future<PerformanceSampleIdentityRead> header() async =>
      PerformanceSampleIdentityRead(
        accountId: const ReadText.inline(text: 'account-a'),
        accountDisplayName: const ReadText.inline(text: 'Alpha'),
        modelId: entry == 32
            ? null
            : const ReadText.inline(text: 'shared-model'),
        sentModel: ReadText.inline(
          text: entry == 32 ? 'legacy-alias' : 'shared-model',
        ),
        reportedModel: null,
        modelMatchState: entry == 32
            ? ModelMatchState.legacyUnknown
            : ModelMatchState.matched,
        effort: entry == 30 ? const ReadText.inline(text: 'high') : null,
      );
}
