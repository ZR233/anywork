import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_graph.dart';
import '../../../../presentation/providers/account_domains.dart';
import '../../../../presentation/providers/attachment_drafts.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/composer_draft_controller.dart';
import '../../../../presentation/providers/mode_catalog_store.dart';
import '../../../../presentation/providers/observe_client.dart';
import '../../../../presentation/providers/project_store.dart';
import '../../../../presentation/providers/recovery_store.dart';
import '../../../../presentation/providers/selection_store.dart';
import '../../../../presentation/providers/settings_store.dart';
import '../../../../presentation/providers/start_session_controller.dart';
import '../../../../presentation/providers/thread_directory_store.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../../interactions/state/interaction_payload.dart';
import '../state/composer_view_state.dart';

part 'composer_view_model.g.dart';

@riverpod
class StartPageComposerViewModel extends _$StartPageComposerViewModel {
  @override
  FutureOr<StartPageComposerViewState> build() {
    final sessionDraft = ref.watch(startSessionControllerProvider);
    final selection = ref.watch(selectionStoreProvider);
    final settings = ref.watch(settingsStoreProvider);
    final accounts = ref.watch(modelSelectionAccountsProvider);
    final projects =
        ref.watch(projectStoreProvider).projects?.values ?? const [];
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
    return StartPageComposerViewState(
      project: project,
      accounts: accounts,
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

  void updateDraft(String projectId, String text) => ref
      .read(anyworkClientProvider)
      .drafts
      .startDraft
      .updateDraft(projectId, text);

  void setMode(String projectId, ThreadModeId mode) => ref
      .read(anyworkClientProvider)
      .drafts
      .startDraft
      .setMode(projectId, mode);

  void setWorkspaceMode(String projectId, ThreadWorkspaceMode mode) => ref
      .read(anyworkClientProvider)
      .drafts
      .startDraft
      .setWorkspaceMode(projectId, mode);

  void setDelegationMode(String projectId, DelegationMode? mode) => ref
      .read(anyworkClientProvider)
      .drafts
      .startDraft
      .setDelegationModeOverride(projectId, mode);

  void setDelegationPreference(
    String projectId,
    DelegationPreference? preference,
  ) => ref
      .read(anyworkClientProvider)
      .drafts
      .startDraft
      .setDelegationPreferenceOverride(projectId, preference);

  void setModelIntent(ThreadModeId mode, String accountId, String modelId) =>
      ref
          .read(anyworkClientProvider)
          .drafts
          .startDraft
          .setModelIntent(mode, accountId, modelId);

  void setEffortIntent(ThreadModeId mode, String effort) => ref
      .read(anyworkClientProvider)
      .drafts
      .startDraft
      .setEffortIntent(mode, effort);

  Future<bool> submitStart(String projectId) =>
      ref.read(anyworkClientProvider).drafts.startDraft.submit(projectId);

  Future<void> admitAttachments({
    required String projectId,
    required ThreadModeId mode,
    required List<AttachmentDraftSource> sources,
  }) => ref
      .read(anyworkClientProvider)
      .drafts
      .attachments
      .admitNewThread(projectId: projectId, mode: mode, sources: sources);

  Future<void> pasteImage(
    String projectId,
    ThreadModeId mode,
    Uint8List bytes,
  ) => ref
      .read(anyworkClientProvider)
      .drafts
      .attachments
      .addNewThreadClipboard(projectId: projectId, mode: mode, pngBytes: bytes);

  Future<void> addRemoteAttachment(
    String projectId,
    ThreadModeId mode,
    String url,
  ) => ref
      .read(anyworkClientProvider)
      .drafts
      .attachments
      .addNewThreadRemote(projectId: projectId, mode: mode, url: url);

  Future<void> removeAttachment(String projectId, String draftId) => ref
      .read(anyworkClientProvider)
      .drafts
      .attachments
      .removeNewThreadDraft(projectId, draftId);

  void reportAttachmentFailure(String projectId, Object error) => ref
      .read(anyworkClientProvider)
      .drafts
      .attachments
      .reportNewThreadFailure(projectId, error);
}

@riverpod
class ComposerDockViewModel extends _$ComposerDockViewModel {
  int? _queuedStopStartedAtMs;
  Object? _lifecycle;

  @override
  FutureOr<ComposerDockViewState> build(String threadId) {
    final session = ref.watch(threadSessionStoreProvider(threadId));
    final draft = ref.watch(composerDraftControllerProvider(threadId));
    final settings = ref.watch(settingsStoreProvider);
    final accounts = ref.watch(modelSelectionAccountsProvider);
    final directory = ref.watch(threadDirectoryStoreProvider);
    final attachments = ref.watch(attachmentDraftsProvider);
    final recovery = ref.watch(recoveryStoreProvider).value?.values ?? const [];
    final threads = [...directory.window.threads, ...directory.overlayThreads];
    final thread = ModelRouteQueries.threadIdentity(
      threadId: threadId,
      directory: threads,
    );
    final projectId = thread?.projectId;
    final routeCommand = settings.commands['thread-route:$threadId'];
    final canonicalRoute = session.runtime?.modelRoute;
    final client = ref.read(anyworkClientProvider);
    final lifecycle = Object();
    _lifecycle = lifecycle;
    ref.onDispose(() {
      if (identical(_lifecycle, lifecycle)) {
        _lifecycle = null;
      }
    });
    final commandBoardState = _observe(lifecycle, client.threadCommands.source);
    final childInteractions = _observe(
      lifecycle,
      client.childInteractions.source,
    );
    final stopKey = 'stop:$threadId';
    final commandBoard = commandBoardState.commands;
    final stopCommand = commandBoard[stopKey];
    final continueCommand = commandBoard['continue:$threadId'];
    final ChildInteractionsState visibleChildInteractions =
        (thread?.isRoot ?? false)
        ? childInteractions
        : const ChildInteractionsState();
    final agents =
        ref.watch(projectStoreProvider).agents?.values ??
        const <StudioAgentView>[];
    final storage = session.storage;
    return ComposerDockViewState(
      thread: thread,
      hasSnapshot: session.hasSnapshot,
      revision: session.revision,
      composer: draft,
      activeInteraction: activePendingInteraction(session.interactions),
      turn: session.activeTurn,
      execution: session.runtime?.execution,
      continuation: session.runtime?.continuation,
      stopCommand: stopCommand,
      continueCommand: continueCommand,
      queuedStopStartedAtMs: stopCommand?.startedAtMs == _queuedStopStartedAtMs
          ? _queuedStopStartedAtMs
          : null,
      saveBlocked:
          storage != null && (storage.hasFault || storage.resumeRequired),
      workspaceBlocked: recovery.any(
        (issue) =>
            issue.blocksAccess &&
            issue.scope == RecoveryIssueScope.thread &&
            issue.threadId == threadId,
      ),
      childInteractions: visibleChildInteractions.hostThreadId == threadId
          ? visibleChildInteractions.visibleItems
          : const [],
      childInteractionGeneration: childInteractions.displayGeneration,
      childInteractionSources: {
        for (final agent in AgentDirectoryQueries.forRoot(
          rootThreadId: (thread?.isRoot ?? false) ? threadId : null,
          agents: agents,
          threads: threads,
        ))
          agent.threadId: _childSourceLabel(
            agent,
            threads
                .where((candidate) => candidate.id == agent.threadId)
                .firstOrNull,
          ),
      },
      modelRoute: canonicalRoute,
      routeDisplay: ModelRouteQueries.threadRoute(
        canonical: canonicalRoute,
        command: routeCommand,
        accounts: accounts,
      ),
      routePending: routeCommand?.isPending ?? false,
      routeFailure: routeCommand?.phase == CommandPhase.failed
          ? routeCommand?.error?.message
          : null,
      workflow: session.workflow,
      accounts: accounts,
      settingsLoaded: settings.configLoaded,
      targetDiagnostic: projectId == null
          ? null
          : attachments.diagnostics[attachmentTargetKey(projectId, threadId)],
      additionalDiagnostics: attachments.forProject(projectId),
    );
  }

  T _observe<T>(Object lifecycle, ValueObservation<T> source) {
    return observeClient(ref, source, (_) {
      if (ref.mounted && identical(_lifecycle, lifecycle)) {
        ref.invalidateSelf();
      }
    });
  }

  Future<void> submit(String threadId) => ref
      .read(anyworkClientProvider)
      .drafts
      .composer(threadId)
      .submit(
        beforeSubmit: () =>
            ref.read(appGraphProvider).timeline.prepareSend(threadId),
      );

  void updateDraft(String threadId, String text) => ref
      .read(anyworkClientProvider)
      .drafts
      .composer(threadId)
      .updateDraft(text);

  void refreshSession(String threadId) =>
      ref.read(anyworkClientProvider).conversations.session(threadId).refresh();

  Future<ThreadStopOutcome> stop(
    String threadId, {
    required String expectedExecutionId,
  }) async {
    final lifecycle = _lifecycle;
    if (lifecycle == null || !ref.mounted) {
      throw StateError('Composer view model is no longer active');
    }
    final previousStartedAt = state.value?.stopCommand?.startedAtMs;
    final outcome = await ref
        .read(anyworkClientProvider)
        .threadCommands
        .stop(threadId, expectedExecutionId: expectedExecutionId);
    if (!ref.mounted || !identical(_lifecycle, lifecycle)) return outcome;
    switch (outcome) {
      case StopQueued():
        _queuedStopStartedAtMs = previousStartedAt;
      case StopRequested():
        _queuedStopStartedAtMs = null;
      case StopNoExecution():
        _queuedStopStartedAtMs = null;
      case StopNotQualified():
        _queuedStopStartedAtMs = null;
    }
    ref.invalidateSelf();
    return outcome;
  }

  Future<ContinueThreadCommandReply> continueExecution(
    String threadId,
    ContinuationView continuation, {
    required int expectedModelRouteRevision,
  }) => ref
      .read(anyworkClientProvider)
      .threadCommands
      .continueThread(
        threadId,
        continuation,
        expectedModelRouteRevision: expectedModelRouteRevision,
      );

  Future<void> setThreadRoute({
    required String threadId,
    required String accountId,
    required String modelId,
    required String? effort,
  }) => ref
      .read(anyworkClientProvider)
      .threadCommands
      .setThreadModelRoute(
        threadId: threadId,
        accountId: accountId,
        modelId: modelId,
        effort: effort,
      );

  Future<void> setThreadMode(ThreadModeId mode, {required String threadId}) =>
      ref
          .read(anyworkClientProvider)
          .threadCommands
          .setThreadMode(mode, threadId: threadId);

  Future<void> addLocalAttachments(String threadId, List<String> paths) async {
    final client = ref.read(anyworkClientProvider);
    final owner = client.drafts.composer(threadId);
    await owner.addLocalAttachments(paths);
  }

  void reportDraftFailure(String threadId, Object error) => ref
      .read(anyworkClientProvider)
      .drafts
      .composer(threadId)
      .reportFailure(error);

  Future<void> pasteImage(String threadId, Uint8List bytes) => ref
      .read(anyworkClientProvider)
      .drafts
      .composer(threadId)
      .addClipboardImage(bytes);

  Future<void> addRemoteAttachment(String threadId, String url) => ref
      .read(anyworkClientProvider)
      .drafts
      .composer(threadId)
      .addRemoteAttachment(url);

  Future<void> removeAttachment(String threadId, String draftId) => ref
      .read(anyworkClientProvider)
      .drafts
      .composer(threadId)
      .removeAttachment(draftId);
}

String _childSourceLabel(StudioAgentView agent, StudioThread? thread) {
  final title = thread?.title.trim() ?? '';
  if (title.isNotEmpty) return title;
  final task = agent.task.trim();
  if (task.isNotEmpty) return task;
  final role = agent.role.trim();
  return role.isNotEmpty ? role : agent.threadId;
}
