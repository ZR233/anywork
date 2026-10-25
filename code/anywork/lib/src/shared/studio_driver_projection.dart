import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../domain/models/agent_workspace_view.dart';
import '../domain/models/plan_confirmation_ownership.dart';
import '../domain/models/timeline_presentation.dart';
import '../features/shell/shell_view.dart' show primaryInteraction, projectById;
import '../presentation/view_models/timeline_session_owner.dart';
import 'studio_driver_key_values.dart';
import 'studio_driver_state.dart';

/// The Driver borrows this application's Client. Binding creates no account,
/// observation, draft, Session, ChatView, or native subscription.
///
/// [timeline] 只被读取当前展示；绑定它不建立内容订阅、业务 demand 或展示 lease。
void bindStudioDriver(
  AnyworkClient client, {
  required TimelineSessionOwner timeline,
}) {
  StudioDriverState.bindSnapshotQuery(
    () => queryStudioDriverFacts(client, timeline: timeline),
  );
}

/// Read immutable current mirrors synchronously. No business projection is
/// retained by Driver, and owner existence never depends on a account family.
StudioDriverFacts queryStudioDriverFacts(
  AnyworkClient client, {
  required TimelineSessionOwner timeline,
}) {
  final selection = client.selection.state;
  final directory = client.threadDirectory.state;
  final threads = [...directory.window.threads, ...directory.overlayThreads];
  final settings = client.settings.state;
  final canonical = settings.canonical;
  final accounts = accountsWithCatalogMetadata(
    canonical?.accounts ?? const <AccountSettingsView>[],
    settings.accountCatalog,
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
  final agents = projects.agents?.values ?? const <StudioAgentView>[];
  final rootId = AgentDirectoryQueries.rootThreadId(
    threadId: selectedThreadId,
    agents: agents,
    threads: threads,
  );
  final root = threads
      .where((thread) => thread.id == rootId && thread.isRoot)
      .firstOrNull;
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
    workspace = AgentWorkspaceView(
      thread: thread,
      rootThread: root,
      syncState: session == null
          ? AgentWorkspaceSyncState.idle
          : _sessionSyncState(session),
      loadError: session?.sync.phase == DomainSyncPhase.failed
          ? session?.sync.errorMessage
          : null,
      todo: session?.workspace?.todo,
      runtime: session?.runtime ?? _emptyRuntime,
      turn: session?.activeTurn,
      lastTurn: session?.workspace?.lastTurn,
      activeInteraction: primaryInteraction(session?.interactions ?? const []),
      composer: threadComposer,
      composerMode: thread.isAgent
          ? AgentComposerMode.runtimeDriven
          : AgentComposerMode.editable,
      accounts: accounts,
      modeModelRoutes: canonical?.modeModelRoutes ?? const [],
      roles: canonical?.roles ?? const [],
      agents: AgentDirectoryQueries.forRoot(
        rootThreadId: rootId,
        agents: agents,
        threads: threads,
      ),
    );
  }

  return StudioDriverFacts(
    timeline: _timelineFacts(timeline, selectedThreadId),
    timelineScroll: _timelineScrollFacts(timeline, selectedThreadId),
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
    sidebarWidth: canonical?.state.value?.general.sidebarWidth,
    modelCatalogRevision: settings.modelCatalogRevision,
    modeModelRoutes: canonical?.modeModelRoutes ?? const [],
    roles: canonical?.roles ?? const [],
    accounts: accounts,
    acpAccounts: canonical?.acpAccounts ?? const [],
    accountTemplates: [
      for (final template in settings.accountCatalog.templates) template.id,
    ],
    acpAuth: client.acpAuth.state.value ?? const AcpAuthSnapshotView.empty(),
    // 单一来源：canonical 观察的加载事实，不由 revision 或空快照推断。
    acpAuthLoaded: client.acpAuth.state.loaded,
    commands: settings.commands.values.toList(growable: false),
    settingsReady: canonical?.state.value != null,
    persistence:
        client.persistence.state.persistence ??
        const PersistenceStateSnapshot.ready(),
    recoveryIssues: client.recovery.state.value?.values ?? const [],
    project: project,
    workspace: workspace,
    bots: _botsFacts(client),
    acpInstall: _acpInstallFacts(client),
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

/// 当前展示代次的只读事实。
///
/// 它只在请求时同步读取 owner 的当前 lease 与 stock controller 的消息集合，序列化后不保留
/// 任何投影；切换 Thread／代次后不会继续抓住旧正文（design/26 §26.9）。
TimelineDisplayFacts? _timelineFacts(
  TimelineSessionOwner owner,
  String? threadId,
) {
  if (threadId == null) return null;
  final view = owner.source.value;
  if (view == null || view.threadId != threadId) return null;
  final lease = owner.lease(threadId);
  return TimelineDisplayFacts(
    threadId: view.threadId,
    generation: lease?.generation ?? view.generation,
    ready: lease != null,
    mode: view.mode,
    connection: view.connection,
    appliedVersion: lease?.appliedVersion,
    olderCursor: view.olderCursor,
    hasOlder: view.hasOlder,
    loadingOlder: view.isLoadingOlder,
    olderError: view.olderError?.toString(),
    olderErrorCode: switch (view.olderError) {
      StudioFailure(:final code) => code,
      _ => null,
    },
    hasNewOutput: view.hasNewOutput,
    preparingLive: view.isPreparingLive,
    items: [
      for (final payload in lease?.payloads ?? const <TimelineMessagePayload>[])
        _timelineItemFacts(payload),
    ],
    presentationItems: [
      for (final message in lease?.controller.messages ?? const <Message>[])
        if (timelinePresentationOf(message) case final item?)
          TimelinePresentationFacts(
            id: item.id,
            kind: item.kind.name,
            ordinal: item.position.$1,
            memberIds: item.memberIds,
            visibleMemberIds: item.visibleMemberIds,
            skillPairs: {
              for (final id in item.visibleMemberIds)
                id: ?item.pairedToolId(id),
            },
            expanded: item.expanded,
            activeCount: item.activeCount,
            issueCount: item.issueCount,
          ),
    ],
  );
}

/// 只读滚动几何：每次诊断请求**现场**读当前展示 lease 实测挂载的标准 controller。
///
/// 不消费任何通知快照、不缓存上一代几何：`ScrollEndNotification` 与 activity/notifier 的
/// 提交不同步，缓存会在没有新几何事件时永久过期（design/26 §26.9）。
TimelineScrollDiagnostic? _timelineScrollFacts(
  TimelineSessionOwner owner,
  String? threadId,
) {
  if (threadId == null) return null;
  final lease = owner.lease(threadId);
  if (lease == null || lease.isRetired) return null;
  final controller = lease.scrollController;
  final position = controller.hasClients ? controller.position : null;
  final mounted = position != null && position.hasContentDimensions;
  return TimelineScrollDiagnostic(
    threadId: lease.threadId,
    generation: lease.generation,
    pixels: mounted ? position.pixels : null,
    minScrollExtent: mounted ? position.minScrollExtent : null,
    maxScrollExtent: mounted ? position.maxScrollExtent : null,
    viewportDimension: mounted ? position.viewportDimension : null,
    extentBefore: mounted ? position.extentBefore : null,
    extentAfter: mounted ? position.extentAfter : null,
    atLiveEdge: mounted && position.pixels <= 0.5,
    isScrolling: mounted && position.isScrollingNotifier.value,
  );
}

TimelineItemFacts _timelineItemFacts(TimelineMessagePayload payload) {
  final item = payload.item;
  final tool = item.tool;
  final userInput = tool?.userInput ?? item.tool?.userInput;
  // 与时间线同一归属规则：只有 `plan_submit` 发起的调用才是计划确认，
  // 普通问答即使带保留的问题 ID 也必须报告为普通问答。
  final receipt = ownsPlanConfirmation(tool?.name)
      ? userInput?.planReceipt
      : null;
  return TimelineItemFacts(
    id: item.id,
    ordinal: item.ordinal,
    revision: item.revision,
    saved: payload.saved,
    terminal: payload.terminal,
    omittedBytes: payload.omittedBytes,
    kind: item.kind.name,
    status: item.status,
    text: item.text,
    channel: switch (item.state) {
      ThreadTextItemStateView(:final channel) => channel,
      _ => null,
    },
    details: [
      for (final detail in payload.details)
        TimelineDetailFacts(
          field: StudioDriverKeyValues.timelineDetailField(detail.field),
          revision: detail.revision,
          totalBytes: detail.totalBytes,
          previewBytes: detail.previewBytes,
        ),
    ],
    attachments: [
      for (final attachment in item.attachments)
        TimelineAttachmentFacts(
          id: attachment.id,
          modality: attachment.modality.name,
          filename: attachment.filename ?? '',
          byteSize: attachment.byteSize,
        ),
      // 可空工具附件的空集合必须带元素类型：无上下文的 `const []` 会让
      // `??` 的 LUB 退化成 `List<dynamic>`，元素随之变成 dynamic，`modality.name`
      // 就按实例查找 `AttachmentModalityView` 而抛 NoSuchMethodError。
      for (final attachment
          in tool?.attachments ?? const <ThreadAttachmentView>[])
        TimelineAttachmentFacts(
          id: attachment.id,
          modality: attachment.modality.name,
          filename: attachment.filename ?? '',
          byteSize: attachment.byteSize,
          source: 'tool',
        ),
    ],
    tool: tool == null
        ? null
        : TimelineToolFacts(
            name: tool.name,
            status: item.status,
            callId: tool.callId ?? tool.toolCallId,
            arguments: tool.arguments,
            result: tool.result,
            progressBytes: _utf8Bytes(tool.result ?? ''),
            itemRevision: item.revision,
            denialReason: tool.denialReason,
            workingDirectory: tool.workingDirectory,
            exitCode: tool.exitCode,
            attachments: [
              for (final attachment in tool.attachments)
                TimelineAttachmentFacts(
                  id: attachment.id,
                  modality: attachment.modality.name,
                  filename: attachment.filename ?? '',
                  byteSize: attachment.byteSize,
                ),
            ],
          ),
    userInput: userInput == null
        ? null
        : TimelineUserInputFacts(
            interactionId: userInput.interactionId,
            state: switch (userInput.state) {
              PendingThreadToolUserInputView() => 'pending',
              ResolvedThreadToolUserInputView() => 'resolved',
              CancelledThreadToolUserInputView() => 'cancelled',
            },
            isPlanConfirmation: receipt != null,
            planDecision: receipt?.decision.name,
          ),
  );
}

int _utf8Bytes(String text) => utf8.encode(text).length;

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
  counts.add(client.acpAuth.state.sync);
  counts.add(client.project.state.projectSync);
  counts.add(client.project.state.agentSync);
  counts.add(client.threadDirectory.state.sync);
  counts.add(client.recovery.state.sync);
  counts.add(client.mcp.state.sync);
  counts.add(client.lsp.state.sync);
  counts.add(client.modeCatalog.state.sync);
  counts.add(client.accountUsage.state.sync);
  counts.add(client.updater.state.sync);
  counts.add(client.persistence.state.stateSync);
  counts.add(client.persistence.state.queueSync);
  counts.add(client.bots.state.sync);
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
    'accountUsage': client.accountUsage.state.revision,
    'persistence': client.persistence.state.stateRevision,
    'persistenceQueue': client.persistence.state.queue?.revision,
    'agentProfiles': settings.agentProfiles?.revision,
    'acpAuth': client.acpAuth.state.revision,
    'bots': client.bots.state.revision,
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
  modelId: '',
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

StudioDriverBotsFacts? _botsFacts(AnyworkClient client) {
  final clock = client.bots.state;
  final snapshot = clock.value;
  if (!clock.loaded && snapshot == null) return null;
  final bots = snapshot?.bots ?? const <BotSnapshot>[];
  String connectionKind(BotConnectionState state) => switch (state) {
    BotConnectionDisabled() => 'disabled',
    BotConnectionConnecting() => 'connecting',
    BotConnectionConnected() => 'connected',
    BotConnectionReconnecting() => 'reconnecting',
    BotConnectionFailed() => 'failed',
  };
  String credentialKind(BotCredentialAvailability value) => value.name;
  String? pendingKind(BotCredentialOperation value) => switch (value) {
    BotCredentialOperationIdle() => null,
    BotCredentialOperationPreparing() => 'preparing',
    BotCredentialOperationCommitUncertain() => 'commitUncertain',
    BotCredentialOperationCleanupPending() => 'cleanupPending',
  };
  bool? configCommitted(BotCredentialOperation value) => switch (value) {
    BotCredentialOperationCleanupPending(:final configCommitted) =>
      configCommitted,
    _ => null,
  };
  String? registrationKind(BotRegistrationStatus? status) => switch (status) {
    null || BotRegistrationIdle() => null,
    BotRegistrationPreparing() => 'preparing',
    BotRegistrationWaiting() => 'waiting',
    BotRegistrationSlowDown() => 'slowDown',
    BotRegistrationCompleted() => 'completed',
    BotRegistrationCommitting() => 'committing',
    BotRegistrationDenied() => 'denied',
    BotRegistrationExpired() => 'expired',
    BotRegistrationCancelled() => 'cancelled',
    BotRegistrationFailed() => 'failed',
  };
  return StudioDriverBotsFacts(
    revision: snapshot?.revision ?? clock.revision,
    bots: [
      for (final bot in bots)
        StudioDriverBotFacts(
          id: bot.id,
          name: bot.name,
          enabled: bot.enabled,
          credential: credentialKind(bot.credential),
          connectionKind: connectionKind(bot.connection),
          pendingKind: pendingKind(bot.credentialOperation),
          configCommitted: configCommitted(bot.credentialOperation),
          configRevision: bot.configRevision,
          trustedUserCount: bot.trustedOpenIds.length,
          trustedGroupCount: bot.trustedChatIds.length,
          pairingCount: bot.pairing.length,
          canChangeProject: bot.canChangeProject,
          canChangeAppId: bot.canChangeAppId,
        ),
    ],
    pending: [
      for (final pending in snapshot?.pendingCredentialOperations ?? const [])
        StudioDriverPendingCredentialFacts(
          botId: pending.botId,
          kind: pendingKind(pending.credentialOperation) ?? 'idle',
          configCommitted: configCommitted(pending.credentialOperation),
        ),
    ],
    registrationAttemptId: snapshot?.registration?.attemptId,
    registrationKind: registrationKind(snapshot?.registration?.status),
    registrationBotId: switch (snapshot?.registration?.status) {
      BotRegistrationCommitting(:final botId) => botId,
      _ => null,
    },
    completedBotId: snapshot?.registration?.completedBotId,
  );
}

/// `acpInstall` 的只读取证：阶段 token 由 typed 状态映射，不做字符串解析。
///
/// 未加载时返回 null（不能把空快照当成“未准备”的事实）；loaded 但 revision 0
/// 仍然如实给出事实，Driver 需要的正是 rev0 也提交观察的证据。
StudioDriverAcpInstallFacts? _acpInstallFacts(AnyworkClient client) {
  final clock = client.acpInstall.state;
  final snapshot = clock.value;
  if (!clock.loaded && snapshot == null) return null;
  String phase(AcpInstallStateView state) => switch (state) {
    AcpInstallIdleState() => 'idle',
    AcpResolvingState() => 'resolving',
    AcpWaitingForAssetState() => 'waiting',
    AcpDownloadingState() => 'downloading',
    AcpInstallVerifyingState() => 'verifying',
    AcpExtractingState() => 'extracting',
    AcpPublishingState() => 'publishing',
    AcpInstallClosingState() => 'closing',
    AcpInstallReadyState() => 'ready',
    AcpInstallCancellingState() => 'cancelling',
    AcpInstallCancelledState() => 'cancelled',
    AcpInstallFailedState() => 'failed',
  };
  String stage(AcpInstallStageView value) => value.name;
  // 显式给出空集合的元素类型：`?? const []` 会把循环变量退化成 dynamic，
  // 随后 `code.name` 这类 extension 成员会在运行期抛 NoSuchMethodError。
  final installations =
      snapshot?.installations ?? const <AcpInstallEntryView>[];
  return StudioDriverAcpInstallFacts(
    loaded: clock.loaded,
    revision: snapshot?.revision ?? clock.revision,
    installations: [
      for (final entry in installations)
        StudioDriverAcpInstallEntryFacts(
          provider: entry.provider.wire,
          phase: phase(entry.state),
          operationId: entry.state.operationId,
          stage: entry.state.stage == null ? null : stage(entry.state.stage!),
          completedBytes: entry.state.progress?.completedBytes ?? 0,
          totalBytes: entry.state.progress?.totalBytes,
          bytesPerSecond: entry.state.progress?.effectiveBytesPerSecond,
          retryCount: entry.state.retryCount,
          version: entry.state.release?.version,
          target: entry.state.release?.target,
          archiveUrl: entry.state.release?.archiveUrl,
          sha256: entry.state.release?.sha256,
          hasPublisherChecksum:
              entry.state.release?.hasPublisherChecksum ?? false,
          program: entry.state.server?.program,
          reused: entry.state.server?.reused ?? false,
          failureCode: entry.state.failure?.code.name,
          failureRetryable: entry.state.failure?.retryable,
        ),
    ],
  );
}
