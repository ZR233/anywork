import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/statistics_ports.dart';

import '../../../../anywork_client/test/support/statistics_test_port.dart';

const _summaryCounters = PerformanceCounters(
  sampleCount: 2,
  completionTokens: 200,
  totalTtftMillis: 600,
  ttftSampleCount: 2,
  totalResponseMillis: 2600,
  tokensPerSecond: 100.0,
  averageTtftMillis: 300.0,
  averageResponseMillis: 1300.0,
);

const _sampleCounters = PerformanceSampleCounters(
  completedAt: 1769903940,
  completionTokens: 100,
  ttftMillis: 300,
  decodeMillis: 1000,
  totalResponseMillis: 1300,
  tokensPerSecond: 100.0,
);

const _missingSampleCounters = PerformanceSampleCounters(
  completedAt: 1769904000,
  completionTokens: 10,
  ttftMillis: null,
  decodeMillis: null,
  totalResponseMillis: null,
  tokensPerSecond: null,
);

/// Immutable native statistics material for the real Repository + ViewModel +
/// Connector. Grouping, identity resolution, paging and filtering stay
/// production behavior; this environment only answers native reads.
final class StatisticsEnvironment {
  StatisticsEnvironment({this.empty = false, this.historyRows = 6}) {
    summaryMaterial = _summaries(empty: empty);
    historyMaterial = _history(empty: empty, rows: historyRows);
    port = ScriptedStatisticsPort(
      origin: origin,
      summariesFeedId: summariesFeedId,
      historyFeedId: historyFeedId,
      summaryScripts: {summaryRef: summaryMaterial},
      historyScripts: {historyRef: historyMaterial},
    );
    repository = createStatisticsRepository(port: port, budget: budget);
  }

  static const origin = ProductReadOrigin(
    ownerEpoch: 'statistics-native',
    incarnation: 1,
  );
  static const summariesFeedId = 'statistics-summaries';
  static const historyFeedId = 'statistics-history';
  static const summaryRef = PerformanceSummariesReadRef(entry: 1, revision: 1);
  static const historyRef = PerformanceHistoryReadRef(entry: 2, revision: 1);

  /// A complete publication with no rows, used to prove that an unknown or
  /// incomplete projection never claims a known empty collection.
  final bool empty;
  final int historyRows;
  final budget = ResourceBudget();
  late final SummariesMaterialScript summaryMaterial;
  late final HistoryMaterialScript historyMaterial;
  late final ScriptedStatisticsPort port;
  late final StatisticsRepository repository;

  Future<void> establish({int ordinal = 1, bool pending = false}) async {
    final summaries = await port.summariesAt(ordinal);
    final history = await port.historyAt(ordinal);
    await summaries.listened.future;
    await history.listened.future;
    summaries.emit(
      summariesBaseline(
        feedId: summariesFeedId,
        origin: origin,
        revision: 1,
        reference: summaryRef,
        collection: summaryMaterial.collection,
        statisticsPending: pending,
      ),
    );
    history.emit(
      historyBaseline(
        feedId: historyFeedId,
        origin: origin,
        revision: 1,
        reference: historyRef,
        collection: historyMaterial.collection,
        statisticsPending: pending,
      ),
    );
    await summaries.acknowledged(1);
    await history.acknowledged(1);
  }

  /// A status-only republication: neither reference nor material changes.
  Future<void> republish({
    bool pending = false,
    bool gap = false,
    bool readFailed = false,
  }) async {
    final summaries = port.summariesFeed;
    final history = port.historyFeed;
    summaries.emit(
      summariesChange(
        origin: origin,
        deliverySequence: 2,
        revision: 2,
        baseRevision: 1,
        reference: summaryRef,
        collection: ProductCollectionRef(
          entry: summaryMaterial.collection.entry,
          revision: 2,
          total: summaryMaterial.collection.total,
        ),
        baseCollectionRevision: 1,
        statisticsPending: pending,
        statisticsGap: gap,
        readFailed: readFailed,
      ),
    );
    history.emit(
      historyChange(
        origin: origin,
        deliverySequence: 2,
        revision: 2,
        baseRevision: 1,
        reference: historyRef,
        collection: ProductCollectionRef(
          entry: historyMaterial.collection.entry,
          revision: 2,
          total: historyMaterial.collection.total,
        ),
        baseCollectionRevision: 1,
        statisticsPending: pending,
        statisticsGap: gap,
        readFailed: readFailed,
      ),
    );
    await summaries.acknowledged(2);
    await history.acknowledged(2);
  }

  /// No deadline: the widget test advances both queues through the client
  /// pump helper, so a hang has to surface as that helper's failure instead of
  /// a fake-async timer.
  Future<CloseReport> close() => repository.close();

