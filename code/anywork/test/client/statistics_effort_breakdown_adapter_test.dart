import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/settings/state/settings_navigation_state.dart';
import 'package:anywork/src/features/settings/statistics/connectors/statistics_connector.dart';
import 'package:anywork/src/features/settings/statistics/state/statistics_view_state.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_view_model.dart';
import 'package:anywork/src/features/settings/view_models/settings_navigation_view_model.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/resources.dart'
    show ResourceKind, ResourceSyncPhase, StudioFailure, StudioFailureCode;
import 'package:anywork_client/statistics.dart' show ModelMatchState;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/statistics_test_port.dart'
    show StatisticsOpenScript, StatisticsTestGate, summariesFeedFailure;
import 'support/pump_client_future.dart';
import 'support/statistics_environment.dart';

/// 统计页的顶层身份是 (accountId, 配置 modelId)，effort 是组内细分筛选。
///
/// 覆盖：一个账号模型只有一个顶层汇总、细分行按 effort 原值区分（字面 `none`、
/// 未指定 `null` 与“不限”三者互不折叠）、模型筛选以账号+配置模型复合键取行（不用
/// sent/reported 别名）、mismatch 开关只留 frozen 诊断为 mismatched 的行、窄窗口
/// 不溢出也不隐藏、未完成投影不冒充已知空集合、失败首屏与 last-good 后的失败都用
/// 原文案与原 key 的只读重试并保留内容/筛选/滚动、pending 不显示状态行而
/// gap/readFailed 保持一行轻量提示。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'statistics groups by account model and filters effort separately',
    (tester) async {
      final page = await _pumpStatistics(tester);
      await _establish(tester, page.environment);

      // 顶层只有一组 (account-a, shared-model)。
      expect(
        find.byKey(
          StudioDriverKeys.statisticsSummaryRow('account-a', 'shared-model'),
        ),
        findsOneWidget,
      );
      // 组内细分行按 effort 原值区分：high、字面 none、未指定(null) 各一行。
      expect(_summaryEffortRow('high'), findsOneWidget);
      expect(_summaryEffortRow('none'), findsOneWidget);
      expect(_summaryEffortRow(null), findsOneWidget);
      expect(find.byKey(StudioDriverKeys.statisticsFilter), findsOneWidget);
      expect(
        find.byKey(StudioDriverKeys.statisticsEffortFilter),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.statisticsMismatchOnly),
        findsOneWidget,
      );
      // 一个可见页面只有一个可见需求，因此只打开一对统计事件流。
      expect(page.environment.port.summariesOpenCalls, 1);
      expect(page.environment.port.historyOpenCalls, 1);
    },
  );

  testWidgets('narrow width keeps filters visible without overflow', (
    tester,
  ) async {
    // 420 逻辑像素宽：两个筛选控件与“仅看不一致”都必须换行保留，不溢出、不隐藏。
    final page = await _pumpStatistics(
      tester,
      logicalSize: const Size(420, 800),
    );
    await _establish(tester, page.environment);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(
        StudioDriverKeys.statisticsSummaryRow('account-a', 'shared-model'),
      ),
      findsOneWidget,
    );
    expect(_summaryEffortRow('high'), findsOneWidget);
    expect(_summaryEffortRow('none'), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.statisticsFilter), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.statisticsEffortFilter), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.statisticsMismatchOnly), findsOneWidget);
  });

  testWidgets('connecting without a snapshot does not claim empty statistics', (
    tester,
  ) async {
    final page = await _pumpStatistics(tester);
    final l10n = _l10n(tester);

    expect(find.text(l10n.settingsStatisticsSummaryEmpty), findsNothing);
    expect(find.text(l10n.settingsStatisticsEmpty), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(page.environment.port.summariesOpenCalls, 1);
    expect(page.environment.port.historyOpenCalls, 1);
  });

  testWidgets(
    'a failed first publication keeps the real error and the original retry',
    (tester) async {
      final environment = StatisticsEnvironment();
      environment.port.summaryOpenScripts.add(
        const StatisticsOpenScript(fail: true),
      );
      final page = await _pumpStatistics(tester, environment: environment);
      await pumpClientUntil(
        tester,
        () => find.byKey(_retryKey).evaluate().isNotEmpty,
        'statistics first failure',
      );
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      // 真实错误文案与原 topic 重试 key/图标/文案。
      expect(find.text(_summariesOpenFailure.message), findsOneWidget);
      expect(find.byKey(_retryKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_retryKey),
          matching: find.byIcon(Icons.refresh),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(_retryKey),
          matching: find.text(l10n.sidebarRetry),
        ),
        findsOneWidget,
      );
      // 未完成投影仍是未知，不冒充已知空集合。
      expect(find.text(l10n.settingsStatisticsSummaryEmpty), findsNothing);
      expect(find.text(l10n.settingsStatisticsEmpty), findsNothing);

      final notifier = page.container.read(
        statisticsViewModelProvider.notifier,
      );
      final phases = <ResourceSyncPhase>[];
      final observation = page.environment.repository.state.watch(
        (state) => phases.add(state.sync.phase),
      );
      await tester.tap(find.byKey(_retryKey));
      await tester.pump();
      // 点击走 Repository.retrySync：同一个页面实例，不重建 provider/需求。
      expect(
        identical(
          page.container.read(statisticsViewModelProvider.notifier),
          notifier,
        ),
        isTrue,
      );

      await _establish(tester, page.environment, ordinal: 2);
      await tester.pumpAndSettle();
      observation.cancel();

      expect(find.byKey(_retryKey), findsNothing);
      expect(find.text(_summariesOpenFailure.message), findsNothing);
      expect(
        find.byKey(
          StudioDriverKeys.statisticsSummaryRow('account-a', 'shared-model'),
        ),
        findsOneWidget,
      );
      expect(page.environment.port.summariesOpenCalls, 2);
      expect(
        phases,
        isNot(contains(ResourceSyncPhase.idle)),
        reason: 'An explicit retry never releases the visible demand',
      );
      expect(phases, contains(ResourceSyncPhase.ready));
    },
  );

  testWidgets(
    'a failure after last good keeps content, model selection, scroll and the original retry',
    (tester) async {
      final page = await _pumpStatistics(
        tester,
        environment: StatisticsEnvironment(historyRows: 24),
        logicalSize: const Size(800, 600),
      );
      await _establish(tester, page.environment);

      // Unfiltered rows span three composite keys: account-a/shared-model,
      // account-b/shared-model (same model name, another account) and
      // account-a/alt-model (same account, another configured model). The full
      // result comes from the real ViewModel value: the history list is lazy, so
      // the built widget tree is never treated as the complete collection.
      expect(_vmRows(page), _fixtureRows(24));
      await _expectHistoryRow(
        tester,
        _historyRow('account-a', 'shared-model', 'high', 0),
      );

      await _pickModel(
        tester,
        page,
        'Alpha · account-a · shared-model',
        _sharedModelKey,
      );
      expect(_vmRows(page), _sharedModelRows(24));
      expect(_rowsLike('"account-b"'), findsNothing);
      expect(_rowsLike('"alt-model"'), findsNothing);
      await _expectHistoryRow(
        tester,
        _historyRow('account-a', 'shared-model', 'high', 0),
      );
      await _expectHistoryRow(
        tester,
        _historyRow('account-a', 'shared-model', 'none', 1),
      );
      await _expectHistoryRow(
        tester,
        _historyRow('account-a', 'shared-model', null, 2),
      );

      final scrollable = find
          .descendant(
            of: find.byKey(StudioDriverKeys.statisticsHistory),
            matching: find.byType(Scrollable),
          )
          .first;
      double offset() =>
          tester.state<ScrollableState>(scrollable).position.pixels;
      await tester.drag(
        find.byKey(StudioDriverKeys.statisticsHistory),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      final scrolled = offset();
      expect(scrolled, greaterThan(0));
      final first = page.environment.repository.state.value.snapshot!;
      final filtered = _vmRows(page);
      expect(_modelFilter(tester).initialSelection, _sharedModelKey);

      page.environment.port.summariesFeed.emit(
        summariesFeedFailure(
          feedId: StatisticsEnvironment.summariesFeedId,
          origin: StatisticsEnvironment.origin,
          error: _laneFailure,
        ),
      );
      final failed = await pumpClientFuture(
        tester,
        page.environment.repository.state.waitFor(
          (state) => state.sync.phase == ResourceSyncPhase.failed,
        ),
        'statistics lane failure',
      );
      await tester.pumpAndSettle();

      // 失败只进 mirror 的 sync；旧快照、模型选择、滚动与筛选后的行集合都还在。
      expect(failed.snapshot, first);
      expect(find.text(_laneFailure.message), findsOneWidget);
      expect(find.byKey(_retryKey), findsOneWidget);
      expect(_modelFilter(tester).initialSelection, _sharedModelKey);
      expect(offset(), scrolled);
      expect(_vmRows(page), filtered);
      expect(_rowsLike('"account-b"'), findsNothing);
      await _expectHistoryRow(
        tester,
        _historyRow('account-a', 'shared-model', 'none', 1),
      );

      final notifier = page.container.read(
        statisticsViewModelProvider.notifier,
      );
      await tester.tap(find.byKey(_retryKey));
      await tester.pump();
      expect(
        identical(
          page.container.read(statisticsViewModelProvider.notifier),
          notifier,
        ),
        isTrue,
      );
      await _establish(tester, page.environment, ordinal: 2);
      await tester.pumpAndSettle();

      // source 恢复后错误与重试消失，模型选择、滚动与筛选后的行集合仍保持。
      expect(find.byKey(_retryKey), findsNothing);
      expect(find.text(_laneFailure.message), findsNothing);
      expect(page.environment.port.summariesOpenCalls, 2);
      expect(_modelFilter(tester).initialSelection, _sharedModelKey);
      expect(offset(), scrolled);
      expect(_vmRows(page), filtered);
      expect(_rowsLike('"account-b"'), findsNothing);
      expect(_rowsLike('"alt-model"'), findsNothing);
      await _expectHistoryRow(
        tester,
        _historyRow('account-a', 'shared-model', 'high', 0),
      );
      await _expectHistoryRow(
        tester,
        _historyRow('account-a', 'shared-model', 'none', 1),
      );
    },
  );

  testWidgets('effort filter narrows history without touching the model key', (
    tester,
  ) async {
    final page = await _pumpStatistics(tester);
    await _establish(tester, page.environment);
    final l10n = _l10n(tester);

    // 不限模型、不限强度：完整身份矩阵由真实 VM 的 filteredHistory 给出。
    expect(_vmRows(page), _fixtureRows(6));

    // 先选一个明确的非空模型键；其后每一步强度筛选都必须保留同一模型键。
    await _pickModel(
      tester,
      page,
      'Alpha · account-a · shared-model',
      _sharedModelKey,
    );
    expect(_modelFilter(tester).initialSelection, _sharedModelKey);
    expect(_vmRows(page), _sharedModelRows(6));

    // 字面 `none` 只选中该细分，未指定(null) 不会被折叠进来。
    await _pickEffort(tester, page, 'none', _effort('none'));
    expect(_modelFilter(tester).initialSelection, _sharedModelKey);
    expect(_vmRows(page), _rowsOf([_shared('none')]));
    await _expectHistoryRow(
      tester,
      _historyRow('account-a', 'shared-model', 'none', 0),
    );

    // 未指定(null) 是真实细分，不等于“不限”，也不与 none 合并。
    await _pickEffort(
      tester,
      page,
      l10n.statisticsReasoningEffortUnspecified,
      _effort(null),
    );
    expect(_modelFilter(tester).initialSelection, _sharedModelKey);
    expect(_vmRows(page), _rowsOf([_shared(null)]));
    expect(
      _vmState(page).filteredHistory.every(
        (sample) =>
            sample.identity.modelId == 'shared-model' &&
            sample.identity.effort == null,
      ),
      isTrue,
      reason: 'The unspecified subgroup keeps the chosen model key',
    );
    await _expectHistoryRow(
      tester,
      _historyRow('account-a', 'shared-model', null, 0),
    );

    // high 只留该模型键的 high 行。
    await _pickEffort(tester, page, 'high', _effort('high'));
    expect(_modelFilter(tester).initialSelection, _sharedModelKey);
    expect(_vmRows(page), _rowsOf([_shared('high')]));

    // 不限强度回到该模型键的全部三行，模型键仍然未被清掉。
    await _pickEffort(tester, page, l10n.statisticsAllEfforts, null);
    expect(_modelFilter(tester).initialSelection, _sharedModelKey);
    expect(_vmRows(page), _sharedModelRows(6));
    // 顶层模型筛选与“仅看不一致”保持独立可用。
    expect(find.byKey(StudioDriverKeys.statisticsFilter), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.statisticsMismatchOnly), findsOneWidget);

    // 显式切回“全部模型”（真实 widget 操作，不是默认 null）：同一 high 强度
    // 这时才跨两个复合键保留。
    await _pickModel(tester, page, l10n.settingsStatisticsAllModels, null);
    expect(_modelFilter(tester).initialSelection, isNull);
    await _pickEffort(tester, page, 'high', _effort('high'));
    expect(
      _vmRows(page),
      _rowsOf([_shared('high'), ('account-a', 'alt-model', 'high')]),
    );
    await _expectHistoryRow(
      tester,
      _historyRow('account-a', 'alt-model', 'high', 1),
    );

    await _pickEffort(tester, page, l10n.statisticsAllEfforts, null);
    expect(_vmRows(page), _fixtureRows(6));
  });

  testWidgets(
    'the model filter keys the account and the configured model, never the sent alias',
    (tester) async {
      final page = await _pumpStatistics(tester);
      await _establish(tester, page.environment);
      final l10n = _l10n(tester);
      expect(_vmRows(page), _fixtureRows(6));

      // 同一模型名的另一个账号是另一复合键。
      await _pickModel(
        tester,
        page,
        'Beta · account-b · shared-model',
        const StatisticsModelKey(
          accountId: 'account-b',
          modelId: 'shared-model',
        ),
      );
      expect(
        _modelFilter(tester).initialSelection,
        const StatisticsModelKey(
          accountId: 'account-b',
          modelId: 'shared-model',
        ),
      );
      expect(_vmRows(page), _rowsOf([('account-b', 'shared-model', 'low')]));
      await _expectHistoryRow(
        tester,
        _historyRow('account-b', 'shared-model', 'low', 0),
      );
      expect(_rowsLike('"shared-model-preview"'), findsNothing);

      // 同一账号的另一个配置模型是另一复合键。
      await _pickModel(
        tester,
        page,
        'Alpha · account-a · alt-model',
        const StatisticsModelKey(accountId: 'account-a', modelId: 'alt-model'),
      );
      expect(_vmRows(page), _rowsOf([('account-a', 'alt-model', 'high')]));
      await _expectHistoryRow(
        tester,
        _historyRow('account-a', 'alt-model', 'high', 0),
      );

      // 配置模型键 (account-a, shared-model) 只取该键三行：legacy 行的 sent
      // 别名与 reported 预览名都不参与建键，因此不会被折算进来。
      await _pickModel(
        tester,
        page,
        'Alpha · account-a · shared-model',
        _sharedModelKey,
      );
      expect(_modelFilter(tester).initialSelection, _sharedModelKey);
      expect(_vmRows(page), _sharedModelRows(6));
      await _expectHistoryRow(
        tester,
        _historyRow('account-a', 'shared-model', 'high', 0),
      );
      expect(_rowsLike('"legacy-alias"'), findsNothing);
      expect(_rowsLike('"shared-model-preview"'), findsNothing);

      // legacy 选项自身的键是 (account-a, 未指定模型)：别名只用于显示。
      await _pickModel(
        tester,
        page,
        'Alpha · account-a · legacy-alias',
        const StatisticsModelKey(accountId: 'account-a', modelId: null),
      );
      expect(_vmRows(page), _rowsOf([('account-a', null, null)]));
      await _expectHistoryRow(tester, _historyRow('account-a', '', null, 0));

      await _pickModel(tester, page, l10n.settingsStatisticsAllModels, null);
      expect(_vmRows(page), _fixtureRows(6));
    },
  );

  testWidgets('the mismatch switch keeps only mismatched frozen diagnostics', (
    tester,
  ) async {
    final page = await _pumpStatistics(tester);
    await _establish(tester, page.environment);
    expect(_vmRows(page), _fixtureRows(6));

    await _setMismatchesOnly(tester, page, true);
    expect(
      _vmRows(page),
      _rowsOf([
        ('account-b', 'shared-model', 'low'),
        ('account-a', 'alt-model', 'high'),
      ]),
    );
    expect(
      _vmState(page).filteredHistory.every(
        (sample) =>
            sample.identity.modelMatchState == ModelMatchState.mismatched,
      ),
      isTrue,
      reason: 'Only frozen diagnostics decide, never the current catalog',
    );
    await _expectHistoryRow(
      tester,
      _historyRow('account-b', 'shared-model', 'low', 0),
    );
    await _expectHistoryRow(
      tester,
      _historyRow('account-a', 'alt-model', 'high', 1),
    );

    await _setMismatchesOnly(tester, page, false);
    expect(_vmRows(page), _fixtureRows(6));
  });

  testWidgets(
    'hiding and destroying the page while connecting leaves no demand or new attempt',
    (tester) async {
      final openGate = StatisticsTestGate();
      final environment = StatisticsEnvironment();
      environment.port.summaryOpenScripts.add(
        StatisticsOpenScript(gate: openGate, fail: true),
      );
      final page = await _pumpStatistics(tester, environment: environment);
      await pumpClientUntil(
        tester,
        () => openGate.entered.isCompleted,
        'statistics open',
      );
      expect(environment.port.summariesOpenCalls, 1);

      // Real hide: the visible demand is released before the open settles.
      page.container
          .read(statisticsViewModelProvider.notifier)
          .setVisible(false);
      await tester.pump();
      expect(
        environment.repository.state.value.sync.phase,
        ResourceSyncPhase.idle,
      );

      // Destroy the page and the container, then let the admitted open fail.
      await tester.pumpWidget(const SizedBox.shrink());
      page.dispose();
      openGate.release.complete();
      await pumpClientUntil(
        tester,
        () => environment.budget.used(ResourceKind.readModel) == 0,
        'statistics late open failure',
      );

      expect(tester.takeException(), isNull);
      expect(
        environment.port.summariesOpenCalls,
        1,
        reason: 'A hidden page never starts another attempt',
      );
      expect(
        environment.repository.state.value.sync.phase,
        ResourceSyncPhase.idle,
      );
      expect(environment.repository.state.value.snapshot, isNull);
    },
  );

  testWidgets(
    'a pending projection never claims empty statistics and header issues stay one status line',
    (tester) async {
      final page = await _pumpStatistics(
        tester,
        environment: StatisticsEnvironment(empty: true),
      );
      await _establish(tester, page.environment, pending: true);

      final l10n = _l10n(tester);
      // pending 是常规暂态：不显示状态行，也不把未知集合显示成已知空集合。
      expect(find.byKey(const ValueKey('statistics-status-gap')), findsNothing);
      expect(
        find.byKey(const ValueKey('statistics-status-read-failed')),
        findsNothing,
      );
      expect(find.text(l10n.settingsStatisticsSummaryEmpty), findsNothing);
      expect(find.text(l10n.settingsStatisticsEmpty), findsNothing);
      expect(find.text(l10n.statisticsMetricNotCollected), findsWidgets);

      await pumpClientFuture(
        tester,
        page.environment.republish(gap: true, readFailed: true),
        'statistics header issues',
      );
      await tester.pumpAndSettle();

      // gap/readFailed 仍是固定页头的一行轻量提示，且不降级为已知空集合。
      expect(
        find.byKey(const ValueKey('statistics-status-gap')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('statistics-status-read-failed')),
        findsOneWidget,
      );
      expect(find.text(l10n.settingsStatisticsSummaryEmpty), findsNothing);
      expect(find.text(l10n.settingsStatisticsEmpty), findsNothing);
    },
  );
}

