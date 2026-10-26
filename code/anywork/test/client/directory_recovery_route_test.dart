import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/workspace/view_models/sidebar_view_model.dart';
import 'package:anywork/src/features/workspace/view_models/workspace_view_model.dart';
import 'package:anywork/src/features/workspace/workspace_screen.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart';
import 'support/pump_client_future.dart';
import 'support/selector_workspace_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const hostChannel = MethodChannel('io.github.zr233.anywork/host_lifecycle');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          hostChannel,
          (call) async => call.method == 'beginExit' ? 30000 : null,
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hostChannel, null),
  );

  Widget harness(SelectorWorkspaceEnvironment env) => UncontrolledProviderScope(
    container: env.container,
    child: MaterialApp(
      theme: pureStudioTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WorkspaceScreen(onAddProject: () {}, onNavigate: (_) {}),
    ),
  );

  Future<SelectorWorkspaceEnvironment> fixture(WidgetTester tester) async {
    late final SelectorWorkspaceEnvironment env;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpClientFuture(tester, env.close(), 'Workspace owner cleanup');
    });
    // Owners and their scripted native feeds must be created in the real async
    // zone: a Completer created inside the fake-async zone only propagates to
    // its listeners on pump(), which cannot happen while establish() itself
    // runs inside runAsync.
    await tester.runAsync(() async {
      env = SelectorWorkspaceEnvironment();
      await env.establish();
    });
    return env;
  }

  testWidgets(
    'closing the selected thread does not reopen content from workspace',
    (tester) async {
      final env = await fixture(tester);
      await pumpClientFuture(
        tester,
        env.core.selectThread('thread-main'),
        'select closing thread',
      );
      final opening = await pumpClientFuture(
        tester,
        env.core.timeline.opened(0),
        'original Timeline open',
      );
      final native = TestTimelineConnection(
        initial: baseline(1, items: [timelineItem(1, threadId: 'thread-main')]),
      );
      opening.result.complete(native);
      await tester.pumpWidget(harness(env));
      await pumpClientFuture(
        tester,
        env.core.conversations.active.value!.timeline.ready,
        'initial content baseline',
      );
      final openedWindows = env.core.timeline.requests.length;
      final closing = env.exit.exit(ExitIntent.exit);
      final report = await pumpClientFuture(
        tester,
        closing,
        'close while WorkspaceScreen remains mounted',
      );
      expect(report.shutdown.outcome, ShutdownOutcome.clean);
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      expect(env.core.timeline.requests, hasLength(openedWindows));
      expect(
        native.closeCalls + native.retryCloseCalls,
        greaterThanOrEqualTo(1),
        reason: '退出必须 join 原 Timeline handle，不得由页面销毁伪造完成',
      );
      expect(env.core.budget.usage, isEmpty);
    },
  );

  testWidgets(
    'directory failure retains the workspace and explicitly retries its typed feed',
    (tester) async {
      final env = await fixture(tester);
      await tester.runAsync(env.core.selectStart);
      await tester.pumpWidget(harness(env));
      await pumpClientUntil(
        tester,
        () => find.byKey(StudioDriverKeys.composerInput).evaluate().length == 1,
        'Start input',
      );
      await tester.pumpAndSettle();
      final input = find.byKey(StudioDriverKeys.composerInput);
      await tester.enterText(input, 'draft survives directory outage');
      final project = env.core.workspace.state.value.selection.projectId;
      env.core.directory.failProjects();
      final notice = find.byKey(const ValueKey('project-directory-failure'));
      // 目录 feed 的失败状态由 shell 通知区投影到 UI，等待该投影而不是只等 repository。
      await pumpClientUntil(
        tester,
        () => notice.evaluate().length == 1,
        'typed project-directory failure',
      );
      expect(
        env.core.workspace.projects.value.projection.sync.phase,
        ResourceSyncPhase.failed,
      );
      expect(find.byKey(StudioDriverKeys.startPage), findsOneWidget);
      expect(find.byKey(const ValueKey('studio-startup')), findsNothing);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'draft survives directory outage',
      );
      expect(env.core.workspace.state.value.selection.projectId, project);
      // 项目目录 feed 失败的 canonical 提示与显式重试入口属于 shell 通知区。
      expect(notice, findsOneWidget);
      expect(
        find.descendant(of: notice, matching: find.text('directory offline')),
        findsOneWidget,
        reason: '提示展示的是该 feed 的 typed failure',
      );
      final retry = find.byKey(const ValueKey('project-directory-retry'));
      expect(retry, findsOneWidget);
      env.core.directory.projectUnavailable = false;
      await tester.tap(retry);
      await pumpClientUntil(
        tester,
        () =>
            env.core.workspace.projects.value.projection.sync.phase ==
            ResourceSyncPhase.ready,
        'project-directory fresh baseline after explicit retry',
      );
      await tester.pumpAndSettle();
      expect(notice, findsNothing);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'draft survives directory outage',
      );
      expect(env.core.workspace.state.value.selection.projectId, project);
      expect(
        env.startupPort.base.attempts,
        hasLength(1),
        reason: 'topic 重试不能重新 bootstrap',
      );
      expect(env.core.directory.projectFeeds, hasLength(2));
      expect(
        env.container
            .read(workspaceViewModelProvider)
            .requireValue
            .workspace
            .selection
            .projectId,
        project,
      );
      expect(
        env.container
            .read(sidebarViewModelProvider)
            .requireValue
            .projects
            .projection
            .sync
            .phase,
        ResourceSyncPhase.ready,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      final closed = await pumpClientFuture(
        tester,
        env.exit.exit(ExitIntent.exit),
        'directory recovery application exit',
      );
      expect(closed.shutdown.outcome, ShutdownOutcome.clean);
    },
  );
}
