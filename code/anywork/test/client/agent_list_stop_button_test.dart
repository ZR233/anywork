import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/shell/agent_switcher_menu.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_client_future.dart';
import 'support/recording_demo_transport.dart';
import 'support/test_statistics_feed.dart';

const _rootId = 'thread-main';
const _runningChild = 'thread-child-running';
const _scheduledChild = 'thread-child-waiting';
const _closedChild = 'thread-child-closed';
const _terminalChild = 'thread-child-terminal';
const _retiredChild = 'thread-child-retired';
const _scheduledWithExecution = 'thread-child-scheduled-exec';
const _scheduledIdle = 'thread-child-scheduled-idle';
const _cancellingChild = 'thread-child-cancelling';
const _preparingChild = 'thread-child-preparing';
const _faultedChild = 'thread-child-faulted';
const _closingChild = 'thread-child-closing';
const _execution = AgentExecutionView(
  id: 'child-execution',
  phase: AgentExecutionPhase.running,
  turnId: 'child-turn',
);

/// 记录列表行的精确停止目标；canonical 目录行由测试自行注入并推进。
final class _AgentStopTransport extends RecordingDemoTransport {
  final List<String> stopTargets = [];
  Object? stopError;

  /// 非空时挂起停止请求，用于在在途期间观察界面。
  Completer<void>? stopGate;

  @override
  Future<StopThreadCommandReply> stopThread(
    String threadId,
    String executionId, {
    required OperationId operationId,
  }) async {
    stopTargets.add('$threadId:$executionId');
    final gate = stopGate;
    if (gate != null) await gate.future;
    final error = stopError;
    if (error != null) throw error;
    return StopThreadCommandReply(
      threadId: threadId,
      executionId: executionId,
      stopped: true,
      receipt: StudioCommandReceipt(
        operationId: operationId,
        disposition: CommitDisposition.applied,
        targets: const [],
        effect: EffectPoint.immediate,
        effective: true,
        durable: false,
        requiresIdentityObservation: true,
      ),
    );
  }
}

