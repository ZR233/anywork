import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:anywork_client/studio_client.dart';

import '../../domain/models/studio_models.dart';

import '../../presentation/providers/mode_catalog_store.dart';
import '../../presentation/providers/persistence_store.dart';
import '../../presentation/providers/project_store.dart';
import '../../presentation/providers/recovery_store.dart';
import '../../presentation/providers/selection_store.dart';
import '../../presentation/providers/session_costs_store.dart';
import '../../presentation/providers/settings_store.dart';
import '../../presentation/providers/account_domains.dart';
import '../../presentation/providers/thread_directory_store.dart';

import '../../presentation/providers/thread_session_store.dart';
import '../../presentation/providers/bootstrap_store.dart';
import '../conversation/interactions/state/interaction_payload.dart';

part 'shell_view.g.dart';

/// 视图层空 runtime。领域里的空值是 [StudioState] 私有常量，这里保持同形。
const shellEmptyRuntime = ThreadRuntimeView(
  modelId: '',
  contextTokens: 0,
  contextWindow: 0,
  totalTokens: 0,
  costLabel: '',
  activeSkills: [],
  activeMcpServers: [],
  activeLspServers: [],
);

@riverpod
SessionCostView? shellSessionCost(Ref ref, String rootThreadId) {
  return ref.watch(sessionCostsStoreProvider(rootThreadId)).value?.cost;
}

/// 启动结果来自 Client；目录传输失败保留已有界面，选择没有 canonical 水位。
class ShellStartupView {
  const ShellStartupView({
    required this.ready,
    this.error,
    this.directoryError,
  });

  final bool ready;
  final Object? error;
  final String? directoryError;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShellStartupView &&
          ready == other.ready &&
          error == other.error &&
          directoryError == other.directoryError;

  @override
  int get hashCode => Object.hash(ready, error, directoryError);
}

@riverpod
ShellStartupView shellStartupView(Ref ref) {
  final bootstrap = ref.watch(clientBootstrapProvider);
  final projects = ref.watch(projectStoreProvider);
  final settings = ref.watch(settingsStoreProvider);
  final modes = ref.watch(modeCatalogStoreProvider);
  final failed = projects.projectSync.phase == DomainSyncPhase.failed;
  final ready =
      bootstrap.phase == StudioBootstrapPhase.ready &&
      projects.projectsLoaded &&
      settings.loaded &&
      modes.loaded;
  return ShellStartupView(
    ready: ready,
    error:
        bootstrap.failure ??
        (!projects.projectsLoaded && failed
            ? projects.projectSync.errorMessage ??
                  'project directory unavailable'
            : null),
    directoryError: projects.projectsLoaded && failed
        ? projects.projectSync.errorMessage ?? 'project directory unavailable'
        : null,
  );
}

/// 已订阅的选择事实。Widget 用它替代一次性读取。
@riverpod
SelectionStoreState shellSelection(Ref ref) {
  return ref.watch(selectionStoreProvider);
}

@riverpod
GeneralSettingsView shellGeneral(Ref ref) {
  return ref.watch(settingsStoreProvider).canonical?.general ??
      const GeneralSettingsView();
}

@riverpod
ShellChromeView shellChromeView(Ref ref) {
  final issues =
      ref.watch(recoveryStoreProvider).value?.values ??
      const <StudioRecoveryIssue>[];
  return ShellChromeView(
    applicationRecoveryIssues: [
      for (final issue in issues)
        if (issue.scope == RecoveryIssueScope.application) issue,
    ],
    persistenceState:
        ref.watch(persistenceStoreProvider).persistence ??
        const PersistenceStateSnapshot.ready(),
  );
}

@riverpod
SidebarView sidebarView(Ref ref) {
  final selection = ref.watch(selectionStoreProvider);
  final projects =
      ref.watch(projectStoreProvider).projects?.values ??
      const <StudioProject>[];
  final recovery =
      ref.watch(recoveryStoreProvider).value?.values ??
      const <StudioRecoveryIssue>[];
  final modes =
      ref.watch(modeCatalogStoreProvider).value?.modes ??
      const <ThreadModeDescriptorView>[];
  var busy = false;
  final selectedId = selection.selectedThreadId;
  if (selectedId != null && !selection.needsOpen) {
    busy =
        ref
            .watch(threadSessionStoreProvider(selectedId))
            .activeTurn
            ?.state
            .isBusy ??
        false;
  }
  return SidebarView.fromProjects(
    projects: projects,
    selectedProjectId: selection.selectedProjectId,
    isBusy: busy,
    recoveryIssues: recovery,
    modeDisplayNames: {for (final mode in modes) mode.id: mode.displayName},
  );
}

