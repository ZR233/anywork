import '../support/test_app_lifecycle.dart';

import 'dart:async';

import '../support/chat_fixtures.dart';
import '../support/test_statistics_feed.dart';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/status/context_usage_readout.dart';
import 'package:anywork/src/features/status/status_bar_item.dart';
import 'package:anywork/src/features/status/status_view.dart';
import 'package:anywork/src/features/status/thread_status_bar.dart';
import 'package:anywork/src/domain/models/studio_reactive_projections.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_previews/src/features/status/previews/thread_status_bar_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'idle context follows canonical catalog while running binding stays frozen',
    () async {
      final transport = _StatusTransport();
      final graph = testAppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'context-policy',
      );
      addTearDown(() => graph.close(budget: testBudgetUntil(_deadline())));
      await graph.client.bootstrap();
      graph.timeline.updateReadDemand(chatDemand);
      await (graph..setConversationPageVisible(true)).client.directoryCommands
          .selectThread('thread-main');
      await graph.client.conversations.visibleThreadId
          .waitFor((value) => value == 'thread-main')
          .timeout(const Duration(seconds: 10));
      final session = graph.client.conversations.existingSession(
        'thread-main',
      )!;
      await timelineReady(graph.timeline, session.threadId);
      await _awaitCurrentReaders(graph, transport, session.threadId);
      await transport.firstSetAcknowledged.future;
      await session.source.waitFor((value) => value.hasSnapshot);
      final initial = session.state.workspace!;
      final summaries = graph.accounts.observeSummaries();
      addTearDown(summaries.release);
      final directory = graph.models.observeDirectory();
      addTearDown(directory.release);
      await graph.accounts.state.waitFor((value) => value.loaded);
      await graph.models.state.waitFor(
        (value) => value.accounts.values.any(
          (resource) =>
              resource.loaded && resource.value?.models.isNotEmpty == true,
        ),
      );
      final account = modelSelectionAccounts(
        graph.accounts.state.value,
        graph.models.state.value,
      ).first;
      final identity = NativeAccountIdentity(account.id);
      final resource = graph.models.state.value.accounts[identity]!;
      final catalog = resource.value!;
      final model = catalog.models.first;
      final frozen = initial.runtime.copyWith(
        modelId: model.modelId,
        autoCompactLimit: 922000,
      );
      await (graph.client.transport as RecordingDemoTransport).publishWorkspace(
        initial.copyWith(
          runtime: frozen,
          modelRoute: ThreadModelRouteView(
            accountId: account.id,
            modelId: model.modelId,
            effort: null,
            revision: 1,
            available: true,
          ),
        ),
      );
      final container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      addTearDown(container.dispose);
      final context = container.listen(
        statusContextProjectionProvider('thread-main'),
        (_, _) {},
      );
      addTearDown(context.close);
      final changed = model.copyWith(
        context: const ModelContextView(
          unavailable: null,
          contextWindow: 1050000,
          autoCompactLimit: 14780,
        ),
      );
      final accounts = [
        ModelSelectionAccount(
          id: account.id,
          name: account.name,
          billingKind: account.billingKind,
          models: [changed],
        ),
      ];
      graph.accountDomains.acceptFrame(
        AccountModelsFrame(
          ResourceStamp(
            resourceKey: 'model-catalog',
            ownerEpoch: resource.stamp!.ownerEpoch,
            revision: resource.stamp!.revision + 1,
          ),
          identity,
          AccountModelCatalog(
            identity: identity,
            models: [changed],
            status: catalog.status,
          ),
        ),
      );
      expect(context.read()?.autoCompactLimit, 14780);
      expect(context.read()?.contextWindow, 1050000);
      graph.accountDomains.acceptFrame(
        AccountModelsFrame(resource.stamp!, identity, catalog),
      );
      expect(
        context.read()?.autoCompactLimit,
        14780,
        reason: 'late catalog cannot undo settings return',
      );
      final running = StudioContextProjection.fromRuntime(
        'thread-main',
        frozen,
        modelRoute: initial.modelRoute,
        accounts: accounts,
        isBusy: true,
      );
      expect(running.autoCompactLimit, 922000);
      expect(
        frozen.autoCompactLimit,
        922000,
        reason: 'historical binding is immutable',
      );
      graph.accountDomains.acceptFrame(
        AccountModelsFrame(
          ResourceStamp(
            resourceKey: 'model-catalog',
            ownerEpoch: resource.stamp!.ownerEpoch,
            revision: resource.stamp!.revision + 2,
          ),
          identity,
          AccountModelCatalog(
            identity: identity,
            models: [model.copyWith(context: const ModelContextView())],
            status: catalog.status,
          ),
        ),
      );
      expect(
        context.read()?.autoCompactLimit,
        isNull,
        reason: 'unknown must not reuse an old threshold',
      );
    },
  );

  testWidgets(
    'cold compact initializes state and retains command state across source updates',
    (tester) async {
      final transport = _StatusTransport()..compactGate = Completer<void>();
      final graph = testAppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'status-cold-compact',
      );
      await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
      graph.timeline.updateReadDemand(chatDemand);
      await pumpClientFuture(
        tester,
        (graph..setConversationPageVisible(true)).client.directoryCommands
            .selectThread('thread-main'),
        'select context thread',
      );
      final session = graph.client.conversations.existingSession(
        'thread-main',
      )!;
      await pumpClientUntil(
        tester,
        () => session.state.hasSnapshot,
        'session baseline',
      );
      await pumpClientFuture(
        tester,
        timelineReady(graph.timeline, 'thread-main'),
        'timeline baseline',
      );
      final timelineReader =
          graph.timeline.lease('thread-main')!.current
              as RecordingCurrentReader;
      final stateReader = _stateCurrentReader(transport);
      await pumpClientUntil(
        tester,
        () => timelineReader.watchEntered.isCompleted,
        'timeline Current watch',
      );
      await pumpClientUntil(
        tester,
        () => stateReader.watchEntered.isCompleted,
        'session Current watch',
      );
      final container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      final provider = startedItemsViewModelProvider('thread-main');
      expect(container.read(provider.exists), isFalse);

      // Exercise a cold command before either the footer or its menu mounts.
      final command = container.read(provider.notifier).compact();
      expect(
        container.read(provider).requireValue.pending,
        contains('compact'),
      );
      await pumpClientFuture(
        tester,
        transport.compactStarted.future,
        'compact admitted',
      );
      expect(transport.compactCalls, 1);
      await pumpClientFuture(
        tester,
        _stateCurrentReader(transport).emitStateAndWait(
          _runtimeFrame(
            session,
            session.state.runtime!.copyWith(
              activeSkills: const ['during-compact'],
            ),
          ),
        ),
        'state update while compacting',
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Center(
                child: ThreadStatusConnector(threadId: 'thread-main'),
              ),
            ),
          ),
        ),
      );
      await pumpClientUntil(
        tester,
        () =>
            container
                    .read(provider)
                    .asData
                    ?.value
                    .skills
                    .contains('during-compact') ==
                true &&
            find.byType(ContextUsageReadout).evaluate().isNotEmpty,
        'production context connector',
      );
      expect(container.read(provider).requireValue.skills, ['during-compact']);
      expect(
        container.read(provider).requireValue.pending,
        contains('compact'),
      );
      final pendingReadout = tester.widget<ContextUsageReadout>(
        find.byType(ContextUsageReadout),
      );
      expect(pendingReadout.compacting, isTrue);
      expect(pendingReadout.compactionFailed, isFalse);
      expect(pendingReadout.onCompact, isNull);

      transport.compactGate!.complete();
      await pumpClientFuture(tester, command, 'compact failure');
      expect(container.read(provider).requireValue.pending, isEmpty);
      expect(
        container.read(provider).requireValue.errors['compact'],
        contains('Manual compaction requires the native runtime'),
      );
      expect(
        graph
            .client
            .threadCommands
            .state
            .commands['compact:thread-main']
            ?.phase,
        CommandPhase.failed,
      );
      await pumpClientFuture(
        tester,
        _stateCurrentReader(transport).emitStateAndWait(
          _runtimeFrame(
            session,
            session.state.runtime!.copyWith(
              activeSkills: const ['after-compact'],
            ),
          ),
        ),
        'state update after compact failure',
      );
      await pumpClientUntil(
        tester,
        () =>
            container
                    .read(provider)
                    .asData
                    ?.value
                    .skills
                    .contains('after-compact') ==
                true &&
            tester
                .widget<ContextUsageReadout>(find.byType(ContextUsageReadout))
                .compactionFailed,
        'VM failure reaches context',
      );
      expect(container.read(provider).requireValue.skills, ['after-compact']);
      expect(
        container.read(provider).requireValue.errors['compact'],
        contains('Manual compaction requires the native runtime'),
      );
      final failedReadout = tester.widget<ContextUsageReadout>(
        find.byType(ContextUsageReadout),
      );
      expect(failedReadout.compacting, isFalse);
      expect(failedReadout.compactionFailed, isTrue);

      // Prove isolation on the production widget, not only on a copied selector.
      await pumpClientUntil(
        tester,
        () =>
            graph.accounts.state.value.loaded &&
            graph.models.state.value.accounts.values.any(
              (resource) =>
                  resource.loaded && resource.value?.models.isNotEmpty == true,
            ),
        'account baseline before measuring context rebuilds',
      );
      await tester.pumpAndSettle();
      final beforeLsp = tester.widget<ContextUsageReadout>(
        find.byType(ContextUsageReadout),
      );
      await tester.tap(find.byKey(StudioDriverKeys.statusStartedItems));
      await tester.pumpAndSettle();
      final lsp = graph.client.existingThreadLsp('thread-main')!.state.value!;
      transport.emitThreadLsp(
        ThreadLspStateSnapshot(
          threadId: 'thread-main',
          bindingId: lsp.bindingId,
          revision: lsp.revision + 1,
          servers: const [
            LspServerStateView(
              id: 'dart',
              displayName: 'Dart',
              configurationPath: null,
              phase: 'ready',
              state: LspAvailableState(
                checkedAt: 1,
                diagnosticCount: 0,
                activity: LspIndexingActivity(percentage: 42),
              ),
            ),
          ],
        ),
      );
      await pumpClientUntil(
        tester,
        () =>
            container
                .read(provider)
                .asData
                ?.value
                .lsp
                .firstOrNull
                ?.percentage ==
            42,
        'real product LSP progress',
      );
      expect(
        tester.widget<ContextUsageReadout>(find.byType(ContextUsageReadout)),
        same(beforeLsp),
      );

      await tester.tap(find.byKey(StudioDriverKeys.statusStartedItems));
      await tester.pumpAndSettle();

      // Client command diagnostics intentionally diverge from VM presentation:
      // a direct Client call is pending while the last VM command is still failed.
      transport.compactGate = Completer<void>();
      final directClientCommand = graph.client.threadCommands.compactThread(
        'thread-main',
      );
      final directFailure = expectLater(
        directClientCommand,
        throwsUnsupportedError,
      );
      await pumpClientUntil(
        tester,
        () => transport.compactCalls == 2,
        'direct Client command',
      );
      expect(
        graph
            .client
            .threadCommands
            .state
            .commands['compact:thread-main']
            ?.phase,
        CommandPhase.pending,
      );
      expect(
        tester.widget<ContextUsageReadout>(find.byType(ContextUsageReadout)),
        same(beforeLsp),
      );
      expect(
        tester
            .widget<ContextUsageReadout>(find.byType(ContextUsageReadout))
            .compacting,
        isFalse,
      );
      expect(
        tester
            .widget<ContextUsageReadout>(find.byType(ContextUsageReadout))
            .compactionFailed,
        isTrue,
      );
      final tooltip = find.descendant(
        of: find.byKey(StudioDriverKeys.contextUsage()),
        matching: find.byType(Tooltip),
      );
      tester.state<TooltipState>(tooltip).ensureTooltipVisible();
      await tester.pumpAndSettle();
      expect(find.text('压缩失败，请重试。'), findsOneWidget);
      expect(find.text('正在压缩…'), findsNothing);
      transport.compactGate!.complete();
      await pumpClientFuture(tester, directFailure, 'direct command finished');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      final report = await pumpClientFuture(
        tester,
        graph.close(budget: testBudgetUntil(_deadline())),
        'context connector teardown',
      );
      expect(report.complete, isTrue);
    },
  );

  test('status projections isolate throughput from context, chrome, and unrelated facts', () async {
    final transport = _StatusTransport();
    final graph = testAppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'status-throughput',
    );
    addTearDown(() => graph.close(budget: testBudgetUntil(_deadline())));
    await graph.client.bootstrap();
    graph.timeline.updateReadDemand(chatDemand);
    await (graph..setConversationPageVisible(true)).client.directoryCommands
        .selectThread('thread-main');
    await graph.client.conversations.visibleThreadId
        .waitFor((value) => value == 'thread-main')
        .timeout(const Duration(seconds: 10));
    final session = graph.client.conversations.existingSession('thread-main')!;
    await timelineReady(graph.timeline, session.threadId);
    await _awaitCurrentReaders(graph, transport, session.threadId);
    await transport.firstSetAcknowledged.future;
    await session.source.waitFor((value) => value.hasSnapshot);
    final composer = graph.client.drafts.existingComposer('thread-main')!;
    composer.updateDraft('keep this draft');
    final initial = session.state.workspace!;
    await (graph.client.transport as RecordingDemoTransport).publishWorkspace(
      initial.copyWith(
        runtime: initial.runtime.copyWith(
          contextTokens: 100,
          turnCompletionTokens: 25,
          turnResponseMillis: 1000,
          activeSkills: const ['skill-a'],
          activeMcpServers: const ['mcp-a'],
          activeLspServers: const ['lsp-a'],
        ),
      ),
    );

    final container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph)],
    );
    addTearDown(container.dispose);
    var throughputNotifications = 0;
    var contextNotifications = 0;
    var chromeNotifications = 0;
    var startedItemsNotifications = 0;
    final throughput = container.listen(
      statusThroughputProjectionProvider('thread-main'),
      (_, _) => throughputNotifications++,
    );
    final context = container.listen(
      statusContextProjectionProvider('thread-main'),
      (_, _) => contextNotifications++,
    );
    final chrome = container.listen(
      statusBarViewProvider('thread-main'),
      (_, _) => chromeNotifications++,
    );
    final startedItems = container.listen(
      startedItemsViewModelProvider('thread-main'),
      (_, _) => startedItemsNotifications++,
    );
    addTearDown(throughput.close);
    addTearDown(context.close);
    addTearDown(chrome.close);
    addTearDown(startedItems.close);

    // Establish the account/model baseline before measuring isolation. Its
    // legitimate first load can change context capacity independently of State.
    await graph.accounts.state.waitFor((value) => value.loaded);
    await graph.models.state.waitFor(
      (value) => value.accounts.values.any(
        (resource) =>
            resource.loaded && resource.value?.models.isNotEmpty == true,
      ),
    );
    await container.pump();
    await Future<void>.delayed(Duration.zero);
    expect(throughput.read()?.tokensPerSecond, 25);
    expect(context.read()?.contextTokens, 100);
    expect(chrome.read()?.row.threadId, 'thread-main');
    expect(startedItems.read().requireValue.skills, ['skill-a']);
    throughputNotifications = 0;
    contextNotifications = 0;
    chromeNotifications = 0;
    startedItemsNotifications = 0;
    final timelineConnections = transport.currentReaders.length;

    await _stateCurrentReader(transport).emitStateAndWait(
      _runtimeFrame(
        session,
        session.state.runtime!.copyWith(
          contextTokens: 100,
          liveUsage: const ThreadRuntimeLiveUsageView(
            turnId: 'turn-2',
            attemptId: 'attempt-2',
            completionTokens: 10,
            state: ThreadRuntimeUsageState.live,
            observationSequence: 1,
          ),
          activeSkills: List<String>.of(['skill-a']),
          activeMcpServers: List<String>.of(['mcp-a']),
          activeLspServers: List<String>.of(['lsp-a']),
        ),
      ),
    );
    expect(
      throughput.read()?.tokensPerSecond,
      25,
      reason: 'a partial live sample must keep the confirmed Turn pair',
    );
    expect(contextNotifications, 0);
    expect(startedItemsNotifications, 0);
    expect(
      chromeNotifications,
      0,
      reason: 'FRB-style equal capability lists must not rebuild chrome',
    );

    await _stateCurrentReader(transport).emitStateAndWait(
      _runtimeFrame(
        session,
        session.state.runtime!.copyWith(
          liveUsage: const ThreadRuntimeLiveUsageView(
            turnId: 'turn-2',
            attemptId: 'attempt-2',
            completionTokens: 20,
            responseMillis: 500,
            state: ThreadRuntimeUsageState.live,
            observationSequence: 2,
          ),
          activeSkills: List<String>.of(['skill-a']),
          activeMcpServers: List<String>.of(['mcp-a']),
          activeLspServers: List<String>.of(['lsp-a']),
        ),
      ),
    );
    expect(throughput.read()?.tokensPerSecond, 40);
    expect(throughputNotifications, 1);
    expect(contextNotifications, 0);
    expect(chromeNotifications, 0);

    final chromeBeforeInvalidate = chrome.read();
    chromeNotifications = 0;
    container.invalidate(statusBarViewProvider('thread-main'));
    expect(
      chrome.read(),
      chromeBeforeInvalidate,
      reason: 'rebuilding statusBar without settings/chrome change is equal',
    );
    expect(chromeNotifications, 0);

    await _stateCurrentReader(transport).emitStateAndWait(
      ThreadNotificationFrame(
        threadId: 'thread-main',
        epoch: session.state.streamEpoch ?? 1,
        baseRevision: session.state.revision,
        revision: session.state.revision + 1,
        update: const ThreadActivityUpdate(
          activity: ThreadActivityView(
            threadId: 'thread-main',
            identity: 'activity:turn-2:1:responding',
            revision: 1,
            turnId: 'turn-2',
            kind: ThreadActivityKind.responding,
            summary: 'streaming',
          ),
        ),
      ),
    );
    await _stateCurrentReader(transport).emitStateAndWait(
      ThreadNotificationFrame(
        threadId: 'thread-main',
        epoch: session.state.streamEpoch ?? 1,
        baseRevision: session.state.revision,
        revision: session.state.revision + 1,
        update: const ThreadStorageUpdate(
          storage: ThreadStorageStateView(acceptedSequence: 8),
        ),
      ),
    );
    expect(throughput.read()?.tokensPerSecond, 40);
    expect(throughputNotifications, 1);
    expect(contextNotifications, 0);
    expect(chromeNotifications, 0);

    await _stateCurrentReader(transport).emitStateAndWait(
      _runtimeFrame(
        session,
        session.state.runtime!.copyWith(
          activeSkills: List<String>.of(['skill-a', 'skill-b']),
          activeMcpServers: List<String>.of(['mcp-a']),
          activeLspServers: List<String>.of(['lsp-a']),
        ),
      ),
    );
    await container.pump();
    await Future<void>.delayed(Duration.zero);
    expect(startedItems.read().requireValue.skills, ['skill-a', 'skill-b']);
    expect(startedItemsNotifications, 1);
    expect(chromeNotifications, 0);
    expect(throughput.read()?.tokensPerSecond, 40);
    expect(throughputNotifications, 1);
    expect(contextNotifications, 0);

    expect(transport.currentReaders, hasLength(timelineConnections));
    expect(
      graph.client.conversations.existingSession('thread-main'),
      same(session),
    );

    final alt = container.listen(
      statusThroughputProjectionProvider('thread-alt'),
      (_, _) {},
    );
    expect(alt.read()?.tokensPerSecond, isNull);
    alt.close();

    throughput.close();
    context.close();
    chrome.close();
    startedItems.close();
    await container.pump();
    expect(
      graph.client.lsp.state.loaded,
      isTrue,
      reason: 'display disposal must not close the shared LSP owner',
    );
    expect(
      graph.client.conversations.existingSession('thread-main'),
      same(session),
    );
    expect(
      graph.client.drafts.composer('thread-main').state.draft,
      'keep this draft',
    );
  });

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

