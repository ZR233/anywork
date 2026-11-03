import 'package:anywork_client/models.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart' show AgentDirectoryQueries;

import 'agent_workspace_view.dart';

// Canonical workspace values are replaced by reducers. UI-only anchor/composer
// changes must not rebuild all row projections; old entries are weakly held.

class _StudioStateUnset {
  const _StudioStateUnset();
}

const _studioStateUnset = _StudioStateUnset();
const _emptySessionRuntime = ThreadRuntimeView(
  modelId: '',
  contextTokens: 0,
  contextWindow: 0,
  totalTokens: 0,
  costLabel: '',
  activeSkills: [],
  activeMcpServers: [],
  activeLspServers: [],
);

class StudioState {
  StudioState({
    required this.projectDirectory,
    required this.threadDirectory,
    required this.agentDirectory,
    required this.settingsState,
    required this.accountsState,
    required this.modelDirectoryState,
    required this.recoveryState,
    required this.mcpState,
    required this.lspState,
    required this.skillsByProject,
    this.threadModeCatalog = const ThreadModeCatalogView(),
    required this.accountUsageState,
    required this.updaterState,
    this.persistenceState = const PersistenceStateSnapshot.ready(),
    this.persistenceQueueState,
    this.agentProfilesState,
    this.sessionCostsByRoot = const {},
    this.mutations = const {},
    this.topicConnections = const {},
    this.workspacesByThread = const {},
    this.workspaceUiByThread = const {},
    this.openedThreadIds = const {},
    this.newThreadComposerByProject = const {},
    this.composerDiagnosticsByTarget = const {},
    this.newThreadModeByProject = const {},
    this.newThreadWorkspaceModeByProject = const {},
    required this.selectedProjectId,
    required this.selectedThreadId,
  });

  final Map<String, ThreadWorkspace> workspacesByThread;
  final Map<String, WorkspaceUiState> workspaceUiByThread;

  /// 已被用户显式打开过的会话。
  ///
  /// 首屏恢复的上次选择只表达选择，不在此集合中（§6.1）：打开是显式用户动作，
  /// 只有打开过的会话才建立订阅、读取当前状态与首个历史窗口。
  final Set<String> openedThreadIds;
  final Map<String, ComposerThreadState> newThreadComposerByProject;

  /// Target-scoped composer/attachment diagnostics survive workspace or
  /// directory removal so cleanup failures remain observable without
  /// resurrecting a destroyed composer target.
  final Map<String, ComposerTargetDiagnostic> composerDiagnosticsByTarget;
  final Map<String, ThreadModeId> newThreadModeByProject;

  /// 按项目隔离的起始页工作区模式草稿；提交后仍保留，供同一项目再次创建会话。
  final Map<String, ThreadWorkspaceMode> newThreadWorkspaceModeByProject;
  final String? selectedProjectId;
  final String? selectedThreadId;
  final ProjectDirectoryState projectDirectory;
  final ThreadDirectoryFrame threadDirectory;
  final AgentDirectoryState agentDirectory;
  final SettingsStateSnapshot settingsState;
  final RecoveryStateSnapshot recoveryState;
  final McpStateSnapshot mcpState;
  final LspStateSnapshot lspState;
  final Map<String, SkillsStateSnapshot> skillsByProject;
  final ThreadModeCatalogView threadModeCatalog;
  final AccountsState accountsState;
  final ModelDirectoryState modelDirectoryState;
  final AccountResource<Map<NativeAccountIdentity, AccountUsageObservation>>
  accountUsageState;
  final UpdaterStateSnapshot updaterState;
  final PersistenceStateSnapshot persistenceState;

  /// 进程级持久化队列诊断；由 PersistenceQueue topic/显式读取更新。
  final PersistenceQueueStateView? persistenceQueueState;

  /// 配置级 Agent Profiles 资源快照；由 AgentProfiles topic/显式读取更新。
  final AgentProfilesStateView? agentProfilesState;

  /// 按 root 会话作用域的费用状态；`cost == null` 是显式清除。
  final Map<String, SessionCostsStateView> sessionCostsByRoot;

  /// Local mutation lifecycle keyed by stable target identity. It is a
  /// presentation projection only; canonical settings remain in
  /// [settingsState].
  final Map<String, StudioMutationView> mutations;

