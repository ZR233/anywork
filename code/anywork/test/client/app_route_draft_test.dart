import 'package:anywork/src/app/anywork_app.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/workspace.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/platform/host_app_icons.dart';
import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart';
import 'support/application_environment.dart';
import 'support/selector_conversation_port.dart';
import 'support/pump_client_future.dart';

void main() {
  testWidgets(
    'Settings retains drafts and observes a Turn completed while hidden',
    (tester) async {
      final environment = ApplicationTestEnvironment()..installHost();
      final graph = environment.graph;
      final domains = environment.domains;
      final exitFinished = environment.hostFinished;
      final exitCodes = environment.exitCodes;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(hostAppsChannel, (_) async => null);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async {
        // Keep host mocks installed while an early assertion failure unmounts
        // the real lifecycle coordinator and joins its shared exit operation.
        environment.releaseNativeReads();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        final exiting = graph.exitCoordinator.requestHostExit(ExitIntent.exit);
        await pumpClientFuture(tester, exiting, 'teardown exit');
        await pumpClientFuture(
          tester,
          environment.close(),
          'teardown graph close',
        );
        messenger.setMockMethodCallHandler(hostAppsChannel, null);
      });

      await pumpClientFuture(
        tester,
        domains.establish(catalog: false),
        'domain baselines',
      );
      await pumpClientFuture(
        tester,
        domains.selectStart(),
        'Start preparation',
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: environment.container,
          child: AnyworkApp(
            graph: graph,
            desktopHostBuilder: (_, child) => child,
          ),
        ),
      );
      // Await the production bootstrap owner, not a timer guessed from frame count.
      await pumpClientFuture(tester, graph.bootstrap.start(), 'bootstrap');
      await tester.pumpAndSettle();
      expect(find.byKey(StudioDriverKeys.startPage), findsOneWidget);
      expect(environment.startupPort.initializeCalls, 1);
      final projectId = graph.workspace.state.value.selection.projectId!;
      final startOwner = graph.drafts.start(projectId);
      await tester.enterText(
        find.byKey(StudioDriverKeys.composerInput),
        'start draft entered before Settings',
      );
      await tester.pump();
      final startRevision = startOwner.state.value.stamp;

      await _settingsRoundTrip(tester, environment);

      expect(graph.drafts.start(projectId), same(startOwner));
      expect(startOwner.state.value.stamp, startRevision);
      expect(
        startOwner.state.value.text,
        'start draft entered before Settings',
      );
      expect(_composerText(tester), 'start draft entered before Settings');
      expect(
        domains.timeline.requests,
        isEmpty,
        reason: 'Settings navigation does not create a Thread',
      );

      await tester.tap(find.byKey(StudioDriverKeys.threadRow('thread-main')));
      await pumpClientUntil(
        tester,
        () =>
            graph.conversation.existingSession('thread-main') != null &&
            domains.timeline.requests.isNotEmpty,
        'selected Thread timeline baseline',
      );
      final connection = TestTimelineConnection(
        initial: baseline(1, items: [timelineItem(1, threadId: 'thread-main')]),
      );
      domains.timeline.requests.single.result.complete(connection);
      final session = graph.conversation.existingSession('thread-main')!;
      await pumpClientFuture(
        tester,
        session.timeline.ready,
        'Thread timeline baseline',
      );
      await tester.pumpAndSettle();
      final attemptId = session.timeline.state.value.attemptId;
      final composer = graph.drafts.composer('thread-main');
      final startedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final running = TurnBrief(
        reference: const TurnReadRef(entry: 40, revision: 1),
        revision: 1,
        updatedAt: startedAt,
        state: TurnBriefState.running(
          startedAt: startedAt,
          phase: TurnPhase.responding,
        ),
      );
      await pumpClientFuture(
        tester,
        domains.conversationPort.publishExecution(
          selectorExecution(
            status: ThreadStatus.running,
            active: running,
            execution: const AgentExecution(
              id: 'settings-route-execution',
              phase: AgentExecutionPhase.running,
              turnId: 'settings-route-turn',
            ),
          ),
        ),
        'running Turn publication',
      );
      await pumpClientUntil(
        tester,
        () => session.execution.value.value?.activeTurn == running,
        'running Turn before Settings',
      );
      // 停止入口只以 canonical 执行身份为目标：轮次运行同时发布该执行身份。
      await pumpClientUntil(
        tester,
        () =>
            session.execution.value.value?.execution?.id ==
            'settings-route-execution',
        'running execution identity',
      );
      await tester.pump();
      expect(find.byKey(StudioDriverKeys.composerStop), findsOneWidget);
      await tester.enterText(
        find.byKey(StudioDriverKeys.composerInput),
        'Thread draft entered before Settings',
      );
      await tester.pump();
      final composerStamp = composer.state.value.stamp;

      await _settingsRoundTrip(
        tester,
        environment,
        whileSettingsOpen: () async {
          // This notification must reach the application owner with both of its
          // business observers hidden by the real Settings route.
          expect(find.byKey(StudioDriverKeys.composerInput), findsNothing);
          expect(find.byKey(StudioDriverKeys.timeline), findsNothing);
          expect(session.execution.value.value?.activeTurn, running);
          expect(domains.conversationPort.facets.execution, hasLength(1));
          expect(
            domains
                .conversationPort
                .facets
                .execution
                .single
                .feed
                .requestCloseCalls,
            0,
          );
          final completed = running.copyWith(
            reference: const TurnReadRef(entry: 40, revision: 2),
            revision: 2,
            updatedAt: startedAt + 1,
            state: TurnBriefState.completed(
              startedAt: startedAt,
              completedAt: startedAt + 1,
              completion: TurnCompletion.normal,
            ),
          );
          await pumpClientFuture(
            tester,
            domains.conversationPort.publishExecution(
              selectorExecution(terminal: completed),
            ),
            'terminal Turn publication while Settings is visible',
          );
          await pumpClientUntil(
            tester,
            () =>
                session.execution.value.value?.recentTerminalTurn ==
                    completed &&
                session.execution.value.value?.activeTurn == null,
            'completed Turn while Settings hides the workspace',
          );
          // 轮次结束即执行结束；停止入口与发送语义随之回到普通发送。
          await pumpClientUntil(
            tester,
            () => session.execution.value.value?.execution == null,
            'execution ended with the Turn',
          );
          expect(find.byKey(StudioDriverKeys.settingsPage), findsOneWidget);
          expect(find.byKey(StudioDriverKeys.composerInput), findsNothing);
          expect(find.byKey(StudioDriverKeys.timeline), findsNothing);
          expect(
            graph.conversation.existingSession('thread-main'),
            same(session),
          );
          expect(session.timeline.state.value.attemptId, attemptId);
          expect(connection.requestCloseCalls, 0);
          expect(connection.closeCalls, 0);
        },
      );

      expect(graph.drafts.composer('thread-main'), same(composer));
      expect(composer.state.value.stamp, composerStamp);
      expect(composer.state.value.text, 'Thread draft entered before Settings');
      expect(_composerText(tester), 'Thread draft entered before Settings');
      expect(session.execution.value.value?.activeTurn, isNull);
      expect(
        session.execution.value.value?.recentTerminalTurn?.state,
        isA<CompletedTurnBrief>(),
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
        startOwner.state.value.text,
        'start draft entered before Settings',
      );
      expect(session.timeline.state.value.attemptId, attemptId);
      expect(session.timeline.state.value.lastStamp != null, isTrue);
      expect(domains.timeline.requests, hasLength(1));
      expect(connection.requestCloseCalls, 0);
      expect(connection.closeCalls, 0);
      expect(environment.startupPort.initializeCalls, 1);
      expect(domains.conversationPort.facets.execution, hasLength(1));
      expect(
        domains.conversationPort.facets.execution.single.feed.requestCloseCalls,
        0,
      );

      // Unmount through the real lifecycle coordinator. Only the host channel is
      // mocked, so the test cannot ask the native runner to exit this test process.
      environment.releaseNativeReads();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpClientUntil(
        tester,
        () => exitFinished.isCompleted,
        'host finishExit',
      );
      await pumpClientFuture(
        tester,
        graph.exitCoordinator.requestHostExit(ExitIntent.exit),
        'repeat exit',
      );
      expect(exitCodes, [0]);
      expect(
        (await pumpClientFuture(
              tester,
              graph.exitCoordinator.exit(ExitIntent.exit),
              'repeat graph close',
            )).shutdown.outcome ==
            ShutdownOutcome.clean,
        isTrue,
      );
      expect(connection.closeCompleted.isCompleted, isTrue);
      expect(tester.takeException(), isNull);
      await pumpClientFuture(
        tester,
        environment.close(),
        'body owned fixture close before widget invariants',
      );
    },
  );
}

Future<void> _settingsRoundTrip(
  WidgetTester tester,
  ApplicationTestEnvironment environment, {
  Future<void> Function()? whileSettingsOpen,
}) async {
  await tester.tap(find.byKey(StudioDriverKeys.settingsOpen));
  // Accounts is the initial tab. This synthetic native environment explicitly
  // declares no ACP templates; answer the admitted read, not an unknown VM value.
  await pumpClientUntil(
    tester,
    () => environment.acpPort.catalogReads.isNotEmpty,
    'Accounts native ACP catalog read',
  );
  expect(environment.acpPort.catalogReads, hasLength(1));
  if (!environment.acpPort.catalogReads.single.isCompleted) {
    environment.acpPort.answerCatalogRead(0, AcpAccountCatalog.empty);
  }
  await tester.pumpAndSettle();
  expect(find.byKey(StudioDriverKeys.settingsPage), findsOneWidget);
  for (final tab in ['general', 'agents', 'accounts']) {
    final target = find.byKey(StudioDriverKeys.settingsTab(tab));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.byKey(StudioDriverKeys.settingsPage), findsOneWidget);
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
