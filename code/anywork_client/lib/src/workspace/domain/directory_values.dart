import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import '../../models/domain/model_values.dart';
import '../../modes/domain/delegation_values.dart';
import '../../modes/domain/mode_values.dart';
import 'agent_execution.dart';

export 'agent_execution.dart';

part 'directory_values.freezed.dart';

enum ThreadWorkspaceMode { local, worktree }

bool isRetiredAgentRole(String role) => role.trim() == 'planner';

enum ThreadStatus {
  idle,
  queued,
  running,
  waitingTool,
  waitingInteraction,
  cancelling,
  closing,
  closed,
  faulted,
}

enum DirectoryFilter { all, running, attention }

@freezed
abstract class DirectoryQuery with _$DirectoryQuery {
  const factory DirectoryQuery({
    required String? projectId,
    required String? search,
    required bool archived,
    required DirectoryFilter filter,
  }) = _DirectoryQuery;
}

@freezed
sealed class ThreadDirectoryScope with _$ThreadDirectoryScope {
  const factory ThreadDirectoryScope.query({
    required DirectoryQuery query,
    @Default(true) bool includePinned,
  }) = QueryThreadDirectoryScope;
  const factory ThreadDirectoryScope.thread({required String threadId}) =
      SingleThreadDirectoryScope;
}

@Freezed(toStringOverride: false)
abstract class ProjectRecord with _$ProjectRecord {
  const factory ProjectRecord({
    required String id,
    required String name,
    required String path,
    required String? sshAlias,
    required int updatedAt,
  }) = _ProjectRecord;
}

@Freezed(toStringOverride: false)
abstract class WorkspaceThreadRecord with _$WorkspaceThreadRecord {
  const WorkspaceThreadRecord._();

  const factory WorkspaceThreadRecord({
    required String id,
    required String projectId,
    required String title,
    required ThreadModeId mode,
    required DelegationMode delegationMode,
    required DelegationPreference delegationPreference,
    required ModelSelection? frozenModel,
    required ThreadWorkspaceMode workspaceMode,
    required String workspacePath,
    required String rootThreadId,
    required String? parentThreadId,
    required String role,
    required String agentPath,
    required ThreadStatus status,
    required int createdAt,
    required int updatedAt,
    required int? lastUserMessageAt,
    required bool archived,
  }) = _WorkspaceThreadRecord;

  bool get isRoot => parentThreadId == null;
  bool get isAgent => !isRoot;
  bool get isRetiredAgent => isAgent && isRetiredAgentRole(role);
  int get directorySortTime => lastUserMessageAt ?? createdAt;
}

enum AgentWorkspaceDisposition { preserve, cleanup }

enum AgentFaultClassification {
  recoverableRuntime,
  recoverableProtocol,
  aggregateCorruption,
  legacyUnknown,
}

@freezed
abstract class AgentBudgetPause with _$AgentBudgetPause {
  const factory AgentBudgetPause({
    required String turnId,
    required BudgetLimitSnapshot limit,
    required int pausedAt,
  }) = _AgentBudgetPause;
}

@Freezed(toStringOverride: false)
sealed class AgentState with _$AgentState {
  const factory AgentState.idle({required AgentBudgetPause? budgetPause}) =
      IdleAgentState;
  const factory AgentState.queued({required String turnId}) = QueuedAgentState;
  const factory AgentState.running({required String turnId}) =
      RunningAgentState;
  const factory AgentState.waitingTool({required String turnId}) =
      WaitingToolAgentState;
  const factory AgentState.waitingInteraction({
    required String turnId,
    required String interactionId,
  }) = WaitingInteractionAgentState;
  const factory AgentState.cancelling({required String turnId}) =
      CancellingAgentState;
  const factory AgentState.closing({
    required AgentWorkspaceDisposition workspaceDisposition,
    required String? turnId,
    required SourceStateError? error,
  }) = ClosingAgentState;
  const factory AgentState.closed() = ClosedAgentState;
  const factory AgentState.faulted({
    required SourceStateError error,
    required String? turnId,
    required AgentFaultClassification classification,
  }) = FaultedAgentState;
}

@Freezed(toStringOverride: false)
abstract class AgentDirectoryEntry with _$AgentDirectoryEntry {
  const factory AgentDirectoryEntry({
    required String id,
    required String threadId,
    required String rootThreadId,
    required String path,
    required String? parentPath,
    required String role,
    required DelegationMode delegationMode,
    required DelegationPreference delegationPreference,
    required ModelSelection? frozenModel,
    required String task,
    required String? summary,
    required int depth,
    required AgentState state,
    AgentExecution? execution,
    @Default(false) bool canStop,
    @Default(false) bool awaitingScheduling,
    required int updatedAt,
  }) = _AgentDirectoryEntry;
}
