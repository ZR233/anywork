import 'dart:ui' as ui;

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/shell/agent_switcher_menu.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_statistics_feed.dart';

const _rootId = 'thread-main';
const _selectedId = 'thread-selected';

StudioAgentView _layoutAgent({
  required String threadId,
  required String task,
  required StudioAgentState state,
  String? parentAgentId,
  AgentExecutionView? execution,
  bool canStop = false,
  bool awaitingScheduling = false,
}) {
  return StudioAgentView(
    agentId: threadId,
    sessionId: _rootId,
    parentAgentId: parentAgentId ?? _rootId,
    threadId: threadId,
    role: 'executor',
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    task: task,
    state: state,
    updatedAt: DateTime.utc(2026, 1, 1),
    execution: execution,
    canStop: canStop,
    awaitingScheduling: awaitingScheduling,
  );
}

List<StudioAgentView> _layoutAgents({bool selectedWaiting = false}) => [
  _layoutAgent(
    threadId: _selectedId,
    task: 'Selected executor with a deliberately long task title',
    state: selectedWaiting
        ? const IdleStudioAgent()
        : const RunningStudioAgent('selected-turn'),
    execution: selectedWaiting
        ? null
        : const AgentExecutionView(
            id: 'selected-execution',
            phase: AgentExecutionPhase.running,
            turnId: 'selected-turn',
          ),
    canStop: !selectedWaiting,
    awaitingScheduling: selectedWaiting,
  ),
  _layoutAgent(
    threadId: 'thread-waiting',
    task: 'Waiting for the main agent to schedule the next independent task',
    state: const IdleStudioAgent(),
    awaitingScheduling: true,
  ),
  _layoutAgent(
    threadId: 'thread-faulted',
    task: 'Faulted member keeps the diagnostic discoverable without changing row identity',
    state: const FaultedStudioAgent(
      failure: AgentStateError(
        code: 'failed',
        message: 'The synthetic member failed',
        retryable: false,
      ),
      diagnosticTurnId: 'faulted-turn',
    ),
  ),
  _layoutAgent(
    threadId: 'thread-running',
    task: 'Running member with a long title to exercise the status and trailing columns',
    state: const RunningStudioAgent('running-turn'),
    execution: const AgentExecutionView(
      id: 'running-execution',
      phase: AgentExecutionPhase.running,
      turnId: 'running-turn',
    ),
    canStop: true,
  ),
];

List<StudioAgentView> _agentsWithSelectedState({
  required StudioAgentState state,
  AgentExecutionView? execution,
  bool canStop = false,
  bool awaitingScheduling = false,
}) => [
  _layoutAgent(
    threadId: _selectedId,
    task: 'Selected executor with a deliberately long task title',
    state: state,
    execution: execution,
    canStop: canStop,
    awaitingScheduling: awaitingScheduling,
  ),
  ..._layoutAgents().skip(1),
];

List<StudioAgentView> _deepLayoutAgents() => [
  _layoutAgent(
    threadId: 'thread-deep-a',
    task: 'First level member',
    state: const IdleStudioAgent(),
  ),
  _layoutAgent(
    threadId: 'thread-deep-b',
    task: 'Second level member',
    state: const IdleStudioAgent(),
    parentAgentId: 'thread-deep-a',
  ),
  _layoutAgent(
    threadId: 'thread-deep-c',
    task: 'Third level member',
    state: const IdleStudioAgent(),
    parentAgentId: 'thread-deep-b',
  ),
];

Future<AppGraph> _layoutGraph(WidgetTester tester) async {
  final graph = AppGraph(
    transport: RecordingDemoTransport(),
    clientId: 'agent-list-layout-test',
    statisticsFeed: const TestStatisticsFeedPort(),
  );
  await pumpClientFuture(
    tester,
    graph.client.bootstrap(),
    'agent layout bootstrap',
  );
  graph.client.project.applyAgentDirectory(
    AgentDirectoryState(revision: 1, values: _layoutAgents()),
  );
  return graph;
}

