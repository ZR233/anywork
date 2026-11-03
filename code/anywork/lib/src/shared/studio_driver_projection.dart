import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../domain/models/agent_workspace_view.dart';
import '../features/conversation/timeline/state/chat_item_presentation.dart';
import '../features/conversation/timeline/state/timeline_display_diagnostics.dart';
import '../features/conversation/timeline/state/timeline_display_unit.dart';
import '../features/conversation/timeline/state/chat_payload_reading.dart';
import '../features/conversation/interactions/state/interaction_payload.dart';
import '../features/shell/shell_view.dart' show projectById;
import '../presentation/view_models/timeline_session_owner.dart';
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
  final rootThreadsById = <String, StudioThread>{};
  var directoryHasMore = false;
  for (final frame in client.threadDirectory.observedWindows) {
    directoryHasMore = directoryHasMore || frame.nextCursor != null;
    for (final thread in frame.threads) {
      if (thread.isRoot) rootThreadsById.putIfAbsent(thread.id, () => thread);
    }
  }
  final rootThreads = rootThreadsById.values.toList(growable: false);
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
  final visibleThreadId = client.conversations.visibleThreadId.value;
  // Hidden pages can still observe the selected background execution; visible
  // bot pages always use their own destination rather than sidebar selection.
  final presentationThreadId = timeline.source.value?.threadId;
  final observedThreadId =
      presentationThreadId ?? visibleThreadId ?? selectedThreadId;
  final session =
      observedThreadId == null ||
          (presentationThreadId == null &&
              visibleThreadId == null &&
              selection.needsOpen)
      ? null
      : client.conversations.sessionState(observedThreadId);
  final thread =
      client.findThread(observedThreadId ?? '') ?? session?.workspace?.thread;
  final agents = projects.agents?.values ?? const <StudioAgentView>[];
  final rootId = thread?.effectiveRootThreadId;
  final root = rootId == null
      ? null
      : client.findThread(rootId) ?? (thread?.id == rootId ? thread : null);
  final observedThreadsById = <String, StudioThread>{
    ...rootThreadsById,
    ?thread?.id: ?thread,
    ?root?.id: ?root,
  };
  final observedThreads = observedThreadsById.values.toList(growable: false);
  final threadComposer = observedThreadId == null
      ? const ComposerThreadState.idle()
      : client.drafts.existingComposer(observedThreadId)?.state ??
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
      modelRoute: session?.modelRoute,
      turn: session?.activeTurn,
      lastTurn: session?.workspace?.lastTurn,
      activeInteraction: activePendingInteraction(
        session?.interactions ?? const [],
      ),
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
        threads: observedThreads,
      ),
    );
  }

  return StudioDriverFacts(
    timeline: _timelineFacts(timeline, presentationThreadId),
    timelineScroll: _timelineScrollFacts(timeline, presentationThreadId),
    workspacesByThread: {
      for (final state in client.conversations.sessionStates)
        if (state.workspace case final workspace?)
          state.threadId: workspace.copyWith(
            thread: client.findThread(state.threadId) ?? workspace.thread,
          ),
    },
    rootThreads: rootThreads,
    directoryHasMore: directoryHasMore,
    selectedProjectId: selection.selectedProjectId,
    selectedThreadId: selectedThreadId,
    visibleThreadId: visibleThreadId,
    presentationThreadId: presentationThreadId,
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
  required TimelineSessionOwner timeline,
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
    'projectionRevisions': _projectionRevisions(
      client,
      timeline.source.value?.threadId,
    ),
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
    loadedCount: lease?.loadedCount,
    olderCursor: lease?.olderCursor,
    hasOlder: lease?.hasOlder ?? false,
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
    appliedSets: lease?.appliedSets,
    appliedPrepends: lease?.appliedPrepends,
    appliedAppends: lease?.appliedAppends,
    current: _currentDisplayJson(lease?.currentDisplay),
    groups: [
      for (final display
          in lease?.groupDisplays ?? const <TimelineGroupDisplay>[])
        {
          'unitId': display.unitId,
          'expanded': display.expanded,
          'completionAnchor': display.completionAnchor,
          'before': display.before,
          'loading': display.loading,
          'error': display.error?.toString(),
          'items': StudioDriverState.timelineItemsJson([
            for (final atom in display.atoms) _atomFacts(atom),
          ]),
        },
    ],
    firstContentLayout: switch (lease?.firstContentLayout) {
      final layout? => TimelineContentLayoutFacts(
        selectionId: layout.selectionId,
        generation: layout.generation,
        itemId: layout.itemId,
        selectionStartedMicros: layout.selectionStartedMicros,
        layoutCompletedMicros: layout.layoutCompletedMicros,
      ),
      null => null,
    },
    children: [
      if (lease != null)
        for (final display in lease.childrenDisplays)
          TimelineChildrenFacts(
            parentId: display.parentId,
            generation: display.generation,
            ready: display.ready,
            olderCursor: display.olderCursor,
            loadingOlder: display.loadingOlder,
            error: display.error?.toString(),
            appliedSets: display.appliedSets,
            appliedPrepends: display.appliedPrepends,
            appliedAppends: display.appliedAppends,
            items: [
              for (final message in display.messages)
                _timelineMessageFacts(message),
            ],
          ),
    ],
    items: [
      for (final message in lease?.controller.messages ?? const <Message>[])
        _timelineMessageFacts(message),
    ],
  );
}

