import 'delegation_models.dart';

/// 一个会话当前执行的生命周期阶段。
///
/// 阶段来自规范状态里的执行记录，不按「有没有活动轮次」推导：准备、等待保存、
/// 等待准入与清理期间同样有可停止的执行身份。
enum AgentExecutionPhase {
  preparing,
  awaitingStorage,
  awaitingAdmission,
  running,
  stopping;

  /// Canonical wire 标签。
  String get label => name;

  /// 停止请求已被受理、清理尚未结束。
  bool get isStopping => this == AgentExecutionPhase.stopping;
}

/// 主会话自身或智能体目录某一行的当前执行身份。
///
/// 精确停止的目标就是这里的 [id]；它独立于当前选中的会话与轮次投影。
final class AgentExecutionView {
  const AgentExecutionView({
    required this.id,
    required this.phase,
    this.turnId,
  });

  final String id;
  final AgentExecutionPhase phase;

  /// 已创建轮次时为其编号；准备期允许为空。
  final String? turnId;

  bool get isStopping => phase.isStopping;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentExecutionView &&
          id == other.id &&
          phase == other.phase &&
          turnId == other.turnId;

  @override
  int get hashCode => Object.hash(id, phase, turnId);
}

sealed class StudioAgentState {
  const StudioAgentState();

  bool get isActive => switch (this) {
    QueuedStudioAgent() ||
    RunningStudioAgent() ||
    WaitingToolStudioAgent() ||
    WaitingInteractionStudioAgent() ||
    CancellingStudioAgent() => true,
    IdleStudioAgent() ||
    ClosingStudioAgent() ||
    ClosedStudioAgent() ||
    FaultedStudioAgent() => false,
  };

  String get label => switch (this) {
    IdleStudioAgent() => 'idle',
    QueuedStudioAgent() => 'queued',
    RunningStudioAgent() => 'running',
    WaitingToolStudioAgent() => 'waitingTool',
    WaitingInteractionStudioAgent() => 'waitingInteraction',
    CancellingStudioAgent() => 'cancelling',
    ClosingStudioAgent() => 'closing',
    ClosedStudioAgent() => 'closed',
    FaultedStudioAgent() => 'faulted',
  };

  String? get errorMessage => switch (this) {
    ClosingStudioAgent(:final failure) => failure?.message,
    FaultedStudioAgent(:final failure) => failure.message,
    IdleStudioAgent() ||
    QueuedStudioAgent() ||
    RunningStudioAgent() ||
    WaitingToolStudioAgent() ||
    WaitingInteractionStudioAgent() ||
    CancellingStudioAgent() ||
    ClosedStudioAgent() => null,
  };

  @override
  bool operator ==(Object other) => runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class IdleStudioAgent extends StudioAgentState {
  const IdleStudioAgent();
}

final class QueuedStudioAgent extends StudioAgentState {
  const QueuedStudioAgent(this.turnId);
  final String turnId;

  @override
  bool operator ==(Object other) =>
      other is QueuedStudioAgent && turnId == other.turnId;

  @override
  int get hashCode => Object.hash(runtimeType, turnId);
}

final class RunningStudioAgent extends StudioAgentState {
  const RunningStudioAgent(this.turnId);
  final String turnId;

  @override
  bool operator ==(Object other) =>
      other is RunningStudioAgent && turnId == other.turnId;

  @override
  int get hashCode => Object.hash(runtimeType, turnId);
}

final class WaitingToolStudioAgent extends StudioAgentState {
  const WaitingToolStudioAgent(this.turnId);
  final String turnId;

  @override
  bool operator ==(Object other) =>
      other is WaitingToolStudioAgent && turnId == other.turnId;

  @override
  int get hashCode => Object.hash(runtimeType, turnId);
}

final class WaitingInteractionStudioAgent extends StudioAgentState {
  const WaitingInteractionStudioAgent(this.turnId, this.interactionId);
  final String turnId;
  final String interactionId;

  @override
  bool operator ==(Object other) =>
      other is WaitingInteractionStudioAgent &&
      turnId == other.turnId &&
      interactionId == other.interactionId;

  @override
  int get hashCode => Object.hash(runtimeType, turnId, interactionId);
}

final class CancellingStudioAgent extends StudioAgentState {
  const CancellingStudioAgent(this.turnId);
  final String turnId;

