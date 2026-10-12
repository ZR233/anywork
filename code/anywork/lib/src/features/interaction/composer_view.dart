import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/stores/domain_sync.dart';
import '../../data/stores/mode_catalog_store.dart';
import '../../data/stores/project_store.dart';
import '../../data/stores/recovery_store.dart';
import '../../data/stores/selection_store.dart';
import '../../data/stores/settings_store.dart';
import '../../data/stores/thread_directory_store.dart';
import '../../data/stores/thread_session_store.dart';
import '../../domain/models/studio_models.dart';
import '../status/session_selectors.dart';
import 'attachment_drafts.dart';
import 'composer_draft_controller.dart';
import 'interaction_payload.dart';
import 'start_session_controller.dart';

part 'composer_view.g.dart';

/// 起始页投影。Mode、工作区、正文与模型意图来自 route 作用域草稿；
/// 未显式选择时跟随 settingsStore canonical，并用命令 lane 的 pending 目标覆盖。
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
    permissionMode: canonical?.permissionMode ?? PermissionMode.requestApproval,
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
  final catalog = ref.watch(modeCatalogStoreProvider).value;
  StudioThread? thread;
  for (final candidate in directory.window.threads) {
    if (candidate.id == threadId) {
      thread = candidate;
      break;
    }
  }
  thread ??= session.workspace?.thread;
  final projectId = thread?.projectId;
  final modeId = thread?.mode.id;
  final routeCommand = settings.commands['thread-route:$threadId'];
  final canonicalRoute = session.runtime?.modelRoute;
  return ComposerDockView(
    thread: thread,
    hasSnapshot: session.hasSnapshot,
    revision: session.revision,
    composer: draft,
    activeInteraction: activePendingInteraction(session.interactions),
    turn: session.activeTurn,
    modelRoute: overlayThreadRoute(canonicalRoute, routeCommand),
    routePending: routeCommand?.isPending ?? false,
    routeFailure: routeCommand?.phase == CommandPhase.failed
        ? routeCommand?.error?.message
        : null,
    workflow: session.workflow,
    permissionMode:
        settings.canonical?.permissionMode ?? PermissionMode.requestApproval,
    providers: settings.canonical?.providers ?? const [],
    settingsLoaded: settings.configLoaded,
    requiresFunctionCalling: modeId == null
        ? false
        : catalog?.modes
                  .where((mode) => mode.id == modeId)
                  .firstOrNull
                  ?.hasWorkflow ??
              false,
    targetDiagnostic: projectId == null
        ? null
        : attachments.diagnostics[attachmentTargetKey(projectId, threadId)],
    additionalDiagnostics: attachments.forProject(projectId),
  );
}

ThreadModelRouteView? overlayThreadRoute(
  ThreadModelRouteView? canonical,
  CommandStatus? pending,
) {
  final target = pending?.isPending == true ? pending?.target : null;
  if (target?.providerId == null || target?.model == null) return canonical;
  return ThreadModelRouteView(
    providerId: target!.providerId!,
    model: target.model!,
    effort: target.effort ?? canonical?.effort,
    revision: canonical?.revision ?? 0,
    available: canonical?.available ?? true,
    unavailableReason: canonical?.unavailableReason,
  );
}

class StartPageComposerProjection {
  const StartPageComposerProjection({
    required this.project,
    required this.providers,
    required this.modeModelRoutes,
    required this.permissionMode,
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
  final PermissionMode permissionMode;
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
      modeRouteFor(modeModelRoutes, mode);

  bool routePending(ThreadModeId mode) {
    return commands['new-thread-route:model:${mode.id}']?.isPending == true ||
        commands['new-thread-route:effort:${mode.id}']?.isPending == true;
  }

  ModeModelRouteView? displayRoute(ThreadModeId mode) {
    return overlayStartSessionRoute(
      mode: mode,
      laneRoute: laneRoute(mode),
      modelIntent: sessionDraft.modelIntentFor(mode),
      effortIntent: sessionDraft.effortIntentFor(mode),
    );
  }

  /// 命令 lane 的 `pending.target ?? canonical`。草稿意图不在这里覆盖。
  ModeModelRouteView? laneRoute(ThreadModeId mode) {
    final canonical = canonicalRoute(mode);
    final model = commands['new-thread-route:model:${mode.id}'];
    final effort = commands['new-thread-route:effort:${mode.id}'];
    if (model != null &&
        model.isPending &&
        model.target.providerId != null &&
        model.target.model != null) {
      return ModeModelRouteView(
        modeId: mode,
        providerId: model.target.providerId!,
        model: model.target.model!,
        effort: model.target.effort ?? canonical?.effort ?? '',
      );
    }
    if (effort != null && effort.isPending && canonical != null) {
      return ModeModelRouteView(
        modeId: mode,
        providerId: canonical.providerId,
        model: canonical.model,
        effort: effort.target.effort ?? canonical.effort,
      );
    }
    return canonical;
  }

  bool requiresFunctionCalling(ThreadModeId mode) =>
      modeCatalog?.modes
          .where((descriptor) => descriptor.id == mode.id)
          .firstOrNull
          ?.hasWorkflow ??
      false;

  String? routeFailure(ThreadModeId mode) {
    for (final key in [
      'new-thread-route:model:${mode.id}',
      'new-thread-route:effort:${mode.id}',
    ]) {
      final status = commands[key];
      if (status?.phase == CommandPhase.failed) {
        return status?.error?.message;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StartPageComposerProjection &&
          project?.id == other.project?.id &&
          settingsLoaded == other.settingsLoaded &&
          canSubmit == other.canSubmit &&
          permissionMode == other.permissionMode &&
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
    permissionMode,
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
    required this.routePending,
    required this.routeFailure,
    required this.workflow,
    required this.permissionMode,
    required this.providers,
    required this.settingsLoaded,
    required this.requiresFunctionCalling,
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
  final bool routePending;
  final String? routeFailure;
  final WorkflowRuntimeView? workflow;
  final PermissionMode permissionMode;
  final List<ProviderSettingsView> providers;
  final bool settingsLoaded;
  final bool requiresFunctionCalling;
  final ComposerTargetDiagnostic? targetDiagnostic;
  final List<ComposerTargetDiagnostic> additionalDiagnostics;

  bool get isBusy => turn?.state.isBusy ?? false;
  bool get hasActiveWorkflow => workflow?.isActive ?? false;

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
          routePending == other.routePending &&
          routeFailure == other.routeFailure &&
          workflow == other.workflow &&
          permissionMode == other.permissionMode &&
          settingsLoaded == other.settingsLoaded &&
          requiresFunctionCalling == other.requiresFunctionCalling &&
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
    routePending,
    routeFailure,
    workflow,
    permissionMode,
    settingsLoaded,
    requiresFunctionCalling,
    targetDiagnostic,
    identityHashCode(providers),
    identityHashCode(additionalDiagnostics),
  );
}