/// PR160 的统计失败控件身份：状态行按原 key/图标/文案暴露同一个只读重试。
const _retryKey = ValueKey<String>(
  'settings-topic-retry-ModelPerformanceTopic',
);

const _summariesOpenFailure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The scripted summaries feed is unavailable.',
  retryable: true,
  correlationId: 'statistics-summaries',
);

const _laneFailure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The scripted summaries lane reported a failure.',
  retryable: true,
  correlationId: 'statistics',
);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(StatisticsConnector)));

Finder _summaryEffortRow(String? effort) => find.byKey(
  StudioDriverKeys.statisticsSummaryEffortRow(
    'account-a',
    'shared-model',
    effort,
  ),
);

Finder _historyRow(
  String accountId,
  String modelId,
  String? effort,
  int index,
) => find.byKey(
  StudioDriverKeys.statisticsHistoryRow(accountId, modelId, effort, index),
);

/// Addresses one keyed history row the way a driven UI does: the page arrives as
/// one complete snapshot, so the history list builds its rows on demand and a row
/// is reached by the official test scroll of the page's own vertical view. The
/// key, the order and the expectation are the real page's; a row the filter
/// excluded is never produced by scrolling.
///
/// Scroll budget: the widest fixture publishes 24 history rows of about 41 logical
/// pixels each (one `bodySmall` line plus 10 pixels of vertical padding), so with
/// the summary table, the filters and the wide header the page travels about 1.06k
/// logical pixels. The official step is 200 pixels, which is about six steps;
/// twelve keeps headroom for a taller row or a shorter window and stays far below
/// the API default of fifty.
const _historyRevealScrolls = 12;

