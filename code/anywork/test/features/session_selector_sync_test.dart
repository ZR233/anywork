import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/data/frb/studio_api.dart';
import 'package:anywork/src/data/repositories/studio_repository.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';

/// 用户可见症状的回归证据：主界面（起始页）的会话模式与思考强度选择器必须在不发生
/// 任何页面跳转的情况下显示 canonical 新值，菜单行的选中态也必须随同一事实移动。
///
/// 这里渲染的是产品自身的 [SessionModeSelector] / [ReasoningEffortSelector]，canonical
/// 事实来自 demo bridge（与生产共用同一套 reducer/merge/投影路径），断言直接落在
/// "触发器文案 + 菜单选中态"上而不是中间状态字段上。真实 Rust bridge 的语义由 CI 的
/// `cargo xtask verify-gui` 与 `cargo xtask manual-gui` 人工验收覆盖。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late DemoStudioBridgeDataSource api;
  var disposed = false;

  setUp(() async {
    disposed = false;
    api = DemoStudioBridgeDataSource(lspActivityLoop: false);
    container = ProviderContainer(
      overrides: [studioBridgeDataSourceProvider.overrideWithValue(api)],
    );
    await container.read(studioControllerProvider.future);
    // 起始页草稿：模式选择器此时改的是"新会话草稿"，不经过任何路由。
    await container.read(studioControllerProvider.notifier).beginNewThread();
    expect(
      container.read(studioControllerProvider).value!.selectedThreadId,
      isNull,
    );
  });

  tearDown(() {
    if (!disposed) container.dispose();
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

  /// 结束一个用例：先推进 topic 稳定性窗口，再释放 controller。
  ///
  /// 这些计时器属于 app 级 topic 订阅（与 UI 行为无关），不推进完会让 `testWidgets`
  /// 因"仍有待处理计时器"判失败；释放必须放在推进之后，避免在已释放的容器上重建。
  Future<void> settleAndDispose(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 12));
    container.dispose();
    disposed = true;
  }

  /// 命中"被标记为选中"的菜单行：选中态由行自身的 `Semantics.selected` 表达，
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

    expect(find.text('任务'), findsOneWidget, reason: '选中的模式必须立即出现在触发器上');
    expect(find.text('简洁'), findsNothing, reason: '旧模式不得残留');

    // 再次打开菜单：选中态必须跟着新事实走（而不是停在旧的深色行）。
    await tester.tap(find.byKey(StudioDriverKeys.sessionMode));
    await tester.pumpAndSettle();
    expect(
      selectedRow(taskKey),
      findsOneWidget,
      reason: '菜单选中态必须随 canonical 事实移动',
    );
    expect(selectedRow(simpleKey), findsNothing, reason: '旧选中行不得保持深色选中态');

    await settleAndDispose(tester);
  });

  testWidgets('修改思考强度后选择器立即显示 canonical 新值，无需页面往返', (tester) async {
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
    await _settleBridgeWrite(
      tester,
      () => _currentEffort(container) == nextEffort,
    );

    expect(
      _currentEffort(container),
      nextEffort,
      reason: 'canonical route 必须在没有任何页面跳转的情况下收敛',
    );
    expect(
      find.text(nextEffort),
      findsOneWidget,
      reason: '选择器必须显示 canonical 新强度',
    );
    expect(find.text(before), findsNothing, reason: '旧强度不得回落到触发器上');

    await settleAndDispose(tester);
  });
}

class _ModeSelectorHost extends ConsumerWidget {
  const _ModeSelectorHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(startPageProvider).value!;
    return SessionModeSelector(
      mode: page.mode,
      onSelected: ref.read(studioControllerProvider.notifier).setNewThreadMode,
    );
  }
}

class _EffortSelectorHost extends ConsumerWidget {
  const _EffortSelectorHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(startPageProvider).value!;
    final route = modeRouteFor(page.modeModelRoutes, page.mode);
    if (route == null) return const SizedBox.shrink();
    return ReasoningEffortSelector(
      providers: page.providers,
      providerId: route.providerId,
      model: route.model,
      effort: route.effort,
      onEffortSelected: (effort) => ref
          .read(studioControllerProvider.notifier)
          .setModeReasoningEffortField(mode: page.mode, effort: effort),
    );
  }
}

String? _currentEffort(ProviderContainer container) {
  final page = container.read(startPageProvider).value;
  if (page == null) return null;
  return modeRouteFor(page.modeModelRoutes, page.mode)?.effort;
}

/// 当前路由模型声明的、与 [current] 不同的思考强度候选。
String? _otherEffort(ProviderContainer container, String current) {
  final page = container.read(startPageProvider).value;
  if (page == null) return null;
  final route = modeRouteFor(page.modeModelRoutes, page.mode);
  if (route == null) return null;
  final model = modelForRoute(page.providers, route.providerId, route.model);
  return model?.reasoningEfforts
      .where((effort) => effort != current)
      .firstOrNull;
}

/// 有界等待一次桥写入收敛。
///
/// 设置写入的 future 链要在**真实事件循环**里推进（`testWidgets` 的受控时钟只推进
/// fake async 的计时器），因此每次等待都经 `runAsync` 放行一小段真实时间，再 `pump`
/// 让 widget 重建；断言仍落在 canonical 值与真实渲染结果上。
Future<void> _settleBridgeWrite(
  WidgetTester tester,
  bool Function() done, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}
