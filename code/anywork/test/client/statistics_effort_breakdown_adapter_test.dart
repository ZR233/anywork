import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/statistics/connectors/statistics_connector.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/statistics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 统计页的顶层身份是 (accountId, 配置 modelId)，effort 是组内细分筛选。
///
/// 该适配测试从公共 StatisticsRepository 边界注入完整快照，不再通过旧 Client store 或
/// bootstrap fixture 构造 GUI 数据。它保护 view model 到纯 View 的筛选与身份映射。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'statistics groups by account model and filters effort separately',
    (tester) async {
      final repository = _FixtureStatisticsRepository(_snapshot());
      await _pumpStatistics(tester, repository);

      expect(
        find.byKey(
          StudioDriverKeys.statisticsSummaryRow('account-a', 'shared-model'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          StudioDriverKeys.statisticsSummaryEffortRow(
            'account-a',
            'shared-model',
            'high',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          StudioDriverKeys.statisticsSummaryEffortRow(
            'account-a',
            'shared-model',
            null,
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(StudioDriverKeys.statisticsFilter), findsOneWidget);
      expect(
        find.byKey(StudioDriverKeys.statisticsEffortFilter),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.statisticsMismatchOnly),
        findsOneWidget,
      );
      expect(repository.visibleDemands, 1);
    },
  );

  testWidgets('narrow width keeps filters visible without overflow', (
    tester,
  ) async {
    final repository = _FixtureStatisticsRepository(_snapshot());
    await _pumpStatistics(
      tester,
      repository,
      logicalSize: const Size(420, 800),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(
        StudioDriverKeys.statisticsSummaryRow('account-a', 'shared-model'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        StudioDriverKeys.statisticsSummaryEffortRow(
          'account-a',
          'shared-model',
          'high',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(StudioDriverKeys.statisticsFilter), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.statisticsEffortFilter), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.statisticsMismatchOnly), findsOneWidget);
  });

  testWidgets('connecting without a snapshot does not claim empty statistics', (
    tester,
  ) async {
    final repository = _FixtureStatisticsRepository(
      null,
      phase: StatisticsConnectionPhase.connecting,
    );
    await _pumpStatistics(tester, repository);

    final context = tester.element(find.byType(StatisticsConnector));
    final l10n = AppLocalizations.of(context);
    expect(find.text(l10n.settingsStatisticsSummaryEmpty), findsNothing);
    expect(find.text(l10n.settingsStatisticsEmpty), findsNothing);
    expect(repository.visibleDemands, 1);
  });

  testWidgets(
    'failed statistics keeps the established topic retry affordance',
    (tester) async {
      final repository = _FixtureStatisticsRepository(
        null,
        phase: StatisticsConnectionPhase.failed,
        failure: StatisticsFailure.local(
          category: StatisticsFailureCategory.connection,
          code: StudioFailureCode.unavailable,
          message: 'Statistics source is unavailable',
          retryable: true,
        ),
      );
      await _pumpStatistics(tester, repository);

      final retry = find.byKey(
        const ValueKey('settings-topic-retry-ModelPerformanceTopic'),
      );
      expect(retry, findsOneWidget);
      await tester.tap(retry);
      await tester.pump();
      expect(repository.retryCalls, 1);
    },
  );

  testWidgets('effort filter narrows history without touching the model key', (
    tester,
  ) async {
    await _pumpStatistics(tester, _FixtureStatisticsRepository(_snapshot()));

    await tester.tap(
      find.descendant(
        of: find.byKey(StudioDriverKeys.statisticsEffortFilter),
        matching: find.byType(TextField),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text('high'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        StudioDriverKeys.statisticsHistoryRow(
          'account-a',
          'shared-model',
          'high',
          0,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key?.toString() ?? '';
        return key.contains('statistics-history-row') &&
            !key.contains('"high"');
      }),
      findsNothing,
    );
    expect(find.byKey(StudioDriverKeys.statisticsFilter), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.statisticsMismatchOnly), findsOneWidget);
  });
}

Future<void> _pumpStatistics(
  WidgetTester tester,
  _FixtureStatisticsRepository repository, {
  Size? logicalSize,
}) async {
  if (logicalSize != null) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = logicalSize;
    addTearDown(tester.view.reset);
  }
  final container = ProviderContainer(
    overrides: [statisticsRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        theme: pureStudioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: StatisticsConnector(visible: true)),
      ),
    ),
  );
  await tester.pump();
}