Future<void> _expectHistoryRow(WidgetTester tester, Finder row) async {
  if (row.evaluate().isNotEmpty) {
    expect(row, findsOneWidget);
    return;
  }
  final page = find
      .descendant(
        of: find.byKey(StudioDriverKeys.statisticsHistory),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  final position = tester.state<ScrollableState>(page).position;
  final restore = position.pixels;
  try {
    // A filter can shrink the list under the current offset, so the reveal starts
    // at the top of the page and then walks forward with the official test scroll.
    position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: page,
      maxScrolls: _historyRevealScrolls,
    );
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
  } finally {
    // Restoring in `finally` keeps the filter controls in place and the scroll
    // assertions meaningful even when the expectation above fails; the scroll
    // failure itself still propagates.
    if (position.pixels != restore) {
      position.jumpTo(restore);
      await tester.pumpAndSettle();
    }
  }
}

Finder _rowsLike(String fragment) => find.byWidgetPredicate((widget) {
  final key = widget.key?.toString() ?? '';
  return key.contains('statistics-history-row') && key.contains(fragment);
});

/// The composite key most scenarios select explicitly.
const _sharedModelKey = StatisticsModelKey(
  accountId: 'account-a',
  modelId: 'shared-model',
);

StatisticsEffortFilter _effort(String? value) =>
    StatisticsEffortFilter(value: value);

