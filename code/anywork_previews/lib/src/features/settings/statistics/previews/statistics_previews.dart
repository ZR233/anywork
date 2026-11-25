import 'package:anywork/src/features/settings/statistics/state/statistics_view_state.dart';
import 'package:anywork/src/features/settings/statistics/views/statistics_view.dart';
import 'package:anywork_client/statistics.dart';
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

import '../../accounts/previews/account_preview_host.dart';
import 'statistics_preview_fixtures.dart';

@Preview(
  name: '请求档位 · 标准 / Fast / Ultrafast · 宽屏',
  group: 'Settings · Statistics',
  size: Size(1320, 1000),
)
Widget statisticsServiceTiersZhWidePreview() => statisticsServiceTiersPreview();

@Preview(
  name: 'Request tiers · Standard / Fast / Ultrafast · Wide',
  group: 'Settings · Statistics',
  size: Size(1320, 1000),
)
Widget statisticsServiceTiersEnWidePreview() =>
    statisticsServiceTiersPreview(locale: const Locale('en'));

@Preview(
  name: '请求档位 · 可组合历史筛选 · 窄屏',
  group: 'Settings · Statistics',
  size: Size(420, 1200),
)
Widget statisticsServiceTiersZhCompactPreview() =>
    statisticsServiceTiersPreview();

@Preview(
  name: 'Request tiers · Combined history filters · Compact',
  group: 'Settings · Statistics',
  size: Size(420, 1200),
)
Widget statisticsServiceTiersEnCompactPreview() =>
    statisticsServiceTiersPreview(locale: const Locale('en'));

@Preview(
  name: '调用记录 · 分页交互 · 宽屏',
  group: 'Settings · Statistics',
  size: Size(1320, 900),
)
Widget statisticsPaginationZhWidePreview() => statisticsPaginationPreview();

@Preview(
  name: '调用记录 · 分页交互 · 窄屏',
  group: 'Settings · Statistics',
  size: Size(420, 900),
)
Widget statisticsPaginationZhCompactPreview() => statisticsPaginationPreview();

Widget statisticsServiceTiersPreview({Locale locale = const Locale('zh')}) =>
    accountPreviewHost(
      (_) => const _StatisticsScenario(),
      scenarioIdentity: 'statistics-request-tiers',
      locale: locale,
    );

Widget statisticsPaginationPreview({Locale locale = const Locale('zh')}) =>
    accountPreviewHost(
      (_) => const _StatisticsPaginationScenario(),
      scenarioIdentity: 'statistics-pagination',
      locale: locale,
    );

/// Derives the presentation state from preview-only interaction values; page
/// clamping reuses the production [StatisticsViewState] helpers instead of a
/// preview-local pagination algorithm.
StatisticsViewState _statisticsPreviewState({
  required StatisticsSnapshot snapshot,
  required bool refreshing,
  required String? modelFilter,
  required String? effortFilter,
  required String? serviceTierFilter,
  required bool mismatchesOnly,
  required StatisticsSection section,
  required int summaryPageIndex,
  required int historyPageIndex,
}) {
  final filteredHistory = _filteredPreviewHistory(
    snapshot.history,
    modelFilter: modelFilter,
    effortFilter: effortFilter,
    serviceTierFilter: serviceTierFilter,
    mismatchesOnly: mismatchesOnly,
  );
  return StatisticsViewState(
    repository: StatisticsRepositoryState(
      snapshot: snapshot,
      connection: StatisticsConnectionState(
        phase: refreshing
            ? StatisticsConnectionPhase.reconnecting
            : StatisticsConnectionPhase.ready,
      ),
    ),
    modelFilter: modelFilter,
    effortFilter: effortFilter,
    serviceTierFilter: serviceTierFilter,
    mismatchesOnly: mismatchesOnly,
    filteredHistory: filteredHistory,
    section: section,
    summaryPageIndex: summaryPageIndex.clamp(
      0,
      StatisticsViewState.pagesFor(snapshot.summaries.length) - 1,
    ),
    historyPageIndex: historyPageIndex.clamp(
      0,
      StatisticsViewState.pagesFor(filteredHistory.length) - 1,
    ),
  );
}

List<StatisticsSample> _filteredPreviewHistory(
  List<StatisticsSample> history, {
  required String? modelFilter,
  required String? effortFilter,
  required String? serviceTierFilter,
  required bool mismatchesOnly,
}) => history
    .where(
      (sample) =>
          (modelFilter == null || sample.filterKey == modelFilter) &&
          (effortFilter == null || sample.effortKey == effortFilter) &&
          (serviceTierFilter == null ||
              sample.serviceTierKey == serviceTierFilter) &&
          (!mismatchesOnly ||
              sample.modelMatchState == StatisticsModelMatchState.mismatched),
    )
    .toList(growable: false);

