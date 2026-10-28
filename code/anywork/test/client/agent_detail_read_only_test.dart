import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/interaction/composer_dock.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_client_future.dart';
import 'support/recording_demo_transport.dart';
import 'support/test_statistics_feed.dart';

const _childId = 'thread-reviewer';

const _unset = Object();

const _running = AgentExecutionView(
  id: 'child-exec',
  phase: AgentExecutionPhase.running,
  turnId: 'child-turn',
);

final _continuation = ContinuationView(
  id: 'child-continuation',
  sourceTurnId: 'child-turn',
  reason: ContinuationReason.userStop,
  createdAt: DateTime.utc(2026, 1, 1),
  claimed: false,
);

const _approval = PendingInteraction(
  id: 'interaction-approval',
  threadId: _childId,
  turnId: 'child-turn',
  kind: InteractionKind.toolApproval,
  title: 'Run the shell command',
  body: 'The child agent wants to run a command',
  payload: ToolApprovalInteractionPayload(
    toolName: 'shell',
    arguments: {'command': 'ls'},
    workingDirectory: '/tmp',
  ),
  revision: 3,
);

final class _Fixture {
  _Fixture(this.graph);

  final AppGraph graph;

  StudioThreadSession get child => graph.client.session(_childId);

  void publishInteraction() {
    final workspace = child.state.workspace!;
    child.applySnapshot(workspace.copyWith(interactions: const [_approval]));
  }

  /// 只替换 canonical 运行时里的执行身份与继续点。
  void publishRuntime({
    Object? execution = _unset,
    Object? continuation = _unset,
  }) {
    final workspace = child.state.workspace!;
    final runtime = workspace.runtime;
    child.applySnapshot(
      workspace.copyWith(
        runtime: runtime.copyWith(
          execution: identical(execution, _unset)
              ? runtime.execution
              : execution as AgentExecutionView?,
          continuation: identical(continuation, _unset)
              ? runtime.continuation
              : continuation as ContinuationView?,
        ),
      ),
    );
  }
}

Future<_Fixture> _fixture(WidgetTester tester) async {
  final graph = AppGraph(
    transport: RecordingDemoTransport(),
    clientId: 'child-read-only',
    statisticsFeed: const TestStatisticsFeedPort(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'child read only teardown',
    );
  });
  await pumpClientFuture(tester, graph.client.bootstrap(), 'child bootstrap');
  await pumpClientFuture(
    tester,
    graph.client.directoryCommands.selectThread('thread-main'),
    'select root thread',
  );
  // 子成员身份来自 canonical 智能体目录；选择详情不建立它的执行许可。
  graph.client.project.applyAgentDirectory(
    AgentDirectoryState(
      revision: 1,
      values: [
        StudioAgentView(
          id: _childId,
          threadId: _childId,
          path: 'root/reviewer',
          parentPath: 'root',
          rootThreadId: 'thread-main',
          depth: 1,
          role: 'reviewer',
          delegationMode: DelegationMode.profile,
          delegationPreference: DelegationPreference.balanced,
          task: 'Review the change',
          state: const IdleStudioAgent(),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    ),
  );
  // 用户对子会话只有列表停止；打开详情只是查看，不是继续执行。
  await pumpClientFuture(
    tester,
    graph.client.directoryCommands.selectAgentThread(_childId),
    'open child detail',
  );
  await pumpClientUntil(
    tester,
    () => graph.client.session(_childId).state.hasSnapshot,
    'child snapshot',
  );
  return _Fixture(graph);
}

Future<void> _pump(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appGraphProvider.overrideWithValue(fixture.graph)],
      child: MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 500,
            child: ComposerDock(threadId: _childId),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _close(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpClientFuture(
    tester,
    fixture.graph.close(
      deadline: DateTime.now().add(const Duration(seconds: 5)),
    ),
    'child read only close',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('子会话详情只读：没有输入、停止、继续或发送', (tester) async {
    final fixture = await _fixture(tester);
    expect(
      fixture.graph.client.findThread(_childId)?.isAgent,
      isTrue,
      reason: '这是主会话的子成员',
    );
    await _pump(tester, fixture);

    expect(find.byKey(StudioDriverKeys.agentReadOnlyPanel), findsOneWidget);
    expect(find.text('Child session (read-only)'), findsOneWidget);
    // 没有中断工作、也没有当前执行时，不声称等待主智能体调度。
    expect(find.byKey(const ValueKey('agent-readonly-waiting')), findsNothing);

    // 执行中的成员只显示真实阶段，不能同时说「等待调度」。
    fixture.publishRuntime(execution: _running);
    await tester.pump();
    expect(find.byKey(const ValueKey('agent-readonly-waiting')), findsNothing);
    expect(find.byKey(StudioDriverKeys.agentReadOnlyPanel), findsOneWidget);

    // canonical 确实有未认领继续点且没有当前执行时才说明等待调度。
    fixture.publishRuntime(execution: null, continuation: _continuation);
    await tester.pump();
    expect(
      find.text('Waiting for the main agent to schedule this member.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-readonly-waiting')),
      findsOneWidget,
    );
    for (final key in [
      StudioDriverKeys.composerInput,
      StudioDriverKeys.composerStop,
      StudioDriverKeys.composerContinue,
      StudioDriverKeys.composerSubmit,
      StudioDriverKeys.composerStopping,
    ]) {
      expect(find.byKey(key), findsNothing, reason: '子详情不提供 $key');
    }
    expect(find.byType(TextField), findsNothing);

    // 待决交互只是同一事实的只读投影：不出现答题、审批或决议控件。
    fixture.publishInteraction();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('agent-readonly-pending')),
      findsOneWidget,
    );
    for (final key in [
      StudioDriverKeys.userInputSubmit,
      StudioDriverKeys.toolApprove,
      StudioDriverKeys.toolDeny,
      StudioDriverKeys.childInteractionCard('interaction-approval'),
    ]) {
      expect(find.byKey(key), findsNothing, reason: '子详情不提供 $key');
    }
    expect(
      find.text('The child agent wants to run a command'),
      findsNothing,
      reason: '只读说明不复刻审批内容',
    );
    await _close(tester, fixture);
  });
}
