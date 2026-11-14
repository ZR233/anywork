import '../support/chat_fixtures.dart';

import 'dart:async';
import 'dart:convert';

import '../support/mapped_conversation_feed.dart';

import 'package:anywork_client/conversation_ports.dart';

import '../support/test_statistics_feed.dart';

import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/platform/clipboard_image_reader.dart';
import 'package:anywork/src/platform/external_url_launcher.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork/src/presentation/providers/account_domains.dart';
import 'package:anywork/src/presentation/providers/selection_store.dart';
import 'package:anywork/src/presentation/providers/settings_store.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/conversation/composer/composer.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_view_state.dart';
import 'package:anywork/src/features/conversation/composer/views/start_environment_bar.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/composer/views/start_environment_view.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_submission_body.dart';
import 'package:anywork/src/features/conversation/composer/view_models/composer_view_model.dart';
import 'package:anywork/src/presentation/providers/start_session_controller.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';

import '../support/pump_client_future.dart';

import 'package:anywork_client/studio_client.dart'
    show
        RecoveryIssueCategory,
        RecoveryIssueImpact,
        RecoveryIssueScope,
        RecoveryStateSnapshot,
        ModelRouteQueries,
        StudioBootstrap,
        ThreadDirectoryPage,
        ThreadMetadataFrame,
        ThreadObservationHandle,
        ThreadRuntimeUpdate;

