import 'package:anywork_client/modes.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../../../rust/api/studio/products/read/agent_directory.dart'
    as agents;
import '../../../../rust/api/studio/products/read/project_directory.dart'
    as projects;
import '../../../../rust/api/studio/products/read/thread_directory.dart'
    as threads;
import '../../../../rust/api/studio/types/delegation.dart' as delegation;
import '../../../../rust/api/studio/types/response.dart' as response;
import '../../conversation/scalar_converters.dart'
    show budgetLimitFromBridge, threadStatusFromBridge;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../source_converters.dart';

threads.BridgeThreadDirectoryScope threadDirectoryScopeToBridge(
  ThreadDirectoryScope value,
) => switch (value) {
  QueryThreadDirectoryScope(:final query, :final includePinned) =>
    threads.BridgeThreadDirectoryScope.query(
      query: threads.BridgeThreadDirectoryQuery(
        projectId: query.projectId,
        search: query.search,
        archived: query.archived,
        filter: switch (query.filter) {
          DirectoryFilter.all => threads.BridgeThreadDirectoryFilter.all,
          DirectoryFilter.running =>
            threads.BridgeThreadDirectoryFilter.running,
          DirectoryFilter.attention =>
            threads.BridgeThreadDirectoryFilter.attention,
        },
      ),
      includePinned: includePinned,
    ),
  SingleThreadDirectoryScope(:final threadId) =>
    threads.BridgeThreadDirectoryScope.thread(threadId: threadId),
};

ProjectRecord projectRecordFromBridge(response.ProjectDto value) =>
    ProjectRecord(
      id: value.id,
      name: value.name,
      path: value.path,
      sshAlias: value.sshAlias,
      updatedAt: exactI64(
        BigInt.from(value.updatedAt),
        'Project updated Unix seconds',
      ),
    );

ProjectRecordRead projectRecordReadFromBridge(
  projects.BridgeProjectRecordRead value,
) => ProjectRecordRead(
  id: readTextFromBridge(value.id),
  name: readTextFromBridge(value.name),
  path: readTextFromBridge(value.path),
  sshAlias: nullableReadText(value.sshAlias),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'Project updated Unix seconds',
  ),
);

FrozenModelSelectionRead frozenSelectionReadFromBridge(
  threads.BridgeFrozenModelSelectionRead value,
) => FrozenModelSelectionRead(
  accountId: readTextFromBridge(value.accountId),
  modelId: readTextFromBridge(value.modelId),
  effort: nullableReadText(value.effort),
);

DelegationMode _delegationMode(delegation.BridgeDelegationMode value) =>
    switch (value) {
      delegation.BridgeDelegationMode.profile => DelegationMode.profile,
      delegation.BridgeDelegationMode.automatic => DelegationMode.automatic,
    };

DelegationPreference _delegationPreference(
  delegation.BridgeDelegationPreference value,
) => switch (value) {
  delegation.BridgeDelegationPreference.economy => DelegationPreference.economy,
  delegation.BridgeDelegationPreference.balanced =>
    DelegationPreference.balanced,
  delegation.BridgeDelegationPreference.fast => DelegationPreference.fast,
};

WorkspaceThreadRecordRead workspaceThreadReadFromBridge(
  threads.BridgeWorkspaceThreadRecordRead value,
) => WorkspaceThreadRecordRead(
  id: readTextFromBridge(value.id),
  projectId: readTextFromBridge(value.projectId),
  title: readTextFromBridge(value.title),
  mode: readTextFromBridge(value.mode),
  workspaceMode: switch (value.workspaceMode) {
    threads.BridgeThreadWorkspaceMode.local => ThreadWorkspaceMode.local,
    threads.BridgeThreadWorkspaceMode.worktree => ThreadWorkspaceMode.worktree,
  },
  delegationMode: _delegationMode(value.delegationMode),
  delegationPreference: _delegationPreference(value.delegationPreference),
  frozenModel: value.frozenModel == null
      ? null
      : frozenSelectionReadFromBridge(value.frozenModel!),
  workspacePath: readTextFromBridge(value.workspacePath),
  rootThreadId: readTextFromBridge(value.rootThreadId),
  parentThreadId: nullableReadText(value.parentThreadId),
  role: readTextFromBridge(value.role),
  agentPath: readTextFromBridge(value.agentPath),
  status: threadStatusFromBridge(value.status),
  createdAt: exactI64(
    BigInt.from(value.createdAt),
    'Thread created Unix seconds',
  ),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'Thread updated Unix seconds',
  ),
  lastUserMessageAt: nullableI64(
    value.lastUserMessageAt == null
        ? null
        : BigInt.from(value.lastUserMessageAt!),
    'Thread last input Unix seconds',
  ),
  archived: value.archived,
);

