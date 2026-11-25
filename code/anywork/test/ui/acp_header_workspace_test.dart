import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/shell/agent_switcher_menu.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/platform/terminal_launcher.dart';
import 'package:anywork/src/platform/vscode_launcher.dart';
import 'package:anywork/src/platform/zed_launcher.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_app_lifecycle.dart';
import '../support/test_statistics_feed.dart';

final _project = StudioProject(id: 'project', name: 'Demo', path: '/workspace');

SessionDirectoryRow _root({required bool acp}) => SessionDirectoryRow(
  sessionId: 'session',
  agentId: 'root-agent',
  threadId: 'root-thread',
  workspaceId: _project.id,
  title: '根会话',
  mode: null,
  delegationMode: DelegationMode.automatic,
  delegationPreference: DelegationPreference.fast,
  workspacePath: '/workspace',
  role: 'root',
  backend: acp
      ? const AcpAgentBackendView(
          reference: AcpSessionReferenceView(
            accountId: 'account',
            acpSessionId: 'remote',
            cwd: '/should-not-be-inferred',
          ),
        )
      : const NativeAgentBackendView(
          config: NativeAgentConfigView(),
          status: ThreadStatusView.idle,
        ),
  updatedAt: DateTime.utc(2025),
);

final _nativeAgent = StudioAgentView(
  agentId: 'root-agent',
  sessionId: 'session',
  threadId: 'root-thread',
  role: 'root',
  delegationMode: DelegationMode.automatic,
  delegationPreference: DelegationPreference.fast,
  task: 'root',
  activity: const NativeStudioAgentActivity(state: IdleStudioAgent()),
  updatedAt: DateTime.utc(2025),
);

HeaderView _header({
  required SessionDirectoryRow? row,
  required StudioProject? project,
  List<StudioAgentView> agents = const [],
  SessionCostView? sessionCost,
}) => HeaderView(
  selectedRootRow: row,
  selectedProject: project,
  selectedProjectId: project?.id,
  workspaceRows: [?row],
  agents: agents,
  selectedThreadId: row?.threadId,
  runtime: const ThreadRuntimeView(
    modelId: '',
    contextTokens: 0,
    contextWindow: 0,
    totalTokens: 0,
    costLabel: '',
    activeSkills: [],
    activeMcpServers: [],
    activeLspServers: [],
  ),
  sessionCost: sessionCost,
  pendingInteractions: const [],
);

Widget _host(HeaderView state, {double width = 900, required AppGraph graph}) =>
    ProviderScope(
      overrides: [
        appGraphProvider.overrideWithValue(graph),
        vsCodeAvailabilityProvider.overrideWith((ref) async => true),
        zedAvailabilityProvider.overrideWith((ref) async => true),
        terminalAvailabilityProvider.overrideWith((ref) async => true),
      ],
      child: MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: SessionHeader(state: state),
          ),
        ),
      ),
    );

AppGraph _testGraph(WidgetTester tester) {
  final graph = testAppGraph(
    transport: RecordingDemoTransport(),
    clientId: 'acp-header-test',
    statisticsFeed: const TestStatisticsFeedPort(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    final report = await pumpClientFuture(
      tester,
      graph.close(budget: testCloseBudget()),
      'ACP header graph teardown',
    );
    expect(report.complete, isTrue, reason: describeTestCloseReport(report));
  });
  return graph;
}

void main() {
  testWidgets(
    'ACP root without members retains workspace entry and no Native details',
    (tester) async {
      final graph = _testGraph(tester);
      await tester.pumpWidget(
        _host(
          _header(row: _root(acp: true), project: _project),
          graph: graph,
        ),
      );
      await tester.pump();
      expect(
        find.byKey(StudioDriverKeys.sessionOpenWorkspaceMenu),
        findsOneWidget,
      );
      expect(find.byType(AgentSwitcherMenu), findsNothing);
      expect(find.textContaining('自动选模'), findsNothing);
      expect(find.textContaining('快速'), findsNothing);
      expect(find.textContaining('Native'), findsNothing);
      expect(find.textContaining('/should-not-be-inferred'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Native root retains member menu and workspace entry at narrow and wide widths',
    (tester) async {
      final graph = _testGraph(tester);
      final state = _header(
        row: _root(acp: false),
        project: _project,
        agents: [_nativeAgent],
      );
      await tester.pumpWidget(_host(state, width: 360, graph: graph));
      await tester.pump();
      expect(
        find.byKey(StudioDriverKeys.sessionOpenWorkspaceMenu),
        findsOneWidget,
      );
      expect(find.byType(AgentSwitcherMenu), findsOneWidget);
      expect(find.textContaining('自动选模'), findsOneWidget);
      expect(find.textContaining('快速'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_host(state, width: 1000, graph: graph));
      await tester.pump();
      expect(
        find.byKey(StudioDriverKeys.sessionOpenWorkspaceMenu),
        findsOneWidget,
      );
      expect(find.byType(AgentSwitcherMenu), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native session cost keeps the amount when usage is incomplete', (
    tester,
  ) async {
    final graph = _testGraph(tester);
    final costChip = find.byKey(StudioDriverKeys.sessionCost);
    const amount = RuntimeCostView(currency: 'USD', amount: 0.25);
    for (final (incomplete, unpriced) in [(true, false), (false, true)]) {
      final cost = SessionCostView(
        rootThreadId: 'root-thread',
        purposeCosts: [
          PurposeCostView(
            purpose: 'main',
            estimatedCosts: const [amount],
            hasUnpricedUsage: unpriced,
          ),
        ],
        estimatedCosts: const [amount],
        hasUnpricedUsage: unpriced,
        hasIncompleteUsage: incomplete,
      );
      await tester.pumpWidget(
        _host(
          _header(
            row: _root(acp: false),
            project: _project,
            agents: [_nativeAgent],
            sessionCost: cost,
          ),
          width: 360,
          graph: graph,
        ),
      );
      await tester.pump();
      expect(
        find.descendant(of: costChip, matching: find.text(r'$0.25')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: costChip, matching: find.text('用量不完整')),
        incomplete ? findsOneWidget : findsNothing,
      );
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: costChip, matching: find.byType(Tooltip)),
      );
      expect(
        tooltip.message,
        unpriced ? contains('未计价') : isNot(contains('未计价')),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('workspace menu is absent without project qualification', (
    tester,
  ) async {
    final graph = _testGraph(tester);
    await tester.pumpWidget(
      _host(_header(row: _root(acp: true), project: null), graph: graph),
    );
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.sessionOpenWorkspaceMenu), findsNothing);
    await tester.pumpWidget(
      _host(_header(row: null, project: _project), graph: graph),
    );
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.sessionOpenWorkspaceMenu), findsNothing);
  });

  testWidgets('workspace click uses the canonical selected workspace path', (
    tester,
  ) async {
    final graph = _testGraph(tester);
    String? openedUri;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appGraphProvider.overrideWithValue(graph),
          vsCodeAvailabilityProvider.overrideWith((ref) async => true),
          zedAvailabilityProvider.overrideWith((ref) async => false),
          terminalAvailabilityProvider.overrideWith((ref) async => false),
          vsCodeLauncherProvider.overrideWith(
            (ref) => (uri) async {
              openedUri = uri;
            },
          ),
        ],
        child: MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SessionHeader(
              state: _header(row: _root(acp: true), project: _project),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(StudioDriverKeys.sessionOpenWorkspaceMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StudioDriverKeys.sessionOpenWorkspaceVsCode));
    await tester.pumpAndSettle();
    expect(openedUri, 'file:///workspace/');
    expect(tester.takeException(), isNull);
  });
}