Future<void> _pumpAgentMenu(
  WidgetTester tester,
  AppGraph graph,
  List<StudioAgentView> agents, {
  String? selectedThreadId = _selectedId,
  List<StudioRecoveryIssue> recoveryIssues = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appGraphProvider.overrideWithValue(graph)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: pureStudioTheme(),
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AgentSwitcherMenu(
            agents: agents,
            workspaceRows: const [],
            recoveryIssues: recoveryIssues,
            selectedThreadId: selectedThreadId,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _ensureLayoutMenuOpen(WidgetTester tester) async {
  if (find.byKey(StudioDriverKeys.agentRow(_selectedId)).evaluate().isEmpty) {
    await _openLayoutMenu(tester);
  }
}

class _AgentGeometry {
  const _AgentGeometry(this.rects, this.rowHeight);

  final Map<String, ui.Rect> rects;
  final double rowHeight;
}

_AgentGeometry _agentGeometry(WidgetTester tester, String threadId) {
  ui.Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));

  return _AgentGeometry({
    'task': tester.getRect(
      find.byKey(StudioDriverKeys.agentTaskSummary(threadId)),
    ),
    'model': tester.getRect(find.byKey(StudioDriverKeys.agentModel(threadId))),
    'selection': rect('agent-selection-slot-$threadId'),
    'status': rect('agent-status-slot-$threadId'),
    'action': rect('agent-action-slot-$threadId'),
  }, tester.getRect(find.byKey(StudioDriverKeys.agentRow(threadId))).height);
}

void _expectAgentGeometryStable(
  _AgentGeometry before,
  _AgentGeometry after, {
  required String reason,
}) {
  for (final name in before.rects.keys) {
    final expected = before.rects[name]!;
    final actual = after.rects[name]!;
    expect(
      actual.left,
      closeTo(expected.left, 0.01),
      reason: '$reason: $name left',
    );
    expect(
      actual.right,
      closeTo(expected.right, 0.01),
      reason: '$reason: $name right',
    );
    expect(
      actual.height,
      closeTo(expected.height, 0.01),
      reason: '$reason: $name height',
    );
  }
  expect(
    after.rowHeight,
    closeTo(before.rowHeight, 0.01),
    reason: '$reason: row height',
  );
}

StudioRecoveryIssue _layoutRecoveryIssue() => const StudioRecoveryIssue(
  id: 'selected-thread-recovery',
  scope: RecoveryIssueScope.thread,
  category: RecoveryIssueCategory.repository,
  impact: RecoveryIssueImpact.executionBlocked,
  availableActions: [RecoveryIssueAction.retry],
  threadId: _selectedId,
  detail: 'The selected synthetic repository needs recovery',
);

Future<void> _openLayoutMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(StudioDriverKeys.agentSwitcher));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _closeLayoutGraph(WidgetTester tester, AppGraph graph) async {
  final anchors = find.byType(MenuAnchor);
  if (anchors.evaluate().isNotEmpty) {
    tester.widget<MenuAnchor>(anchors).controller?.close();
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpClientFuture(
    tester,
    graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    'agent list layout teardown',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows agent state, actions, and diagnostics in the layout', (
    tester,
  ) async {
    final graph = await _layoutGraph(tester);
    await _pumpAgentMenu(tester, graph, _layoutAgents());

    final menuElement = find.byType(AgentSwitcherMenu);
    expect(menuElement, findsOneWidget);
    await _openLayoutMenu(tester);

    expect(find.byKey(StudioDriverKeys.agentRow(_selectedId)), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.agentStop(_selectedId)), findsOneWidget);
    expect(find.text('Executor · Model not recorded'), findsWidgets);
    expect(find.byIcon(Icons.stop_circle_outlined), findsNWidgets(2));
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(
      find.byTooltip('Stopped, waiting for the main agent to schedule'),
      findsOneWidget,
    );
    expect(find.byTooltip('The synthetic member failed'), findsOneWidget);
    expect(find.text('The synthetic member failed'), findsNothing);
    await _closeLayoutGraph(tester, graph);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('keeps fixed slots aligned and rows at one height', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final graph = await _layoutGraph(tester);
    await _pumpAgentMenu(tester, graph, _layoutAgents());
    await _openLayoutMenu(tester);

    final ids = _layoutAgents().map((agent) => agent.threadId).toList();
    final rowHeight = tester
        .getRect(find.byKey(StudioDriverKeys.agentRow(ids.first)))
        .height;
    expect(rowHeight, greaterThan(0));
    for (final id in ids) {
      expect(
        tester.getRect(find.byKey(StudioDriverKeys.agentRow(id))).height,
        closeTo(rowHeight, 0.01),
        reason: 'row height changed for $id',
      );
    }

    final selectionSlot = [
      for (final id in ids)
        tester.getRect(find.byKey(ValueKey('agent-selection-slot-$id'))),
    ];
    final statusSlot = [
      for (final id in ids)
        tester.getRect(find.byKey(ValueKey('agent-status-slot-$id'))),
    ];
    final actionSlot = [
      for (final id in ids)
        tester.getRect(find.byKey(ValueKey('agent-action-slot-$id'))),
    ];
    for (var index = 1; index < ids.length; index++) {
      expect(
        selectionSlot[index].left,
        closeTo(selectionSlot.first.left, 0.01),
      );
      expect(statusSlot[index].left, closeTo(statusSlot.first.left, 0.01));
      expect(actionSlot[index].left, closeTo(actionSlot.first.left, 0.01));
      expect(statusSlot[index].right, closeTo(statusSlot.first.right, 0.01));
      expect(actionSlot[index].right, closeTo(actionSlot.first.right, 0.01));
    }
    expect(
      tester.takeException(),
      isNull,
      reason: 'fixed-column layout produced a Flutter exception',
    );
    await _closeLayoutGraph(tester, graph);
  });

  testWidgets(
    'status transitions preserve all fixed columns and one row height',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 700);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final graph = await _layoutGraph(tester);
      await _pumpAgentMenu(tester, graph, _layoutAgents());
      await _openLayoutMenu(tester);
      final baseline = _agentGeometry(tester, _selectedId);
      expect(
        find.byKey(StudioDriverKeys.agentStop(_selectedId)),
        findsOneWidget,
      );

      final transitions =
          <({String name, String label, List<StudioAgentView> agents})>[
            (
              name: 'approval',
              label: 'Approval',
              agents: _agentsWithSelectedState(
                state: const WaitingToolStudioAgent('selected-turn'),
              ),
            ),
            (
              name: 'input',
              label: 'Input',
              agents: _agentsWithSelectedState(
                state: const WaitingInteractionStudioAgent(
                  'selected-turn',
                  'input',
                ),
              ),
            ),
            (
              name: 'cancelling',
              label: 'Stopping',
              agents: _agentsWithSelectedState(
                state: const CancellingStudioAgent('selected-turn'),
                execution: const AgentExecutionView(
                  id: 'selected-execution',
                  phase: AgentExecutionPhase.stopping,
                  turnId: 'selected-turn',
                ),
                canStop: true,
              ),
            ),
            (
              name: 'waiting scheduling',
              label: 'Waiting',
              agents: _agentsWithSelectedState(
                state: const IdleStudioAgent(),
                awaitingScheduling: true,
              ),
            ),
            (
              name: 'idle',
              label: 'Idle',
              agents: _agentsWithSelectedState(state: const IdleStudioAgent()),
            ),
            (
              name: 'faulted',
              label: 'Failed',
              agents: _agentsWithSelectedState(
                state: const FaultedStudioAgent(
                  failure: AgentStateError(
                    code: 'selected-failed',
                    message: 'The selected synthetic member failed',
                    retryable: false,
                  ),
                  diagnosticTurnId: 'selected-turn',
                ),
              ),
            ),
            (
              name: 'closed',
              label: 'Closed',
              agents: _agentsWithSelectedState(
                state: const ClosedStudioAgent(),
              ),
            ),
          ];

      var revision = 2;
      for (final transition in transitions) {
        graph.client.project.applyAgentDirectory(
          AgentDirectoryState(revision: revision++, values: transition.agents),
        );
        await _pumpAgentMenu(tester, graph, transition.agents);
        await _ensureLayoutMenuOpen(tester);

        final statusText = tester.widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey('agent-status-slot-$_selectedId')),
            matching: find.byType(Text),
          ),
        );
        expect(statusText.data, transition.label);
        expect(statusText.data!.split(RegExp(r'\s+')), hasLength(1));
        expect(statusText.semanticsLabel, isNotEmpty);
        _expectAgentGeometryStable(
          baseline,
          _agentGeometry(tester, _selectedId),
          reason: transition.name,
        );
        expect(
          find.byKey(StudioDriverKeys.agentTaskSummary(_selectedId)),
          findsOneWidget,
        );
        expect(
          find.byKey(StudioDriverKeys.agentModel(_selectedId)),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('agent-selection-slot-$_selectedId')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('agent-status-slot-$_selectedId')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('agent-action-slot-$_selectedId')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }

      expect(
        find.byKey(StudioDriverKeys.agentStop(_selectedId)),
        findsNothing,
        reason: 'closed state never regains a stop affordance',
      );
      await _closeLayoutGraph(tester, graph);
    },
  );

  testWidgets(
    'recovery appears inside the status slot without moving rows or stop',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 700);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final graph = await _layoutGraph(tester);
      final agents = _layoutAgents();
      await _pumpAgentMenu(tester, graph, agents);
      await _openLayoutMenu(tester);
      final before = _agentGeometry(tester, _selectedId);
      expect(
        find.byKey(StudioDriverKeys.agentStop(_selectedId)),
        findsOneWidget,
      );

      final issue = _layoutRecoveryIssue();
      await _pumpAgentMenu(tester, graph, agents, recoveryIssues: [issue]);
      await _ensureLayoutMenuOpen(tester);
      final withRecovery = _agentGeometry(tester, _selectedId);
      _expectAgentGeometryStable(
        before,
        withRecovery,
        reason: 'recovery added',
      );
      expect(
        find.byKey(StudioDriverKeys.retryRecoveryIssue(issue.id)),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              (widget.message?.contains(issue.detail) ?? false),
        ),
        findsOneWidget,
        reason: 'recovery detail remains discoverable via Tooltip',
      );
      expect(
        find.byKey(StudioDriverKeys.agentStop(_selectedId)),
        findsOneWidget,
        reason: 'recovery does not change stop eligibility',
      );
      await tester.tap(
        find.byKey(StudioDriverKeys.retryRecoveryIssue(issue.id)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await _pumpAgentMenu(tester, graph, agents);
      await _ensureLayoutMenuOpen(tester);
      _expectAgentGeometryStable(
        before,
        _agentGeometry(tester, _selectedId),
        reason: 'recovery cleared',
      );
      expect(
        find.byKey(StudioDriverKeys.retryRecoveryIssue(issue.id)),
        findsNothing,
      );
      expect(
        find.byKey(StudioDriverKeys.agentStop(_selectedId)),
        findsOneWidget,
      );

      tester.view.physicalSize = const Size(320, 700);
      await _pumpAgentMenu(tester, graph, agents);
      await _ensureLayoutMenuOpen(tester);
      final narrowBefore = _agentGeometry(tester, _selectedId);
      await _pumpAgentMenu(tester, graph, agents, recoveryIssues: [issue]);
      await _ensureLayoutMenuOpen(tester);
      final narrowWithRecovery = _agentGeometry(tester, _selectedId);
      _expectAgentGeometryStable(
        narrowBefore,
        narrowWithRecovery,
        reason: 'narrow recovery added',
      );
      expect(
        find.byKey(StudioDriverKeys.retryRecoveryIssue(issue.id)),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.agentStop(_selectedId)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _closeLayoutGraph(tester, graph);
    },
  );

  testWidgets('deep indentation and narrow viewport keep columns bounded', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final graph = await _layoutGraph(tester);
    await _pumpAgentMenu(
      tester,
      graph,
      _deepLayoutAgents(),
      selectedThreadId: 'thread-deep-a',
    );
    await _openLayoutMenu(tester);
    final firstLeft = tester
        .getRect(find.byKey(StudioDriverKeys.agentTaskSummary('thread-deep-a')))
        .left;
    final secondLeft = tester
        .getRect(find.byKey(StudioDriverKeys.agentTaskSummary('thread-deep-b')))
        .left;
    final thirdLeft = tester
        .getRect(find.byKey(StudioDriverKeys.agentTaskSummary('thread-deep-c')))
        .left;
    expect(secondLeft, greaterThan(firstLeft));
    expect(thirdLeft, greaterThan(secondLeft));
    expect(thirdLeft - secondLeft, closeTo(secondLeft - firstLeft, 0.01));
    await _closeLayoutGraph(tester, graph);

    final narrowGraph = await _layoutGraph(tester);
    tester.view.physicalSize = const Size(320, 700);
    await _pumpAgentMenu(tester, narrowGraph, _layoutAgents());
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(AgentSwitcherMenu))),
      const Size(320, 700),
    );
    await _openLayoutMenu(tester);
    final narrowIds = _layoutAgents().map((agent) => agent.threadId);
    final narrowRows = [
      for (final id in narrowIds)
        tester.getRect(find.byKey(StudioDriverKeys.agentRow(id))),
    ];
    final viewport =
        Offset.zero &
        MediaQuery.sizeOf(tester.element(find.byType(AgentSwitcherMenu)));
    for (final (index, row) in narrowRows.indexed) {
      expect(row.width, greaterThan(0));
      expect(row.left, greaterThanOrEqualTo(viewport.left));
      expect(row.right, lessThanOrEqualTo(viewport.right));
      expect(row.top, greaterThanOrEqualTo(viewport.top));
      expect(row.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(row.height, closeTo(narrowRows.first.height, 0.01));
      expect(row.left, closeTo(narrowRows.first.left, 0.01));
      expect(row.right, closeTo(narrowRows.first.right, 0.01));
      expect(
        find
            .byKey(StudioDriverKeys.agentRow(narrowIds.elementAt(index)))
            .hitTestable(),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(StudioDriverKeys.agentStop(_selectedId)).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _closeLayoutGraph(tester, narrowGraph);
  });
}