StatisticsSnapshot _snapshot() {
  final now = DateTime.utc(2026, 2, 1);
  final summary = StatisticsSummary(
    accountId: 'account-a',
    accountDisplayName: 'Alpha',
    modelId: 'shared-model',
    sampleCount: 2,
    completionTokens: 200,
    totalTtftMillis: 600,
    ttftSampleCount: 2,
    totalResponseMillis: 2600,
    tokensPerSecond: 100,
    averageTtftMillis: 300,
    averageResponseMillis: 1300,
    effortBreakdowns: const [
      StatisticsEffortSummary(
        effort: 'high',
        sampleCount: 1,
        completionTokens: 100,
        totalTtftMillis: 300,
        ttftSampleCount: 1,
        totalResponseMillis: 1300,
        tokensPerSecond: 100,
        averageTtftMillis: 300,
        averageResponseMillis: 1300,
      ),
      StatisticsEffortSummary(
        effort: null,
        sampleCount: 1,
        completionTokens: 100,
        totalTtftMillis: 300,
        ttftSampleCount: 1,
        totalResponseMillis: 1300,
        tokensPerSecond: 100,
        averageTtftMillis: 300,
        averageResponseMillis: 1300,
      ),
    ],
  );
  return StatisticsSnapshot(
    ownerEpoch: 'owner-test',
    feedId: 'feed-test',
    publicationRevision: 1,
    summariesRevision: 1,
    historyRevision: 1,
    summaries: [summary],
    history: [
      StatisticsSample(
        completedAt: now,
        accountId: 'account-a',
        accountDisplayName: 'Alpha',
        modelId: 'shared-model',
        sentModel: 'shared-model',
        reportedModel: 'shared-model',
        modelMatchState: StatisticsModelMatchState.matched,
        effort: 'high',
        completionTokens: 100,
        ttftMillis: 300,
        decodeMillis: 1000,
        totalResponseMillis: 1300,
        tokensPerSecond: 100,
      ),
      StatisticsSample(
        completedAt: now.subtract(const Duration(minutes: 1)),
        accountId: 'account-a',
        accountDisplayName: 'Alpha',
        modelId: 'shared-model',
        sentModel: 'shared-model',
        reportedModel: 'shared-model',
        modelMatchState: StatisticsModelMatchState.matched,
        effort: null,
        completionTokens: 100,
        ttftMillis: 300,
        decodeMillis: 1000,
        totalResponseMillis: 1300,
        tokensPerSecond: 100,
      ),
      // 缺失配置模型的旧记录只用发送别名显示，不得合并进配置模型汇总。
      StatisticsSample(
        completedAt: now.subtract(const Duration(minutes: 2)),
        accountId: 'account-a',
        accountDisplayName: 'Alpha',
        modelId: null,
        sentModel: 'legacy-alias',
        reportedModel: null,
        modelMatchState: StatisticsModelMatchState.legacyUnknown,
        effort: null,
        completionTokens: 10,
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

final class _FixtureStatisticsRepository implements StatisticsRepository {
  _FixtureStatisticsRepository(
    StatisticsSnapshot? snapshot, {
    StatisticsConnectionPhase phase = StatisticsConnectionPhase.ready,
    StatisticsFailure? failure,
  }) : _state = StatisticsRepositoryState(
         snapshot: snapshot,
         connection: StatisticsConnectionState(phase: phase, failure: failure),
       );

  final StatisticsRepositoryState _state;
  int visibleDemands = 0;
  int retryCalls = 0;

  @override
  StatisticsRepositoryState get state => _state;

  @override
  StatisticsObservation observe(
    void Function(StatisticsRepositoryState state) listener,
  ) => _FixtureObservation(_state);

  @override
  StatisticsVisibilityLease acquireVisibleDemand() {
    visibleDemands++;
    return _FixtureVisibilityLease(() => visibleDemands--);
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) async => CloseReport();

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) async => CloseReport();

  @override
  void retry() => retryCalls++;
}

final class _FixtureObservation implements StatisticsObservation {
  const _FixtureObservation(this.initialState);

  @override
  final StatisticsRepositoryState initialState;

  @override
  void cancel() {}
}

final class _FixtureVisibilityLease implements StatisticsVisibilityLease {
  _FixtureVisibilityLease(this._onRelease);

  final void Function() _onRelease;
  bool _released = false;

  @override
  bool get isReleased => _released;

  @override
  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }
}
