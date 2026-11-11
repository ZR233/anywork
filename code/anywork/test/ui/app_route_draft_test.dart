import '../support/test_statistics_feed.dart';

import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/anywork_app.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/studio_host_lifecycle.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_view_model.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/platform/host_app_icons.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork/src/shared/studio_driver_projection.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/recording_demo_transport.dart';
import '../support/chat_fixtures.dart';
import '../support/display_fixtures.dart';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';

import '../support/pump_client_future.dart';

import 'package:anywork/src/app/routing/app_route.dart';

void main() {
  testWidgets(
    'Settings retains drafts and observes a Turn completed while hidden',
    (tester) async {
      final transport = _RouteTurnTransport();
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'route-draft-owner',
      );
      final exitFinished = Completer<void>();
      final exitCodes = <int>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(StudioHostLifecycle.channel, (
        call,
      ) async {
        switch (call.method) {
          case 'beginExit':
            return 30000;
          case 'finishExit':
            exitCodes.add(
              (call.arguments as Map<Object?, Object?>)['exitCode']! as int,
            );
            if (!exitFinished.isCompleted) exitFinished.complete();
            return null;
          case 'updateExitDiagnostics':
          case 'configureDiagnostics':
            return null;
          default:
            throw StateError('Unexpected host lifecycle call: ${call.method}');
        }
      });
      messenger.setMockMethodCallHandler(hostAppsChannel, (_) async => null);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async {
        // Keep host mocks installed while an early assertion failure unmounts
        // the real lifecycle coordinator and joins its shared exit operation.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final exiting = StudioExitCoordinator.requestExit();
        await pumpClientFuture(tester, exiting, 'teardown exit');
        await pumpClientFuture(
          tester,
          graph.close(deadline: _deadline()),
          'teardown graph close',
        );
        messenger.setMockMethodCallHandler(StudioHostLifecycle.channel, null);
        messenger.setMockMethodCallHandler(hostAppsChannel, null);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appGraphProvider.overrideWithValue(graph),
            statisticsRepositoryProvider.overrideWithValue(
              graph.statisticsRepository,
            ),
          ],
          child: const AnyworkApp(enableDesktopHost: true),
        ),
      );
      // Await the production bootstrap owner, not a timer guessed from frame count.
      await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
      await tester.pump();
      expect(find.byKey(StudioDriverKeys.startPage), findsOneWidget);
      expect(transport.bootstrapCalls, 1);
      final workspaceId = graph.client.selection.state.selectedProjectId!;
      final startOwner = graph.client.drafts.startDraft;
      await tester.enterText(
        find.byKey(StudioDriverKeys.composerInput),
        'start draft entered before Settings',
      );
      await tester.pump();
      final startRevision = startOwner.state.revision;

      await _settingsRoundTrip(tester);

      expect(graph.client.drafts.startDraft, same(startOwner));
      expect(startOwner.state.revision, startRevision);
      expect(
        startOwner.state.forProject(workspaceId).text,
        'start draft entered before Settings',
      );
      expect(_composerText(tester), 'start draft entered before Settings');
      expect(
        transport.timelineFeeds,
        isEmpty,
        reason: 'Settings navigation does not create a Thread',
      );
      expect(
        transport.stateFeeds,
        isEmpty,
        reason: 'Navigating without a Thread opens no state subscription',
      );

      // Raw completions and producer-chosen display positions are seeded separately.
      const firstPosition = 5;
      final seeded = [
        for (var i = 0; i < 40; i++)
          chatMessage('route-item-$i', completionSeq: firstPosition + i),
      ];
      transport.seedTimelineItems('thread-main', seeded);
      transport.seedDisplayBlocks(
        threadId: 'thread-main',
        blocks: [for (final entry in seeded) displaySingle(entry)],
      );
      await tester.tap(find.byKey(StudioDriverKeys.threadRow('thread-main')));
      await pumpClientUntil(
        tester,
        () =>
            graph.client.conversations
                .existingSession('thread-main')
                ?.content
                .state
                .value
                .snapshot !=
            null,
        'selected Thread timeline baseline',
      );
      await tester.pumpAndSettle();
      final session = graph.client.conversations.existingSession(
        'thread-main',
      )!;
      final attemptId = session.content.currentAttemptId?.value;
      final connection = transport.timelineFeeds.single;
      final composer = graph.client.drafts.composer('thread-main');
      final startedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final running = transport.emitTurn(
        RunningStudioTurnState(
          startedAt: startedAt,
          activity: StudioTurnActivity.responding,
        ),
      );
      await pumpClientUntil(
        tester,
        () => session.state.activeTurn == running,
        'running Turn before Settings',
      );
      // 停止入口只以 canonical 执行身份为目标：轮次运行同时发布该执行身份。
      final runningExecution = transport.emitExecution(
        session.state.runtime!,
        const AgentExecutionView(
          id: 'settings-route-execution',
          phase: AgentExecutionPhase.running,
          turnId: 'settings-route-turn',
        ),
        modelRoute: session.state.modelRoute,
      );
      await pumpClientUntil(
        tester,
        () => session.state.runtime?.execution == runningExecution.execution,
        'running execution identity',
      );
      await tester.pump();
      expect(find.byKey(StudioDriverKeys.composerStop), findsOneWidget);
      await tester.enterText(
        find.byKey(StudioDriverKeys.composerInput),
        'Thread draft entered before Settings',
      );
      await tester.pump();
      final composerStamp = composer.stamp;

      // Turn/执行事实可能伴随内容重同步；分页属于此刻实际挂载的展示代次。
      final oldLease = graph.timeline.lease('thread-main')!;
      expect(
        oldLease.hasOlder,
        isTrue,
        reason:
            'route fixture must leave older content: loaded=${oldLease.loadedCount}, reads=${transport.pageCalls}, demand=${oldLease.demand.maxItems}',
      );
      final previousPageCalls = transport.pageCalls;
      final oldPage = Completer<TimelineBatch>();
      addTearDown(() {
        if (!oldPage.isCompleted) {
          oldPage.complete(displayBatch([], placement: ChatPlacement.prepend));
        }
      });
      transport.scriptedPage = oldPage;
      final loading = graph.timeline.loadOlder(
        'thread-main',
        generation: oldLease.generation,
      );
      await pumpClientUntil(
        tester,
        () => transport.pageCalls == previousPageCalls + 1,
        'old page entered',
      );
      var hiddenFrames = 0;
      var hiddenAcks = 0;

      await _settingsRoundTrip(
        tester,
        whileSettingsOpen: () async {
          // 真正 push Settings 撤销 GUI demand，不能向已经关闭的旧 feed 注入帧。
          expect(find.byKey(StudioDriverKeys.composerInput), findsNothing);
          expect(find.byKey(StudioDriverKeys.timeline), findsNothing);
          expect(session.state.activeTurn, running);
          await pumpClientUntil(
            tester,
            () => connection.joined.isCompleted,
            'hidden feed actual close',
          );
          expect(connection.requestCloseCalls, greaterThanOrEqualTo(1));
          expect(connection.closeCalls, 1);
          expect(graph.timeline.lease('thread-main'), isNull);
          expect(
            ProviderScope.containerOf(
              tester.element(find.byType(AnyworkApp)),
              listen: false,
            ).read(liveStatusViewModelProvider('thread-main')),
            isNull,
            reason: '隐藏路由不向实时状态栏交付冻结的正文读取来源',
          );
          expect(oldLease.isRetired, isTrue);
          hiddenFrames = connection.deliveredFrames;
          hiddenAcks = connection.acknowledgements.length;
          expect(composer.state.draft, 'Thread draft entered before Settings');
          expect(composer.stamp, composerStamp);
          expect(
            session.state.runtime?.execution,
            runningExecution.execution,
            reason: 'GUI退订不取消已经运行的业务执行身份',
          );
          final completed = transport.emitTurn(
            CompletedStudioTurnState(
              startedAt: startedAt,
              completedAt: startedAt + 1,
              completion: StudioTurnCompletion.normal,
            ),
          );
          expect(completed.state, isA<CompletedStudioTurnState>());
          final completedBody = chatMessage(
            'settings-completed-body',
            body: '隐藏期间完成的真实正文',
            completionSeq: 100,
          );
          transport.seedTimelineItems('thread-main', [completedBody]);
          transport.seedDisplayBlocks(
            threadId: 'thread-main',
            blocks: [displaySingle(completedBody, historyPos: 45)],
          );
          expect(transport.runtimeCancellations, 1);
          expect(session.state.activeTurn, running, reason: '隐藏镜像不以独立订阅追赶后台事实');
          expect(connection.deliveredFrames, hiddenFrames);
          expect(connection.acknowledgements, hasLength(hiddenAcks));
          expect(find.byKey(StudioDriverKeys.settingsPage), findsOneWidget);
          expect(find.byKey(StudioDriverKeys.composerInput), findsNothing);
          expect(find.byKey(StudioDriverKeys.timeline), findsNothing);
          expect(
            graph.client.conversations.existingSession('thread-main'),
            same(session),
          );
          expect(transport.timelineFeeds, hasLength(1));
        },
      );

      await pumpClientUntil(
        tester,
        () =>
            transport.timelineFeeds.length == 2 &&
            graph.timeline.lease('thread-main') != null &&
            session.state.activeTurn == null &&
            session.state.runtime?.execution == null,
        'fresh visible feed reads hidden completion',
      );
      final newConnection = transport.timelineFeeds.last;
      final newLease = graph.timeline.lease('thread-main')!;
      expect(newConnection.subscriptionId, isNot(connection.subscriptionId));
      expect(newLease, isNot(same(oldLease)));
      final currentMessages = [...newLease.controller.messages];
      final currentBefore = newLease.olderCursor;
      oldPage.complete(
        displayBatch([
          displaySingle(chatMessage('late-old-page')),
        ], placement: ChatPlacement.prepend),
      );
      await pumpClientFuture(tester, loading, 'late page from retired lease');
      expect(newLease.controller.messages, currentMessages);
      expect(newLease.olderCursor, currentBefore);
      expect(
        newLease.controller.messages.any(
          (message) => message.id == 'late-old-page',
        ),
        isFalse,
      );

      expect(graph.client.drafts.composer('thread-main'), same(composer));
      expect(composer.stamp, composerStamp);
      expect(composer.state.draft, 'Thread draft entered before Settings');
      expect(_composerText(tester), 'Thread draft entered before Settings');
      expect(session.state.activeTurn, isNull);
      expect(
        newLease.controller.messages
            .map(
              (message) =>
                  message.metadata![chatItemPresentationKey]
                      as ChatItemPresentation,
            )
            .where(
              (item) =>
                  item.id == 'settings-completed-body' &&
                  item.atom?.lifecycle is TerminalChatAtom &&
                  item.displayUnit?.body is SingleDisplayBlock &&
                  item.atom?.completionSeq == 100,
            ),
        isNotEmpty,
        reason: '新内容基线包含隐藏期间真正提交的终态事实',
      );
      expect(find.byKey(StudioDriverKeys.composerStop), findsNothing);
      final submit = find.byKey(StudioDriverKeys.composerSubmit);
      expect(submit, findsOneWidget);
      expect(
        tester.widget<IconButton>(submit).tooltip,
        AppLocalizations.of(tester.element(submit)).composerSend,
        reason: 'the visible composer must no longer display send-and-continue',
      );
      expect(
        startOwner.state.forProject(workspaceId).text,
        'start draft entered before Settings',
      );
      expect(session.content.currentAttemptId?.value, isNot(attemptId));
      expect(session.content.state.value.snapshot != null, isTrue);
      expect(transport.timelineFeeds, hasLength(2));
      expect(connection.requestCloseCalls, greaterThanOrEqualTo(1));
      expect(connection.closeCalls, 1);
      expect(connection.deliveredFrames, hiddenFrames);
      expect(connection.acknowledgements, hasLength(hiddenAcks));
      expect(transport.bootstrapCalls, 1);
      expect(transport.runtimeSubscriptions, 2);
      expect(transport.runtimeCancellations, 1);

      transport.botProjectId = workspaceId;
      final bots = await pumpClientFuture(
        tester,
        graph.client.botsCommands.saveBot(
          expectedConfigRevision: 0,
          name: 'Route acceptance bot',
          workspaceId: workspaceId,
          appId: 'route-acceptance-app',
          secret: const BotSecretPreserve(),
        ),
        'prepare bot through the canonical command',
      );
      final botId = bots.bots.single.id;
      // Navigate the real Settings -> bot detail -> chat -> platform pages.
      // Hand-built routes would miss production registration and ID wiring.
      await _settingsRoundTrip(
        tester,
        whileSettingsOpen: () async {
          await tester.ensureVisible(
            find.byKey(StudioDriverKeys.settingsTab('bots')),
          );
          await tester.tap(find.byKey(StudioDriverKeys.settingsTab('bots')));
          await pumpClientUntil(
            tester,
            () => find
                .byKey(StudioDriverKeys.botsRow(botId))
                .evaluate()
                .isNotEmpty,
            'real bot overview',
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(StudioDriverKeys.botsRow(botId)),
          );
          await tester.tap(find.byKey(StudioDriverKeys.botsRow(botId)));
          await pumpClientUntil(
            tester,
            () => find
                .byKey(StudioDriverKeys.botsConversation('route-chat'))
                .evaluate()
                .isNotEmpty,
            'real bound chat row',
          );
          await tester.pumpAndSettle();
          final router = GoRouter.of(
            tester.element(find.byKey(StudioDriverKeys.botsBack)),
          );
          expect(router.routerDelegate.state.name, BotDetailsRoute.name);
          expect(router.routerDelegate.state.pathParameters, {'botId': botId});
          expect(graph.client.conversations.visibleThreadId.value, isNull);
          // The bound route has an ID observation independent of the sidebar query.
          final directoryDemand = graph.client.threadDirectory.observeThreads(
            DirectoryQuery(
              workspaceId: workspaceId,
              search: '__no_sidebar_match__',
            ),
            DirectoryWindow(),
          );
          final directoryFrame = await directoryDemand.state
              .waitFor((state) => state.frame != null)
              .timeout(const Duration(seconds: 5));
          expect(directoryFrame.frame!.threadIds, isEmpty);
          final metadataDemand = graph.client.threadDirectory.observeThread(
            'thread-alt',
          );
          final metadataFrame = await metadataDemand.state
              .waitFor((state) => state.frame != null)
              .timeout(const Duration(seconds: 5));
          expect(metadataFrame.frame!.row?.threadId, 'thread-alt');
          addTearDown(() async {
            await pumpClientFuture(
              tester,
              metadataDemand.release(),
              'route metadata release',
            );
            await pumpClientFuture(
              tester,
              directoryDemand.release(),
              'route directory release',
            );
          });
          // The bound route opens directly, independently of the hidden Studio page.
          graph.client.selection.beginNewThread();
          await tester.tap(
            find.byKey(StudioDriverKeys.botsConversation('route-chat')),
          );
          await pumpClientUntil(
            tester,
            () =>
                graph.client.conversations.visibleThreadId.value ==
                    'thread-alt' &&
                graph.timeline.lease('thread-alt') != null &&
                graph.client.conversations
                        .existingSession('thread-alt')
                        ?.content
                        .state
                        .value
                        .snapshot !=
                    null,
            'registered bot chat receives a fresh baseline',
          );
          await tester.pumpAndSettle();
          final botFeed = transport.timelineFeeds.last;
          final botLease = graph.timeline.lease('thread-alt')!;
          expect(botLease, isNot(same(newLease)));
          expect(router.routerDelegate.state.name, BotConversationRoute.name);
          expect(router.routerDelegate.state.pathParameters, {
            'botId': botId,
            'chatId': 'route-chat',
            'threadId': 'thread-alt',
          });
          expect(_composerText(tester), isEmpty);
          await tester.enterText(
            find.byKey(StudioDriverKeys.composerInput),
            'Bot draft follows route target',
          );
          await tester.pump();
          final facts = queryStudioDriverFacts(
            graph.client,
            timeline: graph.timeline,
            accountsRepository: graph.accounts,
            modelsRepository: graph.models,
            usageRepository: graph.accountUsage,
            acpService: graph.acp,
          );
          expect(facts.timeline!.threadId, 'thread-alt');
          expect(facts.workspace!.threadId, 'thread-alt');
          expect(facts.workspacesByThread, contains('thread-alt'));
          expect(facts.threadComposer.draft, 'Bot draft follows route target');
          final observed = jsonDecode(
            StudioDriverState.snapshotJson(observed: facts),
          ) as Map;
          expect(observed['navigation']['visibleThreadId'], 'thread-alt');
          expect(observed['navigation']['selectedThreadId'], isNull);
          expect(observed['navigation']['isStartPage'], isFalse);
          // The visible Conversation owns exact-ID metadata even though the
          // independent sidebar query still has no matching rows.
          expect(graph.client.findThread('thread-alt'), isNotNull);
          expect(facts.workspace!.threadId, 'thread-alt');
          expect(directoryDemand.state.value.frame!.threadIds, isEmpty);
          expect(find.byKey(StudioDriverKeys.sessionMode), findsOneWidget);
          expect(graph.client.selection.state.selectedThreadId, isNull);
          unawaited(
            showDialog<void>(
              context: tester.element(find.byKey(StudioDriverKeys.timeline)),
              builder: (_) => const AlertDialog(content: Text('Dialog')),
            ),
          );
          await tester.pumpAndSettle();
          expect(graph.timeline.lease('thread-alt'), same(botLease));
          expect(botFeed.requestCloseCalls, 0);
          Navigator.of(tester.element(find.byType(AlertDialog))).pop();
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(StudioDriverKeys.botsPlatformTools));
          await pumpClientUntil(
            tester,
            () => botFeed.joined.isCompleted,
            'platform tools close the hidden bot chat feed',
          );
          await tester.pumpAndSettle();
          expect(graph.client.conversations.visibleThreadId.value, isNull);
          expect(graph.timeline.lease('thread-alt'), isNull);
          expect(router.routerDelegate.state.name, BotPlatformToolsRoute.name);
          expect(router.routerDelegate.state.pathParameters, {
            'botId': botId,
            'chatId': 'route-chat',
          });
          await tester.tap(find.byKey(StudioDriverKeys.botsBack));
          await pumpClientUntil(
            tester,
            () =>
                graph.timeline.lease('thread-alt') != null &&
                graph.client.conversations
                        .existingSession('thread-alt')
                        ?.content
                        .state
                        .value
                        .snapshot !=
                    null,
            'returning from platform tools acquires a new bot baseline',
          );
          await tester.pumpAndSettle();
          expect(_composerText(tester), 'Bot draft follows route target');
          final returnedFeed = transport.timelineFeeds.last;
          expect(graph.timeline.lease('thread-alt'), isNot(same(botLease)));
          await tester.tap(find.byKey(StudioDriverKeys.botsChatBack));
          await pumpClientUntil(
            tester,
            () => returnedFeed.joined.isCompleted,
            'returning to bot details retires the bot chat',
          );
          await tester.pumpAndSettle();
          expect(graph.client.conversations.visibleThreadId.value, isNull);
          expect(graph.timeline.lease('thread-alt'), isNull);
          expect(composer.stamp, composerStamp);
          expect(router.routerDelegate.state.name, BotDetailsRoute.name);
          final feedCount = transport.timelineFeeds.length;
          unawaited(
            BotConversationRoute(
              botId: botId,
              chatId: 'route-chat',
              threadId: 'missing-thread',
            ).push<void>(tester.element(find.byKey(StudioDriverKeys.botsBack))),
          );
          await tester.pumpAndSettle();
          await pumpClientUntil(
            tester,
            () => find
                .byKey(const ValueKey('conversation-directory-retry'))
                .evaluate()
                .isNotEmpty,
            'unavailable route does not display the previous selection',
          );
          expect(graph.client.conversations.visibleThreadId.value, isNull);
          expect(find.byKey(StudioDriverKeys.timeline), findsNothing);
          expect(transport.timelineFeeds, hasLength(feedCount));
          await tester.tap(
            find.byKey(const ValueKey('conversation-directory-retry')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('conversation-directory-retry')),
            findsOneWidget,
          );
          expect(transport.timelineFeeds, hasLength(feedCount));
          expect(
            graph.client.drafts.existingComposer('missing-thread'),
            isNull,
          );
          await tester.tap(find.byKey(StudioDriverKeys.botsChatBack));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(StudioDriverKeys.botsBack));
          await tester.pumpAndSettle();
          expect(router.routerDelegate.state.name, SettingsRoute.name);
          expect(
            graph.client.drafts.existingComposer('missing-thread'),
            isNull,
          );
          graph.client.selection.selectThread(
            threadId: 'thread-main',
            workspaceId: workspaceId,
          );
          expect(graph.client.conversations.visibleThreadId.value, isNull);
        },
      );

      // Unmount through the real lifecycle coordinator. Only the host channel is
      // mocked, so the test cannot ask the native runner to exit this test process.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpClientUntil(
        tester,
        () => exitFinished.isCompleted,
        'host finishExit',
      );
      await pumpClientFuture(
        tester,
        StudioExitCoordinator.requestExit(),
        'repeat exit',
      );
      expect(exitCodes, [0]);
      expect(
        (await pumpClientFuture(
          tester,
          graph.close(deadline: _deadline()),
          'repeat graph close',
        )).complete,
        isTrue,
      );
      expect(connection.joined.isCompleted, isTrue);
      expect(newConnection.joined.isCompleted, isTrue);
      expect(
        transport.timelineFeeds.every((feed) => feed.joined.isCompleted),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

Future<void> _settingsRoundTrip(
  WidgetTester tester, {
  Future<void> Function()? whileSettingsOpen,
}) async {
  await tester.tap(find.byKey(StudioDriverKeys.settingsOpen));
  await tester.pumpAndSettle();
  expect(find.byKey(StudioDriverKeys.settingsPage), findsOneWidget);
  // The first category change must retain the shell just like later changes:
  // replacing a pushed Settings page with a declarative match loses its key.
  final settingsShell = tester.element(
    find.byKey(StudioDriverKeys.settingsPage),
  );
  final navigation = tester.element(find.byKey(StudioDriverKeys.settingsBack));
  final controller = DefaultTabController.of(navigation);
  for (final tab in ['general', 'agents', 'accounts']) {
    final target = find.byKey(StudioDriverKeys.settingsTab(tab));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.byKey(StudioDriverKeys.settingsPage), findsOneWidget);
    expect(
      tester.element(find.byKey(StudioDriverKeys.settingsPage)),
      same(settingsShell),
      reason: 'Switching to $tab must retain the Settings shell',
    );
    expect(
      tester.element(find.byKey(StudioDriverKeys.settingsBack)),
      same(navigation),
      reason: 'Switching to $tab must retain the Settings sidebar',
    );
    expect(
      DefaultTabController.of(
        tester.element(find.byKey(StudioDriverKeys.settingsBack)),
      ),
      same(controller),
    );
  }
  await whileSettingsOpen?.call();
  await tester.tap(find.byKey(StudioDriverKeys.settingsBack));
  await tester.pumpAndSettle();
  expect(find.byKey(StudioDriverKeys.settingsPage), findsNothing);
}

