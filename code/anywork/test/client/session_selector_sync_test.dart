import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/presentation/providers/selection_store.dart';
import 'package:anywork/src/presentation/providers/settings_store.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/interaction/composer_dock.dart';
import 'package:anywork/src/features/interaction/composer_view.dart';
import 'package:anywork/src/presentation/providers/start_session_controller.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart' show ModelRouteQueries;

/// 用户可见症状的回归证据：主界面（起始页）的会话模式与思考强度选择器必须在不发生
/// 任何页面跳转的情况下显示新值，菜单行的选中态也必须随同一事实移动。
///
/// 起始页事实是 Client 持有的逻辑草稿，经 [startPageComposerViewProvider] 组合显示：
/// 选中即所见，不依赖设置页往返，也不把草稿写回 settings canonical。真实 Rust
/// bridge/native 的语义另由 `cargo xtask manual-gui` 验收，不能由这里的 Demo 代替。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late AppGraph graph;

  setUp(() async {
    final api = DemoStudioTransport(lspActivityLoop: false);
    graph = AppGraph(transport: api, clientId: 'selector-test');
    container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph)],
    );
    await graph.client.bootstrap();
    await graph.client.directoryCommands.beginNewThread();
    final selection = container.read(selectionStoreProvider);
    expect(selection.selectedProjectId, isNotNull);
    expect(selection.selectedThreadId, isNull, reason: '起始页草稿不绑定已有会话');
    expect(
      container.read(settingsStoreProvider).canonical?.modeModelRoutes,
      isNotEmpty,
    );
  });

  tearDown(() async {
    container.dispose();
    await graph.close(deadline: DateTime.now().add(const Duration(seconds: 5)));
  });

  Widget harness(Widget child) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );

  /// 命中“被标记为选中”的菜单行：选中态由行自身的 `Semantics.selected` 表达，
  /// 而该 `Semantics` 位于行键（`KeyedSubtree`）之内。
  Finder selectedRow(Key itemKey) => find.descendant(
    of: find.byKey(itemKey),
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.selected == true,
    ),
  );

  testWidgets('切换会话模式后触发器与菜单选中态立即更新，无需页面往返', (tester) async {
    final simpleKey = StudioDriverKeys.sessionModeOption(
      ThreadModeId.simple.name,
    );
    final taskKey = StudioDriverKeys.sessionModeOption(ThreadModeId.task.name);

    await tester.pumpWidget(harness(const _ModeSelectorHost()));
    await tester.pumpAndSettle();

    expect(find.text('简洁'), findsOneWidget, reason: '起始页默认模式是 simple');
    expect(find.text('任务'), findsNothing);

    await tester.tap(find.byKey(StudioDriverKeys.sessionMode));
    await tester.pumpAndSettle();
    expect(selectedRow(simpleKey), findsOneWidget, reason: '打开菜单时当前模式行是选中行');
    expect(selectedRow(taskKey), findsNothing);

    await tester.tap(find.byKey(taskKey));
    await tester.pumpAndSettle();

    expect(find.byType(MenuItemButton), findsNothing, reason: '选择菜单项后官方菜单必须关闭');
    final modeTrigger = find.descendant(
      of: find.byKey(StudioDriverKeys.sessionMode),
      matching: find.byType(TextButton),
    );
    expect(
      tester.widget<TextButton>(modeTrigger).focusNode?.hasPrimaryFocus,
      isTrue,
      reason: '选择菜单项后焦点必须回到官方 TextButton 触发器',
    );

    expect(find.text('任务'), findsOneWidget, reason: '选中的模式必须立即出现在触发器上');
    expect(find.text('简洁'), findsNothing, reason: '旧模式不得残留');
    expect(
      container.read(startPageComposerViewProvider).mode,
      ThreadModeId.task,
      reason: '触发器与起始页草稿是同一事实，不能停在本地副本',
    );

    await tester.tap(find.byKey(StudioDriverKeys.sessionMode));
    await tester.pumpAndSettle();
    expect(selectedRow(taskKey), findsOneWidget, reason: '菜单选中态必须随草稿事实移动');
    expect(selectedRow(simpleKey), findsNothing, reason: '旧选中行不得保持深色选中态');
  });

  testWidgets('修改思考强度后选择器立即显示新值，无需页面往返', (tester) async {
    await tester.pumpWidget(harness(const _EffortSelectorHost()));
    await tester.pumpAndSettle();

    final before = _currentEffort(container);
    expect(before, isNotNull);
    expect(find.text(before!), findsOneWidget);

    final nextEffort = _otherEffort(container, before);
    expect(nextEffort, isNotNull, reason: '模型需要至少两个思考强度候选');

    await tester.tap(find.byKey(StudioDriverKeys.reasoningEffort));
    await tester.pumpAndSettle();
    expect(
      selectedRow(StudioDriverKeys.reasoningEffortOption(before)),
      findsOneWidget,
      reason: '打开菜单时当前强度行是选中行',
    );

    await tester.tap(
      find.byKey(StudioDriverKeys.reasoningEffortOption(nextEffort!)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MenuItemButton), findsNothing, reason: '选择菜单项后官方菜单必须关闭');
    final effortTrigger = find.descendant(
      of: find.byKey(StudioDriverKeys.reasoningEffort),
      matching: find.byType(TextButton),
    );
    expect(
      tester.widget<TextButton>(effortTrigger).focusNode?.hasPrimaryFocus,
      isTrue,
      reason: '选择菜单项后焦点必须回到官方 TextButton 触发器',
    );

    expect(
      _currentEffort(container),
      nextEffort,
      reason: '起始页显示值必须在没有任何页面跳转的情况下立即收敛到草稿',
    );
    expect(find.text(nextEffort), findsOneWidget, reason: '选择器必须显示新强度');
    expect(find.text(before), findsNothing, reason: '旧强度不得回落到触发器上');

    await tester.tap(find.byKey(StudioDriverKeys.reasoningEffort));
    await tester.pumpAndSettle();
    expect(
      selectedRow(StudioDriverKeys.reasoningEffortOption(nextEffort)),
      findsOneWidget,
      reason: '菜单选中态必须随草稿事实移动',
    );
    expect(
      selectedRow(StudioDriverKeys.reasoningEffortOption(before)),
      findsNothing,
      reason: '旧选中行不得保持深色选中态',
    );
  });

  testWidgets('切换模型后触发器与菜单选中态立即更新，无需页面往返', (tester) async {
    final initial = container.read(startPageComposerViewProvider);
    final route = initial.displayRoute(initial.mode);
    expect(route, isNotNull);
    final options = modelOptions(initial.providers);
    expect(options.length, greaterThan(1), reason: '模型目录需要至少两个候选');
    final current = options.firstWhere(
      (option) =>
          option.providerId == route!.providerId && option.model == route.model,
    );
    final next = options.firstWhere(
      (option) =>
          option.providerId != route!.providerId || option.model != route.model,
    );

    await tester.pumpWidget(harness(const _ModelSelectorHost()));
    await tester.pumpAndSettle();

    final trigger = find.byKey(StudioDriverKeys.model);
    final before = current.displayName;
    expect(find.text(before), findsOneWidget);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    final nextKey = StudioDriverKeys.modelOption(next.providerId, next.model);
    expect(selectedRow(nextKey), findsNothing);

    await tester.tap(find.byKey(nextKey));
    await tester.pumpAndSettle();

    expect(find.byType(MenuItemButton), findsNothing, reason: '选择模型后官方菜单必须关闭');
    expect(find.text(next.displayName), findsOneWidget);
    expect(find.text(before), findsNothing);
    final after = container
        .read(startPageComposerViewProvider)
        .displayRoute(initial.mode);
    expect(after?.providerId, next.providerId);
    expect(after?.model, next.model);
    final expectedEffort = ModelRouteQueries.effortAfterModelSelection(
      next.descriptor,
      null,
    );
    expect(expectedEffort, isNotNull, reason: 'next 模型需要可归一化的思考强度');
    expect(after?.effort, expectedEffort);
    expect(find.text('缺失（不可用）'), findsNothing);
    expect(
      find.text(expectedEffort!),
      findsOneWidget,
      reason: '思考强度必须立即显示新模型的归一化候选，而不是空值',
    );

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(selectedRow(nextKey), findsOneWidget, reason: '模型选中态必须随草稿事实移动');
  });

  testWidgets('未打开项目时输入与会话选择器按同一准入状态禁用', (tester) async {
    graph.client.selection.restoreStartup(
      projectId: null,
      threadId: null,
      needsOpen: false,
    );

    await tester.pumpWidget(harness(const StartPageComposerDock()));
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(
      find.byKey(StudioDriverKeys.composerInput),
    );
    expect(input.enabled, isFalse, reason: '未打开项目不能提交新会话');

    for (final key in [
      StudioDriverKeys.sessionMode,
      StudioDriverKeys.sessionWorkspaceMode,
      StudioDriverKeys.model,
    ]) {
      final trigger = find.descendant(
        of: find.byKey(key),
        matching: find.byType(TextButton),
      );
      expect(trigger, findsOneWidget, reason: '选择器仍应使用官方 TextButton');
      expect(
        tester.widget<TextButton>(trigger).onPressed,
        isNull,
        reason: '$key 必须反映未打开项目的禁用状态',
      );
    }
  });

  testWidgets('打开项目后原生输入框与工作区选择都更新新会话草稿', (tester) async {
    final projectId = container.read(selectionStoreProvider).selectedProjectId!;

    await tester.pumpWidget(harness(const StartPageComposerDock()));
    await tester.pumpAndSettle();

    final input = find.byKey(StudioDriverKeys.composerInput);
    expect(tester.widget<TextField>(input).enabled, isTrue);
    await tester.tap(input);
    await tester.enterText(input, '新会话正文');
    await tester.pumpAndSettle();
    expect(
      container.read(startSessionControllerProvider).forProject(projectId).text,
      '新会话正文',
    );

    final workspaceTrigger = tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(StudioDriverKeys.sessionWorkspaceMode),
        matching: find.byType(TextButton),
      ),
    );
    expect(
      workspaceTrigger.onPressed,
      isNotNull,
      reason:
          'Demo must deliver the canonical mode catalog to enable selectors',
    );
    await tester.tap(find.byKey(StudioDriverKeys.sessionWorkspaceMode));
    await tester.pumpAndSettle();
    final worktreeKey = StudioDriverKeys.sessionWorkspaceModeOption(
      ThreadWorkspaceMode.worktree.id,
    );
    await tester.tap(find.byKey(worktreeKey));
    await tester.pumpAndSettle();
    expect(
      container
          .read(startSessionControllerProvider)
          .forProject(projectId)
          .workspaceMode,
      ThreadWorkspaceMode.worktree,
    );
  });

  testWidgets(
    'composer uses Shift+Enter for editing and Enter for submission',
    (tester) async {
      await tester.pumpWidget(harness(const StartPageComposerDock()));
      await tester.pumpAndSettle();

      final input = find.byKey(StudioDriverKeys.composerInput);
      await tester.tap(input);
      await tester.enterText(input, '第一行\n第二行');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(
        container.read(anyworkClientProvider).startDraft.state.submitting,
        isFalse,
        reason:
            'Shift+Enter must remain an editing action, not submit the draft',
      );
      expect(
        tester.widget<TextField>(input).controller!.text,
        '第一行\n第二行',
        reason:
            'the widget test binding does not emulate the native newline path',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(
        container.read(anyworkClientProvider).startDraft.state.submitting,
        isTrue,
        reason:
            'an unmodified Enter must share the send button submission path',
      );
    },
  );
}