  @override
  bool operator ==(Object other) =>
      other is CancellingStudioAgent && turnId == other.turnId;

  @override
  int get hashCode => Object.hash(runtimeType, turnId);
}

final class ClosingStudioAgent extends StudioAgentState {
  const ClosingStudioAgent({this.turnId, this.failure});
  final String? turnId;
  final AgentStateError? failure;

  @override
  bool operator ==(Object other) =>
      other is ClosingStudioAgent &&
      turnId == other.turnId &&
      failure == other.failure;
  @override
  int get hashCode => Object.hash(runtimeType, turnId, failure);
}

final class ClosedStudioAgent extends StudioAgentState {
  const ClosedStudioAgent();
}

final class FaultedStudioAgent extends StudioAgentState {
  const FaultedStudioAgent({required this.failure, this.diagnosticTurnId});

  final AgentStateError failure;
  final String? diagnosticTurnId;

  @override
  bool operator ==(Object other) =>
      other is FaultedStudioAgent &&
      failure == other.failure &&
      diagnosticTurnId == other.diagnosticTurnId;

  @override
  int get hashCode => Object.hash(runtimeType, failure, diagnosticTurnId);
}

class AgentStateError {
  const AgentStateError({
    required this.code,
    required this.message,
    required this.retryable,
  });

  final String code;
  final String message;
  final bool retryable;

  @override
  bool operator ==(Object other) =>
      other is AgentStateError &&
      code == other.code &&
      message == other.message &&
      retryable == other.retryable;

  @override
  int get hashCode => Object.hash(code, message, retryable);
}

/// 目录运行事实按后端区分；ACP 未观察到的状态不映射为 Native 空闲。
sealed class StudioAgentActivity {
  const StudioAgentActivity();
}

final class NativeStudioAgentActivity extends StudioAgentActivity {
  const NativeStudioAgentActivity({
    required this.state,
    this.execution,
    this.canStop = false,
    this.awaitingScheduling = false,
  });

  final StudioAgentState state;
  final AgentExecutionView? execution;
  final bool canStop;
  final bool awaitingScheduling;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeStudioAgentActivity &&
          state == other.state &&
          execution == other.execution &&
          canStop == other.canStop &&
          awaitingScheduling == other.awaitingScheduling;

  @override
  int get hashCode =>
      Object.hash(state, execution, canStop, awaitingScheduling);
}

/// 显式关闭意图不等于执行或工作树清理已完成。
final class AcpStudioAgentActivity extends StudioAgentActivity {
  const AcpStudioAgentActivity({required this.explicitlyClosed});

  final bool explicitlyClosed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpStudioAgentActivity &&
          explicitlyClosed == other.explicitlyClosed;

  @override
  int get hashCode => Object.hash(runtimeType, explicitlyClosed);
}

/// 智能体目录行：成员身份四元组加成员执行事实。
///
/// `sessionId` 是归属判据，`parentAgentId` 是 root/child 判据；两者都只读
/// 目录字段，不从 Thread 快照或 ID 形状推导。
class StudioAgentView {
  const StudioAgentView({
    required this.agentId,
    required this.sessionId,
    required this.threadId,
    required this.role,
    required this.delegationMode,
    required this.delegationPreference,
    this.parentAgentId,
    this.frozenModel,
    required this.task,
    required this.activity,
    required this.updatedAt,
    this.summary,
  });

  final String agentId;
  final String sessionId;
  final String? parentAgentId;
  final String threadId;
  final String role;
  final DelegationMode delegationMode;
  final DelegationPreference delegationPreference;
  final NewThreadModelRoute? frozenModel;
  final String task;
  final String? summary;
  final StudioAgentActivity activity;
  final DateTime updatedAt;

  bool get isRootAgent => parentAgentId == null;

  bool get isChildAgent => parentAgentId != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudioAgentView &&
          agentId == other.agentId &&
          sessionId == other.sessionId &&
          parentAgentId == other.parentAgentId &&
          threadId == other.threadId &&
          role == other.role &&
          delegationMode == other.delegationMode &&
          delegationPreference == other.delegationPreference &&
          frozenModel == other.frozenModel &&
          task == other.task &&
          summary == other.summary &&
          activity == other.activity &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    agentId,
    sessionId,
    parentAgentId,
    threadId,
    role,
    delegationMode,
    delegationPreference,
    frozenModel,
    task,
    summary,
    activity,
    updatedAt,
  );
}
