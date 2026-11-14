import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/conversation/composer/composer.dart';
import 'package:anywork/src/features/conversation/composer/views/start_environment_view.dart';
import 'package:anywork/src/features/conversation/composer/widgets/start_backend_selector.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../anywork_client/test/support/acp_business_port.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_statistics_feed.dart';
import 'acp_components_support.dart';

/// Only records transport dispatch and rejects it; production owns freezing,
/// backend selection, submission and failure handling.
final class _Transport extends RecordingDemoTransport {
  final submissions =
      <
        ({String workspaceId, StudioPromptInput input, String? workspaceMode})
      >[];

  @override
  Stream<NewThreadStartEvent> startNewThread(
    String workspaceId,
    StudioPromptInput input,
    ThreadModeId mode, {
    required ModeModelRouteView route,
    required DelegationMode delegationMode,
    required DelegationPreference delegationPreference,
    String? workspaceMode,
  }) async* {
    submissions.add((
      workspaceId: workspaceId,
      input: input,
      workspaceMode: workspaceMode,
    ));
    yield const NewThreadStartFailed(
      StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Scripted Native transport rejection after dispatch',
        retryable: false,
        correlationId: 'start-backend-integration',
      ),
    );
  }
}

Future<({AppGraph graph, _Transport transport, String workspaceId})> _mount(
  WidgetTester tester, {
  ControlledAcpBusinessPort? port,
  bool remoteSshProject = false,
}) async {
  tester.view.physicalSize = const Size(1280, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final transport = _Transport();
  final graph = AppGraph(
    transport: transport,
    statisticsFeed: const TestStatisticsFeedPort(),
    clientId: 'start-backend-integration',
    acpBusinessPort: port,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    final report = await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'close start backend graph',
    );
    expect(report.complete, isTrue, reason: '${report.unresolved}');
  });
  await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
  final projects = graph.client.project.state.projects!.values.toList();
  final localProject = projects.firstWhere(
    (project) => !project.isStandalone && project.sshAlias == null,
  );
  final project = remoteSshProject
      ? StudioProject(
          id: 'remote-acp-project',
          name: '远程 ACP 项目',
          path: '/srv/workspace',
          sshAlias: 'test-host',
        )
      : localProject;
  if (remoteSshProject) {
    graph.client.project.applyProjectDirectory(
      ProjectDirectoryState(
        revision: graph.client.project.state.projectRevision + 1,
        values: [...projects, project],
      ),
    );
  }
  graph.client.selection.selectProject(project.id);
  final accountDemand = graph.accounts.observeSummaries();
  await pumpClientFuture(
    tester,
    graph.accounts.state.waitFor((state) => state.loaded),
    'account summaries',
  );
  final accounts = graph.accounts.state.value;
  final stamp = accounts.stamp!;
  graph.accountDomains.acceptFrame(
    AccountSummariesFrame(
      ResourceStamp(
        resourceKey: stamp.resourceKey,
        ownerEpoch: stamp.ownerEpoch,
        revision: stamp.revision + 1,
      ),
      [
        ...accounts.accounts,
        const AccountSummary(
          identity: AcpAccountIdentity('test-acp'),
          name: 'Local ACP service',
          isDefault: false,
          acpEnabled: true,
          acpConnectionRevision: 29,
          capabilities: AccountCapabilities(
            setDefault: false,
            edit: true,
            remove: true,
            queryUsage: false,
            syncModels: false,
            editModels: false,
            acpAuth: true,
          ),
        ),
      ],
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appGraphProvider.overrideWithValue(graph)],
      child: acpTestApp(
        Composer(target: ComposerTarget.start(workspaceId: project.id)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await pumpClientFuture(
    tester,
    accountDemand.release(),
    'release fixture account demand',
  );
  expect(find.byType(TextField), findsOneWidget);
  return (graph: graph, transport: transport, workspaceId: project.id);
}

Finder _backendButton() => find.descendant(
  of: find.byType(StartBackendSelector),
  matching: find.byType(TextButton),
);

Future<void> _close(WidgetTester tester, AppGraph graph) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final report = await pumpClientFuture(
    tester,
    graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    'close start backend graph before timer invariant',
  );
  expect(report.complete, isTrue, reason: '${report.unresolved}');
}

void main() {
  testWidgets(
    'Native to ACP editing to Native submits the one current Client draft',
    (tester) async {
      final fixture = await _mount(tester);
      final draft = fixture.graph.client.drafts.startDraft;
      final workspaceId = fixture.workspaceId;
      await tester.enterText(find.byType(TextField), 'Native original draft');
      draft.setWorkspaceMode(workspaceId, ThreadWorkspaceMode.worktree);
      await tester.pumpAndSettle();
      final nativeMode = draft.state.forProject(workspaceId).mode;
      expect(find.byKey(StudioDriverKeys.sessionMode), findsOneWidget);
      expect(find.byKey(StudioDriverKeys.sessionSettings), findsOneWidget);
      expect(find.byKey(StudioDriverKeys.sessionWorkspaceMode), findsOneWidget);

      // The real service selector invokes the real setAcpService command.
      await tester.tap(_backendButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local ACP service'));
      await tester.pumpAndSettle();
      expect(draft.state.forProject(workspaceId).acpAccountId, 'test-acp');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Native original draft',
      );
      expect(find.byType(StartEnvironmentView), findsNothing);
      expect(find.byKey(StudioDriverKeys.sessionMode), findsNothing);
      expect(find.byKey(StudioDriverKeys.sessionSettings), findsNothing);
      expect(find.byKey(StudioDriverKeys.sessionWorkspaceMode), findsNothing);
      expect(tester.widget<TextButton>(_backendButton()).onPressed, isNotNull);
      final projectButton = find.byKey(
        const ValueKey('start-project-selector'),
      );
      expect(tester.widget<TextButton>(projectButton).onPressed, isNotNull);
      await tester.tap(projectButton);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MenuItemButton>(
              find.byKey(ValueKey('start-project-$workspaceId')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(projectButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Edited through ACP');
      expect(draft.state.forProject(workspaceId).text, 'Edited through ACP');

      draft.setAcpService(workspaceId, null);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Edited through ACP',
      );
      expect(draft.state.forProject(workspaceId).text, 'Edited through ACP');
      expect(draft.state.forProject(workspaceId).acpAccountId, isNull);
      expect(draft.state.forProject(workspaceId).mode, nativeMode);
      expect(
        draft.state.forProject(workspaceId).workspaceMode,
        ThreadWorkspaceMode.worktree,
      );
      expect(find.byKey(StudioDriverKeys.sessionMode), findsOneWidget);
      expect(find.byKey(StudioDriverKeys.sessionSettings), findsOneWidget);
      expect(find.byKey(StudioDriverKeys.sessionWorkspaceMode), findsOneWidget);

      await tester.tap(find.byKey(StudioDriverKeys.composerSubmit));
      await pumpClientUntil(
        tester,
        () =>
            fixture.transport.submissions.isNotEmpty && !draft.state.submitting,
        'Native dispatch and scripted rejection',
      );
      final submission = fixture.transport.submissions.single;
      expect(submission.workspaceId, workspaceId);
      expect(submission.input.text, 'Edited through ACP');
      expect(submission.workspaceMode, ThreadWorkspaceMode.worktree.id);
      expect(draft.state.forProject(workspaceId).text, isEmpty);
      final failed = draft.submissions.value[workspaceId]!.single;
      expect(failed.text, 'Edited through ACP');
      expect(failed.phase, ComposerSubmissionPhase.failed);
      await _close(tester, fixture.graph);
    },
  );

  testWidgets(
    'ACP creation uses SSH project despite retained Native worktree intent',
    (tester) async {
      final port = ControlledAcpBusinessPort()
        ..admission = Completer<AcpSessionObservationPort>();
      final fixture = await _mount(tester, port: port, remoteSshProject: true);
      final draft = fixture.graph.client.drafts.startDraft;
      final workspaceId = fixture.workspaceId;
      draft.setWorkspaceMode(workspaceId, ThreadWorkspaceMode.worktree);
      draft.setAcpService(workspaceId, 'test-acp');
      await tester.pumpAndSettle();
      // An empty prompt remains a valid ACP session/new, even though Native
      // mode/worktree draft choices are retained for a later switch back.
      await tester.tap(find.text('创建 ACP 会话'));
      await pumpClientUntil(
        tester,
        () => port.calls.isNotEmpty,
        'ACP dispatch',
      );
      final call = port.calls.single;
      expect(call.$1, 'open');
      final request = call.$2 as OpenAcpSessionRequestView;
      expect(request.accountId, 'test-acp');
      expect(request.expectedConnectionRevision, BigInt.from(29));
      expect(request.workspaceId, workspaceId);
      expect(workspaceId, 'remote-acp-project');
      expect(request.intent, isA<AcpNewIntentView>());
      expect(find.textContaining('ACP 服务在本机运行'), findsOneWidget);
      expect(find.text('/srv/workspace'), findsNothing);
      expect(fixture.transport.submissions, isEmpty);
      expect(
        draft.state.forProject(workspaceId).workspaceMode,
        ThreadWorkspaceMode.worktree,
      );
      // End the scripted external operation explicitly before graph shutdown.
      port.admission!.completeError(
        StateError('Scripted ACP admission failure'),
      );
      await pumpClientUntil(
        tester,
        () => !draft.state.submitting,
        'ACP rejection',
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Scripted ACP admission failure'),
        findsOneWidget,
      );
      draft.setAcpService(workspaceId, null);
      await tester.pumpAndSettle();
      expect(
        draft.state.forProject(workspaceId).workspaceMode,
        ThreadWorkspaceMode.worktree,
      );
      expect(find.byKey(StudioDriverKeys.sessionWorkspaceMode), findsOneWidget);
      await _close(tester, fixture.graph);
    },
  );
}
