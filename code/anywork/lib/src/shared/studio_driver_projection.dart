import 'package:anywork_client/studio_client.dart';

import '../domain/models/agent_workspace_view.dart';
import '../features/shell/shell_view.dart'
    show
        agentsForThreads,
        primaryInteraction,
        threadsForRoot,
        projectById,
        rootThread;
import 'studio_driver_state.dart';

/// The Driver borrows this application's Client. Binding creates no provider,
/// observation, draft, Session, ChatView, or native subscription.
void bindStudioDriver(AnyworkClient client) {
  StudioDriverState.bindSnapshotQuery(() => queryStudioDriverFacts(client));
}

/// Read immutable current mirrors synchronously. No business projection is
/// retained by Driver, and owner existence never depends on a provider family.
StudioDriverFacts queryStudioDriverFacts(AnyworkClient client) {
  final selection = client.selection.state;
  final directory = client.threadDirectory.state;
  final threads = directory.window.threads;
  final settings = client.settings.state;
  final canonical = settings.canonical;
  final providers = providersWithCatalogMetadata(
    canonical?.providers ?? const <ProviderSettingsView>[],
    settings.providerCatalog,
  );
  final projects = client.project.state;
  final project = projectById(
    projects.projects?.values.toList(growable: false) ??
        const <StudioProject>[],
    selection.selectedProjectId,
  );
  final selectedThreadId = selection.selectedThreadId;
  final session = selectedThreadId == null || selection.needsOpen
      ? null
      : client.sessionState(selectedThreadId);
  final thread = client.findThread(selectedThreadId ?? '');
  final root = thread == null ? null : rootThread(threads, thread) ?? thread;
  final threadComposer = selectedThreadId == null
      ? const ComposerThreadState.idle()
      : client.composerState(selectedThreadId) ??
            const ComposerThreadState.idle();
  final newThreadComposer = _newThreadComposer(client, selection);
  final projectDraft = client.startDraft.state.forProject(
    selection.selectedProjectId,
  );
  AgentWorkspaceView? workspace;
  if (thread != null && root != null) {
    final agents = projects.agents?.values ?? const <StudioAgentView>[];
    workspace = AgentWorkspaceView(
      thread: thread,
      rootThread: root,
      syncState: session == null
          ? AgentWorkspaceSyncState.idle
          : _sessionSyncState(session),
      loadError: session?.sync.phase == DomainSyncPhase.failed
          ? session?.sync.errorMessage
          : null,
      timelineRows: session == null
          ? const []
          : timelineRowsFromThreadItems(session.items),
      todo: session?.workspace?.todo,
      runtime: session?.runtime ?? _emptyRuntime,
      turn: session?.activeTurn,
      lastTurn: session?.workspace?.lastTurn,
      activeInteraction: primaryInteraction(session?.interactions ?? const []),
      composer: threadComposer,
      composerMode: thread.isAgent
          ? AgentComposerMode.runtimeDriven
          : AgentComposerMode.editable,
      providers: providers,
      modeModelRoutes: canonical?.modeModelRoutes ?? const [],
      roles: canonical?.roles ?? const [],
      agents: agentsForThreads(threadsForRoot(threads, root), agents),
    );
  }

  return StudioDriverFacts(
    timelineWorkspace: session?.workspace,
    history: session?.history ?? const ThreadHistoryWindow(),
    workspacesByThread: {
      for (final state in client.sessionStates)
        if (state.workspace case final workspace?)
          if (client.findThread(state.threadId) case final identity?)
            state.threadId: workspace.copyWith(thread: identity),
    },
    rootThreads: [
      for (final thread in threads)
        if (thread.isRoot) thread,
    ],
    directoryHasMore: directory.hasMore,
    selectedProjectId: selection.selectedProjectId,
    selectedThreadId: selectedThreadId,
    newThreadMode: projectDraft.mode,
    newThreadWorkspaceMode: projectDraft.workspaceMode,
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
        client.persistence.state.persistence ??
        const PersistenceStateSnapshot.ready(),
    recoveryIssues: client.recovery.state.value?.values ?? const [],
    project: project,
    workspace: workspace,
  );
}