/// Only fixture interaction state lives here; all layout is the production View.
class _StatisticsScenario extends StatefulWidget {
  const _StatisticsScenario();

  @override
  State<_StatisticsScenario> createState() => _StatisticsScenarioState();
}

class _StatisticsScenarioState extends State<_StatisticsScenario> {
  final _snapshot = statisticsServiceTierSnapshot();
  StatisticsSection _section = StatisticsSection.summaries;
  int _summaryPageIndex = 0;
  int _historyPageIndex = 0;
  String? _model;
  String? _effort;
  String? _tier;
  bool _mismatchesOnly = false;

  @override
  Widget build(BuildContext context) => StatisticsView(
    state: _statisticsPreviewState(
      snapshot: _snapshot,
      refreshing: false,
      modelFilter: _model,
      effortFilter: _effort,
      serviceTierFilter: _tier,
      mismatchesOnly: _mismatchesOnly,
      section: _section,
      summaryPageIndex: _summaryPageIndex,
      historyPageIndex: _historyPageIndex,
    ),
    visible: true,
    onModelChanged: (value) => setState(() {
      _model = value;
      _historyPageIndex = 0;
    }),
    onEffortChanged: (value) => setState(() {
      _effort = value;
      _historyPageIndex = 0;
    }),
    onServiceTierChanged: (value) => setState(() {
      _tier = value;
      _historyPageIndex = 0;
    }),
    onMismatchesOnlyChanged: (value) => setState(() {
      _mismatchesOnly = value;
      _historyPageIndex = 0;
    }),
    // 固定数据演示：刷新按钮可点击，但不改变合成结果（仅视觉）。
    onRefresh: () {},
    onSectionChanged: (section) => setState(() => _section = section),
    onPageChanged: (page) => setState(() {
      if (_section == StatisticsSection.summaries) {
        _summaryPageIndex = page;
      } else {
        _historyPageIndex = page;
      }
    }),
  );
}

/// Paged history scenario. The first screen lands on the history section so
/// the pagination controls are visible immediately; refresh briefly shows the
/// production busy state, then adopts another fixed synthetic result.
class _StatisticsPaginationScenario extends StatefulWidget {
  const _StatisticsPaginationScenario();

  @override
  State<_StatisticsPaginationScenario> createState() =>
      _StatisticsPaginationScenarioState();
}

class _StatisticsPaginationScenarioState
    extends State<_StatisticsPaginationScenario> {
  final _fixtures = statisticsPaginationFixtures();
  late StatisticsSnapshot _snapshot = _fixtures.snapshot;
  StatisticsSection _section = StatisticsSection.history;
  int _summaryPageIndex = 0;
  int _historyPageIndex = 0;
  String? _model;
  String? _effort;
  String? _tier;
  bool _mismatchesOnly = false;
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    // Preview-only action feedback: a short delay, then adopt the second
    // fixed fixture. No timers, no network; guarded against unmount.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _snapshot = _fixtures.refreshedSnapshot;
      _refreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) => StatisticsView(
    state: _statisticsPreviewState(
      snapshot: _snapshot,
      refreshing: _refreshing,
      modelFilter: _model,
      effortFilter: _effort,
      serviceTierFilter: _tier,
      mismatchesOnly: _mismatchesOnly,
      section: _section,
      summaryPageIndex: _summaryPageIndex,
      historyPageIndex: _historyPageIndex,
    ),
    visible: true,
    onModelChanged: (value) => setState(() {
      _model = value;
      _historyPageIndex = 0;
    }),
    onEffortChanged: (value) => setState(() {
      _effort = value;
      _historyPageIndex = 0;
    }),
    onServiceTierChanged: (value) => setState(() {
      _tier = value;
      _historyPageIndex = 0;
    }),
    onMismatchesOnlyChanged: (value) => setState(() {
      _mismatchesOnly = value;
      _historyPageIndex = 0;
    }),
    onRefresh: _refresh,
    onSectionChanged: (section) => setState(() => _section = section),
    onPageChanged: (page) => setState(() {
      if (_section == StatisticsSection.summaries) {
        _summaryPageIndex = page;
      } else {
        _historyPageIndex = page;
      }
    }),
  );
}
