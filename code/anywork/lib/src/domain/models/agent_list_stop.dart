import 'package:anywork_client/models.dart';

import 'agent_membership.dart';

/// 智能体列表某一行的停止入口语义。
///
/// 用户对子智能体的运行控制只有停止，入口在列表行而不是子会话详情；目标固定为该行
/// 的会话与执行身份，不依赖当前选中的会话（design/19 §19.6.1、design/25 §25.7）。
enum AgentListStopAction {
  /// 没有当前执行或没有停止资格：不显示可点停止，也不据旧摘要虚构运行。
  none,

  /// 有已确认的准备、等待准入或运行中执行：可停止。
  stop,

  /// 停止已受理、清理尚未结束：禁用「正在停止」，不变成继续。
  stopping,

  /// 本进程观察到的停止已经结束：说明等待主智能体调度，不提供继续或消息操作。
  stoppedWaitingScheduling,
}

/// 一行停止入口的只读判定结果。
final class AgentListStopState {
  const AgentListStopState({required this.action, this.executionId});

  /// 本进程已受理、尚未观察到结束的停止目标执行身份；用于禁止重复点击。
  final String? executionId;

  final AgentListStopAction action;

  /// 停止按钮是否可点。
  bool get canStop => action == AgentListStopAction.stop;

  /// 该行是否显示停止区域（可点、正在停止或等待调度说明）。
  bool get showsControl => action != AgentListStopAction.none;

  /// 按目录行的 canonical 轻状态与本次运行已观察到的停止意图推导。
  ///
  /// 优先级（全部以 canonical 事实为准）：
  /// 1. 退役成员 → `none`（与角色标签共用 [isRetiredAgentRow]）；
  /// 2. 永久关闭 → `none`（可靠保存的关闭意图高于任何执行或调度摘要）；
  /// 3. 正在关闭或故障 → `none`（关闭由关闭流程推进、故障成员没有当前工作，都不该
  ///    提供用户停止，即使目录行仍带遗留执行与停止资格）；
  /// 4. 有当前执行，且清理中/阶段为停止/命中已受理目标 → `stopping`；
  /// 5. 有当前执行且具备停止资格 → `stop`；
  /// 6. [StudioAgentView.awaitingScheduling] → `stoppedWaitingScheduling`（只在没有可
  ///    停止执行时兜底，不能掩盖准备期或清理中的同一成员）；
  /// 7. 其余 → `none`。
  ///
  /// 不以 `state.isActive` 作为停止的必要条件：生产投影在没有 Running Turn 时把
  /// `agent_state` 报成 `Idle`，同时按 `execution.is_some()` 发布 `can_stop`，因此
  /// `Idle + execution(preparing/awaiting*) + canStop` 必须仍可停止。
  ///
  /// [acceptedExecutionId] 是本进程已受理、尚未观察到结束的停止目标：它让同一行在
  /// 清理期保持禁用的「正在停止」，不能被第二次点击取代。
  factory AgentListStopState.resolve({
    required StudioAgentView agent,
    String? acceptedExecutionId,
  }) {
    // 退役成员不提供任何运行控制，与角色标签共用同一判据。
    if (isRetiredAgentRow(agent)) {
      return const AgentListStopState(action: AgentListStopAction.none);
    }
    // 永久关闭是终态：可靠保存的关闭意图优先于任何遗留执行或调度摘要。
    if (agent.state is ClosedStudioAgent) {
      return const AgentListStopState(action: AgentListStopAction.none);
    }
    // 正在关闭与故障成员没有当前工作：关闭由关闭流程推进，故障成员不会被用户停止
    // 回收。二者即使仍带遗留执行与停止资格，也不提供可点停止或「正在停止」。
    if (agent.state is ClosingStudioAgent ||
        agent.state is FaultedStudioAgent) {
      return const AgentListStopState(action: AgentListStopAction.none);
    }
    final execution = agent.execution;
    if (execution != null &&
        (agent.state is CancellingStudioAgent ||
            execution.phase.isStopping ||
            execution.id == acceptedExecutionId)) {
      // 停止已受理但清理未结束：目标仍是同一执行，禁止重复点击。
      return AgentListStopState(
        action: AgentListStopAction.stopping,
        executionId: execution.id,
      );
    }
    if (execution != null && agent.canStop) {
      return AgentListStopState(
        action: AgentListStopAction.stop,
        executionId: execution.id,
      );
    }
    // 「等待主智能体调度」只覆盖没有可停止执行的成员；准备期与清理中的同一成员已在
    // 上面处理。
    if (agent.awaitingScheduling) {
      return const AgentListStopState(
        action: AgentListStopAction.stoppedWaitingScheduling,
      );
    }
    return const AgentListStopState(action: AgentListStopAction.none);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentListStopState &&
          action == other.action &&
          executionId == other.executionId;

  @override
  int get hashCode => Object.hash(action, executionId);

  @override
  String toString() => 'AgentListStopState($action, $executionId)';
}
