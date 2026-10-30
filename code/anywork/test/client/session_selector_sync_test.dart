import 'support/mapped_conversation_feed.dart';

import 'package:anywork_client/conversation_ports.dart';

import 'support/test_statistics_feed.dart';

import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/presentation/providers/account_domains.dart';
import 'package:anywork/src/presentation/providers/selection_store.dart';
import 'package:anywork/src/presentation/providers/settings_store.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/conversation/composer/connectors/composer_dock_connector.dart';
import 'package:anywork/src/features/conversation/composer/view_models/composer_view_model.dart';
import 'package:anywork/src/presentation/providers/start_session_controller.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';

import 'support/pump_client_future.dart';

import 'package:anywork_client/studio_client.dart'
    show
        RecoveryIssueCategory,
        RecoveryIssueImpact,
        RecoveryIssueScope,
        RecoveryStateSnapshot,
        ModelRouteQueries,
        ProductTopicBaselineFrame,
        ProductTopicDataFrame,
        ProductTopicEventEnvelope,
        ProductTopicFrame,
        StudioBootstrap,
        ThreadDirectoryBaseline,
        ThreadDirectoryChangedPayload,
        ThreadDirectoryPage,
        ThreadDirectoryTopic,
        ThreadDirectoryWindow,
        ThreadRuntimeUpdate;