  StudioMutationView? mutation(String key) => mutations[key];

  bool mutationPending(String key) => mutations[key]?.isPending ?? false;

  /// 每个已租用 topic 的局部传输连接状态（transport，不是业务 snapshot）。
  ///
  /// 由 data 层的单一 topic 接线写入：Baseline/Data 表示 connected，Lagged/Failure/
  /// closed 表示 reconnecting/failed，同时保留 canonical 领域数据。scope 释放后
  /// 由 data 层清理对应条目，避免无界墓碑。
  final Map<ProductTopic, ProductTopicConnectionStateView> topicConnections;

  ProductTopicConnectionStateView? topicConnection(ProductTopic topic) =>
      topicConnections[topic];

  List<StudioProject> get projects => projectDirectory.values;
  List<SessionDirectoryRow> get rows => threadDirectory.rows;
  Map<String, StudioAgentView> get agentsByThread => {
    for (final agent in agentDirectory.values) agent.threadId: agent,
  };
  List<ModelSelectionAccount> get accounts =>
      modelSelectionAccounts(accountsState, modelDirectoryState);
  String? get defaultAccountId => accountsState.accounts
      .where(
        (account) =>
            account.identity is NativeAccountIdentity && account.isDefault,
      )
      .firstOrNull
      ?.identity
      .accountId;
  List<ModeModelRouteView> get modeModelRoutes => settingsState.modeModelRoutes;
  List<AccountUsageObservation> get accountUsages =>
      accountUsageState.value?.values.toList(growable: false) ?? const [];
  SessionCostsStateView? get selectedSessionCostState {
    final sessionId = selectedRootRow?.sessionId;
    return sessionId == null ? null : sessionCostsByRoot[sessionId];
  }

  SessionCostView? get selectedSessionCost => selectedSessionCostState?.cost;
  List<RoleSettingsView> get roles => settingsState.roles;
  List<McpServerSettingsView> get mcpServers => settingsState.mcpServers;
  InstructionsSettingsView get instructions => settingsState.instructions;
  SkillsSettingsView get skills => settingsState.skills;
  GeneralSettingsView get general => settingsState.general;
  WebSearchSettingsView get webSearch => settingsState.webSearch;
  DeepSeekWebSearchSettingsView get deepSeekWebSearch =>
      settingsState.deepSeekWebSearch;
  List<StudioRecoveryIssue> get recoveryIssues => recoveryState.values;
  int get settingsRevision => settingsState.revision;

  ThreadWorkspace? get selectedWorkspace {
    final id = selectedThreadId;
    return id == null ? null : workspacesByThread[id];
  }

  WorkspaceUiState get selectedWorkspaceUi {
    final id = selectedThreadId;
    // 选中但从未打开过的会话没有 workspace UI 条目：按 `idle`（未打开）而不是
    // 默认的 `loading` 处理，避免首屏把“尚未打开”显示成永久加载中。
    return id == null
        ? const WorkspaceUiState()
        : workspaceUiByThread[id] ??
              const WorkspaceUiState(syncState: AgentWorkspaceSyncState.idle);
  }

  StudioTurnView? get turn => selectedWorkspace?.activeTurn;

  ThreadRuntimeView get runtime =>
      selectedWorkspace?.runtime ?? _emptySessionRuntime;
  ThreadModelRouteView? get modelRoute => selectedWorkspace?.modelRoute;

  ComposerThreadState get composer => selectedWorkspaceUi.composer;

  ComposerThreadState get newThreadComposer {
    final workspaceId = selectedProjectId;
    return workspaceId == null
        ? const ComposerThreadState.idle()
        : newThreadComposerByProject[workspaceId] ??
              const ComposerThreadState.idle();
  }

  ComposerTargetDiagnostic? composerDiagnostic(
    String? workspaceId,
    String? threadId,
  ) {
    if (workspaceId == null) return null;
    return composerDiagnosticsByTarget[attachmentTargetKey(
      workspaceId,
      threadId,
    )];
  }

  ThreadModeId get newThreadMode {
    final workspaceId = selectedProjectId;
    return workspaceId == null
        ? ThreadModeId.simple
        : newThreadModeByProject[workspaceId] ?? ThreadModeId.simple;
  }

