import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_client_future.dart';
import 'support/recording_demo_transport.dart';
import 'support/test_statistics_feed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('要求修订且现有文档时只读详情显示真实状态，不是已批准', (
    tester,
  ) async {
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
      (graph..setConversationPageVisible(true)).client.directoryCommands
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
    await tester.tap(find.byIcon(Icons.more_horiz));
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

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'plan runtime document close',
    );
  });
}