String _composerText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(StudioDriverKeys.composerInput))
    .controller!
    .text;

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));

/// 只选择权威发布时点；状态与正文均由 Demo 自身发布点生成，不向旧 feed 注入事实。
final class _RouteTurnTransport extends RecordingDemoTransport {
  _RouteTurnTransport() {
    timelineFeedFactory = (_, inner) async => _RouteTimelineFeed(inner, this);
  }
  int _turnUpdates = 0;
  int runtimeSubscriptions = 0;
  int runtimeCancellations = 0;
  late String botProjectId;
  Completer<TimelineBatch>? scriptedPage;
  int pageCalls = 0;

  @override
  Future<BotConversationPage> listBotConversations(
    ListBotConversationsRequest request,
  ) async => BotConversationPage(
    botId: request.botId,
    conversations: [
      BotConversation(
        chatId: 'route-chat',
        kind: BotConversationKind.direct,
        source: BotConversationSource.observedDirect,
        name: 'Bound route conversation',
        threadBinding: BotConversationThreadBinding(
          botId: request.botId,
          chatId: 'route-chat',
          workspaceId: botProjectId,
          threadId: 'thread-alt',
          revision: 1,
          state: BotConversationThreadState.bound,
        ),
      ),
    ],
  );

  @override
  Future<TimelineFeed> openTimelineFeed(
    String threadId, {
    required ReadDemand demand,
  }) async {
    final feed = await super.openTimelineFeed(threadId, demand: demand);
    if (threadId != 'thread-main') return feed;
    final owner = feed as RecordingTimelineFeed;
    runtimeSubscriptions++;
    owner.onClosed = () {
      runtimeCancellations++;
    };
    return owner;
  }