@riverpod
HeaderView headerView(Ref ref) {
  final selection = ref.watch(selectionStoreProvider);
  final projects = ref.watch(projectStoreProvider);
  final agents = projects.agents?.values ?? const <StudioAgentView>[];
  final selectedId = selection.selectedThreadId;
  final selected = selectedId == null
      ? null
      : ref.watch(threadMetadataStoreProvider(selectedId)).frame?.row;
  final sessionId = selected?.sessionId;
  final rootAgent = sessionId == null
      ? null
      : agents
            .where(
              (agent) =>
                  agent.sessionId == sessionId && agent.parentAgentId == null,
            )
            .firstOrNull;
  final root = selected == null
      ? null
      : selected.isRootRow
      ? selected
      : rootAgent == null
      ? null
      : ref.watch(threadMetadataStoreProvider(rootAgent.threadId)).frame?.row;
  final workspaceId = root?.workspaceId ?? selection.selectedProjectId;
  final workspaceAgents = AgentDirectoryQueries.forSession(
    sessionId: root?.sessionId,
    agents: agents,
  );
  final workspaceRows = [
    if (root != null && root.isRootRow) root,
    for (final agent in workspaceAgents)
      if (agent.threadId != root?.threadId)
        ?ref.watch(threadMetadataStoreProvider(agent.threadId)).frame?.row,
  ];
  var runtime = shellEmptyRuntime;
  var pending = const <PendingInteraction>[];
  if (selectedId != null && !selection.needsOpen) {
    final session = ref.watch(threadSessionStoreProvider(selectedId));
    runtime = session.runtime ?? shellEmptyRuntime;
    pending = session.interactions;
  }
  return HeaderView(
    selectedRootRow: root != null && root.isRootRow ? root : null,
    selectedProject: projectById(
      projects.projects?.values ?? const [],
      workspaceId,
    ),
    selectedProjectId: selection.selectedProjectId,
    workspaceRows: workspaceRows,
    agents: workspaceAgents,
    selectedThreadId: selection.selectedThreadId,
    runtime: runtime,
    sessionCost: sessionId == null
        ? null
        : ref.watch(shellSessionCostProvider(sessionId)),
    pendingInteractions: pending,
  );
}

/// 目的地会话的输入区事实。草稿仍由 interaction 域覆盖；这里只提供 canonical 会话。
///
/// 不在这里持有 shell 租约：pane/预览也会观察它，不能因此拉起真实 Bridge。
@riverpod
AgentWorkspaceView? conversationWorkspace(
  Ref ref,
  String threadId, {
  bool needsOpen = false,
}) {
  ThreadSessionState? session;
  if (!needsOpen) {
    session = ref.watch(threadSessionStoreProvider(threadId));
  }
  final row = ref.watch(threadMetadataStoreProvider(threadId)).frame?.row;
  if (row == null) return null;
  final agents =
      ref.watch(projectStoreProvider).agents?.values ??
      const <StudioAgentView>[];
  final sessionId = row.sessionId;
  final rootAgent = row.isRootRow
      ? null
      : agents
            .where(
              (agent) =>
                  agent.sessionId == sessionId && agent.parentAgentId == null,
            )
            .firstOrNull;
  final root = row.isRootRow
      ? row
      : rootAgent == null
      ? null
      : ref.watch(threadMetadataStoreProvider(rootAgent.threadId)).frame?.row;
  if (root == null) return null;
  if (row.backend is! NativeAgentBackendView ||
      root.backend is! NativeAgentBackendView) {
    throw StateError(
      'Native workspace projection cannot consume an ACP session',
    );
  }
  final settings = ref.watch(settingsStoreProvider);
  final canonical = settings.canonical;
  return AgentWorkspaceView(
    row: row,
    rootRow: root,
    syncState: session == null
        ? AgentWorkspaceSyncState.idle
        : sessionSyncState(session),
    loadError: session?.sync.phase == DomainSyncPhase.failed
        ? session?.sync.errorMessage
        : null,
    todo: session?.workspace?.todo,
    runtime: session?.runtime ?? shellEmptyRuntime,
    modelRoute: session?.modelRoute,
    turn: session?.activeTurn,
    lastTurn: session?.workspace?.lastTurn,
    activeInteraction: activePendingInteraction(
      session?.interactions ?? const [],
    ),
    composer: const ComposerThreadState.idle(),
    composerMode: row.isChildRow
        ? AgentComposerMode.runtimeDriven
        : AgentComposerMode.editable,
    accounts: ref.watch(modelSelectionAccountsProvider),
    modeModelRoutes: canonical?.modeModelRoutes ?? const [],
    roles: canonical?.roles ?? const [],
    agents: AgentDirectoryQueries.forSession(
      sessionId: sessionId,
      agents: agents,
    ),
  );
}