/// One history identity as the production page exposes it. Effort is kept
/// verbatim so the literal `none` and the unspecified `null` stay distinct.
typedef _Row = (String accountId, String? modelId, String? effort);

_Row _shared(String? effort) => ('account-a', 'shared-model', effort);

/// The real ViewModel's own filter result in a stable comparable form. The
/// history list is lazily built, so the widget tree is never treated as the
/// complete collection.
List<String> _vmRows(_StatisticsPage page) => _rowsOf([
  for (final sample in _vmState(page).filteredHistory)
    (
      sample.identity.accountId,
      sample.identity.modelId,
      sample.identity.effort,
    ),
]);

StatisticsViewState? _vmStateOrNull(_StatisticsPage page) =>
    page.container.read(statisticsViewModelProvider).asData?.value;

StatisticsViewState _vmState(_StatisticsPage page) {
  final value = _vmStateOrNull(page);
  expect(value, isNotNull, reason: 'The statistics page must hold a value');
  return value!;
}

List<String> _rowsOf(Iterable<_Row> rows) => ([
  for (final (accountId, modelId, effort) in rows)
    '$accountId|$modelId|$effort',
]..sort());

/// The fixture's identity matrix: account-a/shared-model with `high`, the
/// literal `none` and no effort; account-b/shared-model mismatched;
/// account-a/alt-model mismatched; and the frozen legacy identity with no
/// configured model. Every further row is one more measured
/// account-a/shared-model sample.
List<String> _fixtureRows(int total) => _rowsOf([
  _shared('high'),
  _shared('none'),
  _shared(null),
  ('account-b', 'shared-model', 'low'),
  ('account-a', 'alt-model', 'high'),
  ('account-a', null, null),
  for (var index = 6; index < total; index++) _shared('low'),
]);

