import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../domain/models/agent_workspace_view.dart';
import '../features/conversation/timeline/state/timeline_entry.dart';
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
  required AccountsRepository accountsRepository,
  required ModelsRepository modelsRepository,
  required AccountUsageRepository usageRepository,
  required AcpService acpService,
  Map<AccountIdentity, AccountResource<AccountDetails>> Function()?
  observedAccountDetails,
}) {
  StudioDriverState.bindSnapshotQuery(
    () => queryStudioDriverFacts(
      client,
      timeline: timeline,
      accountsRepository: accountsRepository,
      modelsRepository: modelsRepository,
      usageRepository: usageRepository,
      acpService: acpService,
      observedAccountDetails: observedAccountDetails?.call() ?? const {},
    ),
  );
}

/// Read immutable current mirrors synchronously. No business projection is
/// retained by Driver, and owner existence never depends on a account family.
StudioDriverFacts queryStudioDriverFacts(
  AnyworkClient client, {
  required TimelineSessionOwner timeline,
  required AccountsRepository accountsRepository,
  required ModelsRepository modelsRepository,
  required AccountUsageRepository usageRepository,
  required AcpService acpService,
  Map<AccountIdentity, AccountResource<AccountDetails>> observedAccountDetails =
      const {},
}) {
  final selection = client.selection.state;
  final directory = client.threadDirectory.state;
  final threads = [...directory.window.threads, ...directory.overlayThreads];
  final settings = client.settings.state;
  final canonical = settings.canonical;
  final summaries = accountsRepository.state.value;
  final models = modelsRepository.state.value;
  final accounts = modelSelectionAccounts(summaries, models);
  final projects = client.project.state;
  final project = projectById(
    projects.projects?.values.toList(growable: false) ??
        const <StudioProject>[],
    selection.selectedProjectId,
  );
  final selectedThreadId = selection.selectedThreadId;
  final session = selectedThreadId == null || selection.needsOpen
      ? null
      : client.conversations.sessionState(selectedThreadId);
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
      : client.drafts.existingComposer(selectedThreadId)?.state ??
            const ComposerThreadState.idle();
  final newThreadComposer = _newThreadComposer(client, selection);
  final projectDraft = client.drafts.startDraft.state.forProject(
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
      for (final state in client.conversations.sessionStates)
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
    modeModelRoutes: canonical?.modeModelRoutes ?? const [],
    roles: canonical?.roles ?? const [],
    accounts: accounts,
    accountSummaries: summaries,
    modelDirectory: models,
    accountUsage: usageRepository.state.value,
    accountUsageQueryFailures: usageRepository.queryFailures.value,
    accountDetails: observedAccountDetails,
    accountTemplates: [
      for (final template in summaries.templates.templates) template.id,
    ],
    acpAuth: acpService.auth.value.value ?? const AcpAuthSnapshotView.empty(),
    acpAuthResource: acpService.auth.value,
    acpInstallResource: acpService.install.value,
    // 单一来源：canonical 观察的加载事实，不由 revision 或空快照推断。
    acpAuthLoaded: acpService.auth.value.loaded,
    commands: settings.commands.values.toList(growable: false),
    settingsReady: canonical?.state.value != null,
    persistence:
        client.persistence.state.persistence ??
        const PersistenceStateSnapshot.ready(),
    recoveryIssues: client.recovery.state.value?.values ?? const [],
    project: project,
    workspace: workspace,
    bots: _botsFacts(client),
    acpInstall: _acpInstallFacts(acpService),
  );
}

