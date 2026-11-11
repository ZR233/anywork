import 'dart:async';

import '../support/chat_fixtures.dart';
import '../support/test_statistics_feed.dart';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/status/context_usage_readout.dart';
import 'package:anywork/src/features/status/status_view.dart';
import 'package:anywork/src/features/status/thread_status_bar.dart';
import 'package:anywork/src/domain/models/studio_reactive_projections.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'context-policy',
      );
      addTearDown(() => graph.close(deadline: _deadline()));
      await graph.client.bootstrap();
      graph.timeline.updateReadDemand(chatDemand);
      await (graph..setConversationPageVisible(true)).client.directoryCommands
          .selectThread('thread-main');
      final session = graph.client.conversations.existingSession(
        'thread-main',
      )!;
      await session.content.ready;
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
          inputTokenLimit: 922000,
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
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'status-cold-compact',
      );
      await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
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
        transport.stateFeeds.last.emitStateAndWait(
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
        transport.stateFeeds.last.emitStateAndWait(
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
      transport.emitLsp(
        LspStateSnapshot(
          revision: graph.client.lsp.state.revision + 1,
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
        graph.close(deadline: _deadline()),
        'context connector teardown',
      );
      expect(report.complete, isTrue);
    },
  );

  test('status projections isolate throughput from context, chrome, and unrelated facts', () async {
    final transport = _StatusTransport();
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'status-throughput',
    );
    addTearDown(() => graph.close(deadline: _deadline()));
    await graph.client.bootstrap();
    graph.timeline.updateReadDemand(chatDemand);
    await (graph..setConversationPageVisible(true)).client.directoryCommands
        .selectThread('thread-main');
    final session = graph.client.conversations.existingSession('thread-main')!;
    await session.content.ready;
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
    final timelineConnections = transport.timelineFeeds.length;

    await transport.stateFeeds.last.emitStateAndWait(
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

    await transport.stateFeeds.last.emitStateAndWait(
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

    await transport.stateFeeds.last.emitStateAndWait(
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
    await transport.stateFeeds.last.emitStateAndWait(
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

    await transport.stateFeeds.last.emitStateAndWait(
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

    expect(transport.timelineFeeds, hasLength(timelineConnections));
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
}

final class _StatusTransport extends RecordingDemoTransport {
  _StatusTransport() {
    timelineFeedFactory = (_, inner) async =>
        _SetAcknowledgedFeed(inner: inner, acknowledged: firstSetAcknowledged);
  }

  final firstSetAcknowledged = Completer<void>();
  final compactStarted = Completer<void>();
  Completer<void>? compactGate;
  int compactCalls = 0;
  StreamController<ProductTopicFrame>? _lspFrames;

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) {
    final upstream = super.subscribeProductTopic(topic);
    if (topic is! LspTopic) return upstream;
    StreamSubscription<ProductTopicFrame>? subscription;
    late final StreamController<ProductTopicFrame> controller;
    controller = StreamController<ProductTopicFrame>(
      onListen: () {
        subscription = upstream.listen(
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
    return controller.stream;
  }

  void emitLsp(LspStateSnapshot snapshot) {
    _lspFrames!.add(
      ProductTopicDataFrame(
        topic: const LspTopic(),
        event: ProductTopicEventEnvelope(
          eventId: 'context-lsp-${snapshot.revision}',
          sequence: BigInt.from(snapshot.revision),
          createdAt: DateTime.utc(2026, 11, 3),
          payload: LspStateChangedPayload(snapshot),
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

/// Wait for the actual Set ACK before injecting State frames into the same feed.
/// This observes transport ownership; it never publishes or reduces a projection.
final class _SetAcknowledgedFeed extends RecordingTimelineFeed {
  _SetAcknowledgedFeed({required super.inner, required this.acknowledged});

  final Completer<void> acknowledged;
  int? _firstSetSequence;

  @override
  Stream<ConversationFrame> get events => super.events.map((frame) {
    if (frame.event case ConversationTimelineEvent(
      batch: TimelineBatch(placement: ChatPlacement.set),
    )) {
      _firstSetSequence ??= frame.deliverySequence;
    }
    return frame;
  });

  @override
  Future<void> acknowledge(int deliverySequence) async {
    await super.acknowledge(deliverySequence);
    final firstSet = _firstSetSequence;
    if (firstSet != null &&
        deliverySequence >= firstSet &&
        !acknowledged.isCompleted) {
      acknowledged.complete();
    }
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
