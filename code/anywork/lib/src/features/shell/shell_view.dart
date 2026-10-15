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
import '../../presentation/providers/thread_directory_store.dart';

import '../../presentation/providers/thread_session_store.dart';
import '../../presentation/providers/bootstrap_store.dart';

part 'shell_view.g.dart';

/// 视图层空 runtime。领域里的空值是 [StudioState] 私有常量，这里保持同形。
const shellEmptyRuntime = ThreadRuntimeView(
  model: '',
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
  final directory = ref.watch(threadDirectoryStoreProvider);
  final threads = directory.window.threads;
  final recovery =
      ref.watch(recoveryStoreProvider).value?.values ??
      const <StudioRecoveryIssue>[];
  final modes =
      ref.watch(modeCatalogStoreProvider).value?.modes ??
      const <ThreadModeDescriptorView>[];
  final selected = threadById(threads, selection.selectedThreadId);
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
  return SidebarView(
    projects: projects,
    rootThreads: [
      for (final thread in threads)
        if (thread.isRoot) thread,
    ],
    selectedProjectId: selection.selectedProjectId,
    selectedRootThreadId: selected == null
        ? null
        : rootThread(threads, selected)?.id,
    isBusy: busy,
    projectRecoveryIssues: {
      for (final issue in recovery)
        if (issue.scope == RecoveryIssueScope.project &&
            issue.projectId != null)
          issue.projectId!: issue,
    },
    threadRecoveryIssues: {
      for (final issue in recovery)
        if (issue.scope == RecoveryIssueScope.thread && issue.threadId != null)
          issue.threadId!: issue,
    },
    modeDisplayNames: {for (final mode in modes) mode.id: mode.displayName},
    directoryHasMore: directory.window.hasMore,
    directoryIsLoading: directory.window.isLoading,
  );
}

@riverpod
HeaderView headerView(Ref ref) {
  final selection = ref.watch(selectionStoreProvider);
  final threads = ref.watch(threadDirectoryStoreProvider).window.threads;
  final projects = ref.watch(projectStoreProvider);
  final selected = threadById(threads, selection.selectedThreadId);
  final root = selected == null ? null : rootThread(threads, selected);
  final projectId = root?.projectId ?? selection.selectedProjectId;
  final workspaceThreads = root == null
      ? const <StudioThread>[]
      : threadsForRoot(threads, root);
  var runtime = shellEmptyRuntime;
  var pending = const <PendingInteraction>[];
  final selectedId = selection.selectedThreadId;
  if (selectedId != null && !selection.needsOpen) {
    final session = ref.watch(threadSessionStoreProvider(selectedId));
    runtime = session.runtime ?? shellEmptyRuntime;
    pending = session.interactions;
  }
  final rootId = root?.id;
  return HeaderView(
    selectedRootThread: root,
    selectedProject: projectById(
      projects.projects?.values ?? const [],
      projectId,
    ),
    selectedProjectId: selection.selectedProjectId,
    workspaceThreads: workspaceThreads,
    agents: agentsForThreads(
      workspaceThreads,
      projects.agents?.values ?? const [],
    ),
    selectedThreadId: selection.selectedThreadId,
    runtime: runtime,
    sessionCost: rootId == null
        ? null
        : ref.watch(shellSessionCostProvider(rootId)),
    pendingInteractions: pending,
  );
}

/// 打开后首窗请求。相等性只含 threadId，同一未完成请求不会重复通知。
class ShellHistoryOpenRequest {
  const ShellHistoryOpenRequest(this.threadId);

  final String threadId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShellHistoryOpenRequest && threadId == other.threadId;

  @override
  int get hashCode => threadId.hashCode;
}

/// `needsOpen` 时不订阅会话。已有历史窗口后不再请求首窗。
@riverpod
ShellHistoryOpenRequest? shellHistoryOpenRequest(Ref ref) {
  final selection = ref.watch(selectionStoreProvider);
  final threadId = selection.selectedThreadId;
  if (threadId == null || selection.needsOpen) return null;
  final session = ref.watch(threadSessionStoreProvider(threadId));
  if (!session.hasSnapshot || sessionHasTimelineWindow(session)) return null;
  return ShellHistoryOpenRequest(threadId);
}

/// 当前选中会话的输入区事实。草稿仍由 interaction 域覆盖；这里只提供 canonical 会话。
///
/// 不在这里持有 shell 租约：pane/预览也会观察它，不能因此拉起真实 Bridge。
@riverpod
AgentWorkspaceView? shellComposerWorkspace(Ref ref) {
  final selection = ref.watch(selectionStoreProvider);
  final threadId = selection.selectedThreadId;
  if (threadId == null) return null;
  final directory = ref.watch(threadDirectoryStoreProvider);
  final threads = directory.window.threads;
  final thread = threadById([
    ...threads,
    ...directory.overlayThreads,
  ], threadId);
  ThreadSessionState? session;
  if (!selection.needsOpen) {
    session = ref.watch(threadSessionStoreProvider(threadId));
  }
  if (thread == null) return null;
  final root = rootThread(threads, thread) ?? thread;
  final settings = ref.watch(settingsStoreProvider);
  final canonical = settings.canonical;
  final workspaceThreads = threadsForRoot(threads, root);
  final agents = ref.watch(projectStoreProvider).agents?.values ?? const [];
  return AgentWorkspaceView(
    thread: thread,
    rootThread: root,
    syncState: session == null
        ? AgentWorkspaceSyncState.idle
        : sessionSyncState(session),
    loadError: session?.sync.phase == DomainSyncPhase.failed
        ? session?.sync.errorMessage
        : null,
    timelineRows: const [],
    todo: session?.workspace?.todo,
    runtime: session?.runtime ?? shellEmptyRuntime,
    turn: session?.activeTurn,
    lastTurn: session?.workspace?.lastTurn,
    activeInteraction: primaryInteraction(session?.interactions ?? const []),
    composer: const ComposerThreadState.idle(),
    composerMode: thread.isAgent
        ? AgentComposerMode.runtimeDriven
        : AgentComposerMode.editable,
    providers: providersWithCatalogMetadata(
      canonical?.providers ?? const <ProviderSettingsView>[],
      settings.providerCatalog,
    ),
    modeModelRoutes: canonical?.modeModelRoutes ?? const [],
    roles: canonical?.roles ?? const [],
    agents: agentsForThreads(workspaceThreads, agents),
  );
}

