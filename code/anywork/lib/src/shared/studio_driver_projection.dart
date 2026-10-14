import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bridge/studio_bridge.dart';
import '../data/stores/domain_sync.dart';
import '../data/stores/lsp_store.dart';
import '../data/stores/mcp_store.dart';
import '../data/stores/mode_catalog_store.dart';
import '../data/stores/model_performance_store.dart';
import '../data/stores/persistence_store.dart';
import '../data/stores/project_store.dart';
import '../data/stores/provider_usage_store.dart';
import '../data/stores/recovery_store.dart';
import '../data/stores/selection_store.dart';
import '../data/stores/session_costs_store.dart';
import '../data/stores/settings_store.dart';
import '../data/stores/skills_store.dart';
import '../data/stores/thread_directory_store.dart';
import '../data/stores/thread_session_store.dart';
import '../data/stores/thread_session_state.dart';
import '../data/stores/updater_store.dart';
import '../domain/models/studio_models.dart';
import '../features/interaction/attachment_drafts.dart';
import '../features/interaction/composer_draft_controller.dart';
import '../features/interaction/start_session_controller.dart';
import '../features/shell/shell_view.dart';
import 'studio_driver_state.dart';

/// 把 Driver 容器接到验收快照。只在 Driver 入口调用。
void bindStudioDriver(ProviderContainer container) {
  StudioDriverState.bindSnapshotRefresh(
    () => projectStudioDriverState(container),
  );
}

/// 从各 store 与已经存在的草稿投影验收快照。
///
/// 不创建会话流，不 read 尚未存在的 family provider，也不调用 `beginSubmission()`。
void projectStudioDriverState(ProviderContainer container) {
  final selection = container.read(selectionStoreProvider);
  final directory = container.read(threadDirectoryStoreProvider);
  final threads = directory.window.threads;
  final settings = container.read(settingsStoreProvider);
  final canonical = settings.canonical;
  final providers = providersWithCatalogMetadata(
    canonical?.providers ?? const <ProviderSettingsView>[],
    settings.providerCatalog,
  );
  final projects =
      container.read(projectStoreProvider).projects?.values ??
      const <StudioProject>[];
  final project = projectById(projects, selection.selectedProjectId);
  final session = _existingSession(container, selection);
  final rootThreads = [
    for (final thread in threads)
      if (thread.isRoot) thread,
  ];
  final selectedThreadId = selection.selectedThreadId;
  final directoryThread = threadById(threads, selectedThreadId);
  final thread = session?.workspace?.thread ?? directoryThread;
  final root = thread == null ? null : rootThread(threads, thread) ?? thread;
  final threadComposer = _existingThreadComposer(container, selectedThreadId);
  final newThreadComposer = _newThreadComposer(container, selection);
  final sessionDraft = _existingStartSession(container);
  final projectDraft = sessionDraft?.forProject(selection.selectedProjectId);
  AgentWorkspaceView? workspace;
  if (thread != null && root != null) {
    final agents =
        container.read(projectStoreProvider).agents?.values ??
        const <StudioAgentView>[];
    workspace = AgentWorkspaceView(
      thread: thread,
      rootThread: root,
      syncState: session == null
          ? AgentWorkspaceSyncState.idle
          : sessionSyncState(session),
      loadError: session?.sync.phase == DomainSyncPhase.failed
          ? session?.sync.errorMessage
          : null,
      timelineRows: session == null
          ? const []
          : timelineRowsFromThreadItems(session.items),
      todo: session?.workspace?.todo,
      runtime: session?.runtime ?? shellEmptyRuntime,
      turn: session?.activeTurn,
      lastTurn: session?.workspace?.lastTurn,
      activeInteraction: primaryInteraction(session?.interactions ?? const []),
      composer: threadComposer,
      composerMode: thread.isAgent
          ? AgentComposerMode.runtimeDriven
          : AgentComposerMode.editable,
      permissionMode:
          canonical?.permissionMode ?? PermissionMode.requestApproval,
      providers: providers,
      modeModelRoutes: canonical?.modeModelRoutes ?? const [],
      roles: canonical?.roles ?? const [],
      agents: agentsForThreads(threadsForRoot(threads, root), agents),
    );
  }

  StudioDriverState.replaceCanonicalFacts(
    timelineWorkspace: session?.workspace,
    history: session?.history ?? const ThreadHistoryWindow(),
    workspacesByThread: {
      for (final existing in _existingSessions(container))
        existing.threadId: ?existing.workspace,
    },
    rootThreads: rootThreads,
    directoryHasMore: directory.hasMore,
    selectedProjectId: selection.selectedProjectId,
    selectedThreadId: selectedThreadId,
    newThreadMode: projectDraft?.mode ?? ThreadModeId.simple,
    newThreadWorkspaceMode:
        projectDraft?.workspaceMode ?? ThreadWorkspaceMode.local,
    newThreadComposer: newThreadComposer,
    threadComposer: threadComposer,
    settingsRevision: settings.settingsRevision,
    modelCatalogRevision: settings.modelCatalogRevision,
    modeModelRoutes: canonical?.modeModelRoutes ?? const [],
    roles: canonical?.roles ?? const [],
    providers: providers,
    commands: settings.commands.values.toList(growable: false),
    settingsReady: canonical?.state.value != null,
    persistence:
        container.read(persistenceStoreProvider).persistence ??
        const PersistenceStateSnapshot.ready(),
    recoveryIssues:
        container.read(recoveryStoreProvider).value?.values ?? const [],
    project: project,
    workspace: workspace,
  );
}