  /// 当前项目的会话工作区模式草稿；默认 `local`。
  ThreadWorkspaceMode get newThreadWorkspaceMode {
    final workspaceId = selectedProjectId;
    return workspaceId == null
        ? ThreadWorkspaceMode.local
        : newThreadWorkspaceModeByProject[workspaceId] ??
              ThreadWorkspaceMode.local;
  }

  List<SessionDirectoryRow> get rootRows =>
      rows.where((row) => row.isRootRow).toList();

  SessionDirectoryRow? get selectedRow {
    final id = selectedThreadId;
    return id == null
        ? null
        : rows.where((row) => row.threadId == id).firstOrNull;
  }

  /// 选中会话的 root 行：归属只读目录行的 `sessionId`，不从 Thread 快照推导。
  SessionDirectoryRow? get selectedRootRow {
    final sessionId = AgentDirectoryQueries.sessionId(
      threadId: selectedThreadId,
      agents: agentDirectory.values,
      rows: rows,
    );
    if (sessionId == null) return null;
    return rows
        .where((row) => row.isRootRow && row.sessionId == sessionId)
        .firstOrNull;
  }

  /// 当前会话的目录行（root 在前，成员按 `parentAgentId` 父先序）。
  List<SessionDirectoryRow> get rowsForSelectedSession {
    final root = selectedRootRow;
    if (root == null) return const [];
    final scoped = rows
        .where((row) => row.sessionId == root.sessionId)
        .toList();
    final children = <String?, List<SessionDirectoryRow>>{};
    for (final row in scoped) {
      children.putIfAbsent(row.parentAgentId, () => []).add(row);
    }
    for (final siblings in children.values) {
      siblings.sort((left, right) {
        final created = left.effectiveCreatedAt.compareTo(
          right.effectiveCreatedAt,
        );
        return created != 0 ? created : left.threadId.compareTo(right.threadId);
      });
    }
    final ordered = <SessionDirectoryRow>[];
    final visited = <String>{};
    void append(SessionDirectoryRow row) {
      if (!visited.add(row.threadId)) return;
      ordered.add(row);
      for (final child
          in children[row.agentId] ?? const <SessionDirectoryRow>[]) {
        append(child);
      }
    }

    append(root);
    for (final row in scoped) {
      append(row);
    }
    return ordered;
  }

  TimelineTodoListUpdate? get selectedTodoList => selectedWorkspace?.todo;

  List<PendingInteraction> get pendingInteractions => [
    for (final workspace in workspacesByThread.values)
      ...workspace.interactions,
  ];

  PendingInteraction? get activeInteraction {
    final interactions = [...(selectedWorkspace?.interactions ?? const [])]
      ..sort(
        (left, right) =>
            interactionPriority(left.kind)
                .compareTo(interactionPriority(right.kind)),
      );
    return interactions.firstOrNull;
  }

  List<StudioAgentView> get selectedAgents {
    return AgentDirectoryQueries.forSession(
      sessionId: AgentDirectoryQueries.sessionId(
        threadId: selectedThreadId,
        agents: agentDirectory.values,
        rows: rows,
      ),
      agents: agentDirectory.values,
    );
  }

  AgentWorkspaceView? get selectedAgentWorkspace {
    final row = selectedRow;
    final root = selectedRootRow;
    if (row == null || root == null) return null;
    return AgentWorkspaceView(
      row: row,
      rootRow: root,
      syncState: selectedWorkspaceUi.syncState,
      loadError: selectedWorkspaceUi.loadError,
      todo: selectedTodoList,
      runtime: runtime,
      modelRoute: modelRoute,
      turn: turn,
      lastTurn: selectedWorkspace?.lastTurn,
      activeInteraction: activeInteraction,
      composer: composer,
      composerMode: row.isChildRow
          ? AgentComposerMode.runtimeDriven
          : AgentComposerMode.editable,
      accounts: accounts,
      modeModelRoutes: modeModelRoutes,
      roles: roles,
      agents: selectedAgents,
    );
  }

  List<StudioRecoveryIssue> get applicationRecoveryIssues => recoveryIssues
      .where((issue) => issue.scope == RecoveryIssueScope.application)
      .toList();

  RoleSettingsView? role(String key) =>
      roles.where((role) => role.key == key).firstOrNull;