/// Diagnostics read an existing registry and existing domain mirrors. Reading
/// this endpoint never changes topic demand, even if no Widget observes it.
Map<String, Object?> studioDriverTopicDiagnostics(
  AnyworkClient client, {
  required AccountsRepository accountsRepository,
  required ModelsRepository modelsRepository,
  required AccountUsageRepository usageRepository,
  required AcpService acpService,
}) {
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
    // Domain observations expose business resource stamps, not transport sync
    // counters. Reading these surfaces acquires no display/network demand.
    'accountDomains': {
      'summaries': studioDriverSummariesJson(accountsRepository.state.value),
      'catalogs': [
        for (final entry in modelsRepository.state.value.accounts.entries)
          {
            'accountId': entry.key.accountId,
            ...studioDriverResourceJson(entry.value),
          },
      ],
      'configurations': [
        for (final entry in modelsRepository.state.value.configurations.entries)
          {
            'accountId': entry.key.accountId,
            ...studioDriverResourceJson(entry.value),
          },
      ],
      'usage': studioDriverResourceJson(usageRepository.state.value),
      'acpAuth': studioDriverResourceJson(acpService.auth.value),
      'acpInstall': studioDriverResourceJson(acpService.install.value),
    },
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
    olderErrorCorrelationId: switch (view.olderError) {
      StudioFailure(:final correlationId) => correlationId,
      _ => null,
    },
    hasNewOutput: view.hasNewOutput,
    preparingLive: view.isPreparingLive,
    items: [
      for (final item in lease?.items ?? const <ConversationItem>[])
        _timelineItemFacts(item),
    ],
    presentationItems: [
      for (final message in lease?.controller.messages ?? const <Message>[])
        if (timelineEntryOf(message) case final item?
            when message.id == item.id)
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

TimelineItemFacts _timelineItemFacts(ConversationItem item) {
  final descriptor = item.descriptor;
  final tool = descriptor is ConversationToolDescriptor ? descriptor : null;
  final userInput = item.userInput;
  // The SDK helper owns plan attribution and secret/redacted answer filtering.
  final receipt = item.planReceipt;
  final attachments = timelineAttachments(item);
  final result = item.fieldFor(const ThreadToolResultFieldView())?.text;
  final status = _itemStatus(descriptor);
  return TimelineItemFacts(
    id: item.id,
    ordinal: item.header.ordinal,
    revision: item.revision,
    saved: item.saved,
    terminal: item.terminal,
    omittedBytes: item.omittedBytes,
    kind: _itemKind(descriptor),
    status: status,
    text: _itemText(item),
    channel: switch (descriptor) {
      ConversationTextDescriptor(:final channel) => channel,
      _ => null,
    },
    details: [
      for (final detail in item.details)
        TimelineDetailFacts(
          field: StudioDriverKeyValues.timelineDetailField(detail.field),
          revision: detail.revision,
          totalBytes: detail.totalBytes,
          previewBytes: detail.previewBytes,
        ),
    ],
    attachments: [
      for (final attachment in attachments)
        TimelineAttachmentFacts(
          id: attachment.id,
          modality: attachment.modality.name,
          filename: attachment.filename ?? '',
          byteSize: attachment.byteSize,
          source: tool == null ? null : 'tool',
        ),
    ],
    tool: tool == null
        ? null
        : TimelineToolFacts(
            name: tool.invocation.name,
            status: status,
            callId: tool.invocation.callId ?? tool.invocation.toolCallId,
            arguments:
                item.fieldFor(const ThreadToolArgumentsFieldView())?.text ?? '',
            result: result,
            progressBytes: _utf8Bytes(result ?? ''),
            itemRevision: item.revision,
            denialReason: switch (tool.state) {
              ConversationToolDenied(:final reason) => reason,
              _ => null,
            },
            workingDirectory: tool.invocation.workingDirectory,
            exitCode: switch (tool.state) {
              ConversationToolSucceeded(:final output) => output.exitCode,
              ConversationToolFailed(:final output) => output?.exitCode,
              _ => null,
            },
            attachments: [
              for (final attachment in attachments)
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
              ConversationUserInputPending() => 'pending',
              ConversationUserInputResolved() => 'resolved',
              ConversationUserInputCancelled() => 'cancelled',
            },
            isPlanConfirmation: receipt != null,
            planDecision: receipt?.decision.name,
          ),
  );
}

int _utf8Bytes(String text) => utf8.encode(text).length;

// Diagnostic labels retain the journey vocabulary, not a retired read model.
// Every value is derived on demand from this exact typed item, without I/O.
String _itemKind(ConversationDescriptor descriptor) => switch (descriptor) {
  ConversationTextDescriptor(:final channel) => switch (channel) {
    ThreadTextChannel.user => 'userMessage',
    ThreadTextChannel.parentAgent => 'parentAgentMessage',
    ThreadTextChannel.commentary ||
    ThreadTextChannel.finalAnswer => 'agentMessage',
  },
  ConversationThinkingDescriptor() => 'reasoning',
  ConversationToolDescriptor() => 'toolCall',
  ConversationAgentDescriptor() => 'agent',
  ConversationTurnDescriptor() => 'turn',
  ConversationInferenceDescriptor() => 'inference',
  ConversationSkillDescriptor() => 'skill',
  ConversationRawDescriptor() => 'raw',
  ConversationFileDescriptor() => 'file',
  ConversationContextCompactionDescriptor() => 'contextCompaction',
};

String _itemStatus(ConversationDescriptor descriptor) => switch (descriptor) {
  ConversationTextDescriptor(:final lifecycle) ||
  ConversationThinkingDescriptor(:final lifecycle) => lifecycle.status,
  ConversationToolDescriptor(:final state) => switch (state) {
    ConversationToolQueued() => 'queued',
    ConversationToolCancelling() => 'cancelling',
    ConversationToolInterrupted() => 'interrupted',
    ConversationToolStarted() => 'started',
    ConversationToolStreaming() => 'streaming',
    ConversationToolAwaitingApproval() => 'awaitingApproval',
    ConversationToolApproved() => 'approved',
    ConversationToolRunning() => 'running',
    ConversationToolSucceeded() => 'succeeded',
    ConversationToolFailed() => 'failed',
    ConversationToolDenied() => 'denied',
    ConversationToolCancelled() => 'cancelled',
  },
  ConversationAgentDescriptor(:final value) => switch (value.lifecycle) {
    QueuedThreadAgentView() => 'queued',
    RunningThreadAgentView() => 'running',
    SucceededThreadAgentView() => 'succeeded',
    DeniedThreadAgentView() => 'denied',
    CancelledThreadAgentView() => 'cancelled',
    FailedThreadAgentView() => 'failed',
  },
  ConversationTurnDescriptor(:final value) => value.state.status.name,
  ConversationInferenceDescriptor(:final value) => switch (value.lifecycle) {
    RunningThreadInferenceView() => 'running',
    CompletedThreadInferenceView() => 'completed',
    FailedThreadInferenceView() => 'failed',
    CancelledThreadInferenceView() => 'cancelled',
  },
  ConversationSkillDescriptor() ||
  ConversationFileDescriptor() ||
  ConversationRawDescriptor() ||
  ConversationContextCompactionDescriptor() => 'completed',
};

String _itemText(ConversationItem item) => switch (item.descriptor) {
  ConversationTextDescriptor() => timelineText(item),
  ConversationRawDescriptor(:final notice) => notice,
  ConversationAgentDescriptor(:final value) => switch (value.lifecycle) {
    SucceededThreadAgentView(:final summary) => summary,
    DeniedThreadAgentView(:final reason) ||
    CancelledThreadAgentView(:final reason) => reason,
    FailedThreadAgentView(:final error) => error,
    QueuedThreadAgentView() || RunningThreadAgentView() => '',
  },
  ConversationSkillDescriptor(:final value) => value.name,
  _ => '',
};

ComposerThreadState _newThreadComposer(
  AnyworkClient client,
  SelectionStoreState selection,
) {
  final projectId = selection.selectedProjectId;
  final draft = client.drafts.startDraft.state;
  final text = draft.forProject(projectId).text;
  final attachments = projectId == null
      ? const ComposerThreadState.idle()
      : client.drafts.attachments.state.newThread(projectId);
  final submitting = draft.submitting || attachments.isSubmissionPending;
  if (!submitting && attachments is FailedComposerThreadState) {
    return FailedComposerThreadState(
      error: attachments.failure,
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
  counts.add(settings.agentProfilesSync);
  counts.add(client.project.state.projectSync);
  counts.add(client.project.state.agentSync);
  counts.add(client.threadDirectory.state.sync);
  counts.add(client.recovery.state.sync);
  counts.add(client.mcp.state.sync);
  counts.add(client.lsp.state.sync);
  counts.add(client.modeCatalog.state.sync);
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
  for (final session in client.conversations.sessionStates) {
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
      : client.conversations.sessionState(selected);
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
    'recovery': client.recovery.state.revision,
    'mcp': client.mcp.state.revision,
    'lsp': client.lsp.state.revision,
    'threadModeCatalog': client.modeCatalog.state.revision,
    'persistence': client.persistence.state.stateRevision,
    'persistenceQueue': client.persistence.state.queue?.revision,
    'agentProfiles': settings.agentProfiles?.revision,
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
StudioDriverAcpInstallFacts? _acpInstallFacts(AcpService service) {
  final clock = service.install.value;
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
    revision: snapshot?.revision ?? clock.stamp?.revision ?? 0,
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
