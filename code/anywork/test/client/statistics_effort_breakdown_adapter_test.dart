import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/statistics/connectors/statistics_connector.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_view_model.dart';
import 'package:anywork/src/features/settings/statistics/widgets/statistics_history_widgets.dart';
import 'package:anywork/src/features/settings/statistics/widgets/statistics_summary_widgets.dart';
import 'package:anywork/src/features/settings/statistics/state/statistics_view_state.dart';
import 'package:anywork/src/features/settings/statistics/views/statistics_view.dart';
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
    'View reuses options, overview and scroll body for status-only publications',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1600);
      addTearDown(tester.view.reset);
      final base = _snapshot();
      final initial = StatisticsSnapshot(
        ownerEpoch: base.ownerEpoch,
        feedId: base.feedId,
        publicationRevision: 1,
        summariesRevision: 1,
        historyRevision: 1,
        summaries: base.summaries,
        history: List.generate(
          3000,
          (index) =>
              _windowSample(index, base.history[index % base.history.length]),
        ),
        statisticsPending: false,
        statisticsGap: false,
        readFailed: false,
      );
      final theme = pureStudioTheme();
      var oldCallbacks = 0;
      var newCallbacks = 0;
      Future<void> pump(
        StatisticsSnapshot snapshot, {
        Locale locale = const Locale('en'),
        ThemeData? presentationTheme,
        String? modelFilter,
        List<StatisticsSample>? filtered,
        ValueChanged<String?>? onModelChanged,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            theme: presentationTheme ?? theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StatisticsView(
                state: StatisticsViewState(
                  repository: StatisticsRepositoryState(
                    snapshot: snapshot,
                    connection: const StatisticsConnectionState(
                      phase: StatisticsConnectionPhase.ready,
                    ),
                  ),
                  modelFilter: modelFilter,
                  effortFilter: null,
                  mismatchesOnly: false,
                  filteredHistory: filtered ?? snapshot.history,
                ),
                visible: true,
                onModelChanged: onModelChanged ?? (_) {},
                onEffortChanged: (_) {},
                onMismatchesOnlyChanged: (_) {},
                onRetry: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump(initial, onModelChanged: (_) => oldCallbacks++);
      final header = tester.widget<StatisticsHistoryHeader>(
        find.byType(StatisticsHistoryHeader),
      );
      final summary = tester.widget<StatisticsSummarySection>(
        find.byType(StatisticsSummarySection),
      );
      final overview = tester.widget<DataTable>(find.byType(DataTable));
      final body = tester.widget<CustomScrollView>(
        find.byKey(StudioDriverKeys.statisticsHistory),
      );
      expect(header.options.models, hasLength(2));
      expect(header.options.efforts, hasLength(2));
      expect(() => header.options.models.clear(), throwsUnsupportedError);
      final list = tester.widget<SliverList>(find.byType(SliverList));
      expect((list.delegate as SliverChildBuilderDelegate).childCount, 3000);

      final statusOnly = initial.withPublication(
        StatisticsFeedIdentity(
          ownerEpoch: initial.ownerEpoch,
          feedId: initial.feedId,
          deliverySequence: 2,
          publicationRevision: 2,
          summariesRevision: initial.summariesRevision,
          historyRevision: initial.historyRevision,
          summaryCount: initial.summaries.length,
          historyCount: initial.history.length,
          statisticsPending: true,
          statisticsGap: true,
          readFailed: true,
        ),
      );
      await pump(statusOnly, onModelChanged: (_) => newCallbacks++);
      expect(
        find.byKey(const ValueKey('statistics-status-gap')),
        findsOneWidget,
      );
      expect(
        tester.widget<StatisticsHistoryHeader>(
          find.byType(StatisticsHistoryHeader),
        ),
        same(header),
      );
      expect(
        tester.widget<StatisticsSummarySection>(
          find.byType(StatisticsSummarySection),
        ),
        same(summary),
      );
      expect(tester.widget<DataTable>(find.byType(DataTable)), same(overview));
      expect(
        tester.widget<CustomScrollView>(
          find.byKey(StudioDriverKeys.statisticsHistory),
        ),
        same(body),
      );
      // This is the real View's cached header, not a ViewModel identity assertion.
      header.onChanged(initial.history.first.filterKey);
      expect(oldCallbacks, 0);
      expect(newCallbacks, 1);

      final filtered = StatisticsMaterial.freeze(
        initial.history.where(
          (sample) => sample.filterKey == initial.history.first.filterKey,
        ),
      );
      await pump(
        statusOnly,
        modelFilter: initial.history.first.filterKey,
        filtered: filtered,
      );
      final selectedHeader = tester.widget<StatisticsHistoryHeader>(
        find.byType(StatisticsHistoryHeader),
      );
      expect(selectedHeader.value, initial.history.first.filterKey);
      expect(selectedHeader.options, same(header.options));
      expect(tester.widget<DataTable>(find.byType(DataTable)), same(overview));

      await pump(initial, locale: const Locale('zh'));
      final localizedHeader = tester.widget<StatisticsHistoryHeader>(
        find.byType(StatisticsHistoryHeader),
      );
      expect(localizedHeader.options, same(header.options));
      final localized = AppLocalizations.of(
        tester.element(find.byType(StatisticsHistoryHeader)),
      );
      expect(
        find.text(localized.settingsStatisticsHistoryTitle),
        findsOneWidget,
      );
      expect(
        find.text(localized.settingsStatisticsSummaryTitle),
        findsOneWidget,
      );
      expect(
        tester.widget<DataTable>(find.byType(DataTable)),
        isNot(same(overview)),
      );

      final changedTheme = theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          titleMedium: theme.textTheme.titleMedium!.copyWith(letterSpacing: 3),
        ),
      );
      await pump(
        initial,
        locale: const Locale('zh'),
        presentationTheme: changedTheme,
      );
      expect(
        tester
            .widget<StatisticsHistoryHeader>(
              find.byType(StatisticsHistoryHeader),
            )
            .options,
        same(header.options),
      );
      expect(
        tester
            .widget<Text>(find.text(localized.settingsStatisticsHistoryTitle))
            .style!
            .letterSpacing,
        3,
      );

      tester.view.physicalSize = const Size(360, 1600);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StatisticsHistoryHeader>(
              find.byType(StatisticsHistoryHeader),
            )
            .options,
        same(header.options),
      );
      expect(
        tester
            .widget<StatisticsSummarySection>(
              find.byType(StatisticsSummarySection),
            )
            .compact,
        isTrue,
      );
      tester.view.physicalSize = const Size(1200, 1600);
      await tester.pumpAndSettle();
      final wideSummary = tester.widget<StatisticsSummarySection>(
        find.byType(StatisticsSummarySection),
      );

      final revisionOnly = StatisticsSnapshot(
        ownerEpoch: initial.ownerEpoch,
        feedId: initial.feedId,
        publicationRevision: 3,
        summariesRevision: initial.summariesRevision,
        historyRevision: 2,
        summaries: initial.summaries,
        history: initial.history,
        statisticsPending: false,
        statisticsGap: false,
        readFailed: false,
      );
      await pump(revisionOnly);
      final revisedOptions = tester
          .widget<StatisticsHistoryHeader>(find.byType(StatisticsHistoryHeader))
          .options;
      expect(revisedOptions, isNot(same(header.options)));
      expect(
        tester.widget<StatisticsSummarySection>(
          find.byType(StatisticsSummarySection),
        ),
        same(wideSummary),
      );
      await pump(
        StatisticsSnapshot(
          ownerEpoch: 'new-view-owner',
          feedId: 'new-view-feed',
          publicationRevision: 1,
          summariesRevision: 1,
          historyRevision: 2,
          summaries: initial.summaries,
          history: initial.history,
          statisticsPending: false,
          statisticsGap: false,
          readFailed: false,
        ),
      );
      expect(
        tester
            .widget<StatisticsHistoryHeader>(
              find.byType(StatisticsHistoryHeader),
            )
            .options,
        isNot(same(revisedOptions)),
      );
      expect(
        tester.widget<StatisticsSummarySection>(
          find.byType(StatisticsSummarySection),
        ),
        isNot(same(wideSummary)),
      );

      final changed = StatisticsSnapshot(
        ownerEpoch: initial.ownerEpoch,
        feedId: initial.feedId,
        publicationRevision: 3,
        summariesRevision: 2,
        historyRevision: 2,
        summaries: const [],
        history: [initial.history.first],
        statisticsPending: false,
        statisticsGap: false,
        readFailed: false,
      );
      await pump(changed);
      final changedHeader = tester.widget<StatisticsHistoryHeader>(
        find.byType(StatisticsHistoryHeader),
      );
      expect(changedHeader.options, isNot(same(header.options)));
      expect(changedHeader.options.models, hasLength(1));
      expect(changedHeader.options.efforts, hasLength(1));
      expect(
        tester.widget<StatisticsSummarySection>(
          find.byType(StatisticsSummarySection),
        ),
        isNot(same(summary)),
      );
      expect(find.byType(DataTable), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final wide in [false, true]) {
    testWidgets(
      '${wide ? "wide" : "compact"} history renders only performance readings',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(wide ? 1100 : 360, 1000);
        addTearDown(tester.view.reset);
        final sample = _windowSample(
          0,
          _snapshot().history.first,
          firstOutputSource: FirstOutputSource.completedToolInput,
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            theme: pureStudioTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: wide
                    ? StatisticsWideHistoryRow(sample: sample)
                    : StatisticsCompactHistoryCard(sample: sample),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // 样本仍保留真实诊断事实，但历史行只呈现性能读数。
        expect(sample.threadId, 'thread-statistics');
        expect(sample.callId, 'window-call-0');
        expect(sample.purpose, 'primary');
        expect(sample.firstOutputSource, FirstOutputSource.completedToolInput);
        expect(find.textContaining('Purpose:'), findsNothing);
        expect(find.textContaining('First content source'), findsNothing);
        expect(find.textContaining('Thread:'), findsNothing);
        expect(find.textContaining('Call:'), findsNothing);
        expect(
          find.byWidgetPredicate((widget) => widget is SelectableText),
          findsNothing,
        );
        expect(find.text('100'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('status publications reuse filtered materials, filter and epoch changes do not', () {
    final snapshot = _snapshot();
    final repository = _FixtureStatisticsRepository(snapshot);
    final container = ProviderContainer(
      overrides: [statisticsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      statisticsViewModelProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    final model = container.read(statisticsViewModelProvider.notifier);
    expect(
      container.read(statisticsViewModelProvider).filteredHistory,
      same(snapshot.history),
    );

    final first = snapshot.history.first;
    model.selectModel(first.filterKey);
    final modelOnly = container
        .read(statisticsViewModelProvider)
        .filteredHistory;
    // Same account/model, two distinct efforts remain separate calls.
    expect(modelOnly.map((item) => item.callId), ['call-1', 'call-2']);
    model.selectEffort(first.effortKey);
    final filtered = container
        .read(statisticsViewModelProvider)
        .filteredHistory;
    expect(filtered.map((item) => item.callId), ['call-1']);

    final statusOnly = snapshot.withPublication(
      StatisticsFeedIdentity(
        ownerEpoch: snapshot.ownerEpoch,
        feedId: snapshot.feedId,
        deliverySequence: 2,
        publicationRevision: 2,
        summariesRevision: snapshot.summariesRevision,
        historyRevision: snapshot.historyRevision,
        summaryCount: snapshot.summaries.length,
        historyCount: snapshot.history.length,
        statisticsPending: true,
        statisticsGap: true,
        readFailed: false,
      ),
    );
    repository.publish(statusOnly);
    expect(
      container.read(statisticsViewModelProvider).filteredHistory,
      same(filtered),
    );
    expect(() => filtered.clear(), throwsUnsupportedError);

    model.selectEffort(snapshot.history[1].effortKey);
    final unspecified = container
        .read(statisticsViewModelProvider)
        .filteredHistory;
    expect(unspecified.map((item) => item.callId), ['call-2']);
    expect(unspecified, isNot(same(filtered)));
    model.selectEffort(first.effortKey);
    final selectedAgain = container
        .read(statisticsViewModelProvider)
        .filteredHistory;

    // Even deliberately reused material objects may not carry a cache across an owner epoch.
    repository.publish(
      StatisticsSnapshot(
        ownerEpoch: 'new-owner',
        feedId: 'new-feed',
        publicationRevision: 1,
        summariesRevision: 1,
        historyRevision: 1,
        summaries: snapshot.summaries,
        history: snapshot.history,
        statisticsPending: false,
        statisticsGap: false,
        readFailed: false,
      ),
    );
    final newOwner = container
        .read(statisticsViewModelProvider)
        .filteredHistory;
    expect(newOwner, isNot(same(selectedAgain)));
    expect(newOwner.map((item) => item.callId), ['call-1']);

    repository.publish(
      StatisticsSnapshot(
        ownerEpoch: 'new-owner',
        feedId: 'new-feed',
        publicationRevision: 2,
        summariesRevision: 1,
        historyRevision: 2,
        summaries: snapshot.summaries,
        history: [snapshot.history[1]],
        statisticsPending: false,
        statisticsGap: false,
        readFailed: false,
      ),
    );
    final replaced = container.read(statisticsViewModelProvider);
    expect(replaced.effortFilter, isNull);
    expect(replaced.filteredHistory.map((item) => item.callId), ['call-2']);
    expect(replaced.filteredHistory, isNot(same(newOwner)));
  });

  testWidgets(
    'history preserves typed unknown versus zero without sample diagnostics',
    (tester) async {
      Future<void> pump(int? output, MetricAvailability availability) async {
        final sample = StatisticsSample(
          threadId: 'thread-observed',
          callId: 'call-observed',
          purpose: 'compaction',
          firstOutputSource: FirstOutputSource.completedToolInput,
          usageStatus: UsageReportStatus.partial,
          ttftAvailability: MetricAvailability.available,
          throughputAvailability: availability,
          completedAt: DateTime.utc(2026, 2, 1),
          accountId: 'account-a',
          accountDisplayName: 'Alpha',
          modelId: 'shared-model',
          sentModel: 'shared-model',
          reportedModel: 'shared-model',
          modelMatchState: StatisticsModelMatchState.matched,
          effort: 'high',
          completionTokens: output,
          ttftMillis: 100,
          decodeMillis: 0,
          totalResponseMillis: 100,
          tokensPerSecond: null,
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            theme: pureStudioTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 320,
                  child: StatisticsCompactHistoryCard(sample: sample),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await pump(null, MetricAvailability.missingOutput);
      expect(find.text('Unknown'), findsOneWidget);
      expect(find.textContaining('Output usage unknown'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data?.contains('First complete tool input observed') ==
                  true,
        ),
        findsNothing,
      );
      expect(find.textContaining('compaction'), findsNothing);
      expect(find.textContaining('Thread: thread-observed'), findsNothing);
      expect(find.textContaining('Call: call-observed'), findsNothing);
      expect(
        find.byWidgetPredicate((widget) => widget is SelectableText),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await pump(0, MetricAvailability.invalidUsage);
      expect(find.text('Unknown'), findsNothing);
      expect(find.text('0'), findsOneWidget);
      // 诊断事实不从输出值反推，也不在历史行内联展示。
      expect(
        find.textContaining('Inconsistent or overflowing usage'),
        findsNothing,
      );
      expect(find.textContaining('Reported output is 0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
        const ValueKey(
          'statistics-history-call:["thread-statistics","call-1"]',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is StatisticsCompactHistoryCard ||
            widget is StatisticsWideHistoryRow,
      ),
      findsOneWidget,
    );
    expect(find.byKey(StudioDriverKeys.statisticsFilter), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.statisticsMismatchOnly), findsOneWidget);
  });
}

StatisticsSample _windowSample(
  int index,
  StatisticsSample source, {
  FirstOutputSource? firstOutputSource,
}) => StatisticsSample(
  threadId: source.threadId,
  callId: 'window-call-$index',
  purpose: source.purpose,
  firstOutputSource: firstOutputSource ?? source.firstOutputSource,
  usageStatus: source.usageStatus,
  ttftAvailability: source.ttftAvailability,
  throughputAvailability: source.throughputAvailability,
  completedAt: source.completedAt,
  accountId: source.accountId,
  accountDisplayName: source.accountDisplayName,
  modelId: source.modelId,
  sentModel: source.sentModel,
  reportedModel: source.reportedModel,
  modelMatchState: source.modelMatchState,
  effort: source.effort,
  completionTokens: source.completionTokens,
  ttftMillis: source.ttftMillis,
  decodeMillis: source.decodeMillis,
  totalResponseMillis: source.totalResponseMillis,
  tokensPerSecond: source.tokensPerSecond,
);

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
        threadId: 'thread-statistics',
        callId: 'call-1',
        purpose: 'primary',
        firstOutputSource: FirstOutputSource.incremental,
        usageStatus: UsageReportStatus.reported,
        ttftAvailability: MetricAvailability.available,
        throughputAvailability: MetricAvailability.available,
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
        threadId: 'thread-statistics',
        callId: 'call-2',
        purpose: 'primary',
        firstOutputSource: FirstOutputSource.incremental,
        usageStatus: UsageReportStatus.reported,
        ttftAvailability: MetricAvailability.available,
        throughputAvailability: MetricAvailability.available,
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
        threadId: 'thread-statistics',
        callId: 'call-3',
        purpose: null,
        firstOutputSource: FirstOutputSource.legacyUnknown,
        usageStatus: UsageReportStatus.legacyUnknown,
        ttftAvailability: MetricAvailability.legacyUnknown,
        throughputAvailability: MetricAvailability.legacyUnknown,
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

  StatisticsRepositoryState _state;
  final _listeners = <void Function(StatisticsRepositoryState)>{};
  int visibleDemands = 0;
  int retryCalls = 0;

  @override
  StatisticsRepositoryState get state => _state;

  @override
  StatisticsObservation observe(
    void Function(StatisticsRepositoryState state) listener,
  ) {
    _listeners.add(listener);
    return _FixtureObservation(_state, () => _listeners.remove(listener));
  }

  void publish(StatisticsSnapshot snapshot) {
    _state = StatisticsRepositoryState(
      snapshot: snapshot,
      connection: const StatisticsConnectionState(
        phase: StatisticsConnectionPhase.ready,
      ),
    );
    for (final listener in _listeners.toList()) {
      listener(_state);
    }
  }

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
  const _FixtureObservation(this.initialState, this._onCancel);

  final void Function() _onCancel;

  @override
  final StatisticsRepositoryState initialState;

  @override
  void cancel() => _onCancel();
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
