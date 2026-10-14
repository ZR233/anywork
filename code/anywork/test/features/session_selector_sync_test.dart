import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/data/commands/directory_commands.dart';
import 'package:anywork/src/data/frb/studio_api.dart';
import 'package:anywork/src/data/repositories/studio_api_provider.dart';
import 'package:anywork/src/data/stores/project_store.dart';
import 'package:anywork/src/data/stores/selection_store.dart';
import 'package:anywork/src/data/stores/settings_store.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/interaction/composer_view.dart';
import 'package:anywork/src/features/interaction/start_session_controller.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';

/// 用户可见症状的回归证据：主界面（起始页）的会话模式与思考强度选择器必须在不发生
/// 任何页面跳转的情况下显示新值，菜单行的选中态也必须随同一事实移动。
///
/// 起始页事实是 route 作用域草稿，经 [startPageComposerViewProvider] 组合显示：
/// 选中即所见，不依赖设置页往返，也不把草稿写回 settings canonical。真实 Rust
/// bridge 的语义由 `cargo xtask verify-gui` 与 `cargo xtask manual-gui` 覆盖。
///
/// 旧用例用 12 秒 pump 排空 app 级 topic 稳定性计时器。这里不取得 shell 租约，
/// 因此没有该计时器；`pumpAndSettle` 只等菜单关闭动画，不代替页面往返。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() async {
    final api = DemoStudioBridgeDataSource(lspActivityLoop: false);
    container = ProviderContainer(
      overrides: [studioBridgeDataSourceProvider.overrideWithValue(api)],
    );
    final snapshot = await api.readStudioState();
    container
        .read(settingsStoreProvider.notifier)
        .merge(snapshot.settingsState);
    container
        .read(projectStoreProvider.notifier)
        .applyProjectDirectory(snapshot.projectDirectory);
    container
        .read(selectionStoreProvider.notifier)
        .restoreStartup(
          projectId: snapshot.selectedProjectId,
          threadId: snapshot.selectedThreadId,
          needsOpen: snapshot.selectedThreadId != null,
        );
    await container.read(directoryCommandsProvider.notifier).beginNewThread();
    final selection = container.read(selectionStoreProvider);
    expect(selection.selectedProjectId, isNotNull);
    expect(selection.selectedThreadId, isNull, reason: '起始页草稿不绑定已有会话');
    expect(
      container.read(settingsStoreProvider).canonical?.modeModelRoutes,
      isNotEmpty,
    );
  });

  tearDown(() {
    container.dispose();
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

    expect(
      find.byType(MenuItemButton),
      findsNothing,
      reason: '选择菜单项后官方菜单必须关闭',
    );
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

    expect(
      find.byType(MenuItemButton),
      findsNothing,
      reason: '选择菜单项后官方菜单必须关闭',
    );
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

    expect(
      find.byType(MenuItemButton),
      findsNothing,
      reason: '选择模型后官方菜单必须关闭',
    );
    expect(find.text(next.displayName), findsOneWidget);
    expect(find.text(before), findsNothing);
    final after = container
        .read(startPageComposerViewProvider)
        .displayRoute(initial.mode);
    expect(after?.providerId, next.providerId);
    expect(after?.model, next.model);

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(selectedRow(nextKey), findsOneWidget, reason: '模型选中态必须随草稿事实移动');
  });
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
        ref
            .read(startSessionControllerProvider.notifier)
            .setMode(projectId, mode);
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
            .read(startSessionControllerProvider.notifier)
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
    return ModelRoleSelector(
      providers: page.providers,
      providerId: route.providerId,
      model: route.model,
      effort: route.effort,
      onModelSelected: (providerId, model) {
        ref
            .read(startSessionControllerProvider.notifier)
            .setModelIntent(page.mode, providerId, model);
      },
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
