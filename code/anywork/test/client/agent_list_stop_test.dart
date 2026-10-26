import 'package:anywork/src/features/workspace/state/agent_list_stop.dart';
import 'package:anywork_client/workspace.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

AgentDirectoryEntry _agent({
  AgentExecution? execution,
  bool canStop = false,
  bool awaitingScheduling = false,
  AgentState state = const RunningAgentState(turnId: 'turn-1'),
  String? parentPath = 'root',
  String role = 'executor',
}) {
  return AgentDirectoryEntry(
    id: 'child-1',
    threadId: 'thread-child',
    path: 'root/child',
    parentPath: parentPath,
    role: role,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    task: 'child task',
    state: state,
    updatedAt: 1767225600,
    rootThreadId: 'thread-root',
    depth: 1,
    summary: null,
    frozenModel: null,
    execution: execution,
    canStop: canStop,
    awaitingScheduling: awaitingScheduling,
  );
}

const _execution = AgentExecution(
  id: 'exec-child-1',
  phase: AgentExecutionPhase.running,
  turnId: 'turn-1',
);

void main() {
  test('运行中的成员提供停止入口，目标是该行的执行身份', () {
    for (final phase in const [
      AgentExecutionPhase.preparing,
      AgentExecutionPhase.awaitingStorage,
      AgentExecutionPhase.awaitingAdmission,
      AgentExecutionPhase.running,
    ]) {
      final state = AgentListStopState.resolve(
        agent: _agent(
          execution: AgentExecution(id: 'exec-child-1', phase: phase, turnId: null),
          canStop: true,
        ),
      );
      expect(state.action, AgentListStopAction.stop, reason: '$phase');
      expect(state.canStop, isTrue, reason: '$phase');
      expect(state.executionId, 'exec-child-1', reason: '$phase');
    }
  });

  test('没有停止资格时即使有执行也不提供可点停止', () {
    final state = AgentListStopState.resolve(
      agent: _agent(execution: _execution),
    );
    expect(state.action, AgentListStopAction.none);
    expect(state.showsControl, isFalse);
  });

  test('accepted停止在空Idle目录行上仍等待独立观察屏障，不用Idle伪造完成', () {
    final state = AgentListStopState.resolve(
      agent: _agent(state: const IdleAgentState(budgetPause: null), awaitingScheduling: true),
      acceptedExecutionId: 'exec-child-1',
    );
    expect(state.action, AgentListStopAction.stopping);
    expect(state.executionId, 'exec-child-1');
    expect(state.canStop, isFalse);
  });

  test('停止已受理、清理未结束显示禁用的正在停止', () {
    final stopping = AgentListStopState.resolve(
      agent: _agent(
        execution: const AgentExecution(
          id: 'exec-child-1',
          phase: AgentExecutionPhase.stopping,
          turnId: 'turn-1',
        ),
        canStop: true,
      ),
    );
    expect(stopping.action, AgentListStopAction.stopping);
    expect(stopping.canStop, isFalse);

    final cancelling = AgentListStopState.resolve(
      agent: _agent(
        execution: _execution,
        state: const CancellingAgentState(turnId: 'turn-1'),
      ),
    );
    expect(cancelling.action, AgentListStopAction.stopping);
    expect(cancelling.canStop, isFalse);

    final accepted = AgentListStopState.resolve(
      agent: _agent(execution: _execution, canStop: true),
      acceptedExecutionId: 'exec-child-1',
    );
    expect(
      accepted.action,
      AgentListStopAction.stopping,
      reason: '已受理且尚未观察到结束的停止不能被第二次点击取代',
    );
    expect(accepted.canStop, isFalse);
  });

  test('有未认领继续点的成员说明等待主智能体调度，且没有继续或消息操作', () {
    final state = AgentListStopState.resolve(
      agent: _agent(state: const IdleAgentState(budgetPause: null), awaitingScheduling: true),
    );
    expect(state.action, AgentListStopAction.stoppedWaitingScheduling);
    expect(state.canStop, isFalse);
    expect(state.showsControl, isTrue);
  });

  test('正常完成、关闭与退役成员不声称等待调度', () {
    for (final state in const <AgentState>[
      IdleAgentState(budgetPause: null),
      ClosingAgentState(workspaceDisposition: AgentWorkspaceDisposition.preserve, error: null, turnId: null),
      ClosedAgentState(),
      FaultedAgentState(
        error: SourceStateError(
          code: 'failed',
          message: 'failed',
          retryable: false,
        ),
        turnId: null,
        classification: AgentFaultClassification.recoverableRuntime,
      ),
    ]) {
      final resolved = AgentListStopState.resolve(agent: _agent(state: state));
      expect(resolved.action, AgentListStopAction.none, reason: state.runtimeType.toString());
      expect(resolved.showsControl, isFalse, reason: state.runtimeType.toString());
    }
  });

  test('已关闭成员即使遗留执行与停止资格也不产生停止入口', () {
    final resolved = AgentListStopState.resolve(
      agent: _agent(
        state: const ClosedAgentState(),
        execution: _execution,
        canStop: true,
        awaitingScheduling: true,
      ),
      acceptedExecutionId: 'exec-child-1',
    );
    expect(resolved.action, AgentListStopAction.none);
    expect(resolved.canStop, isFalse);
    expect(resolved.showsControl, isFalse);
  });

  test('没有当前执行的终态成员不产生任何控制', () {
    for (final state in const <AgentState>[
      IdleAgentState(budgetPause: null),
      FaultedAgentState(
        error: SourceStateError(
          code: 'failed',
          message: 'failed',
          retryable: false,
        ),
        turnId: null,
        classification: AgentFaultClassification.recoverableRuntime,
      ),
      ClosingAgentState(workspaceDisposition: AgentWorkspaceDisposition.preserve, error: null, turnId: null),
      ClosedAgentState(),
    ]) {
      final resolved = AgentListStopState.resolve(
        agent: _agent(state: state, canStop: true),
      );
      expect(resolved.action, AgentListStopAction.none, reason: state.runtimeType.toString());
      expect(resolved.showsControl, isFalse, reason: state.runtimeType.toString());
    }
  });

  test('正在关闭与故障成员即使遗留执行与停止资格也不产生控制', () {
    for (final state in const <AgentState>[
      ClosingAgentState(workspaceDisposition: AgentWorkspaceDisposition.preserve, error: null, turnId: 'turn-1'),
      FaultedAgentState(
        error: SourceStateError(
          code: 'failed',
          message: 'failed',
          retryable: false,
        ),
        turnId: 'turn-1',
        classification: AgentFaultClassification.recoverableRuntime,
      ),
    ]) {
      for (final phase in const [
        AgentExecutionPhase.preparing,
        AgentExecutionPhase.running,
        AgentExecutionPhase.stopping,
      ]) {
        final resolved = AgentListStopState.resolve(
          agent: _agent(
            state: state,
            execution: AgentExecution(id: 'exec-child-1', phase: phase, turnId: null),
            canStop: true,
          ),
          acceptedExecutionId: 'exec-child-1',
        );
        expect(
          resolved.action,
          AgentListStopAction.none,
          reason: '${state.runtimeType} / $phase',
        );
        expect(resolved.canStop, isFalse, reason: '${state.runtimeType} / $phase');
        expect(
          resolved.showsControl,
          isFalse,
          reason: '${state.runtimeType} / $phase',
        );
      }
    }
  });

  test('准备期执行不以 state 为必要条件：Idle 行同样可停止', () {
    for (final phase in const [
      AgentExecutionPhase.preparing,
      AgentExecutionPhase.awaitingStorage,
      AgentExecutionPhase.awaitingAdmission,
    ]) {
      final resolved = AgentListStopState.resolve(
        agent: _agent(
          state: const IdleAgentState(budgetPause: null),
          execution: AgentExecution(id: 'exec-child-1', phase: phase, turnId: null),
          canStop: true,
        ),
      );
      expect(resolved.action, AgentListStopAction.stop, reason: '$phase');
      expect(resolved.executionId, 'exec-child-1', reason: '$phase');
    }
  });

  test('Idle 行的清理中执行仍显示正在停止，而不是等待调度', () {
    final resolved = AgentListStopState.resolve(
      agent: _agent(
        state: const IdleAgentState(budgetPause: null),
        execution: const AgentExecution(
          id: 'exec-child-1',
          phase: AgentExecutionPhase.stopping,
          turnId: null,
        ),
        awaitingScheduling: true,
      ),
    );
    expect(resolved.action, AgentListStopAction.stopping);
    expect(resolved.executionId, 'exec-child-1');
  });

  test('Idle 行带执行与等待调度事实时按执行态判定', () {
    final resolved = AgentListStopState.resolve(
      agent: _agent(
        state: const IdleAgentState(budgetPause: null),
        execution: _execution,
        canStop: true,
        awaitingScheduling: true,
      ),
    );
    expect(resolved.action, AgentListStopAction.stop);
  });

  test('退役成员即使带遗留执行与停止资格也不产生控制', () {
    final resolved = AgentListStopState.resolve(
      agent: _agent(
        state: const RunningAgentState(turnId: 'turn-1'),
        execution: _execution,
        canStop: true,
        role: 'planner',
        parentPath: 'root',
      ),
    );
    expect(resolved.action, AgentListStopAction.none);
    expect(resolved.canStop, isFalse);
    expect(resolved.showsControl, isFalse);
  });

  test('角色相同但非子成员不算退役，仍按可执行中资格判定', () {
    final resolved = AgentListStopState.resolve(
      agent: _agent(
        state: const RunningAgentState(turnId: 'turn-1'),
        execution: _execution,
        canStop: true,
        role: 'planner',
        parentPath: null,
      ),
    );
    expect(resolved.action, AgentListStopAction.stop);
  });

  test('可执行中且具备停止资格时，即使同时带等待调度事实也给出停止', () {
    final resolved = AgentListStopState.resolve(
      agent: _agent(
        state: const RunningAgentState(turnId: 'turn-1'),
        execution: _execution,
        canStop: true,
        awaitingScheduling: true,
      ),
    );
    expect(resolved.action, AgentListStopAction.stop);
    expect(resolved.executionId, 'exec-child-1');
  });

  test('清理中即使同时带等待调度事实也显示正在停止', () {
    for (final agent in [
      _agent(
        state: const CancellingAgentState(turnId: 'turn-1'),
        execution: _execution,
        canStop: true,
        awaitingScheduling: true,
      ),
      _agent(
        state: const RunningAgentState(turnId: 'turn-1'),
        execution: const AgentExecution(
          id: 'exec-child-1',
          phase: AgentExecutionPhase.stopping,
          turnId: 'turn-1',
        ),
        canStop: true,
        awaitingScheduling: true,
      ),
      _agent(
        state: const RunningAgentState(turnId: 'turn-1'),
        execution: _execution,
        canStop: true,
        awaitingScheduling: true,
      ),
    ]) {
      final resolved = AgentListStopState.resolve(
        agent: agent,
        acceptedExecutionId: null,
      );
      expect(
        resolved.action,
        agent.execution!.phase == AgentExecutionPhase.stopping ||
                agent.state is CancellingAgentState
            ? AgentListStopAction.stopping
            : AgentListStopAction.stop,
      );
    }
  });

  test('已受理停止且清理未结束优先于等待调度', () {
    final resolved = AgentListStopState.resolve(
      agent: _agent(
        state: const RunningAgentState(turnId: 'turn-1'),
        execution: _execution,
        canStop: true,
        awaitingScheduling: true,
      ),
      acceptedExecutionId: 'exec-child-1',
    );
    expect(resolved.action, AgentListStopAction.stopping);
    expect(resolved.executionId, 'exec-child-1');
    expect(resolved.canStop, isFalse);
  });

  test('没有可执行中状态时等待调度才显示说明', () {
    final resolved = AgentListStopState.resolve(
      agent: _agent(state: const IdleAgentState(budgetPause: null), awaitingScheduling: true),
    );
    expect(resolved.action, AgentListStopAction.stoppedWaitingScheduling);
    expect(resolved.canStop, isFalse);
    expect(resolved.showsControl, isTrue);
  });

  test('可执行中但无停止资格时不提供停止', () {
    for (final state in const <AgentState>[
      QueuedAgentState(turnId: 'turn-1'),
      RunningAgentState(turnId: 'turn-1'),
      WaitingToolAgentState(turnId: 'turn-1'),
      WaitingInteractionAgentState(turnId: 'turn-1', interactionId: 'interaction-1'),
    ]) {
      final resolved = AgentListStopState.resolve(
        agent: _agent(state: state, execution: _execution),
      );
      expect(resolved.action, AgentListStopAction.none, reason: state.runtimeType.toString());
    }
  });
}
