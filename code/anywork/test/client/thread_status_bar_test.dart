import 'support/test_statistics_feed.dart';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/status/status_view.dart';
import 'package:anywork/src/domain/models/studio_reactive_projections.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'idle context follows canonical catalog while running binding stays frozen',
    () async {
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: RecordingDemoTransport(),
        clientId: 'context-policy',
      );
      addTearDown(() => graph.close(deadline: _deadline()));
      await graph.client.bootstrap();
      await graph.client.directoryCommands.selectThread('thread-main');
      final session = graph.client.existingSession('thread-main')!;
      await session.timeline.state.waitFor(
        (state) => state.snapshot is StudioTimelineBaselineFrame,
      );
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
        modelRoute: ThreadModelRouteView(
          accountId: account.id,
          modelId: model.modelId,
          effort: null,
          revision: 1,
          available: true,
        ),
      );
      session.applySnapshot(initial.copyWith(runtime: frozen));
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

  test('status projections isolate throughput from context, chrome, and unrelated facts', () async {
    final transport = RecordingDemoTransport();
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'status-throughput',
    );
    addTearDown(() => graph.close(deadline: _deadline()));
    await graph.client.bootstrap();
    await graph.client.directoryCommands.selectThread('thread-main');
    final session = graph.client.existingSession('thread-main')!;
    await session.timeline.state.waitFor(
      (state) => state.snapshot is StudioTimelineBaselineFrame,
    );
    final composer = graph.client.existingComposer('thread-main')!;
    composer.updateDraft('keep this draft');
    final initial = session.state.workspace!;
    session.applySnapshot(
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
    addTearDown(throughput.close);
    addTearDown(context.close);
    addTearDown(chrome.close);

    expect(throughput.read()?.tokensPerSecond, 25);
    expect(context.read()?.contextTokens, 100);
    expect(chrome.read()?.thread.id, 'thread-main');
    expect(chrome.read()?.activeSkills, ['skill-a']);
    throughputNotifications = 0;
    contextNotifications = 0;
    chromeNotifications = 0;
    final observersBefore = graph.client.budget.used(ResourceKind.observer);
    final timelineConnections = transport.timelines.length;

    session.applyNotification(
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
    expect(
      chromeNotifications,
      0,
      reason: 'FRB-style equal capability lists must not rebuild chrome',
    );

    session.applyNotification(
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

    session.applyNotification(
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
    session.applyNotification(
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

    session.applyNotification(
      _runtimeFrame(
        session,
        session.state.runtime!.copyWith(
          activeSkills: List<String>.of(['skill-a', 'skill-b']),
          activeMcpServers: List<String>.of(['mcp-a']),
          activeLspServers: List<String>.of(['lsp-a']),
        ),
      ),
    );
    expect(chrome.read()?.activeSkills, ['skill-a', 'skill-b']);
    expect(chromeNotifications, 1);
    expect(throughput.read()?.tokensPerSecond, 40);
    expect(throughputNotifications, 1);
    expect(contextNotifications, 0);

    expect(transport.timelines, hasLength(timelineConnections));
    expect(graph.client.existingSession('thread-main'), same(session));

    final alt = container.listen(
      statusThroughputProjectionProvider('thread-alt'),
      (_, _) {},
    );
    expect(alt.read()?.tokensPerSecond, isNull);
    alt.close();

    throughput.close();
    context.close();
    chrome.close();
    await container.pump();
    expect(graph.client.existingSession('thread-main'), same(session));
    expect(graph.client.composer('thread-main').state.draft, 'keep this draft');
    expect(
      graph.client.budget.used(ResourceKind.observer),
      lessThan(observersBefore),
    );
  });
}

ThreadNotificationFrame _runtimeFrame(
  StudioThreadSession session,
  ThreadRuntimeView runtime,
) {
  return ThreadNotificationFrame(
    threadId: 'thread-main',
    epoch: session.state.streamEpoch ?? 1,
    baseRevision: session.state.revision,
    revision: session.state.revision + 1,
    update: ThreadRuntimeUpdate(runtime: runtime, todo: null),
  );
}

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