/// The rows of the (account-a, shared-model) key inside the same fixture.
List<String> _sharedModelRows(int total) => _rowsOf([
  _shared('high'),
  _shared('none'),
  _shared(null),
  for (var index = 6; index < total; index++) _shared('low'),
]);

DropdownMenu<StatisticsModelKey?> _modelFilter(WidgetTester tester) =>
    tester.widget<DropdownMenu<StatisticsModelKey?>>(
      find.descendant(
        of: find.byKey(StudioDriverKeys.statisticsFilter),
        matching: find.byType(DropdownMenu<StatisticsModelKey?>),
      ),
    );

/// Opens the model menu, picks [label] and waits until the real ViewModel holds
/// [expected] as its key: the widget operation is confirmed through production
/// state, not through an assumed complete widget build.
Future<void> _pickModel(
  WidgetTester tester,
  _StatisticsPage page,
  String label,
  StatisticsModelKey? expected,
) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(StudioDriverKeys.statisticsFilter),
      matching: find.byType(TextField),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(MenuItemButton),
      matching: find.text(label),
    ),
  );
  await pumpClientUntil(
    tester,
    () => _vmStateOrNull(page)?.modelFilter == expected,
    'statistics model filter "$label"',
  );
  await tester.pumpAndSettle();
}

Future<void> _pickEffort(
  WidgetTester tester,
  _StatisticsPage page,
  String label,
  StatisticsEffortFilter? expected,
) async {
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
      matching: find.text(label),
    ),
  );
  await pumpClientUntil(
    tester,
    () => _vmStateOrNull(page)?.effortFilter == expected,
    'statistics effort filter "$label"',
  );
  await tester.pumpAndSettle();
}