/// 用户可见症状的回归证据：主界面（起始页）的会话模式与思考强度选择器必须在不发生
/// 任何页面跳转的情况下显示新值，菜单行的选中态也必须随同一事实移动。
///
/// 起始页事实是 Client 持有的逻辑草稿，经 [startPageComposerViewModelProvider] 组合显示：
/// 选中即所见，不依赖设置页往返，也不把草稿写回 settings canonical。真实 Rust
/// bridge/native 的语义另由 `cargo xtask manual-gui` 验收，不能由这里的 Demo 代替。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late AppGraph graph;
  late DemoStudioTransport transport;
  late ProviderSubscription<Object?> modelsHold;
  var containerDisposed = false;
  var graphClosed = false;

  setUp(() async {
    transport = DemoStudioTransport(lspActivityLoop: false);
    containerDisposed = false;
    graphClosed = false;
    graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'selector-test',
    );
    container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph)],
    );
    await graph.client.bootstrap();
    await graph.client.directoryCommands.beginNewThread();
    modelsHold = container.listen(modelSelectionAccountsProvider, (_, _) {});
    await _waitForModelDirectory(graph);
    // Finish the real-zone provider baseline before testWidgets enters its
    // fake clock; otherwise an already queued rebuild blocks later UI updates.
    await container.pump();
    final selection = container.read(selectionStoreProvider);
    expect(selection.selectedProjectId, isNotNull);
    expect(selection.selectedThreadId, isNull, reason: '起始页草稿不绑定已有会话');
    expect(
      container.read(settingsStoreProvider).canonical?.modeModelRoutes,
      isNotEmpty,
    );
  });

  tearDown(() async {
    if (!containerDisposed) {
      modelsHold.close();
      container.dispose();
    }
    if (graphClosed) return;
    final report = await graph
        .close(deadline: DateTime.now().add(const Duration(seconds: 5)))
        .timeout(const Duration(seconds: 6));
    expect(
      report.complete,
      isTrue,
      reason: report.unresolved
          .map((value) => '${value.owner}: ${value.reason}')
          .join('; '),
    );
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

  Future<void> closeStartPageFixture(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    modelsHold.close();
    container.dispose();
    containerDisposed = true;
    await pumpClientFuture(
      tester,
      transport.beginRuntimeExit(remainingMs: 5000),
      'start-page demo business stop',
    );
    final report = await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'start-page selector fixture close',
    );
    expect(
      report.complete,
      isTrue,
      reason: report.unresolved
          .map((value) => '${value.owner}: ${value.reason}')
          .join('; '),
    );
    graphClosed = true;
  }

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
      container.read(startPageComposerViewModelProvider).requireValue.mode,
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
    final initial = container
        .read(startPageComposerViewModelProvider)
        .requireValue;
    final route = initial.displayRoute(initial.mode);
    expect(route, isNotNull);
    final options = modelOptions(initial.accounts);
    expect(options.length, greaterThan(1), reason: '模型目录需要至少两个候选');
    final current = options.firstWhere(
      (option) =>
          option.accountId == route!.accountId &&
          option.modelId == route.modelId,
    );
    final next = options.firstWhere(
      (option) =>
          option.accountId != route!.accountId ||
          option.modelId != route.modelId,
    );

    await tester.pumpWidget(harness(const _ModelSelectorHost()));
    await tester.pumpAndSettle();

    final trigger = find.byKey(StudioDriverKeys.model);
    final before = current.displayName;
    expect(find.text(before), findsOneWidget);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    final nextKey = StudioDriverKeys.modelOption(next.accountId, next.modelId);
    expect(selectedRow(nextKey), findsNothing);

    await tester.tap(find.byKey(nextKey));
    await tester.pumpAndSettle();

    expect(find.byType(MenuItemButton), findsNothing, reason: '选择模型后官方菜单必须关闭');
    expect(find.text(next.displayName), findsOneWidget);
    expect(find.text(before), findsNothing);
    final after = container
        .read(startPageComposerViewModelProvider)
        .requireValue
        .displayRoute(initial.mode);
    expect(after?.accountId, next.accountId);
    expect(after?.modelId, next.modelId);
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

  testWidgets('未打开项目时输入禁用，会话选择器仍可先定好草稿路由', (tester) async {
    await tester.runAsync(() async {
      // This is fixture setup, not a widget action. Retire the project topics
      // on the same real queue on which bootstrap opened them.
      graph.client.selection.restoreStartup(
        workspaceId: null,
        threadId: null,
        needsOpen: false,
      );
      await container.pump();
    });

    await tester.pumpWidget(harness(const StartPageComposerDockConnector()));
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(
      find.byKey(StudioDriverKeys.composerInput),
    );
    expect(input.enabled, isFalse, reason: '未打开项目不能提交新会话');

    final accounts = container.read(modelSelectionAccountsProvider);
    final before = container
        .read(startPageComposerViewModelProvider)
        .requireValue;
    final routeBefore = before.displayRoute(before.mode)!;
    // 选一个与当前路由不同、且带有多个强度候选的模型：证明选择真的落到草稿上。
    final candidates = modelOptions(accounts)
        .where(
          (option) =>
              option.accountId != routeBefore.accountId ||
              option.modelId != routeBefore.modelId,
        )
        .toList();
    final next = candidates.firstWhere(
      (option) => option.reasoningEfforts.length > 1,
      orElse: () => candidates.first,
    );

    final modelTrigger = find.descendant(
      of: find.byKey(StudioDriverKeys.model),
      matching: find.byType(TextButton),
    );
    expect(tester.widget<TextButton>(modelTrigger).onPressed, isNotNull);
    await tester.tap(modelTrigger);
    await tester.pumpAndSettle();
    final modelRow = find.byKey(
      StudioDriverKeys.modelOption(next.accountId, next.modelId),
    );
    expect(modelRow, findsOneWidget, reason: '模型与强度可以在选项目之前先定草稿路由');
    await tester.tap(modelRow);
    await tester.pumpAndSettle();

    final afterModel = container
        .read(startPageComposerViewModelProvider)
        .requireValue;
    final modelRoute = afterModel.displayRoute(afterModel.mode)!;
    expect(modelRoute.accountId, next.accountId, reason: '草稿路由真的换了账号');
    expect(modelRoute.modelId, next.modelId, reason: '草稿路由真的换了模型');
    expect(
      find.byKey(StudioDriverKeys.modelOption(next.accountId, next.modelId)),
      findsNothing,
      reason: '菜单必须真正收起，而不是只把标签改成同一个名字',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(StudioDriverKeys.composerInput))
          .enabled,
      isFalse,
      reason: '选了路由不等于能提交：没有项目仍然不能发送',
    );

    if (next.reasoningEfforts.length > 1) {
      final nextEffort = next.reasoningEfforts.firstWhere(
        (effort) => effort != modelRoute.effort,
        orElse: () => next.reasoningEfforts.last,
      );
      await tester.tap(find.byKey(StudioDriverKeys.reasoningEffort));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(StudioDriverKeys.reasoningEffortOption(nextEffort)),
      );
      await tester.pumpAndSettle();
      final afterEffort = container
          .read(startPageComposerViewModelProvider)
          .requireValue;
      expect(
        afterEffort.displayRoute(afterEffort.mode)!.effort,
        nextEffort,
        reason: '思考强度同样能在选项目之前定下来',
      );
    }

    // 会话模式按项目保存：没有项目就明确禁用并解释，绝不静默丢掉选择。
    final modeTrigger = find.descendant(
      of: find.byKey(StudioDriverKeys.sessionMode),
      matching: find.byType(TextButton),
    );
    expect(
      tester.widget<TextButton>(modeTrigger).onPressed,
      isNotNull,
      reason: '锁定也必须能解释',
    );
    await tester.tap(modeTrigger);
    await tester.pumpAndSettle();
    expect(
      find.text(
        tester
            .element(find.byKey(StudioDriverKeys.sessionMode))
            .l10n
            .statusModeNeedsProject,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(StudioDriverKeys.sessionModeOption(ThreadModeId.simple.name)),
      findsNothing,
      reason: '禁用状态下不展开菜单',
    );
    expect(
      find.byKey(StudioDriverKeys.sessionWorkspaceMode),
      findsNothing,
      reason:
          'Workspace is only inside session settings, not a duplicate shortcut',
    );
    expect(
      find.byKey(StudioDriverKeys.sessionSettings),
      findsNothing,
      reason: 'There is no project-scoped settings menu before a project is selected',
    );
  });

  testWidgets('选择器被锁定时点击给出可见原因，不静默吞掉点击', (tester) async {
    final accounts = container.read(modelSelectionAccountsProvider);
    final option = modelOptions(accounts).first;

    await tester.pumpWidget(
      harness(
        ModelRoleSelector(
          accounts: accounts,
          accountId: option.accountId,
          modelId: option.modelId,
          effort: null,
          enabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final trigger = find.descendant(
      of: find.byKey(StudioDriverKeys.model),
      matching: find.byType(TextButton),
    );
    expect(
      tester.widget<TextButton>(trigger).onPressed,
      isNotNull,
      reason: '被锁定也必须能解释，而不是吞掉点击',
    );

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    final reason = tester
        .element(find.byKey(StudioDriverKeys.model))
        .l10n
        .statusSelectorsNotReady;
    expect(find.text(reason), findsOneWidget);
  });

  testWidgets('打开项目后原生输入框与工作区选择都更新新会话草稿', (tester) async {
    final workspaceId = container.read(selectionStoreProvider).selectedProjectId!;

    await tester.pumpWidget(harness(const StartPageComposerDockConnector()));
    await tester.pumpAndSettle();

    final input = find.byKey(StudioDriverKeys.composerInput);
    expect(tester.widget<TextField>(input).enabled, isTrue);
    await tester.tap(input);
    await tester.enterText(input, '新会话正文');
    await tester.pumpAndSettle();
    expect(
      container.read(startSessionControllerProvider).forProject(workspaceId).text,
      '新会话正文',
    );

    final settingsTrigger = tester.widget<IconButton>(
      find.byKey(StudioDriverKeys.sessionSettings),
    );
    expect(
      settingsTrigger.onPressed,
      isNotNull,
      reason:
          'Demo must deliver the canonical mode catalog to enable selectors',
    );
    await tester.tap(find.byKey(StudioDriverKeys.sessionSettings));
    await tester.pumpAndSettle();
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
          .forProject(workspaceId)
          .workspaceMode,
      ThreadWorkspaceMode.worktree,
    );
  });

  testWidgets('起始页Recovery诊断完整可滚动且附件错误不被遮蔽', (tester) async {
    final workspaceId = container.read(selectionStoreProvider).selectedProjectId!;
    final current = graph.client.recovery.state.value;
    final detail = List.filled(12, '项目工作区需要检查').join('，');
    graph.client.recovery.apply(
      RecoveryStateSnapshot(
        revision: (current?.revision ?? 0) + 1,
        values: [
          StudioRecoveryIssue(
            id: 'start-project-recovery',
            scope: RecoveryIssueScope.project,
            category: RecoveryIssueCategory.repository,
            impact: RecoveryIssueImpact.executionBlocked,
            availableActions: const [],
            workspaceId: workspaceId,
            detail: detail,
          ),
        ],
      ),
    );

    await tester.pumpWidget(harness(const StartPageComposerDockConnector()));
    await tester.pumpAndSettle();

    final blocker = tester.widget<Text>(
      find.byKey(StudioDriverKeys.composerBlocker),
    );
    expect(blocker.data, contains('恢复问题 start-project-recovery'));
    expect(blocker.data, contains('项目 $workspaceId'));
    expect(blocker.data, contains('执行受阻，仍可读取安全的历史'));
    expect(blocker.data, contains(detail));
    expect(blocker.data, contains('可用恢复操作：当前无可用操作'));
    expect(blocker.maxLines, isNull);
    expect(blocker.overflow, isNull);

    final reasons = find.byKey(const ValueKey('composer-reasons'));
    expect(tester.getSize(reasons).height, lessThanOrEqualTo(84));
    final scrollable = find.descendant(
      of: reasons,
      matching: find.byType(Scrollable),
    );
    final scrollPosition = tester.state<ScrollableState>(scrollable).position;
    expect(scrollPosition.maxScrollExtent, greaterThan(0));
    await tester.drag(scrollable, const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(scrollPosition.pixels, greaterThan(0));

    graph.client.drafts.attachments.reportNewThreadFailure(
      workspaceId,
      StateError('Clipboard image could not be read during recovery'),
    );
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.composerError), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(StudioDriverKeys.composerError)).data,
      contains('Clipboard image could not be read during recovery'),
    );
  });

  testWidgets(
    'composer keeps Shift+Enter editing and official Enter submission',
    (tester) async {
      await tester.pumpWidget(harness(const StartPageComposerDockConnector()));
      await tester.pumpAndSettle();

      final input = find.byKey(StudioDriverKeys.composerInput);
      await tester.tap(input);
      await tester.enterText(input, '第一行');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(
        container
            .read(anyworkClientProvider)
            .drafts
            .startDraft
            .state
            .submitting,
        isFalse,
        reason:
            'Shift+Enter must remain an editing action, not submit the draft',
      );
      expect(
        tester.widget<TextField>(input).controller!.text,
        '第一行\n',
        reason: 'Shift+Enter inserts the line break through the local editing action',
      );

      // 标准编辑语义：Shift+Enter 用换行替换当前选区，光标落到换行之后。
      final controller = tester.widget<TextField>(input).controller!;
      final beforeSelection = controller.text;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        controller.text,
        '\n${beforeSelection.substring(3)}',
        reason: 'Shift+Enter 必须以换行替换选区，而不是保留选中文本再追加换行',
      );
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 1),
        reason: '插入后光标落在新行起点',
      );
      expect(
        container
            .read(anyworkClientProvider)
            .drafts
            .startDraft
            .state
            .submitting,
        isFalse,
        reason: '替换选区仍是编辑动作，不是提交',
      );
      await tester.enterText(input, '最后一行');
      await tester.pump();

      // The engine translates Enter into the field's text input action; sending
      // that action is the real Enter submission path shared with the button.
      // 模拟提交后仍可见的会话宿主：创建前没有选中会话，不会提前产生 feed。
      graph.setConversationPageVisible(true);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(
        container
            .read(anyworkClientProvider)
            .drafts
            .startDraft
            .state
            .submitting,
        isTrue,
        reason:
            'an unmodified Enter must share the send button submission path',
      );
      await pumpClientFuture(
        tester,
        graph.client.drafts.startDraft.source.waitFor(
          (state) => !state.submitting,
        ),
        'Enter submission terminal',
      );
      final createdThreadId = graph.client.selection.state.selectedThreadId!;
      await pumpClientFuture(
        tester,
        graph.client.conversations.session(createdThreadId).content.ready,
        'Enter submission observed through the visible conversation feed',
      );
      final created = await pumpClientFuture(
        tester,
        graph.client.threadDirectory.source.waitFor(
          (state) => state.window.threads.any(
            (thread) => thread.id == createdThreadId,
          ),
        ),
        'Enter submission canonical directory row',
      );
      final provisionalTitle = created.window.threads
          .firstWhere((thread) => thread.id == createdThreadId)
          .title;
      final titlePublished = graph.client.threadDirectory.source.waitFor(
        (state) => state.window.threads.any(
          (thread) =>
              thread.id == createdThreadId && thread.title != provisionalTitle,
        ),
      );
      // Drain Demo's 650ms title job through its actual directory publication;
      // stopping the runtime only cancels its separately tracked prompt jobs.
      await tester.pump(const Duration(milliseconds: 650));
      await pumpClientFuture(tester, titlePublished, 'demo title publication');
      await closeStartPageFixture(tester);
    },
  );

  group('已建根会话：Turn 空闲后 workflow active 不再阻塞模型路由切换', () {
    const threadId = 'thread-main';

    late _WorkflowScenarioTransport transport;
    late AppGraph graph;
    late ProviderContainer workflowContainer;
    late ProviderSubscription<Object?> composerHold;

    Future<void> openScenario({
      ThreadStatusView status = ThreadStatusView.idle,
    }) async {
      transport = _WorkflowScenarioTransport(threadStatus: status);
      graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'workflow-route-test',
      );
      workflowContainer = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      await graph.client.bootstrap();
      await (graph..setConversationPageVisible(true)).client.directoryCommands
          .selectThread(threadId);
      // ComposerDockConnector 只在 Client 已持有该会话草稿时渲染输入区。
      graph.client.drafts.composer(threadId);
      composerHold = workflowContainer.listen(
        composerDockViewModelProvider(threadId),
        (_, _) {},
      );
      await graph.client.conversations
          .session(threadId)
          .source
          .waitFor((state) => state.hasSnapshot);
      await _waitForModelDirectory(graph);
    }

    /// testWidgets 在测试体结束前检查未完成定时器：成功路径在这里关闭 owner。
    Future<void> closeScenario(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final report = await pumpClientFuture(
        tester,
        graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
        'workflow route scenario close',
      );
      expect(
        report.complete,
        isTrue,
        reason: report.unresolved
            .map((value) => '${value.owner}: ${value.reason}')
            .join('; '),
      );
      composerHold.close();
      workflowContainer.dispose();
    }

    Future<void> pumpDock(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: workflowContainer,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Center(child: ComposerDockConnector(threadId: threadId)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    int routeRevision() =>
        workflowContainer
            .read(composerDockViewModelProvider(threadId))
            .requireValue
            .modelRoute
            ?.revision ??
        -1;

    testWidgets('运行中的根会话点击模型或强度选择器不打开菜单、不发命令', (tester) async {
      await openScenario(status: ThreadStatusView.running);
      await pumpDock(tester);

      final view = workflowContainer
          .read(composerDockViewModelProvider(threadId))
          .requireValue;
      expect(view.hasActiveWorkflow, isTrue, reason: '场景前提：workflow active');
      expect(view.thread?.status, ThreadStatusView.running);
      final revisionBefore = routeRevision();

      await tester.tap(find.byKey(StudioDriverKeys.model));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing, reason: '运行中不得打开模型菜单');
      await tester.tap(find.byKey(StudioDriverKeys.reasoningEffort));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing, reason: '运行中不得打开强度菜单');
      expect(
        find.text('会话正在执行或等待处理，暂时无法切换模型。请停止当前执行或等待完成后重试。'),
        findsOneWidget,
        reason: '阻塞原因必须解释为运行中，而不是 workflow active',
      );
      expect(routeRevision(), revisionBefore, reason: '不得发出路由命令');
      await closeScenario(tester);
    });

    testWidgets('Turn 空闲且 workflow active：模型与强度可切换并经 canonical 收敛', (
      tester,
    ) async {
      await openScenario();
      await pumpDock(tester);

      final initial = workflowContainer
          .read(composerDockViewModelProvider(threadId))
          .requireValue;
      expect(initial.hasActiveWorkflow, isTrue);
      expect(initial.thread?.status, ThreadStatusView.idle);
      final workflowRunBefore = initial.workflow?.currentRun?.runId;
      expect(workflowRunBefore, isNotNull);

      final modeTrigger = tester.widget<TextButton>(
        find.descendant(
          of: find.byKey(StudioDriverKeys.sessionMode),
          matching: find.byType(TextButton),
        ),
      );
      expect(
        modeTrigger.onPressed,
        isNotNull,
        reason: '锁定不是静默：点击要给出原因，而不是什么都不发生',
      );
      await tester.tap(find.byKey(StudioDriverKeys.sessionMode));
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          StudioDriverKeys.sessionModeOption(ThreadModeId.simple.name),
        ),
        findsNothing,
        reason: 'workflow active 期间 Mode 仍冻结，不得随本次修复放开',
      );

      final options = modelOptions(initial.accounts);
      expect(options.length, greaterThan(1), reason: '模型目录需要至少两个候选');
      final route = initial.displayRoute!;
      final next = options.firstWhere(
        (option) =>
            option.accountId != route.accountId ||
            option.modelId != route.modelId,
      );
      final revisionBefore = routeRevision();

      await tester.tap(find.byKey(StudioDriverKeys.model));
      await tester.pumpAndSettle();
      final nextKey = StudioDriverKeys.modelOption(
        next.accountId,
        next.modelId,
      );
      expect(find.byKey(nextKey), findsOneWidget, reason: '空闲会话必须能打开模型菜单');
      await tester.tap(find.byKey(nextKey));
      await tester.pumpAndSettle();

      final settled = workflowContainer
          .read(composerDockViewModelProvider(threadId))
          .requireValue;
      expect(settled.modelRoute?.accountId, next.accountId);
      expect(settled.modelRoute?.modelId, next.modelId);
      expect(settled.modelRoute?.revision, revisionBefore + 1);
      expect(settled.routePending, isFalse, reason: '收敛后不得停在乐观目标值');
      expect(
        settled.workflow?.currentRun?.runId,
        workflowRunBefore,
        reason: '切换路由不得重置 workflow run',
      );
      expect(
        find.text(next.displayName),
        findsOneWidget,
        reason: '选择器必须显示收敛后的新模型',
      );

      final model = modelForRoute(
        settled.accounts,
        next.accountId,
        next.modelId,
      )!;
      final targetEffort = model.reasoningEfforts
          .where((effort) => effort != settled.modelRoute!.effort)
          .firstOrNull;
      expect(targetEffort, isNotNull, reason: '模型需要至少两个思考强度候选');

      await tester.tap(find.byKey(StudioDriverKeys.reasoningEffort));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(StudioDriverKeys.reasoningEffortOption(targetEffort!)),
      );
      await tester.pumpAndSettle();

      final afterEffort = workflowContainer
          .read(composerDockViewModelProvider(threadId))
          .requireValue;
      expect(afterEffort.modelRoute?.effort, targetEffort);
      expect(afterEffort.routePending, isFalse);
      expect(
        afterEffort.workflow?.currentRun?.runId,
        workflowRunBefore,
        reason: '调整强度同样不得重置 workflow run',
      );
      await closeScenario(tester);
    });

    testWidgets('提交后停止：Turn 终态收敛后仍可在 active workflow 上切换路由', (tester) async {
      await openScenario();
      await pumpDock(tester);

      final input = find.byKey(StudioDriverKeys.composerInput);
      await tester.tap(input);
      await tester.enterText(input, '第一轮任务');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      // 只推进到提交受理后、Demo Turn 完成脚本（120ms 起）之前，保持运行中可停止。
      await tester.pump(const Duration(milliseconds: 50));

      final running = workflowContainer
          .read(composerDockViewModelProvider(threadId))
          .requireValue;
      expect(running.isBusy, isTrue, reason: '提交受理后 Turn 进入运行态');
      final stopButton = find.byKey(StudioDriverKeys.composerStop);
      expect(stopButton, findsOneWidget, reason: '草稿清空后停止按钮必须出现');

      await tester.tap(stopButton);
      await tester.pumpAndSettle();

      final stopped = workflowContainer
          .read(composerDockViewModelProvider(threadId))
          .requireValue;
      expect(stopped.isBusy, isFalse, reason: '停止必须等到 canonical 终态，不是 ACK');
      expect(
        stopped.hasActiveWorkflow,
        isTrue,
        reason: '停止 Turn 不得结束 workflow',
      );

      final initial = workflowContainer
          .read(composerDockViewModelProvider(threadId))
          .requireValue;
      final options = modelOptions(initial.accounts);
      final route = initial.displayRoute!;
      final next = options.firstWhere(
        (option) =>
            option.accountId != route.accountId ||
            option.modelId != route.modelId,
      );
      await tester.tap(find.byKey(StudioDriverKeys.model));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(StudioDriverKeys.modelOption(next.accountId, next.modelId)),
      );
      await tester.pumpAndSettle();

      final settled = workflowContainer
          .read(composerDockViewModelProvider(threadId))
          .requireValue;
      expect(settled.modelRoute?.modelId, next.modelId);
      expect(settled.routePending, isFalse);
      expect(settled.hasActiveWorkflow, isTrue);
      await closeScenario(tester);
    });
  });
}