/// 活动条的 canonical 输入。展开详情是 host 的 ephemeral 状态，不进 store。
class ConversationActivityInput {
  const ConversationActivityInput({
    required this.activity,
    required this.storage,
    required this.interaction,
  });

  final ThreadActivityView? activity;
  final ThreadStorageStateView? storage;
  final PendingInteraction? interaction;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationActivityInput &&
          activity == other.activity &&
          storage == other.storage &&
          interaction == other.interaction;

  @override
  int get hashCode => Object.hash(activity, storage, interaction);
}

@riverpod
ConversationActivityInput? conversationActivityInput(Ref ref, String threadId) {
  final selection = ref.watch(selectionStoreProvider);
  if (selection.needsOpen || selection.selectedThreadId != threadId) {
    return null;
  }
  final session = ref.watch(threadSessionStoreProvider(threadId));
  if (session.workspace == null && !session.hasSnapshot) return null;
  return ConversationActivityInput(
    activity: session.activity,
    storage: session.storage,
    interaction: primaryInteraction(session.interactions),
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
      final directory = ref.watch(threadDirectoryStoreProvider);
      final title =
          threadById([
            ...directory.window.threads,
            ...directory.overlayThreads,
          ], selectedId)?.title.trim() ??
          '';
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

/// 与 `timelineSessionWindowProvider` 共用的「已有时间线窗口」判定；正文镜像只在
/// 内容绑定交付首帧后出现，历史库 identity 不再参与（SQL 分页旁路已删除）。
bool sessionHasTimelineWindow(ThreadSessionState session) {
  return session.hasChatWindow || session.items.isNotEmpty;
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

PendingInteraction? primaryInteraction(List<PendingInteraction> interactions) {
  if (interactions.isEmpty) return null;
  final ordered = [...interactions]
    ..sort(
      (left, right) =>
          interactionPriority(left.kind)
              .compareTo(interactionPriority(right.kind)),
    );
  return ordered.first;
}

StudioThread? threadById(List<StudioThread> threads, String? id) {
  if (id == null) return null;
  for (final thread in threads) {
    if (thread.id == id) return thread;
  }
  return null;
}

StudioThread? rootThread(List<StudioThread> threads, StudioThread selected) {
  final rootId = selected.effectiveRootThreadId;
  for (final thread in threads) {
    if (thread.id == rootId && thread.isRoot) return thread;
  }
  return selected.isRoot ? selected : null;
}

StudioProject? projectById(List<StudioProject> projects, String? id) {
  if (id == null) return null;
  for (final project in projects) {
    if (project.id == id) return project;
  }
  return null;
}

List<StudioThread> threadsForRoot(
  List<StudioThread> threads,
  StudioThread root,
) {
  final scoped = [
    for (final thread in threads)
      if (thread.effectiveRootThreadId == root.id) thread,
  ];
  final children = <String?, List<StudioThread>>{};
  for (final thread in scoped) {
    children.putIfAbsent(thread.parentThreadId, () => []).add(thread);
  }
  for (final siblings in children.values) {
    siblings.sort((left, right) {
      final created = left.effectiveCreatedAt.compareTo(
        right.effectiveCreatedAt,
      );
      return created != 0 ? created : left.id.compareTo(right.id);
    });
  }
  final ordered = <StudioThread>[];
  final visited = <String>{};
  void append(StudioThread thread) {
    if (!visited.add(thread.id)) return;
    ordered.add(thread);
    for (final child in children[thread.id] ?? const <StudioThread>[]) {
      append(child);
    }
  }

  append(root);
  for (final thread in scoped) {
    append(thread);
  }
  return ordered;
}

List<StudioAgentView> agentsForThreads(
  List<StudioThread> threads,
  List<StudioAgentView> agents,
) {
  final byThread = {for (final agent in agents) agent.threadId: agent};
  return [
    for (final thread in threads)
      byThread[thread.id] ??
          StudioAgentView(
            id: thread.id,
            threadId: thread.id,
            path: thread.agentPath.isEmpty ? thread.id : thread.agentPath,
            parentPath: thread.parentThreadId,
            role: thread.role,
            task: thread.title,
            state: const IdleStudioAgent(),
            summary: null,
            depth: thread.isRoot ? 0 : 1,
            updatedAt: thread.updatedAt,
          ),
  ];
}