  bool get isBusy => turn?.state.isBusy ?? false;

  StudioState copyWith({
    Map<String, ThreadWorkspace>? workspacesByThread,
    Map<String, WorkspaceUiState>? workspaceUiByThread,
    Set<String>? openedThreadIds,
    Map<String, ComposerThreadState>? newThreadComposerByProject,
    Map<String, ComposerTargetDiagnostic>? composerDiagnosticsByTarget,
    Map<String, ThreadModeId>? newThreadModeByProject,
    Map<String, ThreadWorkspaceMode>? newThreadWorkspaceModeByProject,
    Object? selectedProjectId = _studioStateUnset,
    Object? selectedThreadId = _studioStateUnset,
    ProjectDirectoryState? projectDirectory,
    ThreadDirectoryFrame? threadDirectory,
    AgentDirectoryState? agentDirectory,
    SettingsStateSnapshot? settingsState,
    AccountsState? accountsState,
    ModelDirectoryState? modelDirectoryState,
    RecoveryStateSnapshot? recoveryState,
    McpStateSnapshot? mcpState,
    LspStateSnapshot? lspState,
    Map<String, SkillsStateSnapshot>? skillsByProject,
    ThreadModeCatalogView? threadModeCatalog,
    AccountResource<Map<NativeAccountIdentity, AccountUsageObservation>>?
    accountUsageState,
    UpdaterStateSnapshot? updaterState,
    PersistenceStateSnapshot? persistenceState,
    Object? persistenceQueueState = _studioStateUnset,
    Object? agentProfilesState = _studioStateUnset,
    Map<String, SessionCostsStateView>? sessionCostsByRoot,
    Map<String, StudioMutationView>? mutations,
    Map<ProductTopic, ProductTopicConnectionStateView>? topicConnections,
  }) {
    return StudioState(
      workspacesByThread: workspacesByThread ?? this.workspacesByThread,
      workspaceUiByThread: workspaceUiByThread ?? this.workspaceUiByThread,
      openedThreadIds: openedThreadIds ?? this.openedThreadIds,
      newThreadComposerByProject:
          newThreadComposerByProject ?? this.newThreadComposerByProject,
      composerDiagnosticsByTarget:
          composerDiagnosticsByTarget ?? this.composerDiagnosticsByTarget,
      newThreadModeByProject:
          newThreadModeByProject ?? this.newThreadModeByProject,
      newThreadWorkspaceModeByProject:
          newThreadWorkspaceModeByProject ??
          this.newThreadWorkspaceModeByProject,
      selectedProjectId: identical(selectedProjectId, _studioStateUnset)
          ? this.selectedProjectId
          : selectedProjectId as String?,
      selectedThreadId: identical(selectedThreadId, _studioStateUnset)
          ? this.selectedThreadId
          : selectedThreadId as String?,
      projectDirectory: projectDirectory ?? this.projectDirectory,
      threadDirectory: threadDirectory ?? this.threadDirectory,
      agentDirectory: agentDirectory ?? this.agentDirectory,
      settingsState: settingsState ?? this.settingsState,
      accountsState: accountsState ?? this.accountsState,
      modelDirectoryState: modelDirectoryState ?? this.modelDirectoryState,
      recoveryState: recoveryState ?? this.recoveryState,
      mcpState: mcpState ?? this.mcpState,
      lspState: lspState ?? this.lspState,
      skillsByProject: skillsByProject ?? this.skillsByProject,
      threadModeCatalog: threadModeCatalog ?? this.threadModeCatalog,
      accountUsageState: accountUsageState ?? this.accountUsageState,
      updaterState: updaterState ?? this.updaterState,
      persistenceState: persistenceState ?? this.persistenceState,
      persistenceQueueState: identical(persistenceQueueState, _studioStateUnset)
          ? this.persistenceQueueState
          : persistenceQueueState as PersistenceQueueStateView?,
      agentProfilesState: identical(agentProfilesState, _studioStateUnset)
          ? this.agentProfilesState
          : agentProfilesState as AgentProfilesStateView?,
      sessionCostsByRoot: sessionCostsByRoot ?? this.sessionCostsByRoot,
      mutations: mutations ?? this.mutations,
      topicConnections: topicConnections ?? this.topicConnections,
    );
  }
}