/// Diagnostics read an existing registry and existing domain mirrors. Reading
/// this endpoint never changes topic demand, even if no Widget observes it.
Map<String, Object?> studioDriverTopicDiagnostics(AnyworkClient client) {
  final refs = client.channels.activeTopicRefCountViews();
  return <String, Object?>{
    'availability': 'available',
    'registryAvailability': 'available',
    'leaseRefs': <String, int>{
      'topicCount': refs.length,
      'totalRefs': refs.values.fold(0, (total, value) => total + value),
    },
    'connections': _connectionCounts(client),
    'projectionRevisions': _projectionRevisions(client),
  };
}

ComposerThreadState _newThreadComposer(
  AnyworkClient client,
  SelectionStoreState selection,
) {
  final projectId = selection.selectedProjectId;
  final draft = client.startDraft.state;
  final text = draft.forProject(projectId).text;
  final attachments = projectId == null
      ? const ComposerThreadState.idle()
      : client.attachments.state.newThread(projectId);
  final submitting = draft.submitting || attachments.isSubmissionPending;
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

Map<String, int> _connectionCounts(AnyworkClient client) {
  final counts = _SyncCounts();
  final settings = client.settings.state;
  counts.add(settings.configSync);
  counts.add(settings.catalogSync);
  counts.add(settings.agentProfilesSync);
  counts.add(client.project.state.projectSync);
  counts.add(client.project.state.agentSync);
  counts.add(client.threadDirectory.state.sync);
  counts.add(client.recovery.state.sync);
  counts.add(client.mcp.state.sync);
  counts.add(client.lsp.state.sync);
  counts.add(client.modeCatalog.state.sync);
  counts.add(client.providerUsage.state.sync);
  counts.add(client.modelPerformance.state.sync);
  counts.add(client.updater.state.sync);
  counts.add(client.persistence.state.stateSync);
  counts.add(client.persistence.state.queueSync);
  for (final store in client.ownedSkills) {
    counts.add(store.state.sync);
  }
  for (final store in client.ownedSessionCosts) {
    counts.add(store.state.sync);
  }
  for (final session in client.sessionStates) {
    counts.add(session.sync);
  }
  return counts.toJson();
}

Map<String, Object?> _projectionRevisions(AnyworkClient client) {
  final settings = client.settings.state;
  final selection = client.selection.state;
  final selected = selection.selectedThreadId;
  final session = selected == null || selection.needsOpen
      ? null
      : client.sessionState(selected);
  final skills = [
    for (final store in client.ownedSkills)
      if (store.state.value != null) store.state.revision,
  ];
  final costs = [
    for (final store in client.ownedSessionCosts)
      if (store.state.value != null) store.state.revision,
  ];
  return <String, Object?>{
    'settings': settings.settingsRevision,
    'modelCatalog': settings.modelCatalogRevision,
    'recovery': client.recovery.state.revision,
    'mcp': client.mcp.state.revision,
    'lsp': client.lsp.state.revision,
    'threadModeCatalog': client.modeCatalog.state.revision,
    'providerUsage': client.providerUsage.state.revision,
    'modelPerformance': client.modelPerformance.state.revision,
    'persistence': client.persistence.state.stateRevision,
    'persistenceQueue': client.persistence.state.queue?.revision,
    'agentProfiles': settings.agentProfiles?.revision,
    'threadDirectory': client.threadDirectory.state.revision,
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

AgentWorkspaceSyncState _sessionSyncState(ThreadSessionState session) =>
    switch (session.sync.phase) {
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

const _emptyRuntime = ThreadRuntimeView(
  model: '',
  contextTokens: 0,
  contextWindow: 0,
  totalTokens: 0,
  costLabel: '',
  activeSkills: [],
  activeMcpServers: [],
  activeLspServers: [],
);

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