class _ModeSelectorHost extends ConsumerWidget {
  const _ModeSelectorHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(startPageComposerViewModelProvider).requireValue;
    final workspaceId = page.project?.id;
    return SessionModeSelector(
      mode: page.mode,
      onSelected: (mode) {
        if (workspaceId == null) return;
        ref
            .read(anyworkClientProvider)
            .drafts
            .startDraft
            .setMode(workspaceId, mode);
      },
    );
  }
}

class _EffortSelectorHost extends ConsumerWidget {
  const _EffortSelectorHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(startPageComposerViewModelProvider).requireValue;
    final route = page.displayRoute(page.mode);
    if (route == null) return const SizedBox.shrink();
    return ReasoningEffortSelector(
      accounts: page.accounts,
      accountId: route.accountId,
      modelId: route.modelId,
      effort: route.effort,
      onEffortSelected: (effort) {
        ref
            .read(anyworkClientProvider)
            .drafts
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
    final page = ref.watch(startPageComposerViewModelProvider).requireValue;
    final route = page.displayRoute(page.mode);
    if (route == null) return const SizedBox.shrink();
    return Wrap(
      children: [
        ModelRoleSelector(
          accounts: page.accounts,
          accountId: route.accountId,
          modelId: route.modelId,
          effort: route.effort,
          onModelSelected: (accountId, model) {
            ref
                .read(anyworkClientProvider)
                .drafts
                .startDraft
                .setModelIntent(page.mode, accountId, model);
          },
        ),
        ReasoningEffortSelector(
          accounts: page.accounts,
          accountId: route.accountId,
          modelId: route.modelId,
          effort: route.effort,
          onEffortSelected: (effort) {
            ref
                .read(anyworkClientProvider)
                .drafts
                .startDraft
                .setEffortIntent(page.mode, effort);
          },
        ),
      ],
    );
  }
}

String? _currentEffort(ProviderContainer container) {
  final page = container.read(startPageComposerViewModelProvider).requireValue;
  return page.displayRoute(page.mode)?.effort;
}

/// 当前显示路由模型声明的、与 [current] 不同的思考强度候选。
String? _otherEffort(ProviderContainer container, String current) {
  final page = container.read(startPageComposerViewModelProvider).requireValue;
  final route = page.displayRoute(page.mode);
  if (route == null) return null;
  final model = modelForRoute(page.accounts, route.accountId, route.modelId);
  return model?.reasoningEfforts
      .where((effort) => effort != current)
      .firstOrNull;
}

Future<void> _waitForModelDirectory(AppGraph graph) async {
  const limit = Duration(seconds: 5);
  await graph.accounts.state.waitFor((state) => state.loaded).timeout(limit);
  await graph.models.state
      .waitFor(
        (state) => state.accounts.values.any(
          (resource) =>
              resource.loaded && resource.value?.models.isNotEmpty == true,
        ),
      )
      .timeout(limit);
}

/// 已建根会话的 workflow 场景注入：Demo transport 不产生 workflow runtime，也不随
/// 提交推进 Thread 目录 status；这里只在 canonical 帧上补齐这两类环境事实（active
/// workflow run 与目录 status），命令、CAS 与帧收敛全部走真实 Demo transport 与
/// Client，不在测试内复刻任何业务判定。
class _WorkflowScenarioTransport extends DemoStudioTransport {
  _WorkflowScenarioTransport({this.threadStatus = ThreadStatusView.idle})
    : super(lspActivityLoop: false);