/// Driver topic 诊断。Bridge 不存在时不创建；family store 只枚举已经存在的实例。
Map<String, Object?> studioDriverTopicDiagnostics(ProviderContainer container) {
  if (!container.exists(studioBridgeProvider)) {
    return const <String, Object?>{
      'availability': 'unavailable',
      'registryAvailability': 'unavailable',
      'leaseRefs': null,
      'connections': null,
      'projectionRevisions': null,
    };
  }
  Map<String, int>? leaseRefs;
  try {
    leaseRefs = container.read(studioBridgeProvider).activeTopicRefCountViews();
  } on Object {
    leaseRefs = null;
  }
  final registryAvailable = leaseRefs != null;
  return <String, Object?>{
    'availability': registryAvailable ? 'available' : 'unavailable',
    'registryAvailability': registryAvailable ? 'available' : 'unavailable',
    'leaseRefs': registryAvailable ? _aggregateLeaseRefs(leaseRefs) : null,
    'connections': registryAvailable ? _connectionCounts(container) : null,
    'projectionRevisions': registryAvailable
        ? _projectionRevisions(container)
        : null,
  };
}

ThreadSessionState? _existingSession(
  ProviderContainer container,
  SelectionStoreState selection,
) {
  final threadId = selection.selectedThreadId;
  if (threadId == null || selection.needsOpen) return null;
  final provider = threadSessionStoreProvider(threadId);
  if (!container.exists(provider)) return null;
  return container.read(provider);
}

ComposerThreadState _existingThreadComposer(
  ProviderContainer container,
  String? threadId,
) {
  if (threadId == null) return const ComposerThreadState.idle();
  final provider = composerDraftControllerProvider(threadId);
  if (!container.exists(provider)) return const ComposerThreadState.idle();
  return container.read(provider);
}

StartSessionDraft? _existingStartSession(ProviderContainer container) {
  if (!container.exists(startSessionControllerProvider)) return null;
  return container.read(startSessionControllerProvider);
}

ComposerThreadState _newThreadComposer(
  ProviderContainer container,
  SelectionStoreState selection,
) {
  final projectId = selection.selectedProjectId;
  final session = _existingStartSession(container);
  final text = session?.forProject(projectId).text ?? '';
  final attachments =
      projectId != null && container.exists(attachmentDraftsProvider)
      ? container.read(attachmentDraftsProvider).newThread(projectId)
      : const ComposerThreadState.idle();
  final submitting =
      session?.submitting == true || attachments.isSubmissionPending;
  if (!submitting && attachments is FailedComposerThreadState) {
    return FailedComposerThreadState(
      error: attachments.error,
      draft: text,
      attachments: attachments.attachments,
      submissionRevision: attachments.submissionRevision,
      attachmentGeneration: attachments.attachmentGeneration,
      inputId: attachments.inputId,
      cleanupFailureDraftIds: attachments.cleanupFailureDraftIds,
    );
  }
  if (submitting) {
    return SubmittingComposerThreadState(
      draft: text,
      attachments: attachments.attachments,
      submissionRevision: attachments.submissionRevision,
      attachmentGeneration: attachments.attachmentGeneration,
      inputId: attachments is SubmittingComposerThreadState
          ? attachments.inputId
          : '',
      cleanupFailureDraftIds: attachments.cleanupFailureDraftIds,
    );
  }
  return IdleComposerThreadState(
    draft: text,
    attachments: attachments.attachments,
    submissionRevision: attachments.submissionRevision,
    attachmentGeneration: attachments.attachmentGeneration,
    cleanupFailureDraftIds: attachments.cleanupFailureDraftIds,
  );
}

Iterable<ThreadSessionState> _existingSessions(
  ProviderContainer container,
) sync* {
  for (final reference in container.allProviders(
    family: threadSessionStoreProvider,
  )) {
    final provider = reference.provider;
    if (provider is! ThreadSessionStoreProvider) continue;
    yield container.read(provider);
  }
}

Map<String, int> _aggregateLeaseRefs(Map<String, int> leaseRefs) {
  var totalRefs = 0;
  for (final refs in leaseRefs.values) {
    totalRefs += refs;
  }
  return <String, int>{'topicCount': leaseRefs.length, 'totalRefs': totalRefs};
}

