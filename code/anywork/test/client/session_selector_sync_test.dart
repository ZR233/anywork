import 'dart:async';

import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/conversation/presentation/model_route_presentation.dart';
import 'package:anywork/src/features/conversation/view_models/conversation_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/thread_status_view_model.dart';
import 'package:anywork/src/features/interaction/connectors/conversation_input_connector.dart';
import 'package:anywork/src/features/interaction/connectors/start_input_connector.dart';
import 'package:anywork/src/features/status/status.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';
import 'package:anywork/src/features/interaction/views/input_model_controls_view.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart' show StopExecutionReply;
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/configuration_start_fixture.dart'
    show ConfigurationStartResolve;
import 'support/pump_client_future.dart';
import 'support/selector_command_reply.dart';
import 'support/selector_configuration_port.dart';
import 'support/selector_conversation_port.dart';
import 'support/selector_environment.dart';

/// Production Smart connectors + generated VMs + real domain owners. Only
/// native material/receipts are scripted; no widget owns a canonical copy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SelectorEnvironment env;

  setUp(() {
    env = SelectorEnvironment();
  });
  Future<void> initialize(WidgetTester tester) async {
    await tester.runAsync(() async {
      await env.establish();
      await env.selectStart();
    });
    expect(env.workspace.state.value.selection.projectId, 'project');
    expect(
      env.workspace.state.value.selection.threadId,
      isNull,
      reason: '起始页草稿不绑定已有会话',
    );
    expect(
      env.configuration.state.value.modeRoutes,
      isA<ReadyReadValue<List<ModeModelRoute>, ConfigurationReadRef>>(),
    );
  }

  tearDown(() => env.close());

  Widget harness(Widget child) => UncontrolledProviderScope(
    container: env.container,
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(child: SizedBox(width: 760, child: child)),
      ),
    ),
  );

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(tester, env.close(), 'selector owners close');
  }

  Finder selectedRow(Key itemKey) => find.descendant(
    of: find.byKey(itemKey),
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.selected == true,
    ),
  );
  Finder trigger(Key key) =>
      find.descendant(of: find.byKey(key), matching: find.byType(TextButton));
  StartDraftState start() => env.drafts.start('project').state.value;
  ModelSelection prepared() {
    final preparation = start().routePreparation;
    expect(
      preparation,
      isA<ReadyStartRoutePreparation>(),
      reason:
          'Native route calls: ${[
            for (final opening in env.configurationPort.opens) [for (final call in opening.native?.calls ?? []) '${call.query.runtimeType}:completed=${call.reply.isCompleted}'],
          ]}',
    );
    return (preparation as ReadyStartRoutePreparation).result.route;
  }

  Future<void> settleStart(WidgetTester tester, ModelSelection route) async {
    await pumpClientFuture(
      tester,
      env.prepareStart(route: route),
      'original native Start query',
    );
    await tester.pumpAndSettle();
    // The visible reader can request the normalized intent after a model
    // suggestion. Complete that actual second native read, rather than calling
    // prepareRoute() again and introducing another test-owned read intent.
    // At most the already-queued suggestion and its normalized resolve remain;
    // these are distinct native queries, not retries or business resubmission.
    for (
      var nativeStage = 0;
      nativeStage < 2 &&
          start().routePreparation is LoadingStartRoutePreparation;
      nativeStage++
    ) {
      final opening = env.configurationPort.opens.last;
      final pin = opening.native!;
      final pending =
          pin.calls.where((call) => !call.reply.isCompleted).firstOrNull ??
          await pumpClientFuture<ConfigurationStartResolve>(
            tester,
            pin.called(pin.calls.length),
            'visible normalized route query',
          );
      final query = pending.query;
      pending.reply.complete(
        StartRouteRead.ready(
          sources: opening.sources,
          query: query,
          intent: query is SelectModelStartRouteQuery
              ? query.intent.copyWith(
                  model: query.selected,
                  effort: route.effort,
                )
              : query.intent,
          route: route,
          defaults: selectorDefaults,
        ),
      );
      await pumpClientUntil(
        tester,
        () =>
            start().routePreparation is ReadyStartRoutePreparation ||
            pin.calls.any((call) => !call.reply.isCompleted),
        'next visible native route stage',
      );
      await tester.pumpAndSettle();
    }
    await pumpClientUntil(
      tester,
      () => start().routePreparation is ReadyStartRoutePreparation,
      'visible normalized route material',
    );
  }

  Future<void> mountStart(WidgetTester tester) async {
    await tester.pumpWidget(
      harness(const StartInputConnector(projectId: 'project')),
    );
    await settleStart(tester, selectorInitialRoute);
  }

  testWidgets('切换会话模式后触发器与菜单选中态立即更新，无需页面往返', (tester) async {
    await initialize(tester);
    final simpleKey = StudioDriverKeys.sessionModeOption(
      ThreadModeId.simple.id,
    );
    final taskKey = StudioDriverKeys.sessionModeOption(ThreadModeId.task.id);
    await mountStart(tester);
    expect(find.text('简洁'), findsOneWidget);
    expect(find.text('任务'), findsNothing);
    await tester.tap(find.byKey(StudioDriverKeys.sessionMode));
    await tester.pumpAndSettle();
    expect(selectedRow(simpleKey), findsOneWidget);
    expect(selectedRow(taskKey), findsNothing);
    await tester.tap(find.byKey(taskKey));
    await settleStart(tester, selectorInitialRoute);
    expect(find.byType(MenuItemButton), findsNothing, reason: '选择菜单项后官方菜单必须关闭');
    expect(
      tester
          .widget<TextButton>(trigger(StudioDriverKeys.sessionMode))
          .focusNode
          ?.hasPrimaryFocus,
      isTrue,
      reason: '焦点必须回到官方 TextButton 触发器',
    );
    expect(find.text('任务'), findsOneWidget);
    expect(find.text('简洁'), findsNothing);
    expect(start().mode, ThreadModeId.task, reason: '触发器与逻辑草稿是同一事实');
    await tester.tap(find.byKey(StudioDriverKeys.sessionMode));
    await tester.pumpAndSettle();
    expect(selectedRow(taskKey), findsOneWidget);
    expect(selectedRow(simpleKey), findsNothing);
    await finish(tester);
  });

  testWidgets('修改思考强度后选择器立即显示新值，无需页面往返', (tester) async {
    await initialize(tester);
    await mountStart(tester);
    final before = prepared().effort;
    expect(before, isNotNull);
    expect(find.text(before!), findsOneWidget);
    const next = 'high';
    final catalog = env.container
        .read(selectorCatalogViewModelProvider)
        .requireValue;
    final model = selectedDescriptor(catalog.models, 'account-0', 'text');
    expect(model, isNotNull);
    expect(model!.reasoning!.candidates, contains(next));
    await tester.tap(find.byKey(StudioDriverKeys.reasoningEffort));
    await tester.pumpAndSettle();
    expect(
      selectedRow(StudioDriverKeys.reasoningEffortOption(before)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(StudioDriverKeys.reasoningEffortOption(next)));
    await tester.pump();
    await tester.pump();
    final disabledDuringRead =
        tester
            .widget<TextButton>(trigger(StudioDriverKeys.reasoningEffort))
            .onPressed ==
        null;
    await settleStart(tester, selectorInitialRoute.copyWith(effort: next));
    expect(find.byType(MenuItemButton), findsNothing);
    expect(
      tester
          .widget<TextButton>(trigger(StudioDriverKeys.reasoningEffort))
          .focusNode
          ?.hasPrimaryFocus,
      isTrue,
      reason:
          'The official trigger must regain focus; disabled during native read=$disabledDuringRead',
    );
    expect(env.drafts.startRoutes.value.efforts[ThreadModeId.simple.id], next);
    expect(prepared().effort, next);
    expect(find.text(next), findsOneWidget);
    expect(find.text(before), findsNothing);
    await tester.tap(find.byKey(StudioDriverKeys.reasoningEffort));
    await tester.pumpAndSettle();
    expect(
      selectedRow(StudioDriverKeys.reasoningEffortOption(next)),
      findsOneWidget,
    );
    expect(
      selectedRow(StudioDriverKeys.reasoningEffortOption(before)),
      findsNothing,
    );
    await finish(tester);
  });

  testWidgets('切换模型后触发器与菜单选中态立即更新，无需页面往返', (tester) async {
    await initialize(tester);
    final initial = prepared();
    final catalog = env.container
        .read(selectorCatalogViewModelProvider)
        .requireValue;
    final options = selectorModels(catalog);
    expect(options.length, greaterThan(1));
    final current = options.firstWhere(
      (item) => item.accountId == initial.model.accountId,
    );
    final next = options.firstWhere(
      (item) => item.accountId != initial.model.accountId,
    );
    await mountStart(tester);
    expect(find.text(current.displayName), findsOneWidget);
    final modelTrigger = find.byKey(StudioDriverKeys.model);
    final nextKey = StudioDriverKeys.modelOption(next.accountId, next.modelId);
    await tester.tap(modelTrigger);
    await tester.pumpAndSettle();
    expect(selectedRow(nextKey), findsNothing);
    await tester.tap(find.byKey(nextKey));
    final target = ModelSelection(
      model: AccountModelKey(accountId: next.accountId, modelId: next.modelId),
      effort: 'high',
    );
    await settleStart(tester, target);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.text(next.displayName), findsOneWidget);
    expect(find.text(current.displayName), findsNothing);
    expect(prepared().model.accountId, next.accountId);
    expect(prepared().model.modelId, next.modelId);
    expect(prepared().effort, 'high', reason: 'native 归一化结果不能丢失或被本地猜测替代');
    expect(find.text('缺失（不可用）'), findsNothing);
    expect(find.text('high'), findsOneWidget);
    await tester.tap(modelTrigger);
    await tester.pumpAndSettle();
    expect(selectedRow(nextKey), findsOneWidget);
    await finish(tester);
  });

  testWidgets('未打开项目时输入禁用，模型和强度仍能先选；Mode锁定有可见原因', (tester) async {
    await initialize(tester);
    env.workspace.restoreSelection(const WorkspaceSelection(projectId: null, threadId: null, needsOpen: false));
    await tester.pumpWidget(harness(const StartInputConnector(projectId: null)));
    await tester.pump();
    final input = tester.widget<TextField>(find.byKey(StudioDriverKeys.composerInput));
    expect(input.enabled, isFalse, reason: '未打开项目不能发送');
    final controls = tester.widget<InputModelControlsView>(find.byType(InputModelControlsView));
    final next = controls.models.firstWhere((option) => (option.descriptor.reasoning?.candidates.length ?? 0) > 1);
    final modelTrigger = trigger(StudioDriverKeys.model);
    expect(tester.widget<TextButton>(modelTrigger).onPressed, isNotNull, reason: '保留main：选项目之前可先选模型');
    await tester.tap(modelTrigger);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StudioDriverKeys.modelOption(next.accountId, next.modelId)));
    await tester.pumpAndSettle();
    final selected = tester.widget<InputModelControlsView>(find.byType(InputModelControlsView));
    expect((selected.accountId, selected.modelId), (next.accountId, next.modelId));
    final effort = next.descriptor.reasoning!.candidates.firstWhere((effort) => effort != selected.effort);
    await tester.tap(trigger(StudioDriverKeys.reasoningEffort));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StudioDriverKeys.reasoningEffortOption(effort)));
    await tester.pumpAndSettle();
    expect(tester.widget<InputModelControlsView>(find.byType(InputModelControlsView)).effort, effort);
    expect(tester.widget<TextField>(find.byKey(StudioDriverKeys.composerInput)).enabled, isFalse);
    final mode = trigger(StudioDriverKeys.sessionMode);
    expect(tester.widget<TextButton>(mode).onPressed, isNotNull);
    await tester.tap(mode);
    await tester.pumpAndSettle();
    expect(find.text(tester.element(mode).l10n.statusModeNeedsProject), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.sessionModeOption(ThreadModeId.simple.name)), findsNothing);
    expect(find.byKey(StudioDriverKeys.sessionWorkspaceMode), findsNothing);
    expect(find.byKey(StudioDriverKeys.sessionSettings), findsNothing);
    await finish(tester);
  });

  testWidgets('选择器锁定点击有可见原因且不打开菜单', (tester) async {
    await initialize(tester);
    String? explanation;
    await tester.pumpWidget(harness(StatefulBuilder(builder: (context, update) => InputModelControlsView(
      modes: const [], models: const [], efforts: const [], mode: ThreadModeId.simple,
      workspaceMode: ThreadWorkspaceMode.local, accountId: '', modelId: '', effort: null,
      enabled: false, showWorkspace: false, blockedReason: context.l10n.statusSelectorsNotReady,
      explanation: explanation, onExplain: (reason) => update(() => explanation = reason),
    ))));
    await tester.pump();
    final model = trigger(StudioDriverKeys.model);
    expect(tester.widget<TextButton>(model).onPressed, isNotNull);
    await tester.tap(model);
    await tester.pump();
    expect(find.byKey(const ValueKey('input-model-explanation')), findsOneWidget);
    expect(find.text(tester.element(model).l10n.statusSelectorsNotReady), findsOneWidget);
    await finish(tester);
  });

  testWidgets('打开项目后原生输入框与工作区选择都更新新会话草稿', (tester) async {
    await initialize(tester);
    await mountStart(tester);
    final input = find.byKey(StudioDriverKeys.composerInput);
    expect(tester.widget<TextField>(input).enabled, isTrue);
    await tester.tap(input);
    await tester.enterText(input, '新会话正文');
    await tester.pumpAndSettle();
    expect(start().text, '新会话正文');
    expect(
      tester
          .widget<IconButton>(find.byKey(StudioDriverKeys.sessionSettings))
          .onPressed,
      isNotNull,
      reason: '真实 catalog/material 必须交付后才能编辑',
    );
    // Workspace is now its own official selector in InputModelControlsView.
    await tester.tap(find.byKey(StudioDriverKeys.sessionWorkspaceMode));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        StudioDriverKeys.sessionWorkspaceModeOption(
          ThreadWorkspaceMode.worktree.name,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(start().workspaceMode, ThreadWorkspaceMode.worktree);
    await finish(tester);
  });

  testWidgets(
    'composer keeps Shift+Enter editing and official Enter submission',
    (tester) async {
      await initialize(tester);
      await mountStart(tester);
      final input = find.byKey(StudioDriverKeys.composerInput);
      await tester.tap(input);
      await tester.enterText(input, '第一行');
      await tester.pump();
      Future<void> shiftEnter(TextEditingValue nativeEdit) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        expect(
          await tester.sendKeyEvent(LogicalKeyboardKey.enter),
          isFalse,
          reason: 'Shift+Enter must remain delegated to the native multiline editor',
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        tester.testTextInput.updateEditingValue(nativeEdit);
        await tester.testTextInput.receiveAction(TextInputAction.newline);
        await tester.pump();
      }

      await shiftEnter(
        const TextEditingValue(
          text: '第一行\n',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      expect(start().submission, isA<IdleDraftSubmission>());
      expect(tester.widget<TextField>(input).controller!.text, '第一行\n');
      final controller = tester.widget<TextField>(input).controller!;
      final beforeSelection = controller.text;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      await shiftEnter(
        const TextEditingValue(
          text: '\n\n',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      expect(controller.text, '\n${beforeSelection.substring(3)}');
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
      expect(start().submission, isA<IdleDraftSubmission>());
      await tester.enterText(input, '最后一行');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(
        start().submission,
        isA<SubmittingDraft>(),
        reason: 'Enter 与发送按钮共用同一提交入口',
      );
      expect(env.creations.begins.values, hasLength(1));
      await finish(tester);
    },
  );

  group('已建根会话：Turn 空闲后 workflow active 不再阻塞模型路由切换', () {
    const threadId = 'thread-main';
    Future<void> openScenario(
      WidgetTester tester, {
      ThreadStatus status = ThreadStatus.idle,
    }) async {
      await initialize(tester);
      env.conversationPort.initialStatus = status;
      env.conversationPort.activeWorkflow = true;
      await pumpClientFuture(tester, env.selectThread(threadId), 'select root');
      await tester.pumpWidget(
        harness(const _LiveInputHost(threadId: threadId)),
      );
      await pumpClientUntil(
        tester,
        () =>
            env.container
                .read(threadStatusViewModelProvider(threadId))
                .value
                ?.configurationRead
                .header !=
            null,
        'original route material',
      );
      await tester.pumpAndSettle();
    }

    ConversationModelRouteProps props() => env.container
        .read(threadStatusViewModelProvider(threadId).notifier)
        .modelRouteProps(
          env.container
              .read(conversationViewModelProvider(threadId))
              .value
              ?.metadata,
        );
    ThreadModelRoute route() => props().route!;
    Object? run() => env.container
        .read(threadStatusViewModelProvider(threadId))
        .requireValue
        .workflowRead
        .header
        ?.currentRun
        ?.runId;
    bool pending() => env.operations.observations.records.value.any(
      (record) => record.isPending,
    );
    Future<void> changeModel(WidgetTester tester) async {
      final options = selectorModels(
        env.container.read(selectorCatalogViewModelProvider).requireValue,
      );
      final next = options.firstWhere(
        (item) => item.accountId != route().accountId,
      );
      final before = route();
      await tester.tap(find.byKey(StudioDriverKeys.model));
      await tester.pumpAndSettle();
      final key = StudioDriverKeys.modelOption(next.accountId, next.modelId);
      expect(find.byKey(key), findsOneWidget);
      await tester.tap(find.byKey(key));
      await tester.pump();
      final call = await pumpClientFuture(
        tester,
        env.commands.routes.at(env.commands.routes.values.length - 1),
        'native route command',
      );
      expect(call.routeRevision, before.revision);
      expect(call.settingsRevision, 1);
      expect(route(), before, reason: '命令不能乐观改写 canonical');
      final target = before.copyWith(
        accountId: next.accountId,
        modelId: next.modelId,
        effort: 'low',
        revision: before.revision + 1,
      );
      call.reply.complete(selectorRouteReply(call, target));
      await pumpClientFuture(
        tester,
        env.conversationPort.publishRoute(target),
        'route facet change',
      );
      await pumpClientUntil(
        tester,
        () => route().revision == target.revision && !pending(),
        'route convergence',
      );
      await tester.pumpAndSettle();
      expect(route().accountId, next.accountId);
      expect(route().modelId, next.modelId);
      expect(route().revision, before.revision + 1);
      expect(pending(), isFalse);
      expect(find.text(next.displayName), findsOneWidget);
    }

    testWidgets('运行中的根会话点击模型或强度选择器不打开菜单、不发命令', (tester) async {
      await openScenario(tester, status: ThreadStatus.running);
      final view = env.container
          .read(threadStatusViewModelProvider(threadId))
          .requireValue;
      expect(view.workflow?.lifecycle, WorkflowLifecycle.active);
      expect(view.execution?.value?.status, ThreadStatus.running);
      final revisionBefore = route().revision;
      await tester.tap(find.byKey(StudioDriverKeys.model));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      await tester.tap(find.byKey(StudioDriverKeys.reasoningEffort));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(
        find.text('会话正在执行或等待处理，暂时无法切换模型。请停止当前执行或等待完成后重试。'),
        findsOneWidget,
      );
      expect(route().revision, revisionBefore);
      expect(env.commands.routes.values, isEmpty);
      await finish(tester);
    });

    testWidgets('Turn 空闲且 workflow active：模型与强度可切换并经 canonical 收敛', (
      tester,
    ) async {
      await openScenario(tester);
      final initial = env.container
          .read(threadStatusViewModelProvider(threadId))
          .requireValue;
      expect(initial.workflow?.lifecycle, WorkflowLifecycle.active);
      expect(initial.execution?.value?.status, ThreadStatus.idle);
      final workflowRunBefore = run();
      expect(workflowRunBefore, isNotNull);
      expect(
        tester
            .widget<TextButton>(trigger(StudioDriverKeys.sessionMode))
            .onPressed,
        isNull,
        reason: 'Mode 仍冻结，不能跟随 live 模型编辑放开',
      );
      await changeModel(tester);
      expect(run(), workflowRunBefore);
      final settled = route();
      final descriptor = selectedDescriptor(
        env.models.state.value,
        settled.accountId,
        settled.modelId,
      )!;
      final targetEffort = descriptor.reasoning!.candidates
          .where((effort) => effort != settled.effort)
          .firstOrNull;
      expect(targetEffort, isNotNull);
      await tester.tap(find.byKey(StudioDriverKeys.reasoningEffort));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(StudioDriverKeys.reasoningEffortOption(targetEffort!)),
      );
      await tester.pump();
      final call = await pumpClientFuture(
        tester,
        env.commands.routes.at(1),
        'native effort command',
      );
      expect(route(), settled, reason: '只有 canonical feed 可改变显示值');
      final target = settled.copyWith(
        effort: targetEffort,
        revision: settled.revision + 1,
      );
      call.reply.complete(selectorRouteReply(call, target));
      await pumpClientFuture(
        tester,
        env.conversationPort.publishRoute(target),
        'effort facet',
      );
      await pumpClientUntil(
        tester,
        () => route().effort == targetEffort && !pending(),
        'effort convergence',
      );
      await tester.pumpAndSettle();
      expect(route().effort, targetEffort);
      expect(pending(), isFalse);
      expect(run(), workflowRunBefore, reason: '强度编辑不得重置 workflow run');
      await finish(tester);
    });

    testWidgets('提交后停止：Turn 终态收敛后仍可在 active workflow 上切换路由', (tester) async {
      await openScenario(tester);
      final input = find.byKey(StudioDriverKeys.composerInput);
      await tester.tap(input);
      await tester.enterText(input, '第一轮任务');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      final prompt = await pumpClientFuture(
        tester,
        env.commands.prompts.at(0),
        'prompt native dispatch',
      );
      prompt.reply.complete(
        SubmitPromptReceipt(
          threadId: threadId,
          inputId: prompt.input.inputId,
          cursor: 1,
          requestDigest: 'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        ),
      );
      await tester.pump();
      final acceptance = await pumpClientFuture(
        tester,
        env.commands.acceptances.at(0),
        'input acceptance',
      );
      acceptance.reply.complete(
        const InputAcceptanceEvidence(
          acceptedSequence: 1,
          disposition: PersistedInputDisposition.consumed,
          requestDigest: 'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        ),
      );
      const turnRef = TurnReadRef(entry: 40, revision: 1);
      final brief = TurnBrief(
        reference: turnRef,
        revision: 1,
        updatedAt: 1,
        state: const TurnBriefState.running(
          startedAt: 1,
          phase: TurnPhase.thinking,
        ),
      );
      env.conversationPort.turn = TurnReadHeader(
        scope: selectorScope(
          selectorFacet(ThreadFacet.execution, 2),
          'turn',
        ).copyWith(sourceRevision: turnRef.revision),
        inputId: ReadText.inline(text: prompt.input.inputId),
        id: const ReadText.inline(text: 'turn-1'),
        threadId: const ReadText.inline(text: threadId),
        revision: 1,
        updatedAt: 1,
        state: const TurnReadState.running(
          startedAt: 1,
          phase: TurnPhase.thinking,
        ),
      );
      final runningDelivery = env.conversationPort.publishExecution(
        selectorExecution(status: ThreadStatus.running, active: brief, execution: const AgentExecution(id: 'execution-1', phase: AgentExecutionPhase.running, turnId: 'turn-1')),
      );
      await tester.pumpAndSettle();
      final nativeExecution = env.conversations.active.value!.execution.value;
      expect(
        nativeExecution.sync.phase,
        FacetSyncPhase.ready,
        reason: 'running frame error=${nativeExecution.sync.error?.message}',
      );
      await pumpClientFuture(tester, runningDelivery, 'running Turn');
      await tester.pumpAndSettle();
      final execution = env.container
          .read(conversationViewModelProvider(threadId))
          .requireValue
          .execution;
      expect(
        env.container
            .read(conversationViewModelProvider(threadId))
            .requireValue
            .running,
        isTrue,
        reason:
            'execution phase=${execution?.sync.phase}; error=${execution?.sync.error?.message}; '
            'active=${execution?.value?.activeTurn?.state.runtimeType}; '
            'session phase=${env.conversations.active.value?.execution.value.sync.phase}; '
            'session error=${env.conversations.active.value?.execution.value.sync.error?.message}',
      );
      final stopButton = find.byKey(StudioDriverKeys.composerStop);
      expect(stopButton, findsOneWidget);
      await tester.tap(stopButton);
      await tester.pump();
      final interrupt = await pumpClientFuture(
        tester,
        env.commands.interrupts.at(0),
        'exact Turn stop',
      );
      interrupt.reply.complete(
        StopExecutionReply(
          threadId: threadId,
          executionId: interrupt.executionId,
          stopped: true,
          receipt: CommitReceipt(
            operationId: interrupt.operationId,
            disposition: CommitDisposition.applied,
            targets: const [],
            effect: EffectPoint.immediate,
            requiresIdentityObservation: true,
          ),
        ),
      );
      await tester.pump();
      expect(
        env.container
            .read(conversationViewModelProvider(threadId))
            .requireValue
            .running,
        isTrue,
        reason: 'ACK 不等于 canonical Turn 终态',
      );
      await pumpClientFuture(
        tester,
        env.conversationPort.publishExecution(
          selectorExecution(
            terminal: brief.copyWith(
              reference: turnRef.copyWith(revision: 2),
              revision: 2,
              state: const TurnBriefState.cancelled(
                startedAt: 1,
                requestedAt: 2,
                completedAt: 3,
                cause: TurnCancellationKind.userRequested,
              ),
            ),
          ),
        ),
        'terminal Turn',
      );
      await tester.pumpAndSettle();
      expect(
        env.container
            .read(conversationViewModelProvider(threadId))
            .requireValue
            .running,
        isFalse,
      );
      expect(
        env.container
            .read(threadStatusViewModelProvider(threadId))
            .requireValue
            .workflow
            ?.lifecycle,
        WorkflowLifecycle.active,
      );
      await changeModel(tester);
      expect(pending(), isFalse);
      expect(
        env.container
            .read(threadStatusViewModelProvider(threadId))
            .requireValue
            .workflow
            ?.lifecycle,
        WorkflowLifecycle.active,
      );
      await finish(tester);
    });
  });
}

class _LiveInputHost extends ConsumerStatefulWidget {
  const _LiveInputHost({required this.threadId});
  final String threadId;
  @override
  ConsumerState<_LiveInputHost> createState() => _LiveInputHostState();
}

class _LiveInputHostState extends ConsumerState<_LiveInputHost> {
  late final page = ConversationStopPage(isCurrent: () => mounted);
  @override
  void dispose() {
    page.retire();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = conversationViewModelProvider(widget.threadId);
    ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final stop = vm.captureStop(page);
    return ConversationInputConnector(
      threadId: widget.threadId,
      onStop: stop == null ? null : () => unawaited(stop()),
      stopState: vm.stopStateFor(page),
    );
  }
}