  final ThreadStatusView threadStatus;

  WorkflowRuntimeView _workflow(ThreadRuntimeView runtime) {
    return WorkflowRuntimeView(
      revision: runtime.workflow?.revision ?? 1,
      currentRun: WorkflowRunView(
        lineageId: 'demo-workflow-lineage',
        runId: 'demo-workflow-run',
        modeId: 'mode.task',
        graphRevision: 1,
        graphHash: 'demo-workflow-graph',
        currentStateId: 'implement',
        currentStateTitle: '实现',
        terminal: false,
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  }

  ThreadRuntimeView _runtime(ThreadRuntimeView runtime) =>
      runtime.copyWith(workflow: _workflow(runtime));

  StudioThread _thread(StudioThread thread) =>
      thread.id == 'thread-main' && thread.status != threadStatus
      ? thread.copyWith(status: threadStatus)
      : thread;

  /// Bootstrap 直接用返回的目录窗口初始化 store，不经 topic 流；这里同样注入
  /// thread-main 的目录 status，保证初始事实与后续增量一致。
  @override
  Future<StudioBootstrap> readBootstrap() async {
    final snapshot = await super.readBootstrap();
    return StudioBootstrap(
      ownerEpoch: snapshot.ownerEpoch,
      projectDirectory: snapshot.projectDirectory,
      threadDirectory: _window(snapshot.threadDirectory),
      agentDirectory: snapshot.agentDirectory,
      settingsState: snapshot.settingsState,
      recoveryState: snapshot.recoveryState,
      mcpState: snapshot.mcpState,
      lspState: snapshot.lspState,
      skillsByProject: snapshot.skillsByProject,
      threadModeCatalog: snapshot.threadModeCatalog,
      updaterState: snapshot.updaterState,
      persistenceState: snapshot.persistenceState,
      persistenceQueueState: snapshot.persistenceQueueState,
      agentProfilesState: snapshot.agentProfilesState,
      sessionCostsByRoot: snapshot.sessionCostsByRoot,
      selectedProjectId: snapshot.selectedProjectId,
      selectedThreadId: snapshot.selectedThreadId,
    );
  }

  ThreadDirectoryWindow _window(ThreadDirectoryWindow window) =>
      window.copyWith(
        threads: [for (final thread in window.threads) _thread(thread)],
      );

  @override
  Future<ConversationFeed> openConversationFeed(String threadId) async {
    return MappedConversationFeed(
      await super.openConversationFeed(threadId),
      (frame) => switch (frame) {
        ThreadSnapshotFrame(:final workspace) => ThreadSnapshotFrame(
          workspace: workspace.copyWith(runtime: _runtime(workspace.runtime)),
        ),
        ThreadNotificationFrame() => switch (frame.update) {
          ThreadRuntimeUpdate(:final runtime, :final todo) =>
            ThreadNotificationFrame(
              threadId: frame.threadId,
              revision: frame.revision,
              epoch: frame.epoch,
              baseRevision: frame.baseRevision,
              update: ThreadRuntimeUpdate(
                runtime: _runtime(runtime),
                todo: todo,
              ),
            ),
          _ => frame,
        },
        _ => frame,
      },
    );
  }

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) {
    final stream = super.subscribeProductTopic(topic);
    if (topic != const ThreadDirectoryTopic()) return stream;
    return stream.map(
      (frame) => switch (frame) {
        ProductTopicBaselineFrame() => switch (frame.state) {
          ThreadDirectoryBaseline(:final page) => ProductTopicBaselineFrame(
            topic: frame.topic,
            revision: frame.revision,
            state: ThreadDirectoryBaseline(_page(page)),
          ),
          _ => frame,
        },
        ProductTopicDataFrame() => switch (frame.event.payload) {
          ThreadDirectoryChangedPayload(
            :final revision,
            :final upserted,
            :final removed,
          ) =>
            ProductTopicDataFrame(
              topic: frame.topic,
              event: ProductTopicEventEnvelope(
                eventId: frame.event.eventId,
                sequence: frame.event.sequence,
                createdAt: frame.event.createdAt,
                payload: ThreadDirectoryChangedPayload(
                  revision: revision,
                  upserted: [for (final thread in upserted) _thread(thread)],
                  removed: removed,
                ),
              ),
            ),
          _ => frame,
        },
        _ => frame,
      },
    );
  }

  ThreadDirectoryPage _page(ThreadDirectoryPage page) => ThreadDirectoryPage(
    threads: [for (final thread in page.threads) _thread(thread)],
    nextCursor: page.nextCursor,
    revision: page.revision,
  );
}