Map<String, int> _connectionCounts(ProviderContainer container) {
  final counts = _SyncCounts();
  final settings = container.read(settingsStoreProvider);
  counts.add(settings.configSync);
  counts.add(settings.catalogSync);
  counts.add(settings.agentProfilesSync);
  counts.add(container.read(projectStoreProvider).projectSync);
  counts.add(container.read(projectStoreProvider).agentSync);
  counts.add(container.read(threadDirectoryStoreProvider).sync);
  counts.add(container.read(recoveryStoreProvider).sync);
  counts.add(container.read(mcpStoreProvider).sync);
  counts.add(container.read(lspStoreProvider).sync);
  counts.add(container.read(modeCatalogStoreProvider).sync);
  counts.add(container.read(providerUsageStoreProvider).sync);
  counts.add(container.read(modelPerformanceStoreProvider).sync);
  counts.add(container.read(updaterStoreProvider).sync);
  final persistence = container.read(persistenceStoreProvider);
  counts.add(persistence.stateSync);
  counts.add(persistence.queueSync);
  for (final reference in container.allProviders(family: skillsStoreProvider)) {
    final provider = reference.provider;
    if (provider is! SkillsStoreProvider) continue;
    counts.add(container.read(provider).sync);
  }
  for (final reference in container.allProviders(
    family: sessionCostsStoreProvider,
  )) {
    final provider = reference.provider;
    if (provider is! SessionCostsStoreProvider) continue;
    counts.add(container.read(provider).sync);
  }
  for (final session in _existingSessions(container)) {
    counts.add(session.sync);
  }
  return counts.toJson();
}

Map<String, Object?> _projectionRevisions(ProviderContainer container) {
  final settings = container.read(settingsStoreProvider);
  final selection = container.read(selectionStoreProvider);
  final session = _existingSession(container, selection);
  final skills = <int>[];
  for (final reference in container.allProviders(family: skillsStoreProvider)) {
    final provider = reference.provider;
    if (provider is! SkillsStoreProvider) continue;
    final clock = container.read(provider);
    if (clock.value != null) skills.add(clock.revision);
  }
  final costs = <int>[];
  for (final reference in container.allProviders(
    family: sessionCostsStoreProvider,
  )) {
    final provider = reference.provider;
    if (provider is! SessionCostsStoreProvider) continue;
    final clock = container.read(provider);
    if (clock.value != null) costs.add(clock.revision);
  }
  return <String, Object?>{
    'settings': settings.settingsRevision,
    'modelCatalog': settings.modelCatalogRevision,
    'recovery': container.read(recoveryStoreProvider).revision,
    'mcp': container.read(mcpStoreProvider).revision,
    'lsp': container.read(lspStoreProvider).revision,
    'threadModeCatalog': container.read(modeCatalogStoreProvider).revision,
    'providerUsage': container.read(providerUsageStoreProvider).revision,
    'modelPerformance': container.read(modelPerformanceStoreProvider).revision,
    'persistence': container.read(persistenceStoreProvider).stateRevision,
    'persistenceQueue': container
        .read(persistenceStoreProvider)
        .queue
        ?.revision,
    'agentProfiles': settings.agentProfiles?.revision,
    'threadDirectory': container.read(threadDirectoryStoreProvider).revision,
    'selectedThread': session?.workspace?.revision,
    'skills': {
      'scopeCount': skills.length,
      'maxRevision': _maxRevision(skills),
    },
    'sessionCosts': {
      'scopeCount': costs.length,
      'maxRevision': _maxRevision(costs),
    },
  };
}

int? _maxRevision(Iterable<int> revisions) {
  int? maximum;
  for (final revision in revisions) {
    if (maximum == null || revision > maximum) maximum = revision;
  }
  return maximum;
}

class _SyncCounts {
  var topicCount = 0;
  var connectedCount = 0;
  var reconnectingCount = 0;
  var failedCount = 0;
  var errorCount = 0;

  void add(DomainSyncStatus sync) {
    if (sync.phase == DomainSyncPhase.idle) return;
    topicCount++;
    switch (sync.phase) {
      case DomainSyncPhase.connecting:
      case DomainSyncPhase.idle:
        break;
      case DomainSyncPhase.ready:
        connectedCount++;
      case DomainSyncPhase.reconnecting:
        reconnectingCount++;
      case DomainSyncPhase.failed:
        failedCount++;
    }
    if (sync.errorMessage != null) errorCount++;
  }

  Map<String, int> toJson() => <String, int>{
    'topicCount': topicCount,
    'connectedCount': connectedCount,
    'reconnectingCount': reconnectingCount,
    'failedCount': failedCount,
    'errorCount': errorCount,
  };
}