/// Serializes only already mounted, admitted resources. No getter opens a scope or performs IO.
Map<String, Object?>? _currentDisplayJson(TimelineCurrentDisplay? display) {
  if (display == null || !display.isCurrent) return null;
  return {
    'turnId': display.turnId,
    'activityId': display.activityId,
    'expanded': display.expanded,
    'collections': [
      for (final collection in display.collections)
        if (collection.isCurrent)
          {
            'databaseId': collection.reference.databaseId,
            'collection': collection.reference.collection,
            'revision': collection.reference.revision,
            'generation': collection.generation,
            'expanded': collection.expanded,
            'loading': collection.loading,
            'error': collection.error?.toString(),
            'ready': collection.page != null,
            'continuation': collection.page?.continuation,
            'entries': [
              for (final entry
                  in collection.page?.entries ??
                      const <CurrentCollectionEntry>[])
                {
                  'id': entry.id,
                  'position': entry.position,
                  'payload': switch (entry.payload) {
                    InlinePayload(:final bytes) => {
                      'kind': 'inline',
                      'byteLength': bytes.length,
                      'base64': base64Encode(bytes),
                    },
                    DeferredPayload(:final reference, :final byteLength) => {
                      'kind': 'deferred',
                      'byteLength': byteLength,
                      'reference': _currentReferenceJson(reference),
                    },
                  },
                },
            ],
          },
    ],
    'windows': [
      for (final observation in display.windows)
        {
          'id': observation.id,
          'reference': _currentReferenceJson(observation.reference),
          'offset': observation.offset,
          'error': observation.error?.toString(),
          'window': switch (observation.window) {
            final window? => {
              'offset': window.offset,
              'byteLength': window.bytes.length,
              'base64': base64Encode(window.bytes),
              'generation': window.generation,
              'availableThrough': window.availableThrough,
              'sealed': window.sealed,
            },
            null => null,
          },
        },
    ],
  };
}

Map<String, Object?> _currentReferenceJson(ContentRef reference) => {
  'databaseId': reference.databaseId,
  'target': switch (reference.target) {
    ItemPayloadTarget(:final itemId) => {
      'kind': 'itemPayload',
      'itemId': itemId,
    },
    BodyContentTarget(:final owner, :final key) => {
      'kind': 'body',
      'key': key,
      'owner': switch (owner) {
        ItemContentOwner(:final itemId) => {'kind': 'item', 'itemId': itemId},
        CurrentContentOwner(:final domain, :final id, :final revision) => {
          'kind': 'current',
          'domain': domain,
          'id': id,
          'revision': revision,
        },
      },
    },
  },
};

