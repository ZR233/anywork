import '../support/chat_fixtures.dart';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/features/status/thread_status_bar.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_statistics_feed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('当前计划按真实状态重开，缺正文为空态且无计划时不造入口', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final transport = RecordingDemoTransport();
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'plan-runtime-document',
    );
    await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
    await pumpClientFuture(
      tester,
      (graph
            ..timeline.updateReadDemand(chatDemand)
            ..setConversationPageVisible(true))
          .client
          .directoryCommands
          .selectThread('thread-main'),
      'select thread',
    );
    await pumpClientUntil(
      tester,
      () =>
          graph.client.conversations
              .existingSession('thread-main')
              ?.state
              .hasSnapshot ==
          true,
      'thread snapshot',
    );

    final session = graph.client.conversations.session('thread-main');
    final workspace = session.state.workspace!;
    const markdown = '# Delivery Blueprint\n\nKeep the current draft readable.';
    await transport.publishWorkspace(
      workspace.copyWith(
        interactions: const [],
        runtime: workspace.runtime.copyWith(
          plan: PlanRuntimeView(
            revision: 4,
            state: PlanRuntimePhase.revisionRequested,
            updatedAt: DateTime.utc(2026, 3, 18),
            document: const PlanDocumentView(
              version: 7,
              markdown: markdown,
              contentHash: 'revision-document',
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(graph)],
        child: MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(
              width: 1100,
              height: 720,
              child: AgentWorkspacePane(threadId: 'thread-main'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(StudioDriverKeys.planDetails), findsNothing);
    final statusOverflow = find.descendant(
      of: find.byType(ThreadStatusBar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon == Icons.more_horiz,
      ),
    );
    expect(statusOverflow, findsOneWidget);
    await tester.tap(statusOverflow);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StudioDriverKeys.statusPlanEntry));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(StudioDriverKeys.planDetailsStatus)).data,
      '已请求修改',
    );
    expect(find.text('已批准'), findsNothing);
    expect(find.text('等待确认'), findsNothing);
    expect(find.byKey(const ValueKey('plan-approve')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(StudioDriverKeys.planDetailsTitle)).data,
      '实施计划',
      reason: '导航标题不再重复 Markdown 文档标题',
    );

    await tester.tap(find.byKey(StudioDriverKeys.planDetailsClose));
    await tester.pumpAndSettle();
    await transport.publishWorkspace(
      workspace.copyWith(
        interactions: const [],
        runtime: workspace.runtime.copyWith(
          plan: PlanRuntimeView(
            revision: 5,
            state: PlanRuntimePhase.drafting,
            updatedAt: DateTime.utc(2026, 3, 19),
            document: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var reopen = 0; reopen < 2; reopen++) {
      await tester.tap(statusOverflow);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(StudioDriverKeys.statusPlanEntry));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(StudioDriverKeys.planDetailsStatus))
            .data,
        '起草中',
      );
      expect(find.text('计划正在起草'), findsOneWidget);
      expect(find.text('准备好后，你可以在这里阅读完整计划。'), findsOneWidget);
      expect(find.byKey(StudioDriverKeys.planDetailsMarkdown), findsNothing);
      expect(find.byKey(StudioDriverKeys.planApprove), findsNothing);
      await tester.tap(find.byKey(StudioDriverKeys.planDetailsClose));
      await tester.pumpAndSettle();
    }

    await transport.publishWorkspace(
      workspace.copyWith(
        interactions: const [],
        runtime: workspace.runtime.copyWith(plan: null),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(StudioDriverKeys.planDetails), findsNothing);
    if (statusOverflow.evaluate().isNotEmpty) {
      await tester.tap(statusOverflow);
      await tester.pumpAndSettle();
      expect(find.byKey(StudioDriverKeys.statusPlanEntry), findsNothing);
      await tester.tapAt(const Offset(30, 30));
      await tester.pumpAndSettle();
    }

    // Exercise the actual shell footer, whose height budget is smaller than
    // the full Plan form in this viewport.
    await transport.publishWorkspace(
      workspace.copyWith(
        interactions: [
          PendingInteraction(
            id: 'short-plan',
            threadId: 'thread-main',
            turnId: 'short-turn',
            kind: InteractionKind.userInput,
            title: 'Plan',
            body: markdown,
            payload: const UserInputInteractionPayload(
              questions: [
                UserQuestionView(
                  id: agentSessionPlanConfirmationQuestionId,
                  header: 'Plan',
                  question: markdown,
                  isOther: false,
                  isSecret: false,
                  options: [],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    tester.view.physicalSize = const Size(640, 480);
    // The real shell may keep activity animations alive. Wait for the Plan
    // outlet instead of requiring all unrelated animations to stop.
    await pumpClientUntil(
      tester,
      () =>
          find.byKey(StudioDriverKeys.planDetails).evaluate().isNotEmpty &&
          find.byKey(StudioDriverKeys.planApprove).evaluate().isNotEmpty,
      'short viewport Plan outlets',
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('plan-workspace-footer-scroll')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(StudioDriverKeys.planApprove));
    await pumpClientUntil(
      tester,
      () => find
          .byKey(StudioDriverKeys.planApprove)
          .hitTestable()
          .evaluate()
          .isNotEmpty,
      'short viewport Plan approval reachable',
    );
    expect(
      find.byKey(StudioDriverKeys.planApprove).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(StudioDriverKeys.planSubmitRevision).hitTestable(),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'plan runtime document close',
    );
  });
}
