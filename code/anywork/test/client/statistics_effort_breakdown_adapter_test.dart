import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/settings_scope.dart';
import 'package:anywork/src/features/settings/settings_statistics_tab.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 统计页的顶层身份是 (accountId, 配置 modelId)，effort 是组内细分筛选。
///
/// 覆盖：一个账号模型只有一个顶层汇总、细分行按 effort 原值区分（`null` 与
/// `none` 不同）、模型筛选与强度筛选是两个独立控件且各自可用、窄窗口不溢出
/// 也不隐藏控件。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'statistics groups by account model and filters effort separately',
    (tester) async {
      await _pumpStatistics(tester);

      // 顶层只有一组 (account-a, shared-model)。
      expect(
        find.byKey(
          StudioDriverKeys.statisticsSummaryRow('account-a', 'shared-model'),
        ),
        findsOneWidget,
      );
      // 组内细分行按 effort 原值区分：high 与“未指定”(null) 各一行。
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

      // 模型筛选与强度筛选是两个独立控件，强度“不限”不是 `null` 原值。
      expect(find.byKey(StudioDriverKeys.statisticsFilter), findsOneWidget);
      expect(
        find.byKey(StudioDriverKeys.statisticsEffortFilter),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.statisticsMismatchOnly),
        findsOneWidget,
      );
    },
  );

  testWidgets('narrow width keeps filters visible without overflow', (
    tester,
  ) async {
    // 420 逻辑像素宽：两个筛选控件与“仅看不一致”都必须换行保留，不溢出、不隐藏。
    await _pumpStatistics(tester, logicalSize: const Size(420, 800));

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

  testWidgets('effort filter narrows history without touching the model key', (
    tester,
  ) async {
    await _pumpStatistics(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(StudioDriverKeys.statisticsEffortFilter),
        matching: find.byType(TextField),
      ),
    );
    await tester.pumpAndSettle();
    // 菜单项在 overlay 中；按 MenuItemButton 定位，避免命中表格里的同名文本。
    await tester.tap(
      find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text('high'),
      ),
    );
    await tester.pumpAndSettle();

    // 只留下 high 强度样本；未指定强度的历史样本被组内筛选排除。
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
    // 顶层模型筛选与“仅看不一致”保持独立可用。
    expect(find.byKey(StudioDriverKeys.statisticsFilter), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.statisticsMismatchOnly), findsOneWidget);
  });
}

/// 真实 Client + 生产主题装配统计页；`logicalSize` 为空时使用测试默认视口。
Future<void> _pumpStatistics(WidgetTester tester, {Size? logicalSize}) async {
  if (logicalSize != null) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = logicalSize;
    addTearDown(tester.view.reset);
  }
  final client = (await tester.runAsync(
    () async => AnyworkClient(
      transport: _UnusedTransport(),
      clientId: 'statistics-effort',
    ),
  ))!;
  addTearDown(() async {
    await tester.runAsync(
      () => client.close(
        deadline: DateTime.now().add(const Duration(seconds: 3)),
      ),
    );
  });
  final now = DateTime.utc(2026, 2, 1);
  client.modelPerformance.apply(
    ModelPerformanceSnapshotView(
      revision: 1,
      updatedAt: now,
      summaries: [
        ModelPerformanceSummaryView(
          accountId: 'account-a',
          accountDisplayName: 'Alpha',
          modelId: 'shared-model',
          sampleCount: 2,
          completionTokens: 200,
          totalTtftMillis: 600,
          totalDecodeMillis: 2000,
          totalResponseMillis: 2600,
          tokensPerSecond: 100,
          averageTtftMillis: 300,
          averageResponseMillis: 1300,
          effortBreakdowns: [
            ModelPerformanceEffortSummaryView(
              effort: 'high',
              sampleCount: 1,
              completionTokens: 100,
              totalTtftMillis: 300,
              totalDecodeMillis: 1000,
              totalResponseMillis: 1300,
              tokensPerSecond: 100,
              averageTtftMillis: 300,
              averageResponseMillis: 1300,
            ),
            ModelPerformanceEffortSummaryView(
              effort: null,
              sampleCount: 1,
              completionTokens: 100,
              totalTtftMillis: 300,
              totalDecodeMillis: 1000,
              totalResponseMillis: 1300,
              tokensPerSecond: 100,
              averageTtftMillis: 300,
              averageResponseMillis: 1300,
            ),
          ],
        ),
      ],
      history: [
        ModelPerformanceSampleView(
          completedAt: now,
          accountId: 'account-a',
          accountDisplayName: 'Alpha',
          modelId: 'shared-model',
          sentModel: 'shared-model',
          modelMatchState: ModelMatchState.matched,
          effort: 'high',
          completionTokens: 100,
          ttftMillis: 300,
          decodeMillis: 1000,
          totalResponseMillis: 1300,
          tokensPerSecond: 100,
        ),
        ModelPerformanceSampleView(
          completedAt: now.subtract(const Duration(minutes: 1)),
          accountId: 'account-a',
          accountDisplayName: 'Alpha',
          modelId: 'shared-model',
          sentModel: 'shared-model',
          modelMatchState: ModelMatchState.matched,
          effort: null,
          completionTokens: 100,
          ttftMillis: 300,
          decodeMillis: 1000,
          totalResponseMillis: 1300,
          tokensPerSecond: 100,
        ),
        // 旧记录没有配置模型证据：独立为“历史身份未知”，不并入上面的组。
        ModelPerformanceSampleView(
          completedAt: now.subtract(const Duration(minutes: 2)),
          accountId: 'account-a',
          accountDisplayName: 'Alpha',
          sentModel: 'legacy-alias',
          modelMatchState: ModelMatchState.legacyUnknown,
          completionTokens: 10,
          ttftMillis: null,
          decodeMillis: null,
          totalResponseMillis: null,
          tokensPerSecond: null,
        ),
      ],
    ),
  );

  final container = ProviderContainer(
    overrides: [anyworkClientProvider.overrideWith((ref) => client)],
  );
  addTearDown(container.dispose);
  container.read(settingsVisibleTabProvider.notifier).select(3);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        // 生产主题唯一装配入口：StudioSemanticColors 等 extension 由它提供。
        theme: pureStudioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: StatisticsTab(tabIndex: 3)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

class _UnusedTransport implements StudioTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}