StudioAgentView _agent({
  required String threadId,
  required String task,
  StudioAgentState state = const RunningStudioAgent('child-turn'),
  AgentExecutionView? execution,
  bool canStop = false,
  bool awaitingScheduling = false,
  String role = 'executor',
}) {
  return StudioAgentView(
    id: threadId,
    threadId: threadId,
    path: 'root/$threadId',
    parentPath: 'root',
    rootThreadId: _rootId,
    depth: 1,
    role: role,
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

List<StudioAgentView> _members({bool stoppedRunning = false}) => [
  _agent(
    threadId: _runningChild,
    task: 'Running member',
    state: stoppedRunning
        ? const IdleStudioAgent()
        : const RunningStudioAgent('child-turn'),
    execution: stoppedRunning ? null : _execution,
    canStop: !stoppedRunning,
    awaitingScheduling: stoppedRunning,
  ),
  _agent(
    threadId: _scheduledChild,
    task: 'Waiting member',
    state: const IdleStudioAgent(),
    awaitingScheduling: true,
  ),
  _agent(
    threadId: _closedChild,
    task: 'Closed member',
    state: const ClosedStudioAgent(),
  ),
];

Future<void> _pump(
  WidgetTester tester,
  AppGraph graph,
  List<StudioAgentView> agents, {
  List<StudioRecoveryIssue> recoveryIssues = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appGraphProvider.overrideWithValue(graph)],
      child: MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AgentSwitcherMenu(
            agents: agents,
            workspaceThreads: const [],
            recoveryIssues: recoveryIssues,
            selectedThreadId: _rootId,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<AppGraph> _graph(
  WidgetTester tester,
  _AgentStopTransport transport,
) async {
  final graph = AppGraph(
    transport: transport,
    clientId: 'agent-list-stop',
    statisticsFeed: const TestStatisticsFeedPort(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'agent list stop teardown',
    );
  });
  await pumpClientFuture(tester, graph.client.bootstrap(), 'agent bootstrap');
  graph.client.project.applyAgentDirectory(
    AgentDirectoryState(revision: 1, values: _members()),
  );
  return graph;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(StudioDriverKeys.agentSwitcher));
  await tester.pumpAndSettle();
}

/// 重建同一位置的 Widget 会保留菜单状态：只有在菜单确实关闭时才重新打开。
Future<void> _ensureMenuOpen(WidgetTester tester) async {
  if (find.byKey(StudioDriverKeys.agentRow(_runningChild)).evaluate().isEmpty) {
    await _openMenu(tester);
  }
}

Future<void> _close(WidgetTester tester, AppGraph graph) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpClientFuture(
    tester,
    graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    'agent list stop close',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('恢复诊断不替换智能体状态，导航只按访问阻断禁用', (tester) async {
    for (final impact in RecoveryIssueImpact.values) {
      final graph = await _graph(tester, _AgentStopTransport());
      final issue = StudioRecoveryIssue(
        id: 'issue-${impact.name}',
        scope: RecoveryIssueScope.thread,
        category: RecoveryIssueCategory.repository,
        impact: impact,
        availableActions: const [],
        threadId: _runningChild,
        detail: 'Repository recovery is required',
      );
      await _pump(tester, graph, _members(), recoveryIssues: [issue]);
      await _openMenu(tester);
      expect(
        find.text('Running'),
        findsOneWidget,
        reason: '${impact.name} 不覆盖 canonical 生命周期状态',
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              (widget.message?.contains('Repository recovery is required') ??
                  false),
        ),
        findsOneWidget,
        reason: '${impact.name} 的具体诊断仍可查看',
      );
      final diagnosticIcon = tester.widget<Icon>(
        find.byIcon(
          impact == RecoveryIssueImpact.advisory
              ? Icons.info_outline
              : Icons.error_outline,
        ),
      );
      expect(
        diagnosticIcon.color,
        impact == RecoveryIssueImpact.advisory
            ? Theme.of(tester.element(find.byType(AgentSwitcherMenu)))
                  .colorScheme
                  .primary
            : Theme.of(tester.element(find.byType(AgentSwitcherMenu)))
                  .colorScheme
                  .error,
        reason: '${impact.name} 使用相应诊断等级颜色',
      );
      final row = tester.widget<MenuItemButton>(
        find.byKey(StudioDriverKeys.agentRow(_runningChild)),
      );
      expect(
        row.onPressed == null,
        impact == RecoveryIssueImpact.accessBlocked,
        reason: '仅 accessBlocked 禁止历史导航',
      );
      await _close(tester, graph);
    }
  });

  testWidgets('行内停止只停该行执行，不切页、不开会话、不建草稿', (tester) async {
    final transport = _AgentStopTransport();
    final graph = await _graph(tester, transport);
    await _pump(tester, graph, _members());

    // 计数排除永久关闭成员，但菜单仍列出全部成员。
    expect(find.text('2 agents'), findsOneWidget);
    await _openMenu(tester);
    for (final threadId in [_runningChild, _scheduledChild, _closedChild]) {
      expect(
        find.byKey(StudioDriverKeys.agentRow(threadId)),
        findsOneWidget,
        reason: '菜单仍列出全部成员',
      );
    }
    expect(
      find.byKey(StudioDriverKeys.agentStop(_closedChild)),
      findsNothing,
      reason: '已关闭成员没有可点停止',
    );
    expect(
      find.byKey(StudioDriverKeys.agentStop(_scheduledChild)),
      findsNothing,
      reason: '等待主智能体调度的成员没有可点停止',
    );

    final selection = graph.client.selection.state;
    await tester.tap(find.byKey(StudioDriverKeys.agentStop(_runningChild)));
    await tester.pump();
    expect(transport.stopTargets, [
      '$_runningChild:child-execution',
    ], reason: '停止目标固定为该行的会话与执行身份');
    expect(graph.client.selection.state, selection, reason: '点击停止不改变当前选择');
    expect(
      graph.client.conversations.sessionStates.map((state) => state.threadId),
      isNot(contains(_runningChild)),
      reason: '停止不打开子会话',
    );
    expect(
      graph.client.drafts.existingComposer(_runningChild),
      isNull,
      reason: '停止不创建子会话草稿',
    );

    // 停止已受理、尚未观察到结束：就地显示禁用的正在停止。
    expect(
      find.byKey(StudioDriverKeys.agentStopNote(_runningChild)),
      findsOneWidget,
    );
    expect(find.text('Stopping'), findsOneWidget);
    expect(find.byKey(StudioDriverKeys.agentStop(_runningChild)), findsNothing);

    // 目录确认该执行结束后：说明等待主智能体调度，不再提供停止或继续。
    graph.client.project.applyAgentDirectory(
      AgentDirectoryState(revision: 2, values: _members(stoppedRunning: true)),
    );
    await _pump(tester, graph, _members(stoppedRunning: true));
    await _ensureMenuOpen(tester);
    expect(
      find.text('Stopped, waiting for the main agent to schedule'),
      findsNWidgets(2),
      reason: '刚停止的成员与已在等待调度的成员使用同一说明',
    );
    expect(find.byKey(StudioDriverKeys.agentStop(_runningChild)), findsNothing);
    expect(find.text('Continue'), findsNothing);
    expect(
      find.byKey(StudioDriverKeys.agentStopNote(_runningChild)),
      findsOneWidget,
    );

    expect(
      graph.client.mutations
          .latest('stop:$_runningChild')
          ?.state
          .value
          .observed,
      isTrue,
      reason: '目录确认执行结束后停止观察结束',
    );
    await _close(tester, graph);
  });

  testWidgets('停止未被受理时行内显示原因且保留可点停止', (tester) async {
    final transport = _AgentStopTransport()
      ..stopError = const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'raw stop failure',
        retryable: false,
        correlationId: 'list-stop-stale',
        reason: StudioFailureReason.staleExecution,
      );
    final graph = await _graph(tester, transport);
    await _pump(tester, graph, _members());
    await _openMenu(tester);
    final selection = graph.client.selection.state;
    await tester.tap(find.byKey(StudioDriverKeys.agentStop(_runningChild)));
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining(
        'Stop was not accepted: The observed execution already ended or was replaced.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(StudioDriverKeys.agentStop(_runningChild)),
      findsOneWidget,
      reason: '未受理的停止不能被当成已经停止',
    );
    expect(graph.client.selection.state, selection, reason: '错误也不改变当前选择');
    await _close(tester, graph);
  });

  testWidgets('已关闭成员带遗留执行时行内仍无可点停止', (tester) async {
    final transport = _AgentStopTransport();
    final graph = await _graph(tester, transport);
    final members = [
      _agent(
        threadId: _closedChild,
        task: 'Closed member with stale execution',
        state: const ClosedStudioAgent(),
        execution: _execution,
        canStop: true,
        awaitingScheduling: true,
      ),
    ];
    graph.client.project.applyAgentDirectory(
      AgentDirectoryState(revision: 3, values: members),
    );
    await _pump(tester, graph, members);
    expect(find.text('0 agents'), findsOneWidget, reason: '已关闭成员不计入标题数量');
    await _openMenu(tester);
    expect(find.byKey(StudioDriverKeys.agentRow(_closedChild)), findsOneWidget);
    expect(
      find.byKey(StudioDriverKeys.agentStop(_closedChild)),
      findsNothing,
      reason: '遗留执行与停止资格不得复活已关闭成员的停止入口',
    );
    expect(
      find.byKey(StudioDriverKeys.agentStopNote(_closedChild)),
      findsNothing,
      reason: '已关闭成员也不显示停止或等待调度说明',
    );
    await _close(tester, graph);
  });

  testWidgets('视图滞后于目录停止资格时不发请求、不显示正在停止', (tester) async {
    final transport = _AgentStopTransport();
    final graph = await _graph(tester, transport);
    await _pump(tester, graph, _members());
    await _openMenu(tester);
    expect(
      find.byKey(StudioDriverKeys.agentStop(_runningChild)),
      findsOneWidget,
    );

    // 目录已把停止资格撤下（canStop=false），但界面仍是上一帧。
    graph.client.project.applyAgentDirectory(
      AgentDirectoryState(
        revision: 4,
        values: [
          _agent(
            threadId: _runningChild,
            task: 'Running member',
            execution: _execution,
          ),
          _agent(
            threadId: _scheduledChild,
            task: 'Waiting member',
            state: const IdleStudioAgent(),
            awaitingScheduling: true,
          ),
          _agent(
            threadId: _closedChild,
            task: 'Closed member',
            state: const ClosedStudioAgent(),
          ),
        ],
      ),
    );
    await tester.tap(
      find.byKey(StudioDriverKeys.agentStop(_runningChild)),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(transport.stopTargets, isEmpty, reason: '没有停止资格时不生成停止请求');
    expect(
      find.byKey(StudioDriverKeys.agentStopNote(_runningChild)),
      findsNothing,
      reason: '未发出的停止不能显示成正在停止',
    );
    expect(find.text('Stopping'), findsNothing);
    // 目录事实到达界面（_Header 重新投影）后，该行不再提供停止。
    await _pump(tester, graph, [
      _agent(
        threadId: _runningChild,
        task: 'Running member',
        execution: _execution,
      ),
      _agent(
        threadId: _scheduledChild,
        task: 'Waiting member',
        state: const IdleStudioAgent(),
        awaitingScheduling: true,
      ),
      _agent(
        threadId: _closedChild,
        task: 'Closed member',
        state: const ClosedStudioAgent(),
      ),
    ]);
    await _ensureMenuOpen(tester);
    expect(
      find.byKey(StudioDriverKeys.agentStop(_runningChild)),
      findsNothing,
      reason: '按目录事实该行不再提供停止',
    );
    await _close(tester, graph);
  });

  testWidgets('终态、退役与等待调度成员带遗留执行时都没有可点停止', (tester) async {
    final transport = _AgentStopTransport();
    final graph = await _graph(tester, transport);
    final members = [
      _agent(
        threadId: _terminalChild,
        task: 'Finished member',
        state: const IdleStudioAgent(),
        canStop: true,
      ),
      _agent(
        threadId: _preparingChild,
        task: 'Preparing member',
        state: const IdleStudioAgent(),
        execution: const AgentExecutionView(
          id: 'child-execution-preparing',
          phase: AgentExecutionPhase.preparing,
        ),
        canStop: true,
      ),
      _agent(
        threadId: _retiredChild,
        task: 'Retired member',
        execution: _execution,
        canStop: true,
        role: 'planner',
      ),
      _agent(
        threadId: _scheduledIdle,
        task: 'Waiting member',
        state: const IdleStudioAgent(),
        awaitingScheduling: true,
      ),
      _agent(
        threadId: _cancellingChild,
        task: 'Settling member',
        state: const CancellingStudioAgent('child-turn'),
        execution: _execution,
        canStop: true,
        awaitingScheduling: true,
      ),
      _agent(
        threadId: _scheduledWithExecution,
        task: 'Running member with scheduling fact',
        execution: _execution,
        canStop: true,
        awaitingScheduling: true,
      ),
      _agent(
        threadId: _faultedChild,
        task: 'Faulted member',
        state: const FaultedStudioAgent(
          failure: AgentStateError(
            code: 'failed',
            message: 'failed',
            retryable: false,
          ),
          diagnosticTurnId: 'child-turn',
        ),
        execution: _execution,
        canStop: true,
      ),
      _agent(
        threadId: _closingChild,
        task: 'Closing member',
        state: const ClosingStudioAgent(turnId: 'child-turn'),
        execution: const AgentExecutionView(
          id: 'child-execution-closing',
          phase: AgentExecutionPhase.stopping,
          turnId: 'child-turn',
        ),
        canStop: true,
      ),
    ];
    graph.client.project.applyAgentDirectory(
      AgentDirectoryState(revision: 5, values: members),
    );
    await _pump(tester, graph, members);
    await _openMenu(tester);

    expect(
      find.byKey(StudioDriverKeys.agentStop(_terminalChild)),
      findsNothing,
      reason: '没有当前执行的终态成员不提供停止',
    );
    // 准备期执行是真实可停止目标：Idle 行同样要有入口（生产投影就是这样发布的）。
    expect(
      find.byKey(StudioDriverKeys.agentStop(_preparingChild)),
      findsOneWidget,
      reason: '准备期执行不以 state.isActive 为必要条件',
    );
    expect(
      find.byKey(StudioDriverKeys.agentStop(_retiredChild)),
      findsNothing,
      reason: '退役成员没有运行控制',
    );
    expect(
      find.textContaining('This subagent role has been retired'),
      findsOneWidget,
      reason: '退役判定与角色标签共用同一判据',
    );
    // 清理中的成员优先显示正在停止，不被等待调度说明掩盖。
    expect(
      find.byKey(StudioDriverKeys.agentStop(_cancellingChild)),
      findsNothing,
      reason: '清理中没有可点停止',
    );
    expect(
      find.byKey(StudioDriverKeys.agentStopNote(_cancellingChild)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(StudioDriverKeys.agentStopNote(_cancellingChild)),
          )
          .data,
      'Stopping',
    );
    // 可执行中且具备停止资格时仍给停止，即便目录同时带等待调度事实。
    expect(
      find.byKey(StudioDriverKeys.agentStop(_scheduledWithExecution)),
      findsOneWidget,
    );
    // 没有可执行中状态时才是等待调度说明。
    expect(
      find.byKey(StudioDriverKeys.agentStopNote(_scheduledIdle)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(StudioDriverKeys.agentStopNote(_scheduledIdle)),
          )
          .data,
      'Stopped, waiting for the main agent to schedule',
    );
    // 故障与正在关闭成员没有当前工作：遗留执行与停止资格都不产生任何运行控制。
    for (final threadId in [_faultedChild, _closingChild]) {
      expect(
        find.byKey(StudioDriverKeys.agentStop(threadId)),
        findsNothing,
        reason: '终态成员没有可点停止：$threadId',
      );
      expect(
        find.byKey(StudioDriverKeys.agentStopNote(threadId)),
        findsNothing,
        reason: '终态成员不显示正在停止或等待调度说明：$threadId',
      );
    }
    await _close(tester, graph);
  });

  testWidgets('行内停止发送渲染时的执行编号，过时由服务端拒绝且不重试', (tester) async {
    final transport = _AgentStopTransport();
    final graph = await _graph(tester, transport);
    await _pump(tester, graph, _members());
    await _openMenu(tester);
    expect(
      find.byKey(StudioDriverKeys.agentStop(_runningChild)),
      findsOneWidget,
    );

    // 目录推进到新执行，界面仍是上一帧的 child-execution。
    graph.client.project.applyAgentDirectory(
      AgentDirectoryState(
        revision: 6,
        values: [
          _agent(
            threadId: _runningChild,
            task: 'Running member',
            state: const RunningStudioAgent('child-turn-2'),
            execution: const AgentExecutionView(
              id: 'child-execution-2',
              phase: AgentExecutionPhase.running,
              turnId: 'child-turn-2',
            ),
            canStop: true,
          ),
          _agent(
            threadId: _scheduledChild,
            task: 'Waiting member',
            state: const IdleStudioAgent(),
            awaitingScheduling: true,
          ),
          _agent(
            threadId: _closedChild,
            task: 'Closed member',
            state: const ClosedStudioAgent(),
          ),
        ],
      ),
    );
    final gate = Completer<void>();
    transport.stopGate = gate;
    transport.stopError = const StudioFailure(
      code: StudioFailureCode.conflict,
      message: 'raw stale row stop',
      retryable: false,
      correlationId: 'row-stop-stale',
      reason: StudioFailureReason.staleExecution,
    );
    await tester.tap(
      find.byKey(StudioDriverKeys.agentStop(_runningChild)),
      warnIfMissed: false,
    );
    await pumpClientUntil(
      tester,
      () => transport.stopTargets.isNotEmpty,
      'row stop request captured',
    );
    expect(transport.stopTargets, [
      '$_runningChild:child-execution',
    ], reason: '使用渲染该行时的执行编号');
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining(
        'Stop was not accepted: The observed execution already ended or was replaced.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(StudioDriverKeys.agentStopNote(_runningChild)),
      findsNothing,
      reason: '过时目标不进入正在停止',
    );
    // 目录事实到达界面后该行按 canonical 呈现（新执行仍可停止）。
    await _pump(tester, graph, [
      _agent(
        threadId: _runningChild,
        task: 'Running member',
        state: const RunningStudioAgent('child-turn-2'),
        execution: const AgentExecutionView(
          id: 'child-execution-2',
          phase: AgentExecutionPhase.running,
          turnId: 'child-turn-2',
        ),
        canStop: true,
      ),
    ]);
    await _ensureMenuOpen(tester);
    expect(
      find.byKey(StudioDriverKeys.agentStop(_runningChild)),
      findsOneWidget,
      reason: '按 canonical 重新呈现当前可停执行',
    );
    expect(transport.stopTargets, [
      '$_runningChild:child-execution',
    ], reason: '过时目标不自动重试成新编号');
    await _close(tester, graph);
  });

  testWidgets('行内请求在途只禁用按钮，不显示正在停止；受理后才显示', (tester) async {
    final transport = _AgentStopTransport();
    final graph = await _graph(tester, transport);
    await _pump(tester, graph, _members());
    await _openMenu(tester);
    final gate = Completer<void>();
    transport.stopGate = gate;
    await tester.tap(find.byKey(StudioDriverKeys.agentStop(_runningChild)));
    await pumpClientUntil(
      tester,
      () => transport.stopTargets.isNotEmpty,
      'row stop request in flight',
    );
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(StudioDriverKeys.agentStop(_runningChild)),
          )
          .onPressed,
      isNull,
      reason: '请求在途禁止重复提交',
    );
    expect(
      find.byKey(StudioDriverKeys.agentStopNote(_runningChild)),
      findsNothing,
      reason: '还没拿到受理回执，不能显示正在停止',
    );
    expect(find.text('Stopping'), findsNothing);

    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await pumpClientUntil(
      tester,
      () => find
          .byKey(StudioDriverKeys.agentStopNote(_runningChild))
          .evaluate()
          .isNotEmpty,
      'row stopping after acceptance',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(StudioDriverKeys.agentStopNote(_runningChild)),
          )
          .data,
      'Stopping',
    );
    expect(find.byKey(StudioDriverKeys.agentStop(_runningChild)), findsNothing);
    await _close(tester, graph);
  });

  testWidgets('行内停止有独立可访问名称、可命中且不触发行选择', (tester) async {
    final transport = _AgentStopTransport();
    final graph = await _graph(tester, transport);
    await _pump(tester, graph, _members());
    await _openMenu(tester);
    final stop = find.byKey(StudioDriverKeys.agentStop(_runningChild));
    expect(stop, findsOneWidget);
    expect(
      tester.widget<IconButton>(stop).tooltip,
      'Stop member Running member',
      reason: '读屏与悬停都能区分这是「停止该成员」',
    );
    expect(stop.hitTestable(), findsOneWidget, reason: '行选中不能覆盖停止按钮的点击区域');
    final handle = tester.ensureSemantics();
    // 可访问名称由 agentStopSemantics 提供，作为该按钮自身的提示存在。
    expect(
      find.byTooltip('Stop member Running member'),
      findsOneWidget,
      reason: '语义名来自 agentStopSemantics',
    );
    expect(
      tester
          .getSemantics(stop)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
      reason: '停止按钮自身可被辅助技术点击',
    );
    handle.dispose();

    final selection = graph.client.selection.state;
    await tester.tap(stop);
    await pumpClientUntil(
      tester,
      () => transport.stopTargets.isNotEmpty,
      'accessible stop dispatched',
    );
    expect(transport.stopTargets, ['$_runningChild:child-execution']);
    expect(graph.client.selection.state, selection);
    await _close(tester, graph);
  });

  testWidgets('行内停止在途由命令板派生：菜单换新 State 后仍禁用', (tester) async {
    final transport = _AgentStopTransport();
    final graph = await _graph(tester, transport);
    await _pump(tester, graph, _members());
    await _openMenu(tester);
    final gate = Completer<void>();
    transport.stopGate = gate;
    await tester.tap(find.byKey(StudioDriverKeys.agentStop(_runningChild)));
    await pumpClientUntil(
      tester,
      () => transport.stopTargets.isNotEmpty,
      'row stop in flight before rebuild',
    );
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(StudioDriverKeys.agentStop(_runningChild)),
          )
          .onPressed,
      isNull,
    );

    // 换一个全新的菜单实例（新 State）：在途事实只能来自 Client 命令板。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(graph)],
        child: MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AgentSwitcherMenu(
              key: UniqueKey(),
              agents: _members(),
              workspaceThreads: const [],
              selectedThreadId: _rootId,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // 在途期间有持续动画的进度圈，不能用 pumpAndSettle 打开菜单。
    await tester.tap(find.byKey(StudioDriverKeys.agentSwitcher));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester
          .widget<IconButton>(
            find.byKey(StudioDriverKeys.agentStop(_runningChild)),
          )
          .onPressed,
      isNull,
      reason: '重建后的行仍按命令板显示请求在途',
    );
    expect(
      find.byKey(StudioDriverKeys.agentStopNote(_runningChild)),
      findsNothing,
      reason: '仍未结算，不显示正在停止',
    );

    // 回执到达：命令板把该命令标成 accepted（仍 pending 等 canonical 收敛）。
    // 受理事实在命令板里，因此换过 State 的行同样显示「正在停止」而不是重新开放点击。
    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await pumpClientUntil(
      tester,
      () => find
          .byKey(StudioDriverKeys.agentStopNote(_runningChild))
          .evaluate()
          .isNotEmpty,
      'row stopping from board acceptance after rebuild',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(StudioDriverKeys.agentStopNote(_runningChild)),
          )
          .data,
      'Stopping',
      reason: '重建后的行从命令板 accepted 恢复正在停止',
    );
    expect(
      find.byKey(StudioDriverKeys.agentStop(_runningChild)),
      findsNothing,
      reason: '已受理不提供可点停止',
    );
    expect(
      find.byKey(ValueKey('agent-stop-failure-$_runningChild')),
      findsNothing,
    );

    // 目录收敛（执行结束、等待主智能体调度）：命令板清键，行回到目录事实。
    final converged = [
      _agent(
        threadId: _runningChild,
        task: 'Running member',
        state: const IdleStudioAgent(),
        awaitingScheduling: true,
      ),
    ];
    graph.client.project.applyAgentDirectory(
      AgentDirectoryState(revision: 9, values: converged),
    );
    await _pump(tester, graph, converged);
    await _ensureMenuOpen(tester);
    await tester.pump();
    expect(
      find.byKey(StudioDriverKeys.agentStop(_runningChild)),
      findsNothing,
      reason: '目录收敛后不再显示可点停止',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(StudioDriverKeys.agentStopNote(_runningChild)),
          )
          .data,
      'Stopped, waiting for the main agent to schedule',
    );
    await _close(tester, graph);
  });

  testWidgets('菜单重建时命令已在途会重新启动未确认计时', (tester) async {
    final transport = _AgentStopTransport();
    final graph = await _graph(tester, transport);
    await _pump(tester, graph, _members());
    await _openMenu(tester);
    final gate = Completer<void>();
    transport.stopGate = gate;
    await tester.tap(find.byKey(StudioDriverKeys.agentStop(_runningChild)));
    await pumpClientUntil(
      tester,
      () => transport.stopTargets.isNotEmpty,
      'row stop in flight before menu rebuild',
    );
    await tester.pump();

    // 换一个全新的菜单实例（新 State）：在途事实与计时都要能从命令板恢复。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(graph)],
        child: MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AgentSwitcherMenu(
              key: UniqueKey(),
              agents: _members(),
              workspaceThreads: const [],
              selectedThreadId: _rootId,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(StudioDriverKeys.agentSwitcher));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.byKey(ValueKey('agent-stop-unconfirmed-$_runningChild')),
      findsNothing,
      reason: '重建后阈值未到，不显示未确认',
    );

    // 跨过阈值：新 State 挂载时已按命令板登记时间重新安排了计时。
    await tester.pump(const Duration(seconds: 16));
    expect(
      find.byKey(ValueKey('agent-stop-unconfirmed-$_runningChild')),
      findsOneWidget,
      reason: '重建后的菜单同样会提示未确认',
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(StudioDriverKeys.agentStop(_runningChild)),
          )
          .onPressed,
      isNotNull,
      reason: '未确认后允许同一执行编号再试',
    );
    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await _close(tester, graph);
  });

  testWidgets('行内请求迟迟未受理时提示未确认并允许同一执行再试', (tester) async {
    final transport = _AgentStopTransport();
    final graph = await _graph(tester, transport);
    await _pump(tester, graph, _members());
    await _openMenu(tester);
    final gate = Completer<void>();
    transport.stopGate = gate;
    await tester.tap(find.byKey(StudioDriverKeys.agentStop(_runningChild)));
    await pumpClientUntil(
      tester,
      () => transport.stopTargets.isNotEmpty,
      'row stop in flight before threshold',
    );
    await tester.pump();
    expect(
      find.byKey(ValueKey('agent-stop-unconfirmed-$_runningChild')),
      findsNothing,
      reason: '阈值内只有进度，没有未确认提示',
    );

    // 超过阈值仍未被受理：提示结果未确认，并允许用同一执行编号再试。
    await tester.pump(const Duration(seconds: 16));
    expect(
      find.byKey(ValueKey('agent-stop-unconfirmed-$_runningChild')),
      findsOneWidget,
    );
    expect(
      find.text(
        'The last action could not be confirmed. '
        'Check the session state before retrying.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(StudioDriverKeys.agentStop(_runningChild)),
          )
          .onPressed,
      isNotNull,
      reason: '未确认后允许显式再试',
    );

    // 再试：立刻回到「请求在途」，仍然只有一个待结算停止（lane 串行）。
    final second = Completer<void>();
    transport.stopGate = second;
    await tester.tap(find.byKey(StudioDriverKeys.agentStop(_runningChild)));
    await tester.pump();
    expect(
      find.byKey(ValueKey('agent-stop-unconfirmed-$_runningChild')),
      findsNothing,
      reason: '重试后提示让位给请求在途',
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(StudioDriverKeys.agentStop(_runningChild)),
          )
          .onPressed,
      isNull,
    );
    expect(transport.stopTargets, ['$_runningChild:child-execution']);

    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await pumpClientUntil(
      tester,
      () => transport.stopTargets.length == 2,
      'queued row retry dispatched after the first settles',
    );
    expect(transport.stopTargets, [
      '$_runningChild:child-execution',
      '$_runningChild:child-execution',
    ], reason: '重试仍是同一执行编号');
    await tester.runAsync(() async {
      second.complete();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await _close(tester, graph);
  });

  testWidgets('行内停止失败原因是命令板事实，目录收敛后随之清除', (tester) async {
    final transport = _AgentStopTransport();
    final graph = await _graph(tester, transport);
    await _pump(tester, graph, _members());
    await _openMenu(tester);
    transport.stopError = const StudioFailure(
      code: StudioFailureCode.conflict,
      message: 'raw stale stop',
      retryable: false,
      correlationId: 'row-stop-stale',
      reason: StudioFailureReason.staleExecution,
    );
    await tester.tap(find.byKey(StudioDriverKeys.agentStop(_runningChild)));
    await pumpClientUntil(
      tester,
      () => find
          .byKey(ValueKey('agent-stop-failure-$_runningChild'))
          .evaluate()
          .isNotEmpty,
      'row stop failure from the command board',
    );
    expect(
      find.textContaining(
        'The observed execution already ended or was replaced.',
      ),
      findsOneWidget,
    );

    // 目录收敛后命令板清键：失败说明也随之消失，不残留旧原因。
    final converged = [
      _agent(
        threadId: _runningChild,
        task: 'Running member',
        state: const IdleStudioAgent(),
        awaitingScheduling: true,
      ),
    ];
    graph.client.project.applyAgentDirectory(
      AgentDirectoryState(revision: 10, values: converged),
    );
    await _pump(tester, graph, converged);
    await _ensureMenuOpen(tester);
    await tester.pump();
    expect(
      find.byKey(ValueKey('agent-stop-failure-$_runningChild')),
      findsNothing,
      reason: '命令板结算后不再显示旧失败',
    );
    await _close(tester, graph);
  });
}