TimelineItemFacts _timelineMessageFacts(Message message) {
  final unit =
      message.metadata?[timelineDisplayUnitKey] as TimelineDisplayUnit?;
  if (unit?.kind == TimelineUnitKind.work) {
    return TimelineItemFacts(
      id: message.id,
      sealedAt: unit!.finishedAt,
      compatibility: 'current',
      omittedBytes: null,
      kind: 'workGroup',
      status: unit.live ? 'running' : 'completed',
      text: '',
      channel: null,
      atomic: {
        'source': _sourceFacts(unit.source),
        'firstOrder': unit.firstOrder,
        'lastOrder': unit.lastOrder,
        'completionThrough': unit.completionThrough,
        'loadedCount': unit.memberCount,
        'memberIds': unit.members.map((atom) => atom.id).toList(),
      },
    );
  }
  final item = chatItemPresentationOf(message);
  if (item != null) return _timelineItemFacts(item);
  return TimelineItemFacts(
    id: message.id,
    sealedAt: null,
    compatibility: 'unknown',
    omittedBytes: null,
    kind: 'unknown',
    status: 'unknown',
    text: '',
    channel: null,
    diagnostic: 'Message has no current chat metadata',
  );
}

TimelineItemFacts _atomFacts(ChatAtom atom) {
  if (atom.payload != null) {
    return _timelineItemFacts(ChatItemPresentation.decode(atom));
  }
  return TimelineItemFacts(
    id: atom.id,
    sealedAt: atom.finishedAt,
    compatibility: 'current',
    omittedBytes: null,
    kind: atom.kind.name,
    status: switch (atom.lifecycle) {
      ActiveChatAtom() => 'running',
      TerminalChatAtom(:final outcome) => outcome.name,
    },
    text: '',
    channel: atom.textChannel?.name,
    atomic: {
      'source': _sourceFacts(atom.source),
      'completionSeq': atom.completionSeq,
      'sourceOrder': atom.sourceOrder,
      'completionItemId': atom.completionItemId,
      'toolCallId': atom.tool?.callId,
      'toolName': atom.tool?.name,
    },
  );
}

Map<String, Object?> _sourceFacts(ChatSourceId source) => switch (source) {
  ForegroundTurnChatSource(:final turnId) => {
    'kind': 'foregroundTurn',
    'turnId': turnId,
  },
  InputChatSource(:final inputId) => {'kind': 'input', 'inputId': inputId},
  BackgroundResultChatSource(:final messageId) => {
    'kind': 'backgroundResult',
    'messageId': messageId,
  },
  OperationChatSource(:final operationId) => {
    'kind': 'operation',
    'operationId': operationId,
  },
  ReceiptChatSource(:final receiptId) => {
    'kind': 'receipt',
    'receiptId': receiptId,
  },
};

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

TimelineItemFacts _timelineItemFacts(ChatItemPresentation item) {
  try {
    return _loadedItemFacts(item);
  } on FormatException catch (error) {
    // Only the current in-memory presentation is inspected here; no I/O error
    // can be relabelled by this per-item diagnostic boundary.
    return TimelineItemFacts(
      id: item.id,
      sealedAt: _diagnosticUnixSeconds(item.createdAt),
      compatibility: 'malformed',
      omittedBytes: null,
      kind: item.type,
      status: 'unknown',
      text: '',
      channel: null,
      presentationContract: item.presentationContract,
      diagnostic: error.toString(),
    );
  }
}