  StudioTurnView emitTurn(StudioTurnState state) {
    final turn = StudioTurnView(
      turnId: 'settings-route-turn',
      threadId: 'thread-main',
      revision: 0, // Demo 权威发布点分配真实 revision。
      state: state,
      updatedAt: DateTime.now().add(Duration(seconds: ++_turnUpdates)),
    );
    final workspace = seedConversationState(
      'thread-main',
      ThreadTurnUpdate(turn),
    );
    return workspace.activeTurn ?? turn;
  }

  /// 发布一次 canonical 运行时投影，只用于给出该轮次的执行身份。
  ///
  /// 执行身份与轮次一样只能来自会话状态，不由活动快照或界面记忆推断。
  /// 路由是独立的 Thread 状态领域，本帧只改 runtime，调用方显式给出当前
  /// 路由，使既有 route 不被这一帧清空。
  ThreadRuntimeView emitExecution(
    ThreadRuntimeView current,
    AgentExecutionView? execution, {
    required ThreadModelRouteView? modelRoute,
  }) {
    final next = current.copyWith(execution: execution);
    return seedConversationState(
      'thread-main',
      ThreadRuntimeUpdate(runtime: next, todo: null, modelRoute: modelRoute),
    ).runtime;
  }
}

final class _RouteTimelineFeed extends RecordingTimelineFeed {
  _RouteTimelineFeed(TimelineFeed inner, this.transport) : super(inner: inner);
  final _RouteTurnTransport transport;
  @override
  Future<TimelineBatch> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) {
    transport.pageCalls++;
    final gate = transport.scriptedPage;
    transport.scriptedPage = null;
    return gate?.future ??
        super.loadTimelineOlder(before: before, demand: demand);
  }
}