final class _StatusTransport extends RecordingDemoTransport {
  final firstSetAcknowledged = Completer<void>();
  final compactStarted = Completer<void>();
  Completer<void>? compactGate;
  int compactCalls = 0;
  StreamController<ProductTopicFrame>? _lspFrames;

  @override
  Future<CurrentReader> openCurrentReader(
    String threadId, {
    required int currentProtocolVersion,
    required ReadDemand demand,
  }) async {
    final reader = await super.openCurrentReader(
      threadId,
      currentProtocolVersion: currentProtocolVersion,
      demand: demand,
    );
    if (!firstSetAcknowledged.isCompleted) firstSetAcknowledged.complete();
    return reader;
  }

  @override
  TestTopicFrames testProductTopicFrames(
    ProductTopic topic,
    TestTopicFrames upstream,
  ) {
    if (topic is! ThreadLspTopic) return upstream;
    StreamSubscription<ProductTopicFrame>? subscription;
    late final StreamController<ProductTopicFrame> controller;
    controller = StreamController<ProductTopicFrame>(
      onListen: () {
        subscription = upstream.frames.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );
    _lspFrames = controller;
    return TestTopicFrames.controller(controller);
  }

  void emitThreadLsp(ThreadLspStateSnapshot snapshot) {
    _lspFrames!.add(
      ProductTopicDataFrame(
        topic: ThreadLspTopic(threadId: snapshot.threadId),
        event: ProductTopicEventEnvelope(
          eventId: 'context-lsp-${snapshot.revision}',
          sequence: BigInt.from(snapshot.revision),
          createdAt: DateTime.utc(2026, 11, 3),
          payload: ThreadLspStateChangedPayload(snapshot),
        ),
      ),
    );
  }

  @override
  Future<void> compactThread(String threadId) async {
    compactCalls++;
    if (!compactStarted.isCompleted) compactStarted.complete();
    await compactGate?.future;
    return super.compactThread(threadId);
  }
}

ThreadNotificationFrame _runtimeFrame(
  ConversationSession session,
  ThreadRuntimeView runtime,
) {
  return ThreadNotificationFrame(
    threadId: 'thread-main',
    epoch: session.state.streamEpoch ?? 1,
    baseRevision: session.state.revision,
    revision: session.state.revision + 1,
    update: ThreadRuntimeUpdate(
      runtime: runtime,
      todo: null,
      modelRoute: session.state.modelRoute,
    ),
  );
}

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));

RecordingCurrentReader _stateCurrentReader(RecordingDemoTransport transport) =>
    transport.currentReaders.lastWhere(
      (reader) =>
          reader.threadId == 'thread-main' && reader.demand.maxItems == 128,
    );

Future<void> _awaitCurrentReaders(
  AppGraph graph,
  RecordingDemoTransport transport,
  String threadId,
) async {
  final session = graph.client.conversations.existingSession(threadId);
  if (session == null) {
    throw StateError('Thread session is not open: $threadId');
  }
  await session.source.waitFor((state) => state.hasSnapshot);
  final timeline = graph.timeline.lease(threadId)?.current;
  final state = transport.currentReaders.lastWhere(
    (reader) => reader.threadId == threadId && reader.demand.maxItems == 128,
  );
  expect(timeline, isA<RecordingCurrentReader>());
  await Future.wait([
    (timeline as RecordingCurrentReader).watchEntered.future,
    state.watchEntered.future,
  ]);
}
