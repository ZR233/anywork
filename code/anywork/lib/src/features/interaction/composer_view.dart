import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/composer_primary_action.dart';
import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/account_domains.dart';
import '../../presentation/providers/mode_catalog_store.dart';
import '../../presentation/providers/project_store.dart';
import '../../presentation/providers/recovery_store.dart';
import '../../presentation/providers/selection_store.dart';
import '../../presentation/providers/settings_store.dart';
import '../../presentation/providers/thread_directory_store.dart';
import '../../presentation/providers/thread_session_store.dart';
import '../../presentation/providers/attachment_drafts.dart';
import '../../presentation/providers/composer_draft_controller.dart';
import '../../presentation/providers/observe_client.dart';
import 'interaction_payload.dart';
import '../../presentation/providers/start_session_controller.dart';

part 'composer_view.g.dart';

/// 只读 Connector 投影；草稿、默认路由解析和 pending 展示规则由 Client 持有。
@riverpod
StartPageComposerProjection startPageComposerView(Ref ref) {
  final sessionDraft = ref.watch(startSessionControllerProvider);
  final selection = ref.watch(selectionStoreProvider);
  final settings = ref.watch(settingsStoreProvider);
  final accounts = ref.watch(modelSelectionAccountsProvider);
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

@riverpod
ComposerDockView composerDockView(Ref ref, String threadId) {
  final session = ref.watch(threadSessionStoreProvider(threadId));
  final draft = ref.watch(composerDraftControllerProvider(threadId));
  final settings = ref.watch(settingsStoreProvider);
  final accounts = ref.watch(modelSelectionAccountsProvider);
  final directory = ref.watch(threadDirectoryStoreProvider);
  final attachments = ref.watch(attachmentDraftsProvider);
  final recovery = ref.watch(recoveryStoreProvider).value?.values ?? const [];
  final thread = ModelRouteQueries.threadIdentity(
    threadId: threadId,
    directory: [...directory.window.threads, ...directory.overlayThreads],
  );
  final projectId = thread?.projectId;
  final routeCommand = settings.commands['thread-route:$threadId'];
  final canonicalRoute = session.runtime?.modelRoute;
  // 停止命令的在途与失败以 Client 命令板为唯一事实：它跨 widget 重建与切换会话
  // 存活，输入区不再用本地标记描述「请求是否还在进行」。
  final threadCommands = ref.read(anyworkClientProvider).threadCommands;
  final stopKey = 'stop:$threadId';
  var stopCommand = threadCommands.state.commands[stopKey];
  observeClient(ref, threadCommands.source, (next) {
    final value = next.commands[stopKey];
    if (value == stopCommand) return;
    stopCommand = value;
    ref.invalidateSelf();
  });
  // 主会话可见的子任务待决交互：只观察 Client 已发布的只读投影，不激活 child。
  final ChildInteractionsState childInteractions = (thread?.isRoot ?? false)
      ? observeClient(
          ref,
          ref.read(anyworkClientProvider).childInteractions.source,
          (_) => ref.invalidateSelf(),
        )
      : const ChildInteractionsState();
  final agents =
      ref.watch(projectStoreProvider).agents?.values ??
      const <StudioAgentView>[];
  final storage = session.storage;
  final knownThreads = [
    ...directory.window.threads,
    ...directory.overlayThreads,
  ];
  return ComposerDockView(
    thread: thread,
    hasSnapshot: session.hasSnapshot,
    revision: session.revision,
    composer: draft,
    activeInteraction: activePendingInteraction(session.interactions),
    turn: session.activeTurn,
    execution: session.runtime?.execution,
    continuation: session.runtime?.continuation,
    stopCommand: stopCommand,
    saveBlocked:
        storage != null && (storage.hasFault || storage.resumeRequired),
    workspaceBlocked: recovery.any(
      (issue) =>
          issue.blocksAccess &&
          issue.scope == RecoveryIssueScope.thread &&
          issue.threadId == threadId,
    ),
    childInteractions: childInteractions.hostThreadId == threadId
        ? childInteractions.items
        : const [],
    childInteractionSources: {
      for (final agent in AgentDirectoryQueries.forRoot(
        rootThreadId: (thread?.isRoot ?? false) ? threadId : null,
        agents: agents,
        threads: knownThreads,
      ))
        agent.threadId: _childSourceLabel(
          agent,
          knownThreads
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

/// 子交互卡片的来源成员说明：会话标题、任务概要，最后才是角色标识。
String _childSourceLabel(StudioAgentView agent, StudioThread? thread) {
  final title = thread?.title.trim() ?? '';
  if (title.isNotEmpty) return title;
  final task = agent.task.trim();
  if (task.isNotEmpty) return task;
  final role = agent.role.trim();
  return role.isNotEmpty ? role : agent.threadId;
}

class StartPageComposerProjection {
  const StartPageComposerProjection({
    required this.project,
    required this.accounts,
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
  final List<ModelSelectionAccount> accounts;
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
  NewThreadPreparation? get preparation =>
      sessionDraft.preparations[project?.id];

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
          identical(accounts, other.accounts) &&
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
    identityHashCode(accounts),
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
    required this.execution,
    required this.continuation,
    required this.stopCommand,
    required this.saveBlocked,
    required this.workspaceBlocked,
    required this.childInteractions,
    required this.childInteractionSources,
    required this.modelRoute,
    this.routeDisplay,
    required this.routePending,
    required this.routeFailure,
    required this.workflow,
    required this.accounts,
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

  /// 会话自己的当前执行身份；准备、等待准入、运行与清理期都存在。
  final AgentExecutionView? execution;

  /// 该会话唯一的继续点只读投影；没有被中断的工作时为空。
  final ContinuationView? continuation;

  /// 该会话在 Client 命令板里的停止命令状态（键 `stop:<threadId>`）。
  ///
  /// 它跨 widget 重建与切换会话存活：`phase == pending` 表示请求已发出但结果
  /// 尚未结算，`phase == failed` 携带类型化原因。目标执行编号在 `target.label`。
  final CommandStatus? stopCommand;

  /// 保存被硬故障阻塞（`resumeRequired` 或 `hasFault`）；短暂压力不算阻塞。
  final bool saveBlocked;

  /// 会话工作区被恢复问题判为不可访问。
  final bool workspaceBlocked;

  /// 主会话可见的直接 child 待决交互（只读投影，不激活 child）。
  final List<ChildInteractionSummary> childInteractions;

  /// child 会话编号 → 来源成员说明；用于卡片展示来源，不影响决定权限。
  final Map<String, String> childInteractionSources;

  final ThreadModelRouteView? modelRoute;
  final ModelRouteDisplay? routeDisplay;
  final bool routePending;
  final String? routeFailure;
  final WorkflowRuntimeView? workflow;
  final List<ModelSelectionAccount> accounts;
  final bool settingsLoaded;
  final ComposerTargetDiagnostic? targetDiagnostic;
  final List<ComposerTargetDiagnostic> additionalDiagnostics;

  bool get isBusy => turn?.state.isBusy ?? false;
  bool get hasActiveWorkflow => workflow?.isActive ?? false;

  /// 模型路由当前不可用（canonical `available == false`）。
  bool get modelUnavailable => displayRoute?.available == false;

  /// 主输入区此刻的类型化阻塞原因；没有阻塞时为 `null`。
  ///
  /// 保存与工作区由 canonical 投影判定，模型由 canonical 路由资格判定；命令被明确
  /// 拒绝的原因由调用方另行传入，不在这里猜测。
  ComposerBlocker? get canonicalBlocker {
    if (saveBlocked) return const ComposerStorageBlocker();
    if (workspaceBlocked) return const ComposerWorkspaceBlocker();
    if (modelUnavailable) return const ComposerModelBlocker();
    return null;
  }

  ModelRouteDisplay? get displayRoute =>
      routeDisplay ??
      ModelRouteQueries.threadRoute(
        canonical: modelRoute,
        command: null,
        accounts: accounts,
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
          execution == other.execution &&
          continuation == other.continuation &&
          saveBlocked == other.saveBlocked &&
          workspaceBlocked == other.workspaceBlocked &&
          listEquals(childInteractions, other.childInteractions) &&
          mapEquals(childInteractionSources, other.childInteractionSources) &&
          modelRoute == other.modelRoute &&
          routeDisplay == other.routeDisplay &&
          routePending == other.routePending &&
          routeFailure == other.routeFailure &&
          workflow == other.workflow &&
          settingsLoaded == other.settingsLoaded &&
          targetDiagnostic == other.targetDiagnostic &&
          identical(accounts, other.accounts) &&
          identical(additionalDiagnostics, other.additionalDiagnostics);

  @override
  int get hashCode => Object.hash(
    Object.hash(
      thread?.id,
      thread?.status,
      thread?.mode,
      thread?.role,
      hasSnapshot,
      revision,
      composer,
      activeInteraction?.id,
      turn,
    ),
    Object.hash(
      execution,
      continuation,
      saveBlocked,
      workspaceBlocked,
      Object.hashAll(childInteractions),
      Object.hashAll(childInteractionSources.entries),
      modelRoute,
      routeDisplay,
      routePending,
      routeFailure,
    ),
    Object.hash(
      workflow,
      settingsLoaded,
      targetDiagnostic,
      identityHashCode(accounts),
      identityHashCode(additionalDiagnostics),
    ),
  );
}
