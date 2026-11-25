import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork_previews/src/features/status/previews/thread_status_bar_previews.dart';
import 'package:anywork/src/features/status/status_bar_item.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('面板入口保留启用、禁用与选中的按钮语义', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    for (final enabled in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: pureStudioTheme(),
          home: Scaffold(
            body: StatusBarButton(
              icon: Icons.description_outlined,
              label: '计划',
              iconOnly: true,
              tooltip: '查看计划',
              selected: true,
              onPressed: enabled ? () => taps++ : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('计划'), findsNothing);
      expect(_tooltipWithMessage('查看计划'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(StatusBarButton)),
        matchesSemantics(
          label: '查看计划',
          isButton: true,
          hasEnabledState: true,
          isEnabled: enabled,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: enabled,
        ),
      );
      await tester.tap(find.byType(StatusBarButton));
      expect(taps, 1, reason: '禁用入口不能再次触发动作');
    }
    semantics.dispose();
  });

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
      tester.getRect(find.byKey(const ValueKey('workflow-status-pill'))).left,
      8,
      reason: '首个生产入口贴近状态栏左侧内边距，不应居中收缩',
    );
    expect(find.text('规划'), findsOneWidget);
    expect(find.text('待办'), findsNothing);
    expect(find.text('计划'), findsNothing);
    expect(find.text('42 词元/秒'), findsOneWidget);

    final l10n = AppLocalizations.of(tester.element(bar));
    final workflowLabel = '任务流程 · 规划 · ${l10n.modeDeletedUsingSnapshot}';
    final throughputLabel =
        '${l10n.statusLastConfirmedAgentTokenSpeed}: 42 词元/秒';
    expect(_tooltipWithMessage(workflowLabel), findsOneWidget);
    expect(_tooltipWithMessage(throughputLabel), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('workflow-status-pill')))
          .label,
      workflowLabel,
    );
    expect(
      tester.getSemantics(find.byType(TokenThroughputReadout)).label,
      throughputLabel,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('窄屏无布局溢出，水平滚动仍可访问末端项和完整辅助信息', (tester) async {
    tester.view.devicePixelRatio = 1;
    // The preview remains a 320 px reference scene. At 280 px, production
    // Todo, workflow, context, throughput, started-item and sidebar entries
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
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('workflow-status-pill')))
          .label,
      workflowLabel,
    );
    expect(
      tester.getSemantics(find.byType(TokenThroughputReadout)).label,
      throughputLabel,
    );
    expect(tester.takeException(), isNull);

    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final sidebarToggle = find.byKey(StudioDriverKeys.rightSidebarToggle);
    expect(sidebarToggle, findsOneWidget);
    expect(tester.getRect(sidebarToggle).right, lessThanOrEqualTo(280));
    final planEntry = find.byKey(StudioDriverKeys.statusPlanEntry);
    expect(planEntry, findsOneWidget);
    await tester.ensureVisible(planEntry);
    await tester.pumpAndSettle();
    await tester.tap(planEntry);
    await tester.pumpAndSettle();
    expect(openedPlan, isTrue, reason: '可滚动抵达的生产计划入口应调用所传回调');
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final (theme, fixture) in [
    ('亮色', threadStatusBarNarrowPreview),
    ('深色', threadStatusBarDarkPreview),
  ]) {
    testWidgets('$theme能力菜单在窄窗口打开且 Escape 关闭后恢复入口焦点', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 560);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(fixture());
      await tester.pumpAndSettle();
      final entry = find.byKey(StudioDriverKeys.statusStartedItems);
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('Dart & Flutter'), findsOneWidget);
      expect(find.text('rust-analyzer'), findsOneWidget);
      final service = find.byKey(StudioDriverKeys.mcpServerRow('browser'));
      final rect = tester.getRect(service);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Dart & Flutter'), findsNothing);
      expect(tester.widget<IconButton>(entry).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

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
