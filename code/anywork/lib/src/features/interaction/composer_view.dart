import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../presentation/providers/mode_catalog_store.dart';
import '../../presentation/providers/project_store.dart';
import '../../presentation/providers/recovery_store.dart';
import '../../presentation/providers/selection_store.dart';
import '../../presentation/providers/settings_store.dart';
import '../../presentation/providers/thread_directory_store.dart';
import '../../presentation/providers/thread_session_store.dart';
import '../../presentation/providers/attachment_drafts.dart';
import '../../presentation/providers/composer_draft_controller.dart';
import 'interaction_payload.dart';
import '../../presentation/providers/start_session_controller.dart';

part 'composer_view.g.dart';

/// 只读 Connector 投影；草稿、默认路由解析和 pending 展示规则由 Client 持有。
@riverpod
StartPageComposerProjection startPageComposerView(Ref ref) {
  final sessionDraft = ref.watch(startSessionControllerProvider);
  final selection = ref.watch(selectionStoreProvider);
  final settings = ref.watch(settingsStoreProvider);
  final projects = ref.watch(projectStoreProvider).projects?.values ?? const [];
  final project = projects
      .where((candidate) => candidate.id == selection.selectedProjectId)
      .firstOrNull;
  final recovery = ref.watch(recoveryStoreProvider).value?.values ?? const [];
  final projectId = project?.id;
  final blocked =
      projectId != null &&
      recovery.any(
        (issue) =>
            issue.blocksAccess &&
            issue.scope == RecoveryIssueScope.project &&
            issue.projectId == projectId,
      );
  final canonical = settings.canonical;
  final catalog = ref.watch(modeCatalogStoreProvider).value;
  final attachments = ref.watch(attachmentDraftsProvider);
  return StartPageComposerProjection(
    project: project,
    providers: canonical?.providers ?? const [],
    modeModelRoutes: canonical?.modeModelRoutes ?? const [],
    settingsLoaded: settings.configLoaded,
    canSubmit:
        project != null && selection.selectedThreadId == null && !blocked,
    commands: settings.commands,
    diagnostics: attachments.forProject(projectId),
    modeCatalog: catalog,
    sessionDraft: sessionDraft,
    composer: projectId == null
        ? const ComposerThreadState.idle()
        : attachments.newThread(projectId),
    targetDiagnostic: projectId == null
        ? null
        : attachments.diagnostics[attachmentTargetKey(projectId, null)],
  );
}

@riverpod
ComposerDockView composerDockView(Ref ref, String threadId) {
  final session = ref.watch(threadSessionStoreProvider(threadId));
  final draft = ref.watch(composerDraftControllerProvider(threadId));
  final settings = ref.watch(settingsStoreProvider);
  final directory = ref.watch(threadDirectoryStoreProvider);
  final attachments = ref.watch(attachmentDraftsProvider);
  final thread = ModelRouteQueries.threadIdentity(
    threadId: threadId,
    directory: [...directory.window.threads, ...directory.overlayThreads],
  );
  final projectId = thread?.projectId;
  final routeCommand = settings.commands['thread-route:$threadId'];
  final canonicalRoute = session.runtime?.modelRoute;
  return ComposerDockView(
    thread: thread,
    hasSnapshot: session.hasSnapshot,
    revision: session.revision,
    composer: draft,
    activeInteraction: activePendingInteraction(session.interactions),
    turn: session.activeTurn,
    modelRoute: canonicalRoute,
    routeDisplay: ModelRouteQueries.threadRoute(
      canonical: canonicalRoute,
      command: routeCommand,
      providers: settings.canonical?.providers ?? const [],
    ),
    routePending: routeCommand?.isPending ?? false,
    routeFailure: routeCommand?.phase == CommandPhase.failed
        ? routeCommand?.error?.message
        : null,
    workflow: session.workflow,
    providers: settings.canonical?.providers ?? const [],
    settingsLoaded: settings.configLoaded,
    targetDiagnostic: projectId == null
        ? null
        : attachments.diagnostics[attachmentTargetKey(projectId, threadId)],
    additionalDiagnostics: attachments.forProject(projectId),
  );
}

class StartPageComposerProjection {
  const StartPageComposerProjection({
    required this.project,
    required this.providers,
    required this.modeModelRoutes,
    required this.settingsLoaded,
    required this.canSubmit,
    required this.commands,
    required this.diagnostics,
    required this.modeCatalog,
    required this.sessionDraft,
    required this.composer,
    required this.targetDiagnostic,
  });

  final StudioProject? project;
  final List<ProviderSettingsView> providers;
  final List<ModeModelRouteView> modeModelRoutes;
  final bool settingsLoaded;
  final bool canSubmit;
  final Map<String, CommandStatus> commands;
  final List<ComposerTargetDiagnostic> diagnostics;
  final ThreadModeCatalogView? modeCatalog;
  final StartSessionDraft sessionDraft;
  final ComposerThreadState composer;
  final ComposerTargetDiagnostic? targetDiagnostic;