TimelineItemFacts _loadedItemFacts(ChatItemPresentation item) {
  final data = item.data;
  final outcome = _diagnosticObject(data['outcome']);
  final state = _diagnosticObject(data['state']);
  final userInput = _diagnosticObject(data['userInput']);
  final tool = item.type == 'tool'
      ? switch (item.toolCard) {
          DecodedToolCard(:final value) => value,
          _ => null,
        }
      : null;
  final attachments = [
    for (final attachment in item.attachments)
      TimelineAttachmentFacts(
        id: attachment.id,
        modality: attachment.modality.name,
        filename: attachment.filename ?? '',
        byteSize: attachment.byteSize,
        source: item.type == 'tool' ? 'tool' : null,
      ),
  ];
  final status =
      tool?.statusString ??
      _diagnosticString(outcome?['kind']) ??
      _diagnosticString(state?['kind']) ??
      _diagnosticString(data['decision']) ??
      'unknown';
  return TimelineItemFacts(
    id: item.id,
    atomic: item.atom == null
        ? null
        : {
            'source': _sourceFacts(item.atom!.source),
            'sourceOrder': item.atom!.sourceOrder,
            'completionSeq': item.atom!.completionSeq,
            'completionItemId': item.atom!.completionItemId,
          },
    sealedAt: _diagnosticUnixSeconds(item.createdAt),
    compatibility: item.compatibility.name,
    omittedBytes: item.compatibility == ChatItemCompatibility.current
        ? item.bodies.fold<int>(
            0,
            (bytes, body) =>
                bytes + body.byteLength - (body.inline?.length ?? 0),
          )
        : null,
    payloadByteLength:
        item.byteLength ??
        (item.raw == null ? null : utf8.encode(item.raw!).length),
    kind: item.type,
    status: status,
    text:
        item.inlineText('body') ??
        item.inlineText('plan.document') ??
        _diagnosticString(data['notice']) ??
        '',
    channel: _diagnosticString(data['channel']),
    presentationContract: item.presentationContract,
    diagnostic:
        item.diagnostic ??
        (item.type == 'tool'
            ? switch (item.toolCard) {
                UnavailableToolCard(:final reason) => reason,
                _ => null,
              }
            : null),
    details: [
      for (final body in item.bodies)
        TimelineDetailFacts(
          field: body.key,
          totalBytes: body.byteLength,
          previewBytes: body.inline?.length ?? 0,
          hasReference: body.reference != null,
        ),
    ],
    attachments: attachments,
    tool: tool == null
        ? null
        : TimelineToolFacts(
            name: tool.name,
            status: tool.statusString,
            callId: tool.toolCallId,
            arguments: tool.arguments,
            result: tool.output,
            progressBytes: utf8.encode(tool.output).length,
            presentationContract: tool.presentationContract,
            denialReason: tool.error,
            workingDirectory: tool.workingDirectory,
            exitCode: tool.exitCode,
            attachments: attachments,
          ),
    userInput: switch (userInput) {
      {
        'interactionId': final String id,
        'state': final Map<String, Object?> state,
      }
          when state['kind'] is String =>
        TimelineUserInputFacts(
          interactionId: id,
          state: state['kind']! as String,
          isPlanConfirmation: false,
        ),
      _ => null,
    },
    plan: item.type == 'plan'
        ? switch (data) {
            {
              'interactionId': final String id,
              'decision': final String decision,
            } =>
              TimelinePlanFacts(
                interactionId: id,
                decision: decision,
                documentVersion: data['documentVersion'] is int
                    ? data['documentVersion']! as int
                    : null,
                contentHash: _diagnosticString(data['contentHash']),
                document: item.inlineText('plan.document'),
                feedback: item.inlineText('plan.feedback'),
              ),
            _ => null,
          }
        : null,
  );
}

Map<String, Object?>? _diagnosticObject(Object? value) =>
    value is Map<String, Object?> ? value : null;
String? _diagnosticString(Object? value) => value is String ? value : null;
int? _diagnosticUnixSeconds(DateTime? value) =>
    value == null ? null : value.millisecondsSinceEpoch ~/ 1000;

ComposerThreadState _newThreadComposer(
  AnyworkClient client,
  SelectionStoreState selection,
) {
  final workspaceId = selection.selectedProjectId;
  final draft = client.drafts.startDraft.state;
  final text = draft.forProject(workspaceId).text;
  final attachments = workspaceId == null
      ? const ComposerThreadState.idle()
      : client.drafts.attachments.state.newThread(workspaceId);
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

Map<String, Object?> _projectionRevisions(
  AnyworkClient client,
  String? presentationThreadId,
) {
  final settings = client.settings.state;
  final selection = client.selection.state;
  final visible = client.conversations.visibleThreadId.value;
  final selected =
      presentationThreadId ?? visible ?? selection.selectedThreadId;
  final session =
      selected == null ||
          (presentationThreadId == null &&
              visible == null &&
              selection.needsOpen)
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
    // Directory revisions belong to explicit observation frames. This
    // request-local diagnostic owns no directory demand.
    'threadDirectory': null,
    'presentationThread': session?.workspace?.revision,
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