AgentDirectoryEntryRead agentDirectoryReadFromBridge(
  agents.BridgeAgentDirectoryEntryRead value,
) => AgentDirectoryEntryRead(
  id: readTextFromBridge(value.id),
  threadId: readTextFromBridge(value.threadId),
  rootThreadId: readTextFromBridge(value.rootThreadId),
  path: readTextFromBridge(value.path),
  parentPath: nullableReadText(value.parentPath),
  role: readTextFromBridge(value.role),
  task: readTextFromBridge(value.task),
  summary: nullableReadText(value.summary),
  delegationMode: _delegationMode(value.delegationMode),
  delegationPreference: _delegationPreference(value.delegationPreference),
  frozenModel: value.frozenModel == null
      ? null
      : frozenSelectionReadFromBridge(value.frozenModel!),
  depth: value.depth,
  state: agentStateReadFromBridge(value.state),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'Agent updated Unix seconds',
  ),
);

AgentStateRead agentStateReadFromBridge(agents.BridgeAgentStateRead value) =>
    switch (value) {
      agents.BridgeAgentStateRead_Idle(:final budgetPause) =>
        AgentStateRead.idle(
          budgetPause: budgetPause == null
              ? null
              : AgentBudgetPauseRead(
                  turnId: readTextFromBridge(budgetPause.turnId),
                  limit: budgetLimitFromBridge(budgetPause.limit),
                  pausedAt: exactI64(
                    BigInt.from(budgetPause.pausedAt),
                    'Agent paused Unix seconds',
                  ),
                ),
        ),
      agents.BridgeAgentStateRead_Queued(:final turnId) =>
        AgentStateRead.queued(turnId: readTextFromBridge(turnId)),
      agents.BridgeAgentStateRead_Running(:final turnId) =>
        AgentStateRead.running(turnId: readTextFromBridge(turnId)),
      agents.BridgeAgentStateRead_WaitingTool(:final turnId) =>
        AgentStateRead.waitingTool(turnId: readTextFromBridge(turnId)),
      agents.BridgeAgentStateRead_WaitingInteraction(
        :final turnId,
        :final interactionId,
      ) =>
        AgentStateRead.waitingInteraction(
          turnId: readTextFromBridge(turnId),
          interactionId: readTextFromBridge(interactionId),
        ),
      agents.BridgeAgentStateRead_Cancelling(:final turnId) =>
        AgentStateRead.cancelling(turnId: readTextFromBridge(turnId)),
      agents.BridgeAgentStateRead_Closing(
        :final workspaceDisposition,
        :final turnId,
        :final error,
      ) =>
        AgentStateRead.closing(
          workspaceDisposition: switch (workspaceDisposition) {
            agents.BridgeAgentWorkspaceDisposition.preserve =>
              AgentWorkspaceDisposition.preserve,
            agents.BridgeAgentWorkspaceDisposition.cleanup =>
              AgentWorkspaceDisposition.cleanup,
          },
          turnId: nullableReadText(turnId),
          error: error == null ? null : sourceErrorReadFromBridge(error),
        ),
      agents.BridgeAgentStateRead_Closed() => const AgentStateRead.closed(),
      agents.BridgeAgentStateRead_Faulted(
        :final error,
        :final turnId,
        :final classification,
      ) =>
        AgentStateRead.faulted(
          error: sourceErrorReadFromBridge(error),
          turnId: nullableReadText(turnId),
          classification: switch (classification) {
            agents.BridgeAgentFaultClassification.recoverableRuntime =>
              AgentFaultClassification.recoverableRuntime,
            agents.BridgeAgentFaultClassification.recoverableProtocol =>
              AgentFaultClassification.recoverableProtocol,
            agents.BridgeAgentFaultClassification.aggregateCorruption =>
              AgentFaultClassification.aggregateCorruption,
            agents.BridgeAgentFaultClassification.legacyUnknown =>
              AgentFaultClassification.legacyUnknown,
          },
        ),
    };