  static SummariesMaterialScript _summaries({required bool empty}) {
    if (empty) {
      return SummariesMaterialScript(
        collection: const ProductCollectionRef(entry: 3, revision: 1, total: 0),
        entries: const <ProductEntityRef>[],
        entities: const <int, PerformanceSummaryRead>{},
      );
    }
    return SummariesMaterialScript(
      collection: const ProductCollectionRef(entry: 3, revision: 1, total: 1),
      entries: const [ProductEntityRef(entry: 10, revision: 1)],
      entities: const {
        10: PerformanceSummaryRead(
          identity: PerformanceSummaryIdentityRef(entry: 10, revision: 1),
          counters: _summaryCounters,
          effortBreakdowns: TypedListRef(listId: 2, total: 3),
        ),
      },
      identities: const {
        10: PerformanceSummaryIdentityRead(
          accountId: ReadText.inline(text: 'account-a'),
          accountDisplayName: ReadText.inline(text: 'Alpha'),
          modelId: ReadText.inline(text: 'shared-model'),
        ),
      },
      efforts: const {
        2: [
          PerformanceEffortRead(
            identity: PerformanceEffortIdentityRef(entry: 20, revision: 1),
            counters: _summaryCounters,
          ),
          PerformanceEffortRead(
            identity: PerformanceEffortIdentityRef(entry: 21, revision: 1),
            counters: _summaryCounters,
          ),
          PerformanceEffortRead(
            identity: PerformanceEffortIdentityRef(entry: 22, revision: 1),
            counters: _summaryCounters,
          ),
        ],
      },
      effortIdentities: const {
        20: PerformanceEffortIdentityRead(
          effort: ReadText.inline(text: 'high'),
        ),
        // `none` is a real literal effort and never the same subgroup as an
        // unspecified (null) effort.
        21: PerformanceEffortIdentityRead(
          effort: ReadText.inline(text: 'none'),
        ),
        22: PerformanceEffortIdentityRead(effort: null),
      },
    );
  }

  static HistoryMaterialScript _history({
    required bool empty,
    required int rows,
  }) {
    if (empty) {
      return HistoryMaterialScript(
        collection: const ProductCollectionRef(entry: 4, revision: 1, total: 0),
        entries: const <ProductEntityRef>[],
        entities: const <int, PerformanceSampleRead>{},
      );
    }
    return HistoryMaterialScript(
      collection: ProductCollectionRef(entry: 4, revision: 1, total: rows),
      entries: [
        for (var index = 0; index < rows; index++)
          ProductEntityRef(entry: 30 + index, revision: 1),
      ],
      entities: {
        for (var index = 0; index < rows; index++)
          30 + index: PerformanceSampleRead(
            identity: PerformanceSampleIdentityRef(
              entry: 30 + index,
              revision: 1,
            ),
            counters: index == 5 ? _missingSampleCounters : _sampleCounters,
          ),
      },
      identities: {
        for (var index = 0; index < rows; index++)
          30 + index: _sampleIdentity(index),
      },
    );
  }

  /// The first six rows are the identity matrix:
  /// 0. account-a/shared-model, effort `high`;
  /// 1. the same key with the literal effort `none` (never the same as null);
  /// 2. the same key with an unspecified (null) effort;
  /// 3. account-b/shared-model with a mismatched response model;
  /// 4. account-a/alt-model with a mismatched response model;
  /// 5. a frozen legacy identity with no configured model (sent alias only).
  /// Any further row is another measured account-a/shared-model sample.
  static PerformanceSampleIdentityRead _sampleIdentity(int index) {
    return switch (index) {
      0 => _sample(effort: 'high'),
      1 => _sample(effort: 'none'),
      2 => _sample(effort: null),
      3 => _sample(
        accountId: 'account-b',
        accountDisplayName: 'Beta',
        reportedModel: 'shared-model-preview',
        state: ModelMatchState.mismatched,
        effort: 'low',
      ),
      4 => _sample(
        modelId: 'alt-model',
        sentModel: 'alt-model',
        reportedModel: 'alt-model-preview',
        state: ModelMatchState.mismatched,
        effort: 'high',
      ),
      5 => const PerformanceSampleIdentityRead(
        accountId: ReadText.inline(text: 'account-a'),
        accountDisplayName: ReadText.inline(text: 'Alpha'),
        modelId: null,
        sentModel: ReadText.inline(text: 'legacy-alias'),
        reportedModel: null,
        modelMatchState: ModelMatchState.legacyUnknown,
        effort: null,
      ),
      _ => _sample(effort: 'low'),
    };
  }

  static PerformanceSampleIdentityRead _sample({
    String accountId = 'account-a',
    String accountDisplayName = 'Alpha',
    String? modelId = 'shared-model',
    String? sentModel = 'shared-model',
    String? reportedModel = 'shared-model',
    ModelMatchState state = ModelMatchState.matched,
    required String? effort,
  }) {
    ReadText? text(String? value) =>
        value == null ? null : ReadText.inline(text: value);
    return PerformanceSampleIdentityRead(
      accountId: ReadText.inline(text: accountId),
      accountDisplayName: ReadText.inline(text: accountDisplayName),
      modelId: text(modelId),
      sentModel: text(sentModel),
      reportedModel: text(reportedModel),
      modelMatchState: state,
      effort: text(effort),
    );
  }
}