/// 用户可见症状的回归证据：主界面（起始页）的会话模式与思考强度选择器必须在不发生
/// 任何页面跳转的情况下显示新值，菜单行的选中态也必须随同一事实移动。
///
/// 起始页事实是 Client 持有的逻辑草稿，经 [_startProjectionProvider] 组合显示：
/// 选中即所见，不依赖设置页往返，也不把草稿写回 settings canonical。真实 Rust
/// bridge/native 的语义另由 `cargo xtask manual-gui` 验收，不能由这里的 Demo 代替。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late AppGraph graph;
  late _ComposerStartTransport transport;
  late List<String> openedLinks;
  late _DelayedClipboardReader clipboardReader;
  late ProviderSubscription<Object?> modelsHold;
  var containerDisposed = false;
  var graphClosed = false;

  setUp(() async {
    transport = _ComposerStartTransport();
    openedLinks = [];
    clipboardReader = _DelayedClipboardReader();
    containerDisposed = false;
    graphClosed = false;
    graph = AppGraph(
      clipboardImageStager: _TestImageStager(),
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'selector-test',
    );
    container = ProviderContainer(
      overrides: [
        appGraphProvider.overrideWithValue(graph),
        clipboardImageReaderProvider.overrideWithValue(clipboardReader),
        externalUrlLauncherProvider.overrideWithValue((url) async {
          openedLinks.add(url);
        }),
      ],
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

  Widget harness(Widget child, {Locale locale = const Locale('zh')}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: pureStudioTheme(locale: locale),
          locale: locale,
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
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

  for (final language in ['zh', 'en']) {
    testWidgets('环境菜单本地化 $language：目标、工作区、分发与锁定说明使用当前语言', (tester) async {
      final locale = Locale(language);
      final l10n = await AppLocalizations.delegate.load(locale);
      final originalId = container
          .read(selectionStoreProvider)
          .selectedProjectId!;
      await tester.pumpWidget(
        harness(const _SelectedComposerHost(), locale: locale),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-project-selector')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('start-project-search')),
            )
            .decoration!
            .hintText,
        l10n.composerProjectSearch,
      );
      expect(find.text(l10n.composerNoProject), findsOneWidget);
      expect(find.text(l10n.composerNewProject), findsOneWidget);
      if (language == 'en') expect(find.text('无项目'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(StudioDriverKeys.sessionWorkspaceMode));
      await tester.pumpAndSettle();
      expect(find.text(l10n.composerWorktreeHint), findsOneWidget);
      expect(find.text(l10n.composerLocalDirectoryHint), findsOneWidget);
      await tester.tap(
        find.byKey(
          StudioDriverKeys.sessionWorkspaceModeOption(
            ThreadWorkspaceMode.worktree.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        graph.client.drafts.startDraft.state
            .forProject(originalId)
            .workspaceMode,
        ThreadWorkspaceMode.worktree,
      );

      await tester.tap(find.byKey(StudioDriverKeys.sessionSettings));
      await tester.pumpAndSettle();
      expect(find.text(l10n.delegationProfile), findsWidgets);
      expect(find.text(l10n.delegationOnlyAutomatic), findsOneWidget);
      expect(
        tester
            .widget<MenuItemButton>(
              find.byKey(
                StudioDriverKeys.delegationPreferenceOption(
                  'draft',
                  DelegationPreference.economy,
                ),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(SubmenuButton), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('start-project-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-project-standalone')));
      await pumpClientUntil(
        tester,
        () =>
            container.read(selectionStoreProvider).selectedProjectId !=
            originalId,
        'localized standalone target',
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.composerNoProject), findsOneWidget);
      expect(find.text(l10n.composerFixedLocalDirectory), findsOneWidget);

      await tester.pumpWidget(
        harness(
          _EnvironmentHost(
            workspaceId: container
                .read(selectionStoreProvider)
                .selectedProjectId,
            enabled: false,
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip(l10n.composerEnvironmentLocked), findsNWidgets(2));
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('start-project-selector')),
            )
            .onPressed,
        isNull,
      );

      await tester.pumpWidget(
        harness(
          const ReasoningEffortSelector(
            accounts: [],
            accountId: '',
            modelId: '',
            effort: null,
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsUsageUnsupported), findsOneWidget);
      expect(find.byTooltip(l10n.composerEffortUnsupported), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeStartPageFixture(tester);
    });
  }

  testWidgets('公开 Composer 目标独立于全局选择，切换后迟到粘贴不污染新目标', (tester) async {
    final firstId = container.read(selectionStoreProvider).selectedProjectId!;
    await pumpClientFuture(
      tester,
      graph.client.directoryCommands.beginStandaloneThread(),
      'prepare second target',
    );
    final secondId = container.read(selectionStoreProvider).selectedProjectId!;
    expect(secondId, isNot(firstId));
    final drafts = graph.client.drafts.startDraft;
    drafts.updateDraft(firstId, 'first draft');
    drafts.updateDraft(secondId, 'second draft');
    final reader = clipboardReader;
    Widget composerFor(String id) =>
        harness(Composer(target: ComposerTarget.start(workspaceId: id)));
    await tester.pumpWidget(composerFor(firstId));
    await tester.pumpAndSettle();
    final input = find.byKey(StudioDriverKeys.composerInput);
    expect(
      tester.widget<TextField>(input).controller!.text,
      'first draft',
      reason: '挂载目标与全局选中的第二个工作区不同',
    );
    await tester.enterText(input, 'first edited');
    await tester.pump();
    Actions.invoke(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .context!,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    expect(reader.calls, 1);
    await tester.pumpWidget(composerFor(secondId));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, 'second draft');
    reader.result.complete(null);
    await tester.pump();
    expect(
      tester.widget<TextField>(input).controller!.text,
      'second draft',
      reason: '旧 editor 的官方 paste 委托已经失效',
    );
    expect(drafts.state.forProject(firstId).text, 'first edited');
    expect(drafts.state.forProject(secondId).text, 'second draft');
    await closeStartPageFixture(tester);
  });

  testWidgets('图片粘贴进入本目标附件，保留文本和编辑焦点', (tester) async {
    final workspaceId = container
        .read(selectionStoreProvider)
        .selectedProjectId!;
    final accounts = container.read(modelSelectionAccountsProvider);
    final candidates = [
      for (final account in accounts)
        for (final model in account.models)
          if (model.enabled &&
              model.inputCapabilities.any(
                (capability) =>
                    capability.modality == ModelModalityView.image &&
                    capability.supportsSource(ModelInputSourceView.local),
              ))
            (accountId: account.id, modelId: model.modelId),
    ];
    expect(candidates, isNotEmpty, reason: 'Demo 真实目录必须提供可用图像模型');
    final candidate = candidates.first;
    final drafts = graph.client.drafts.startDraft;
    drafts.setModelIntent(
      drafts.state.forProject(workspaceId).mode,
      candidate.accountId,
      candidate.modelId,
    );
    final reader = clipboardReader;
    await tester.pumpWidget(
      harness(Composer(target: ComposerTarget.start(workspaceId: workspaceId))),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(StudioDriverKeys.composerInput);
    await tester.enterText(input, 'keep text');
    await tester.pump();
    Actions.invoke(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .context!,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    reader.result.complete(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=',
      ),
    );
    await pumpClientUntil(
      tester,
      () => graph.client.drafts.attachments.state
          .newThread(workspaceId)
          .attachments
          .isNotEmpty,
      'clipboard image admitted',
    );
    expect(
      graph.client.drafts.attachments.state
          .newThread(workspaceId)
          .attachments
          .single
          .modality,
      AttachmentModalityView.image,
    );
    expect(
      tester.widget<TextField>(input).controller!.text,
      'keep text',
      reason: '图片路径不委托文本粘贴、不重写编辑区',
    );
    expect(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .hasFocus,
      isTrue,
    );
    await closeStartPageFixture(tester);
  });

  testWidgets('失败项操作呈现 owner 的真实资格错误，未知结果不提供重发', (tester) async {
    final workspaceId = container
        .read(selectionStoreProvider)
        .selectedProjectId!;
    final target = ComposerTarget.start(workspaceId: workspaceId);
    graph.client.drafts.startDraft.updateDraft(
      workspaceId,
      'new editable draft',
    );
    final stale = ComposerSubmission(
      inputId: 'removed-input',
      text: 'old input',
      attachments: const [],
      phase: ComposerSubmissionPhase.failed,
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    await tester.pumpWidget(
      harness(ComposerSubmissionControls(target: target, submission: stale)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.composerRetrySubmission));
    await pumpClientUntil(
      tester,
      () => find.textContaining('not retryable').evaluate().isNotEmpty,
      'owner rejects stale failed item',
    );
    expect(
      graph.client.drafts.startDraft.state.forProject(workspaceId).text,
      'new editable draft',
      reason: '失败项动作不读取或清理当前编辑草稿',
    );
    await tester.pumpWidget(
      harness(
        ComposerSubmissionControls(
          target: target,
          submission: stale.withPhase(ComposerSubmissionPhase.unknownOutcome),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(l10n.composerRetrySubmission), findsNothing);
    expect(find.text(l10n.composerRemoveSubmission), findsNothing);
    await closeStartPageFixture(tester);
  });

  testWidgets('新建失败保留可复制正文，恢复仅重试原冻结设置或移除本项', (tester) async {
    transport.failPreparation = true;
    final workspaceId = container
        .read(selectionStoreProvider)
        .selectedProjectId!;
    final target = ComposerTarget.start(workspaceId: workspaceId);
    final owner = graph.client.drafts.startDraft;
    const code = '  final value = 1;';
    const source =
        '**冻结正文**\n\n```dart\n$code\n```\n\n'
        '[安全链接](https://fixture.invalid/guide)\n\n'
        '[危险链接](javascript:alert)\n\n'
        '![预览](https://fixture.invalid/image.png)';
    owner.setWorkspaceMode(workspaceId, ThreadWorkspaceMode.worktree);
    owner.updateDraft(workspaceId, source);
    expect(
      await pumpClientFuture(
        tester,
        owner.submit(workspaceId),
        'worktree preparation rejected',
      ),
      isFalse,
    );
    final firstInputId = owner.submissions.value[workspaceId]!.single.inputId;
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    await tester.pumpWidget(
      harness(SingleChildScrollView(child: Composer(target: target))),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('preparation-use-local-directory')),
      findsNothing,
    );
    expect(find.textContaining('worktree preparation failed'), findsWidgets);
    expect(find.text(l10n.composerRetrySubmission), findsOneWidget);
    expect(find.text(l10n.composerRemoveSubmission), findsOneWidget);
    expect(find.text(l10n.preparationRetainedBody), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(StudioDriverKeys.composerInput))
          .controller!
          .text,
      isEmpty,
    );

    final body = find.byType(ComposerSubmissionBody);
    expect(
      find.descendant(of: body, matching: find.byType(SelectionArea)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: body, matching: find.byType(Image)),
      findsNothing,
      reason: '未持内容资源资格的远程图不发起下载',
    );
    expect(openedLinks, isEmpty, reason: '显示回显不自动打开链接或图片');
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final selection = tester.state<SelectableRegionState>(
      find.descendant(of: body, matching: find.byType(SelectableRegion)),
    );
    selection.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    selection.contextMenuButtonItems
        .firstWhere((item) => item.type == ContextMenuButtonType.copy)
        .onPressed!();
    await tester.pump();
    expect(copied, contains('冻结正文'));
    expect(copied, contains(code), reason: '复用共用正文的代码缩进复制能力');
    expect(
      copied,
      isNot(contains(l10n.composerSubmissionFailed)),
      reason: '状态和正文保持独立，不混入复制内容',
    );
    await tester.ensureVisible(find.text('危险链接', findRichText: true));
    await tester.tap(find.text('危险链接', findRichText: true));
    await tester.pump();
    expect(openedLinks, isEmpty);
    await tester.ensureVisible(find.text('安全链接', findRichText: true));
    await tester.tap(find.text('安全链接', findRichText: true));
    await tester.pump();
    await tester.ensureVisible(find.text('https://fixture.invalid/image.png'));
    await tester.tap(find.text('https://fixture.invalid/image.png'));
    await tester.pump();
    expect(openedLinks, [
      'https://fixture.invalid/guide',
      'https://fixture.invalid/image.png',
    ], reason: '安全链接和图片仅显式交由 VM 打开，不在 Flutter 下载');

    owner.updateDraft(workspaceId, 'new independent draft');
    owner.setWorkspaceMode(workspaceId, ThreadWorkspaceMode.local);
    await tester.pump();
    await tester.ensureVisible(find.text(l10n.composerRetrySubmission));
    await tester.tap(find.text(l10n.composerRetrySubmission));
    await pumpClientUntil(tester, () {
      final item = owner.submissions.value[workspaceId]?.firstOrNull;
      return transport.failedWorkspaceModes.length == 2 &&
          item?.phase == ComposerSubmissionPhase.failed &&
          item?.inputId != firstInputId;
    }, 'retry retains frozen worktree');
    expect(transport.failedWorkspaceModes, ['worktree', 'worktree']);
    expect(transport.failedTexts, [source, source]);
    expect(owner.state.forProject(workspaceId).text, 'new independent draft');
    expect(
      owner.state.forProject(workspaceId).workspaceMode,
      ThreadWorkspaceMode.local,
    );
    await tester.ensureVisible(find.text(l10n.composerRemoveSubmission));
    await tester.tap(find.text(l10n.composerRemoveSubmission));
    await pumpClientUntil(
      tester,
      () => owner.submissions.value[workspaceId]?.isEmpty ?? true,
      'remove frozen failed input',
    );
    expect(owner.state.forProject(workspaceId).text, 'new independent draft');
    await closeStartPageFixture(tester);
  });

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
    expect(
      container.read(_startProjectionProvider).requireValue.mode,
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
    final initial = container.read(_startProjectionProvider).requireValue;
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
        .read(_startProjectionProvider)
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

  testWidgets('目标工作区尚未解析时输入禁用，路由选择仍可配置', (tester) async {
    const target = ComposerTarget.start(workspaceId: 'unresolved-workspace');
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

    await tester.pumpWidget(harness(const Composer(target: target)));
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(
      find.byKey(StudioDriverKeys.composerInput),
    );
    expect(input.enabled, isFalse, reason: '未打开项目不能提交新会话');

    final accounts = container.read(modelSelectionAccountsProvider);
    final before = container
        .read(composerViewModelProvider(target))
        .requireValue
        .start!;
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
        .read(composerViewModelProvider(target))
        .requireValue
        .start!;
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
          .read(composerViewModelProvider(target))
          .requireValue
          .start!;
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
    final workspaceId = container
        .read(selectionStoreProvider)
        .selectedProjectId!;

    await tester.pumpWidget(harness(const _SelectedComposerHost()));
    await tester.pumpAndSettle();

    final input = find.byKey(StudioDriverKeys.composerInput);
    expect(tester.widget<TextField>(input).enabled, isTrue);
    await tester.tap(input);
    await tester.enterText(input, '新会话正文');
    await tester.pumpAndSettle();
    expect(
      container
          .read(startSessionControllerProvider)
          .forProject(workspaceId)
          .text,
      '新会话正文',
    );

    final settingsTrigger = tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(StudioDriverKeys.sessionSettings),
        matching: find.byType(TextButton),
      ),
    );
    expect(
      settingsTrigger.onPressed,
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
          .forProject(workspaceId)
          .workspaceMode,
      ThreadWorkspaceMode.worktree,
    );

    // 创建栏是外层，输入状态机与运行期共用同一个组件。
    expect(find.byType(PromptComposerView), findsOneWidget);
    expect(find.byKey(const ValueKey('start-creation-card')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('start-creation-card'))).width,
      760,
    );
    await tester.tap(find.byKey(StudioDriverKeys.sessionSettings));
    await tester.pumpAndSettle();
    expect(find.byType(SubmenuButton), findsNothing);
    await tester.tap(
      find.byKey(
        StudioDriverKeys.delegationModeOption(
          'draft',
          DelegationMode.automatic,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StudioDriverKeys.sessionSettings));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        StudioDriverKeys.delegationPreferenceOption(
          'draft',
          DelegationPreference.economy,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final configured = container
        .read(startSessionControllerProvider)
        .forProject(workspaceId);
    expect(configured.delegationModeOverride, DelegationMode.automatic);
    expect(
      configured.delegationPreferenceOverride,
      DelegationPreference.economy,
    );
    expect(find.text('自动选模 · 经济'), findsOneWidget);
    await tester.tap(find.byKey(StudioDriverKeys.sessionSettings));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        StudioDriverKeys.delegationModeOption('draft', DelegationMode.profile),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StudioDriverKeys.sessionSettings));
    await tester.pumpAndSettle();
    final preference = tester.widget<MenuItemButton>(
      find.byKey(
        StudioDriverKeys.delegationPreferenceOption(
          'draft',
          DelegationPreference.economy,
        ),
      ),
    );
    expect(preference.onPressed, isNull);
    expect(
      container
          .read(startSessionControllerProvider)
          .forProject(workspaceId)
          .delegationPreferenceOverride,
      DelegationPreference.economy,
    );
  });

  testWidgets('创建栏切换项目与无项目时恢复各自草稿和配置，不迁移正文', (tester) async {
    final firstId = container.read(selectionStoreProvider).selectedProjectId!;
    graph.client.drafts.attachments.seedNewThreadIfEmpty(
      firstId,
      const ComposerThreadState.idle(
        attachments: [
          AttachmentDraftView(
            id: 'project-attachment',
            modality: AttachmentModalityView.file,
            mediaType: 'text/plain',
            filename: 'project-context.txt',
            byteSize: 12,
          ),
        ],
      ),
    );
    var addProjectCalls = 0;
    await tester.pumpWidget(
      harness(_SelectedComposerHost(onAddProject: () => addProjectCalls++)),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(StudioDriverKeys.composerInput);
    await tester.enterText(input, '项目自己的草稿');
    graph.client.drafts.startDraft.setWorkspaceMode(
      firstId,
      ThreadWorkspaceMode.worktree,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('start-project-selector')));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('start-project-search'));
    await tester.enterText(search, '不存在的项目');
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('start-project-$firstId')), findsNothing);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('start-project-$firstId')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('start-project-add')));
    await tester.pumpAndSettle();
    expect(addProjectCalls, 1);
    expect(container.read(selectionStoreProvider).selectedProjectId, firstId);
    expect(tester.widget<TextField>(input).controller!.text, '项目自己的草稿');
    await tester.tap(find.byKey(const ValueKey('start-project-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-project-standalone')));
    await pumpClientUntil(
      tester,
      () => container.read(selectionStoreProvider).selectedProjectId != firstId,
      'select standalone target',
    );
    await tester.pumpAndSettle();
    final standaloneId = container
        .read(selectionStoreProvider)
        .selectedProjectId!;
    expect(standaloneId, isNot(firstId));
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(find.text('project-context.txt'), findsNothing);
    expect(find.text('固定项目目录'), findsOneWidget);
    await tester.enterText(input, '无项目自己的草稿');

    await tester.tap(find.byKey(const ValueKey('start-project-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('start-project-$firstId')));
    await pumpClientUntil(
      tester,
      () => container.read(selectionStoreProvider).selectedProjectId == firstId,
      'restore project target',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, '项目自己的草稿');
    expect(find.text('project-context.txt'), findsOneWidget);
    expect(
      container
          .read(startSessionControllerProvider)
          .forProject(firstId)
          .workspaceMode,
      ThreadWorkspaceMode.worktree,
    );
    expect(
      container
          .read(startSessionControllerProvider)
          .forProject(standaloneId)
          .text,
      '无项目自己的草稿',
    );

    await tester.tap(find.byKey(const ValueKey('start-project-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-project-standalone')));
    await pumpClientUntil(
      tester,
      () =>
          container.read(selectionStoreProvider).selectedProjectId ==
          standaloneId,
      'restore standalone target',
    );
    await tester.pumpAndSettle();
    expect(
      container.read(selectionStoreProvider).selectedProjectId,
      standaloneId,
    );
    expect(tester.widget<TextField>(input).controller!.text, '无项目自己的草稿');
    expect(find.text('project-context.txt'), findsNothing);
    await closeStartPageFixture(tester);
  });

  testWidgets('窄窗长名称及两倍文字时输入、选择器与主按钮不发生布局溢出', (tester) async {
    final workspaceId = container
        .read(selectionStoreProvider)
        .selectedProjectId!;
    await pumpClientFuture(
      tester,
      transport.renameProject(workspaceId, '一个非常非常长的项目名称用于检验换行和截断行为'),
      'rename long project',
    );
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: pureStudioTheme(locale: const Locale('zh')),
          locale: const Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Composer(
                target: ComposerTarget.start(
                  workspaceId:
                      container
                          .read(selectionStoreProvider)
                          .selectedProjectId ??
                      '',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(StudioDriverKeys.composerInput), '窄窗草稿');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(StudioDriverKeys.composerSubmit), findsOneWidget);
    final sendRect = tester.getRect(
      find.byKey(StudioDriverKeys.composerSubmit),
    );
    expect(sendRect.left, greaterThanOrEqualTo(0));
    expect(sendRect.right, lessThanOrEqualTo(360));
    expect(find.byType(StartEnvironmentView), findsOneWidget);
  });

  testWidgets('起始页Recovery诊断完整可滚动且附件错误不被遮蔽', (tester) async {
    final workspaceId = container
        .read(selectionStoreProvider)
        .selectedProjectId!;
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

    await tester.pumpWidget(harness(const _SelectedComposerHost()));
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
      await tester.pumpWidget(harness(const _SelectedComposerHost()));
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
      graph.timeline.updateReadDemand(chatDemand);
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
      for (final key in [
        const ValueKey('start-project-selector'),
        StudioDriverKeys.sessionWorkspaceMode,
        StudioDriverKeys.sessionSettings,
      ]) {
        final target = find.byKey(key);
        final button = tester.widget<TextButton>(
          tester.widget(target) is TextButton
              ? target
              : find.descendant(of: target, matching: find.byType(TextButton)),
        );
        expect(button.onPressed, isNull, reason: '创建在途时冻结目标和外层配置');
      }
      expect(tester.widget<TextField>(input).enabled, isTrue);
      await tester.enterText(input, '准备时编辑的下一条草稿');
      await tester.pump();
      await pumpClientFuture(
        tester,
        graph.client.drafts.startDraft.source.waitFor(
          (state) => !state.submitting,
        ),
        'Enter submission terminal',
      );
      expect(
        graph.client.drafts.startDraft.state
            .forProject(graph.client.selection.state.selectedProjectId!)
            .text,
        '准备时编辑的下一条草稿',
      );
      final createdThreadId = graph.client.selection.state.selectedThreadId!;
      await pumpClientFuture(
        tester,
        graph.client.conversations.session(createdThreadId).content.ready,
        'Enter submission observed through the visible conversation feed',
      );
      final metadataDemand = graph.client.threadDirectory.observeThread(
        createdThreadId,
      );
      try {
        final created = await pumpClientFuture(
          tester,
          metadataDemand.state
              .waitFor((state) => state.frame?.row != null)
              .timeout(const Duration(seconds: 5)),
          'Enter submission canonical metadata observation',
        );
        final provisionalTitle = created.frame!.row!.title;
        final titlePublished = metadataDemand.state
            .waitFor(
              (state) =>
                  state.frame?.row?.title != null &&
                  state.frame!.row!.title != provisionalTitle,
            )
            .timeout(const Duration(seconds: 5));
        // Drain Demo's title job through its actual ID metadata publication.
        await tester.pump(const Duration(milliseconds: 650));
        await pumpClientFuture(
          tester,
          titlePublished,
          'demo title publication',
        );
      } finally {
        await metadataDemand.release();
      }
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
      await (graph
            ..timeline.updateReadDemand(chatDemand)
            ..setConversationPageVisible(true))
          .client
          .directoryCommands
          .selectThread(threadId);
      // Composer 只在 Client 已持有该会话草稿时渲染输入区。
      graph.client.drafts.composer(threadId);
      composerHold = workflowContainer.listen(
        _threadProjectionProvider(threadId),
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
            theme: pureStudioTheme(locale: const Locale('zh')),
            locale: const Locale('zh'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Center(
                child: Composer(
                  target: ComposerTarget.thread(threadId: threadId),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    int routeRevision() =>
        workflowContainer
            .read(_threadProjectionProvider(threadId))
            .requireValue
            .modelRoute
            ?.revision ??
        -1;

    testWidgets('运行中的根会话点击模型或强度选择器不打开菜单、不发命令', (tester) async {
      await openScenario(status: ThreadStatusView.running);
      await pumpDock(tester);

      final view = workflowContainer
          .read(_threadProjectionProvider(threadId))
          .requireValue;
      expect(view.hasActiveWorkflow, isTrue, reason: '场景前提：workflow active');
      expect(
        (view.row!.backend as NativeAgentBackendView).status,
        ThreadStatusView.running,
      );
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
          .read(_threadProjectionProvider(threadId))
          .requireValue;
      expect(initial.hasActiveWorkflow, isTrue);
      expect(
        (initial.row!.backend as NativeAgentBackendView).status,
        ThreadStatusView.idle,
      );
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
          .read(_threadProjectionProvider(threadId))
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
          .read(_threadProjectionProvider(threadId))
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
          .read(_threadProjectionProvider(threadId))
          .requireValue;
      expect(running.isBusy, isTrue, reason: '提交受理后 Turn 进入运行态');
      final stopButton = find.byKey(StudioDriverKeys.composerStop);
      expect(stopButton, findsOneWidget, reason: '草稿清空后停止按钮必须出现');
      final lockedGeometry = {
        for (final key in [
          StudioDriverKeys.sessionMode,
          StudioDriverKeys.model,
          StudioDriverKeys.reasoningEffort,
        ])
          key: tester.getRect(find.byKey(key)),
      };
      expect(find.byIcon(Icons.lock), findsNothing);

      await tester.tap(stopButton);
      await tester.pumpAndSettle();

      final stopped = workflowContainer
          .read(_threadProjectionProvider(threadId))
          .requireValue;
      expect(stopped.isBusy, isFalse, reason: '停止必须等到 canonical 终态，不是 ACK');
      for (final entry in lockedGeometry.entries) {
        final unlocked = tester.getRect(find.byKey(entry.key));
        expect(unlocked.left, entry.value.left, reason: '配置解锁不改变横向位置');
        expect(unlocked.size, entry.value.size, reason: '配置解锁保留触发器几何');
      }
      expect(
        stopped.hasActiveWorkflow,
        isTrue,
        reason: '停止 Turn 不得结束 workflow',
      );

      final initial = workflowContainer
          .read(_threadProjectionProvider(threadId))
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
          .read(_threadProjectionProvider(threadId))
          .requireValue;
      expect(settled.modelRoute?.modelId, next.modelId);
      expect(settled.routePending, isFalse);
      expect(settled.hasActiveWorkflow, isTrue);
      await closeScenario(tester);
    });
  });
}

// Test-only selectors retain assertions on the underlying immutable projection;
// production pages mount Composer rather than composing these providers.
class _DelayedClipboardReader implements ClipboardImageReader {
  final result = Completer<Uint8List?>();
  int calls = 0;
  @override
  Future<Uint8List?> readImage() {
    calls++;
    return result.future;
  }
}

class _ComposerStartTransport extends DemoStudioTransport {
  _ComposerStartTransport() : super(lspActivityLoop: false);
  bool failPreparation = false;
  final failedWorkspaceModes = <String?>[];
  final failedTexts = <String>[];

  @override
  Stream<NewThreadStartEvent> startNewThread(
    String workspaceId,
    StudioPromptInput input,
    ThreadModeId mode, {
    required ModeModelRouteView route,
    required DelegationMode delegationMode,
    required DelegationPreference delegationPreference,
    String? workspaceMode,
  }) {
    if (!failPreparation) {
      return super.startNewThread(
        workspaceId,
        input,
        mode,
        route: route,
        delegationMode: delegationMode,
        delegationPreference: delegationPreference,
        workspaceMode: workspaceMode,
      );
    }
    failedWorkspaceModes.add(workspaceMode);
    failedTexts.add(input.text);
    return Stream.fromIterable([
      NewThreadStartProgress(
        ThreadPreparationProgress(
          workspaceId: workspaceId,
          inputId: input.inputId,
          stage: ThreadPreparationStage.creatingWorktree,
        ),
      ),
      const NewThreadStartFailed(
        StudioFailure(
          code: StudioFailureCode.invalidArgument,
          message: 'worktree preparation failed',
          retryable: false,
          correlationId: 'composer-worktree-failure',
        ),
      ),
    ]);
  }
}

class _TestImageStager implements ClipboardImageStager {
  int _next = 0;
  @override
  Future<StagedClipboardImage> stage(Uint8List pngBytes) async =>
      StagedClipboardImage(
        path: 'clipboard-${_next++}.png',
        dispose: () async {},
      );
}

final _startProjectionProvider =
    Provider.autoDispose<AsyncValue<StartPageComposerViewState>>((ref) {
      final workspaceId = ref.watch(selectionStoreProvider).selectedProjectId;
      if (workspaceId == null) return const AsyncLoading();
      return ref
          .watch(
            composerViewModelProvider(
              ComposerTarget.start(workspaceId: workspaceId),
            ),
          )
          .whenData((state) => state.start!);
    });

final _threadProjectionProvider = Provider.autoDispose
    .family<AsyncValue<ComposerDockViewState>, String>((ref, threadId) {
      return ref
          .watch(
            composerViewModelProvider(
              ComposerTarget.thread(threadId: threadId),
            ),
          )
          .whenData((state) => state.thread!);
    });

/// A page supplies the selected typed target; Composer never reads selection.
class _SelectedComposerHost extends ConsumerWidget {
  const _SelectedComposerHost({this.onAddProject});
  final VoidCallback? onAddProject;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(selectionStoreProvider).selectedProjectId;
    if (id == null) return const SizedBox.shrink();
    return Composer(
      target: ComposerTarget.start(workspaceId: id),
      onAddProject: onAddProject,
    );
  }
}

class _EnvironmentHost extends ConsumerWidget {
  const _EnvironmentHost({required this.workspaceId, required this.enabled});
  final String? workspaceId;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ComposerTarget.start(workspaceId: workspaceId!);
    final provider = composerViewModelProvider(target);
    final state = ref.watch(provider).value;
    if (state == null) return const SizedBox.shrink();
    return StartEnvironmentBar(
      state: state,
      actions: ref.read(provider.notifier),
      enabled: enabled,
    );
  }
}

class _ModeSelectorHost extends ConsumerWidget {
  const _ModeSelectorHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(_startProjectionProvider).requireValue;
    final workspaceId = page.project?.id;
    return SessionModeSelector(
      catalog: page.modeCatalog ?? const ThreadModeCatalogView(),
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
    final page = ref.watch(_startProjectionProvider).requireValue;
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
    final page = ref.watch(_startProjectionProvider).requireValue;
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
  final page = container.read(_startProjectionProvider).requireValue;
  return page.displayRoute(page.mode)?.effort;
}

/// 当前显示路由模型声明的、与 [current] 不同的思考强度候选。
String? _otherEffort(ProviderContainer container, String current) {
  final page = container.read(_startProjectionProvider).requireValue;
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

  @override
  Future<ThreadObservationHandle> openThreadObservation(
    String threadId,
  ) async => _WorkflowThreadObservation(
    await super.openThreadObservation(threadId),
    _thread,
  );

  SessionDirectoryRow _thread(SessionDirectoryRow row) =>
      row.threadId == 'thread-main' &&
          (row.backend as NativeAgentBackendView).status != threadStatus
      ? row.copyWith(
          backend: (row.backend as NativeAgentBackendView).copyWith(
            status: threadStatus,
          ),
        )
      : row;

  /// Bootstrap remains a protocol fixture; typed metadata observations receive
  /// the same scenario status from the external feed fixture.
  @override
  Future<StudioBootstrap> readBootstrap() async {
    final snapshot = await super.readBootstrap();
    return StudioBootstrap(
      ownerEpoch: snapshot.ownerEpoch,
      projectDirectory: snapshot.projectDirectory,
      threadDirectory: _page(snapshot.threadDirectory),
      agentDirectory: snapshot.agentDirectory,
      settingsState: snapshot.settingsState,
      recoveryState: snapshot.recoveryState,
      mcpCatalog: snapshot.mcpCatalog,
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

  @override
  Future<ConversationStateFeed> openConversationStateFeed(
    String threadId,
  ) async => MappedConversationStateFeed(
    await super.openConversationStateFeed(threadId),
    (frame) => switch (frame) {
      ThreadSnapshotFrame(
        :final workspace,
        :final completedHistoryVersion,
        :final schemaVersion,
      ) =>
        ThreadSnapshotFrame(
          workspace: workspace.copyWith(runtime: _runtime(workspace.runtime)),
          completedHistoryVersion: completedHistoryVersion,
          schemaVersion: schemaVersion,
        ),
      ThreadNotificationFrame() => switch (frame.update) {
        ThreadRuntimeUpdate(:final runtime, :final todo, :final modelRoute) =>
          ThreadNotificationFrame(
            threadId: frame.threadId,
            revision: frame.revision,
            epoch: frame.epoch,
            baseRevision: frame.baseRevision,
            update: ThreadRuntimeUpdate(
              runtime: _runtime(runtime),
              todo: todo,
              modelRoute: modelRoute,
            ),
          ),
        _ => frame,
      },
      _ => frame,
    },
  );

  ThreadDirectoryPage _page(ThreadDirectoryPage page) => ThreadDirectoryPage(
    rows: [for (final row in page.rows) _thread(row)],
    nextCursor: page.nextCursor,
    revision: page.revision,
  );
}

final class _WorkflowThreadObservation implements ThreadObservationHandle {
  _WorkflowThreadObservation(this._inner, this._map);

  final ThreadObservationHandle _inner;
  final SessionDirectoryRow Function(SessionDirectoryRow) _map;

  @override
  Future<ThreadMetadataFrame?> next() async {
    final frame = await _inner.next();
    final row = frame?.row;
    if (frame == null || row == null) return frame;
    return ThreadMetadataFrame(
      threadId: frame.threadId,
      stamp: frame.stamp,
      row: _map(row),
    );
  }

  @override
  void requestClose() => _inner.requestClose();

  @override
  Future<void> close() => _inner.close();
}
