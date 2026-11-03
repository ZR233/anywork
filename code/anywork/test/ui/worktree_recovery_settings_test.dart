import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/settings_agents_tab.dart';
import 'package:anywork/src/features/settings/settings_general_tab.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_statistics_feed.dart';

Widget _host(AppGraph graph, Widget child) => ProviderScope(
  overrides: [appGraphProvider.overrideWithValue(graph)],
  child: MaterialApp(
    theme: pureStudioTheme(),
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

Future<AppGraph> _bootstrap(
  WidgetTester tester,
  RecordingDemoTransport transport,
) async {
  final graph = AppGraph(
    statisticsFeed: const TestStatisticsFeedPort(),
    transport: transport,
    clientId: 'worktree-recovery-settings',
  );
  addTearDown(() async {
    await _close(tester, graph);
  });
  await pumpClientFuture(
    tester,
    graph.client.bootstrap(),
    'worktree bootstrap',
  );
  return graph;
}

Future<void> _close(WidgetTester tester, AppGraph graph) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpClientFuture(
    tester,
    graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    'worktree settings teardown',
  );
}

void main() {
  testWidgets('工作目录故障在通用设置中展示，文件类别与诊断不重复', (tester) async {
    final graph = await _bootstrap(tester, RecordingDemoTransport());
    graph.client.recovery.apply(
      RecoveryStateSnapshot(
        revision: graph.client.recovery.state.revision + 1,
        values: const [
          StudioRecoveryIssue(
            id: 'retained-site-failure',
            scope: RecoveryIssueScope.thread,
            category: RecoveryIssueCategory.repository,
            impact: RecoveryIssueImpact.advisory,
            availableActions: [RecoveryIssueAction.retry],
            threadId: 'thread-main',
            detail: 'cleanup-failure-evidence',
            worktree: WorktreeRecoveryPreview(
              inspection: WorktreeInspection.available,
              ownerKind: WorktreeOwnerKind.session,
              ownerThreadId: 'thread-main',
              leaseRevision: 9,
              state: 'active',
              repositoryRoot: '/project',
              path: '/project/.anywork/worktrees/thread-main/session',
              branch: 'business',
              baseCommit: 'base',
              headCommit: 'head',
              dirty: true,
              changedFiles: ['src/example.rs'],
              ignoredFiles: ['build/'],
            ),
          ),
          StudioRecoveryIssue(
            id: 'unregistered-workspace',
            scope: RecoveryIssueScope.project,
            category: RecoveryIssueCategory.repository,
            impact: RecoveryIssueImpact.advisory,
            availableActions: [RecoveryIssueAction.retry],
            workspaceId: 'project-local',
            detail: 'unknown-ownership-evidence',
          ),
        ],
      ),
    );
    await tester.pumpWidget(_host(graph, const AgentsTab(tabIndex: 1)));
    await tester.pumpAndSettle();
    expect(find.textContaining('cleanup-failure-evidence'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-worktree-recovery')),
      findsNothing,
    );

    await tester.pumpWidget(
      _host(
        graph,
        GeneralTab(
          settings: const GeneralSettingsView(),
          webSearch: const WebSearchSettingsView(),
          deepSeekWebSearch: const DeepSeekWebSearchSettingsView(),
          onCommand: (_) async => fail('unexpected settings write'),
          onSaveWebSearch: (_) async =>
              throw StateError('unexpected settings write'),
          onDeepSeekSearchChanged: (_) async =>
              fail('unexpected settings write'),
          onDeepSeekFetchChanged: (_) async =>
              fail('unexpected settings write'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('settings-worktree-recovery'));
    await tester.ensureVisible(panel);
    await tester.tap(panel);
    await tester.pumpAndSettle();
    expect(find.text('待提交文件：src/example.rs'), findsOneWidget);
    expect(find.text('版本管理忽略的本地文件：build/'), findsOneWidget);
    expect(find.textContaining('已绑定'), findsOneWidget);
    expect(find.textContaining('cleanup-failure-evidence'), findsOneWidget);
    expect(find.textContaining('unknown-ownership-evidence'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('worktree-cleanup-session-thread-main')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await _close(tester, graph);
  });

  testWidgets('归档会话可查看并复制原路径，不恢复或激活会话', (tester) async {
    final transport = _WorkspaceLookupTransport();
    final graph = await _bootstrap(tester, transport);
    final metadata = graph.client.threadDirectory.observeThread('thread-main');
    final metadataState = await metadata.state
        .waitFor((state) => state.frame != null)
        .timeout(const Duration(seconds: 5));
    final root = metadataState.frame!.thread!;
    await metadata.release();
    await pumpClientFuture(
      tester,
      graph.client.threadCommands.archiveThread(root.id),
      'archive original workspace',
    );
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? copiedPath;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedPath = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(_host(graph, const StudioShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sidebar-archived')));
    await tester.pumpAndSettle();
    final lookup = find.byKey(ValueKey('thread-archived-workspace-${root.id}'));
    await tester.ensureVisible(lookup);
    final selected = graph.client.selection.state.selectedThreadId;
    final feeds = transport.feeds.length;
    await tester.tap(lookup);
    await tester.pumpAndSettle();
    expect(find.text(root.workspacePath), findsOneWidget);
    await tester.tap(find.byKey(StudioDriverKeys.copyThreadWorkspace(root.id)));
    await tester.pumpAndSettle();
    expect(copiedPath, root.workspacePath);
    expect(transport.restores, 0);
    expect(transport.feeds, hasLength(feeds));
    expect(graph.client.selection.state.selectedThreadId, selected);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('thread-restore-${root.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester, graph);
  });
}

class _WorkspaceLookupTransport extends RecordingDemoTransport {
  int restores = 0;

  @override
  Future<StudioThread> restoreThread(String threadId) {
    restores++;
    return super.restoreThread(threadId);
  }
}
