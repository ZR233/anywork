import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork_previews/src/features/status/previews/thread_status_bar_previews.dart';
import 'package:anywork/src/features/status/status_bar_item.dart';
import 'package:anywork/src/features/status/thread_status_bar.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('宽屏状态栏从左缘开始，阶段与速度直接呈现且完整提示保留', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 180);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(threadStatusBarWidePreview());
    await tester.pumpAndSettle();

    final bar = find.byKey(const ValueKey('thread-status-bar-preview'));
    expect(tester.getRect(bar).left, 0);
    expect(
      tester.getRect(find.byKey(const ValueKey('todo-open-button'))).left,
      8,
      reason: '首个生产入口贴近状态栏左侧内边距，不应居中收缩',
    );
    expect(find.text('规划'), findsOneWidget);
    expect(find.text('42 词元/秒'), findsOneWidget);

    final l10n = AppLocalizations.of(tester.element(bar));
    final workflowLabel = '任务流程 · 规划 · ${l10n.modeDeletedUsingSnapshot}';
    final throughputLabel =
        '${l10n.statusLastConfirmedAgentTokenSpeed}: 42 词元/秒';
    expect(_tooltipWithMessage(workflowLabel), findsOneWidget);
    expect(_tooltipWithMessage(throughputLabel), findsOneWidget);
    final items = find.byType(StatusBarItem);
    expect(tester.getSemantics(items.at(1)).label, workflowLabel);
    expect(tester.getSemantics(items.at(2)).label, throughputLabel);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('窄屏无布局溢出，水平滚动仍可访问末端项和完整辅助信息', (tester) async {
    tester.view.devicePixelRatio = 1;
    // The preview remains a 320 px reference scene. At 280 px, production
    // Todo, workflow, context, throughput, started-item and overflow entries
    // cannot all fit, so this exercises real horizontal overflow without
    // inflating any item label.
    tester.view.physicalSize = const Size(280, 180);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final semantics = tester.ensureSemantics();

    var openedPlan = false;
    await tester.pumpWidget(
      threadStatusBarLayoutFixture(onOpenPlan: () => openedPlan = true),
    );
    await tester.pumpAndSettle();

    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('thread-status-bar-preview')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(find.text('规划'), findsOneWidget);
    expect(find.text('42 词元/秒'), findsOneWidget);
    final bar = find.byKey(const ValueKey('thread-status-bar-preview'));
    final l10n = AppLocalizations.of(tester.element(bar));
    final workflowLabel = '任务流程 · 规划 · ${l10n.modeDeletedUsingSnapshot}';
    final throughputLabel =
        '${l10n.statusLastConfirmedAgentTokenSpeed}: 42 词元/秒';
    expect(_tooltipWithMessage(workflowLabel), findsOneWidget);
    expect(_tooltipWithMessage(throughputLabel), findsOneWidget);
    final items = find.byType(StatusBarItem);
    expect(tester.getSemantics(items.at(1)).label, workflowLabel);
    expect(tester.getSemantics(items.at(2)).label, throughputLabel);
    expect(tester.takeException(), isNull);

    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final moreButton = find.descendant(
      of: find.byKey(const ValueKey('status-overflow')),
      matching: find.byType(IconButton),
    );
    expect(moreButton, findsOneWidget);
    expect(tester.getRect(moreButton).right, lessThanOrEqualTo(280));
    await tester.tap(moreButton);
    await tester.pumpAndSettle();
    final planEntry = find.byKey(StudioDriverKeys.statusPlanEntry);
    expect(planEntry, findsOneWidget);
    await tester.tap(planEntry);
    await tester.pumpAndSettle();
    expect(openedPlan, isTrue, reason: '可滚动抵达的生产计划入口应调用所传回调');
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('未知速度沿用现有不可用占位', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        theme: pureStudioTheme(locale: const Locale('zh')),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: TokenThroughputReadout(tokensPerSecond: null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(TokenThroughputReadout)),
    );
    expect(find.text(l10n.statusThroughputUnavailable), findsOneWidget);
    expect(
      _tooltipWithMessage(
        '${l10n.statusLastConfirmedAgentTokenSpeed}: '
        '${l10n.statusThroughputUnavailable}',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Finder _tooltipWithMessage(String message) => find.byWidgetPredicate(
  (widget) => widget is Tooltip && widget.message == message,
  description: 'Tooltip(message: $message)',
);