  ThreadModeId get mode => sessionDraft.forProject(project?.id).mode;
  ThreadWorkspaceMode get workspaceMode =>
      sessionDraft.forProject(project?.id).workspaceMode;
  String get draftText => sessionDraft.forProject(project?.id).text;
  bool get submitting => sessionDraft.submitting;

  ModeModelRouteView? canonicalRoute(ThreadModeId mode) =>
      _route(mode).canonical;

  bool routePending(ThreadModeId mode) {
    return _route(mode).pending;
  }

  ModeModelRouteView? displayRoute(ThreadModeId mode) {
    return _route(mode).display;
  }

  ModeModelRouteView? laneRoute(ThreadModeId mode) => _route(mode).lane;

  String? routeFailure(ThreadModeId mode) {
    return _route(mode).failure;
  }

  StartRouteQuery _route(ThreadModeId mode) => ModelRouteQueries.startRoute(
    routes: modeModelRoutes,
    commands: commands,
    draft: sessionDraft,
    mode: mode,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StartPageComposerProjection &&
          project?.id == other.project?.id &&
          settingsLoaded == other.settingsLoaded &&
          canSubmit == other.canSubmit &&
          identical(providers, other.providers) &&
          identical(modeModelRoutes, other.modeModelRoutes) &&
          identical(commands, other.commands) &&
          identical(diagnostics, other.diagnostics) &&
          identical(modeCatalog, other.modeCatalog) &&
          sessionDraft == other.sessionDraft &&
          composer == other.composer &&
          targetDiagnostic == other.targetDiagnostic;

  @override
  int get hashCode => Object.hash(
    project?.id,
    settingsLoaded,
    canSubmit,
    identityHashCode(providers),
    identityHashCode(modeModelRoutes),
    identityHashCode(commands),
    identityHashCode(diagnostics),
    identityHashCode(modeCatalog),
    sessionDraft,
    composer,
    targetDiagnostic,
  );
}

class ComposerDockView {
  const ComposerDockView({
    required this.thread,
    required this.hasSnapshot,
    required this.revision,
    required this.composer,
    required this.activeInteraction,
    required this.turn,
    required this.modelRoute,
    this.routeDisplay,
    required this.routePending,
    required this.routeFailure,
    required this.workflow,
    required this.providers,
    required this.settingsLoaded,
    required this.targetDiagnostic,
    required this.additionalDiagnostics,
  });

  final StudioThread? thread;
  final bool hasSnapshot;
  final int revision;
  final ComposerThreadState composer;
  final PendingInteraction? activeInteraction;
  final StudioTurnView? turn;
  final ThreadModelRouteView? modelRoute;
  final ModelRouteDisplay? routeDisplay;
  final bool routePending;
  final String? routeFailure;
  final WorkflowRuntimeView? workflow;
  final List<ProviderSettingsView> providers;
  final bool settingsLoaded;
  final ComposerTargetDiagnostic? targetDiagnostic;
  final List<ComposerTargetDiagnostic> additionalDiagnostics;

  bool get isBusy => turn?.state.isBusy ?? false;
  bool get hasActiveWorkflow => workflow?.isActive ?? false;
  ModelRouteDisplay? get displayRoute =>
      routeDisplay ??
      ModelRouteQueries.threadRoute(
        canonical: modelRoute,
        command: null,
        providers: providers,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComposerDockView &&
          thread?.id == other.thread?.id &&
          thread?.status == other.thread?.status &&
          thread?.mode == other.thread?.mode &&
          thread?.role == other.thread?.role &&
          thread?.isRetiredAgent == other.thread?.isRetiredAgent &&
          hasSnapshot == other.hasSnapshot &&
          revision == other.revision &&
          composer == other.composer &&
          activeInteraction?.id == other.activeInteraction?.id &&
          turn == other.turn &&
          modelRoute == other.modelRoute &&
          routeDisplay == other.routeDisplay &&
          routePending == other.routePending &&
          routeFailure == other.routeFailure &&
          workflow == other.workflow &&
          settingsLoaded == other.settingsLoaded &&
          targetDiagnostic == other.targetDiagnostic &&
          identical(providers, other.providers) &&
          identical(additionalDiagnostics, other.additionalDiagnostics);

  @override
  int get hashCode => Object.hash(
    thread?.id,
    thread?.status,
    thread?.mode,
    thread?.role,
    hasSnapshot,
    revision,
    composer,
    activeInteraction?.id,
    turn,
    modelRoute,
    routeDisplay,
    routePending,
    routeFailure,
    workflow,
    settingsLoaded,
    targetDiagnostic,
    identityHashCode(providers),
    identityHashCode(additionalDiagnostics),
  );
}