class _ModeSelectorHost extends ConsumerWidget {
  const _ModeSelectorHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(startPageComposerViewProvider);
    final projectId = page.project?.id;
    return SessionModeSelector(
      mode: page.mode,
      onSelected: (mode) {
        if (projectId == null) return;
        ref.read(anyworkClientProvider).startDraft.setMode(projectId, mode);
      },
    );
  }
}

class _EffortSelectorHost extends ConsumerWidget {
  const _EffortSelectorHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(startPageComposerViewProvider);
    final route = page.displayRoute(page.mode);
    if (route == null) return const SizedBox.shrink();
    return ReasoningEffortSelector(
      providers: page.providers,
      providerId: route.providerId,
      model: route.model,
      effort: route.effort,
      onEffortSelected: (effort) {
        ref
            .read(anyworkClientProvider)
            .startDraft
            .setEffortIntent(page.mode, effort);
      },
    );
  }
}

class _ModelSelectorHost extends ConsumerWidget {
  const _ModelSelectorHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(startPageComposerViewProvider);
    final route = page.displayRoute(page.mode);
    if (route == null) return const SizedBox.shrink();
    return Wrap(
      children: [
        ModelRoleSelector(
          providers: page.providers,
          providerId: route.providerId,
          model: route.model,
          effort: route.effort,
          onModelSelected: (providerId, model) {
            ref
                .read(anyworkClientProvider)
                .startDraft
                .setModelIntent(page.mode, providerId, model);
          },
        ),
        ReasoningEffortSelector(
          providers: page.providers,
          providerId: route.providerId,
          model: route.model,
          effort: route.effort,
          onEffortSelected: (effort) {
            ref
                .read(anyworkClientProvider)
                .startDraft
                .setEffortIntent(page.mode, effort);
          },
        ),
      ],
    );
  }
}

String? _currentEffort(ProviderContainer container) {
  final page = container.read(startPageComposerViewProvider);
  return page.displayRoute(page.mode)?.effort;
}

/// 当前显示路由模型声明的、与 [current] 不同的思考强度候选。
String? _otherEffort(ProviderContainer container, String current) {
  final page = container.read(startPageComposerViewProvider);
  final route = page.displayRoute(page.mode);
  if (route == null) return null;
  final model = modelForRoute(page.providers, route.providerId, route.model);
  return model?.reasoningEfforts
      .where((effort) => effort != current)
      .firstOrNull;
}
