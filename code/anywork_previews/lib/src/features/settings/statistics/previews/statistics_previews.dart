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

Widget statisticsServiceTiersPreview({Locale locale = const Locale('zh')}) =>
    accountPreviewHost(
      (_) => const _StatisticsScenario(),
      scenarioIdentity: 'statistics-request-tiers',
      locale: locale,
    );

/// Only fixture interaction state lives here; all layout is the production View.
class _StatisticsScenario extends StatefulWidget {
  const _StatisticsScenario();

  @override
  State<_StatisticsScenario> createState() => _StatisticsScenarioState();
}

class _StatisticsScenarioState extends State<_StatisticsScenario> {
  final _snapshot = statisticsServiceTierSnapshot();
  String? _model;
  String? _effort;
  String? _tier;
  bool _mismatchesOnly = false;

  @override
  Widget build(BuildContext context) => StatisticsView(
    state: StatisticsViewState(
      repository: StatisticsRepositoryState(
        snapshot: _snapshot,
        connection: const StatisticsConnectionState(
          phase: StatisticsConnectionPhase.ready,
        ),
      ),
      modelFilter: _model,
      effortFilter: _effort,
      serviceTierFilter: _tier,
      mismatchesOnly: _mismatchesOnly,
      filteredHistory: _snapshot.history.where(
        (sample) =>
            (_model == null || sample.filterKey == _model) &&
            (_effort == null || sample.effortKey == _effort) &&
            (_tier == null || sample.serviceTierKey == _tier) &&
            (!_mismatchesOnly ||
                sample.modelMatchState == StatisticsModelMatchState.mismatched),
      ),
    ),
    visible: true,
    onModelChanged: (value) => setState(() => _model = value),
    onEffortChanged: (value) => setState(() => _effort = value),
    onServiceTierChanged: (value) => setState(() => _tier = value),
    onMismatchesOnlyChanged: (value) => setState(() => _mismatchesOnly = value),
    onRetry: () {},
  );
}