/// 持久化面板视图。只含当前被观察会话的 storage；其他会话的 storage 不在全局 map。
class PersistencePanelView {
  const PersistencePanelView({
    required this.snapshot,
    required this.queue,
    required this.connection,
    required this.selectedStorage,
    required this.pressurePaused,
  });

  final PersistenceStateSnapshot snapshot;
  final PersistenceQueueStateView? queue;
  final ProductTopicConnectionStateView? connection;
  final ShellStorageFact? selectedStorage;
  final bool pressurePaused;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistencePanelView &&
          snapshot == other.snapshot &&
          queue == other.queue &&
          connection == other.connection &&
          selectedStorage == other.selectedStorage &&
          pressurePaused == other.pressurePaused;

  @override
  int get hashCode =>
      Object.hash(snapshot, queue, connection, selectedStorage, pressurePaused);
}

class ShellStorageFact {
  const ShellStorageFact({
    required this.threadId,
    required this.label,
    required this.storage,
    required this.isSelected,
  });

  final String threadId;
  final String label;
  final ThreadStorageStateView storage;
  final bool isSelected;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShellStorageFact &&
          threadId == other.threadId &&
          label == other.label &&
          storage == other.storage &&
          isSelected == other.isSelected;

  @override
  int get hashCode => Object.hash(threadId, label, storage, isSelected);
}

@riverpod
PersistencePanelView persistencePanelView(Ref ref) {
  final persistence = ref.watch(persistenceStoreProvider);
  final selection = ref.watch(selectionStoreProvider);
  ShellStorageFact? selectedStorage;
  final selectedId = selection.selectedThreadId;
  if (selectedId != null && !selection.needsOpen) {
    final session = ref.watch(threadSessionStoreProvider(selectedId));
    final storage = session.storage;
    if (storage != null) {
      final metadata = ref.watch(threadMetadataStoreProvider(selectedId));
      final title = metadata.frame?.row?.title.trim() ?? '';
      selectedStorage = ShellStorageFact(
        threadId: selectedId,
        label: title.isEmpty ? selectedId : title,
        storage: storage,
        isSelected: true,
      );
    }
  }
  final queue = persistence.queue;
  return PersistencePanelView(
    snapshot: persistence.persistence ?? const PersistenceStateSnapshot.ready(),
    queue: queue,
    connection: connectionFromSync(persistence.queueSync),
    selectedStorage: selectedStorage,
    pressurePaused:
        queue?.queue.pressurePaused == true ||
        selectedStorage?.storage.pressurePaused == true,
  );
}

void retryShellPersistenceQueue(AnyworkClient client) {
  client.retryResource(const PersistenceQueueTopic());
}

AgentWorkspaceSyncState sessionSyncState(ThreadSessionState session) {
  return switch (session.sync.phase) {
    DomainSyncPhase.idle =>
      session.hasSnapshot
          ? AgentWorkspaceSyncState.ready
          : AgentWorkspaceSyncState.loading,
    DomainSyncPhase.connecting => AgentWorkspaceSyncState.loading,
    DomainSyncPhase.ready => AgentWorkspaceSyncState.ready,
    DomainSyncPhase.reconnecting =>
      session.hasSnapshot
          ? AgentWorkspaceSyncState.reconnecting
          : AgentWorkspaceSyncState.loading,
    DomainSyncPhase.failed =>
      session.hasSnapshot
          ? AgentWorkspaceSyncState.stale
          : AgentWorkspaceSyncState.failed,
  };
}

ProductTopicConnectionStateView? connectionFromSync(DomainSyncStatus sync) {
  if (sync.phase == DomainSyncPhase.idle) return null;
  return ProductTopicConnectionStateView(
    phase: switch (sync.phase) {
      DomainSyncPhase.connecting => ProductTopicConnectionPhase.connecting,
      DomainSyncPhase.ready => ProductTopicConnectionPhase.connected,
      DomainSyncPhase.reconnecting => ProductTopicConnectionPhase.reconnecting,
      DomainSyncPhase.failed => ProductTopicConnectionPhase.failed,
      DomainSyncPhase.idle => ProductTopicConnectionPhase.connecting,
    },
    errorMessage: sync.errorMessage,
    retryExhausted: sync.retryExhausted,
  );
}

StudioThread? threadById(List<StudioThread> threads, String? id) {
  if (id == null) return null;
  for (final thread in threads) {
    if (thread.id == id) return thread;
  }
  return null;
}

StudioProject? projectById(List<StudioProject> projects, String? id) {
  if (id == null) return null;
  for (final project in projects) {
    if (project.id == id) return project;
  }
  return null;
}
