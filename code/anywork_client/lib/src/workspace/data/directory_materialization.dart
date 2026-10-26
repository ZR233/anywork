import 'package:anywork_client/modes.dart' show ThreadModeId;
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_values.dart';
import '../../models/domain/model_values.dart'
    show AccountModelKey, ModelSelection;
import 'directory_reads.dart';

typedef DirectoryTextRead = Future<TextChunk> Function(int fieldId, int offset);

Future<ProjectRecord> readProjectRecord(
  ProjectRecordRead value,
  DirectoryTextRead read,
) async => ProjectRecord(
  id: await materializeReadText(value.id, read: read),
  name: await materializeReadText(value.name, read: read),
  path: await materializeReadText(value.path, read: read),
  sshAlias: value.sshAlias == null
      ? null
      : await materializeReadText(value.sshAlias!, read: read),
  updatedAt: value.updatedAt,
);

Future<WorkspaceThreadRecord> readWorkspaceThreadRecord(
  WorkspaceThreadRecordRead value,
  DirectoryTextRead read,
) async => WorkspaceThreadRecord(
  id: await materializeReadText(value.id, read: read),
  projectId: await materializeReadText(value.projectId, read: read),
  title: await materializeReadText(value.title, read: read),
  mode: ThreadModeId(await materializeReadText(value.mode, read: read)),
  delegationMode: value.delegationMode,
  delegationPreference: value.delegationPreference,
  frozenModel: await _frozenModel(value.frozenModel, read),
  workspaceMode: value.workspaceMode,
  workspacePath: await materializeReadText(value.workspacePath, read: read),
  rootThreadId: await materializeReadText(value.rootThreadId, read: read),
  parentThreadId: value.parentThreadId == null
      ? null
      : await materializeReadText(value.parentThreadId!, read: read),
  role: await materializeReadText(value.role, read: read),
  agentPath: await materializeReadText(value.agentPath, read: read),
  status: value.status,
  createdAt: value.createdAt,
  updatedAt: value.updatedAt,
  lastUserMessageAt: value.lastUserMessageAt,
  archived: value.archived,
);

Future<SourceStateError> _error(
  SourceStateErrorRead value,
  DirectoryTextRead read,
) async => SourceStateError(
  code: await materializeReadText(value.code, read: read),
  message: await materializeReadText(value.message, read: read),
  retryable: value.retryable,
);

Future<AgentState> _state(
  AgentStateRead value,
  DirectoryTextRead read,
) async => switch (value) {
  IdleAgentStateRead(:final budgetPause) => AgentState.idle(
    budgetPause: budgetPause == null
        ? null
        : AgentBudgetPause(
            turnId: await materializeReadText(budgetPause.turnId, read: read),
            limit: budgetPause.limit,
            pausedAt: budgetPause.pausedAt,
          ),
  ),
  QueuedAgentStateRead(:final turnId) => AgentState.queued(
    turnId: await materializeReadText(turnId, read: read),
  ),
  RunningAgentStateRead(:final turnId) => AgentState.running(
    turnId: await materializeReadText(turnId, read: read),
  ),
  WaitingToolAgentStateRead(:final turnId) => AgentState.waitingTool(
    turnId: await materializeReadText(turnId, read: read),
  ),
  WaitingInteractionAgentStateRead(:final turnId, :final interactionId) =>
    AgentState.waitingInteraction(
      turnId: await materializeReadText(turnId, read: read),
      interactionId: await materializeReadText(interactionId, read: read),
    ),
  CancellingAgentStateRead(:final turnId) => AgentState.cancelling(
    turnId: await materializeReadText(turnId, read: read),
  ),
  ClosingAgentStateRead(
    :final workspaceDisposition,
    :final turnId,
    :final error,
  ) =>
    AgentState.closing(
      workspaceDisposition: workspaceDisposition,
      turnId: turnId == null
          ? null
          : await materializeReadText(turnId, read: read),
      error: error == null ? null : await _error(error, read),
    ),
  ClosedAgentStateRead() => const AgentState.closed(),
  FaultedAgentStateRead(:final error, :final turnId, :final classification) =>
    AgentState.faulted(
      error: await _error(error, read),
      turnId: turnId == null
          ? null
          : await materializeReadText(turnId, read: read),
      classification: classification,
    ),
};

Future<AgentDirectoryEntry> readAgentDirectoryEntry(
  AgentDirectoryEntryRead value,
  DirectoryTextRead read,
) async {
  if (value.depth < 0)
    throw resourceProtocol('The original agent depth is negative.');
  return AgentDirectoryEntry(
    id: await materializeReadText(value.id, read: read),
    threadId: await materializeReadText(value.threadId, read: read),
    rootThreadId: await materializeReadText(value.rootThreadId, read: read),
    path: await materializeReadText(value.path, read: read),
    parentPath: value.parentPath == null
        ? null
        : await materializeReadText(value.parentPath!, read: read),
    role: await materializeReadText(value.role, read: read),
    delegationMode: value.delegationMode,
    delegationPreference: value.delegationPreference,
    frozenModel: await _frozenModel(value.frozenModel, read),
    task: await materializeReadText(value.task, read: read),
    summary: value.summary == null
        ? null
        : await materializeReadText(value.summary!, read: read),
    depth: value.depth,
    state: await _state(value.state, read),
    execution: value.execution,
    canStop: value.canStop,
    awaitingScheduling: value.awaitingScheduling,
    updatedAt: value.updatedAt,
  );
}

Future<ModelSelection?> _frozenModel(
  FrozenModelSelectionRead? value,
  DirectoryTextRead read,
) async => value == null
    ? null
    : ModelSelection(
        model: AccountModelKey(
          accountId: await materializeReadText(value.accountId, read: read),
          modelId: await materializeReadText(value.modelId, read: read),
        ),
        effort: value.effort == null
            ? null
            : await materializeReadText(value.effort!, read: read),
      );