Future<void> _setMismatchesOnly(
  WidgetTester tester,
  _StatisticsPage page,
  bool expected,
) async {
  await tester.tap(find.byKey(StudioDriverKeys.statisticsMismatchOnly));
  await pumpClientUntil(
    tester,
    () => _vmStateOrNull(page)?.mismatchesOnly == expected,
    'statistics mismatch filter',
  );
  await tester.pumpAndSettle();
}

/// One pumped statistics page: real Repository + VM + Connector and the live
/// ProviderContainer that owns them.
final class _StatisticsPage {
  const _StatisticsPage(this.environment, this.container, this.dispose);

  final StatisticsEnvironment environment;
  final ProviderContainer container;
  final void Function() dispose;
}

Future<_StatisticsPage> _pumpStatistics(
  WidgetTester tester, {
  Size? logicalSize,
  StatisticsEnvironment? environment,
}) async {
  if (logicalSize != null) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = logicalSize;
    addTearDown(tester.view.reset);
  }
  final env = environment ?? StatisticsEnvironment();
  final container = ProviderContainer(
    overrides: [statisticsRepositoryProvider.overrideWithValue(env.repository)],
  );
  var disposed = false;
  void dispose() {
    if (disposed) return;
    disposed = true;
    container.dispose();
  }

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    dispose();
    final report = await pumpClientFuture(
      tester,
      env.close(),
      'statistics close',
    );
    expect(report.complete, isTrue);
    expect(env.budget.usage, isEmpty);
  });
  await pumpClientFuture(
    tester,
    container.read(settingsNavigationViewModelProvider.future),
    'statistics navigation',
  );
  container
      .read(settingsNavigationViewModelProvider.notifier)
      .enter(SettingsTab.statistics);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        // 生产主题唯一装配入口：StudioSemanticColors 等 extension 由它提供。
        theme: pureStudioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: StatisticsConnector()),
      ),
    ),
  );
  await tester.pump();
  return _StatisticsPage(env, container, dispose);
}

Future<void> _establish(
  WidgetTester tester,
  StatisticsEnvironment environment, {
  int ordinal = 1,
  bool pending = false,
}) async {
  await pumpClientFuture(
    tester,
    environment.establish(ordinal: ordinal, pending: pending),
    'statistics materialization',
  );
  await tester.pumpAndSettle();
}
