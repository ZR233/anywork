import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/updates.dart';
import 'package:anywork_client/workspace.dart';

import '../diagnostics/timeline_diagnostics_json.dart';
import '../features/conversation/state/read_material.dart';
import 'driver_projection.dart';
import 'driver_snapshot.dart';

/// A deliberate Driver whitelist, not generic serialization of domain values.
/// Unknown current material stays null, including unmaterialized identities;
/// historyAttachments keeps its list shape even without a current display.
extension DriverSnapshotJson on DriverSnapshot {
  List<AccountConfiguration>? get configuredAccounts =>
      configuration.projection.sync.phase == ResourceSyncPhase.ready
      ? currentDriverRows(
          configuration.accounts,
          configuration.projection.stamp?.origin,
        )
      : null;

  List<AccountCatalogEntry>? get catalogAccounts =>
      models.projection.sync.phase == ResourceSyncPhase.ready
      ? currentDriverRows(models.accounts, models.projection.stamp?.origin)
      : null;

  Map<String, Object?> toJson() {
    final rootRows = directory?.where((thread) => thread.isRoot).toList();
    final storage = execution?.value?.storage;
    final usage = context?.value?.usage;
    final activity = execution?.value?.activity;
    final publishedPlan = authoring?.value?.plan;
    final configRead = status?.configurationRead;
    final route = configRead?.header?.route;
    final accountId = configRead?.textOf(route?.accountId);
    final modelId = configRead?.textOf(route?.modelId);
    final routedAccount = configuredAccounts
        ?.where((row) => row.accountId == accountId)
        .firstOrNull;
    final routedModel = catalogAccounts
        ?.where((row) => row.accountId == accountId)
        .firstOrNull
        ?.effectiveModels
        .where((model) => model.modelId == modelId)
        .firstOrNull;
    final recoveryRows =
        recovery.projection.sync.phase == ResourceSyncPhase.ready
        ? currentDriverRows(recovery.issues, recovery.projection.stamp?.origin)
        : null;
    return {
      ...display.toJson(),
      'availability': {
        'directory': directory == null ? 'unknown' : 'available',
        'agents': agents == null ? 'unknown' : 'available',
        'agentDirectoryErrorCode': agentDirectoryError?.code.name,
        'bots': bots is DriverBotsValue ? 'available' : 'unknown',
        'botsDependency': switch (bots) {
          DriverBotsUnknown(:final dependency) => dependency,
          _ => null,
        },
      },
      'navigation': {
        'selectedProjectId': selection.projectId,
        'selectedThreadId': selection.threadId,
        'needsOpen': selection.needsOpen,
        'isStartPage': selection.threadId == null,
        'newThreadMode': startDraft?.mode.id,
        'newThreadWorkspaceMode': startDraft?.workspaceMode.name,
        'newThreadComposer': startDraft == null
            ? null
            : draftDiagnostic(
                text: startDraft!.text,
                attachments: startDraft!.attachments,
                submission: startDraft!.submission,
                revision: startDraft!.submissionRevision,
                generation: startDraft!.attachmentGeneration,
              ),
      },
      'sidebarDirectory': {
        'count': rootRows?.length,
        'hasMore': directoryHasMore,
        'ids': rootRows == null ? null : [for (final row in rootRows) row.id],
        'titles': rootRows == null
            ? null
            : {for (final row in rootRows) row.id: row.title},
        'workspaceModes': rootRows == null
            ? null
            : {for (final row in rootRows) row.id: row.workspaceMode.name},
        'workspacePaths': rootRows == null
            ? null
            : {for (final row in rootRows) row.id: row.workspacePath},
      },
      'project': project == null
          ? null
          : {'id': project!.id, 'path': project!.path},
      'workspace': selection.threadId == null
          ? null
          : {
              'threadId': selection.threadId,
              'rootThreadId': rootThreadId,
              'projectId': selection.projectId,
              'title': thread?.title,
              'threadMode': thread?.mode.id,
              // Directory metadata and execution have independent publication order.
              'threadStatus': thread?.status.name,
              'syncState': execution?.sync.phase.name,
              'loadError': execution?.sync.error?.code.name,
              'isBusy': execution?.value == null
                  ? null
                  : switch (execution!.value!.status) {
                      ThreadStatus.queued ||
                      ThreadStatus.running ||
                      ThreadStatus.waitingTool ||
                      ThreadStatus.waitingInteraction ||
                      ThreadStatus.cancelling => true,
                      _ => false,
                    },
              'model': modelId,
              'modelRoute': route == null
                  ? null
                  : {
                      'accountId': accountId,
                      'modelId': modelId,
                      'effort': configRead?.textOf(route.effort),
                      'revision': route.revision,
                      'available': route.available,
                      'unavailableReason': configRead?.textOf(
                        route.unavailableReason,
                      ),
                    },
              'usage': {
                'inputTokens': usage?.promptTokens,
                'outputTokens':
                    metrics?.value?.live?.completionTokens ??
                    metrics?.value?.authoritative?.completionTokens,
                'cacheReadTokens': usage?.cachedPromptTokens,
                'hasIncompleteUsage': usage?.hasIncompleteUsage,
              },
              'modelCapabilities': routedModel == null
                  ? const <String>[]
                  : [
                      for (final input in routedModel.capabilities.input)
                        input.modality.name,
                    ],
              'modelAccount': routedAccount == null || routedModel == null
                  ? null
                  : {
                      'id': routedAccount.accountId,
                      'hasBearerToken': routedAccount.hasBearerToken,
                      'credentialEnv': routedAccount.bearerTokenEnv ?? '',
                    },
              'composer': composer == null
                  ? null
                  : {
                      ...draftDiagnostic(
                        text: composer!.text,
                        attachments: composer!.attachments,
                        submission: composer!.submission,
                        revision: composer!.submissionRevision,
                        generation: composer!.attachmentGeneration,
                      ),
                      'mode': thread == null
                          ? null
                          : thread!.isRoot
                          ? 'editable'
                          : 'runtimeDriven',
                      'lockedByInteraction':
                          execution?.value?.interactions.pending == null
                          ? null
                          : execution!.value!.interactions.pending > 0,
                    },
              'agents': agents == null
                  ? null
                  : [for (final agent in agents!) agentDiagnostic(agent)],
              'historyAttachments': [
                if (display.timeline case final timeline?)
                  for (final item in timeline.items)
                    for (final attachment in item.attachments)
                      attachment.toJson(),
              ],
              'interactionCount': execution?.value?.interactions.pending,
              // ConversationVM is the existing public interaction selection projection.
              // Index refs are not command IDs, titles or unredacted question bodies.
              'activeInteraction': conversation?.currentEditors.length != 1
                  ? null
                  : {
                      'id': conversation!.currentEditors.single.interactionId,
                      'turnId': null,
                      'kind': null,
                      'title': null,
                      'body': null,
                    },
              'activeInteractions': conversation == null
                  ? null
                  : [
                      for (final editor in conversation!.currentEditors)
                        {'id': editor.interactionId},
                    ],
              'turn': turnDiagnostic(
                execution?.value?.activeTurn,
                material: status?.turnRead,
                origin: execution?.stamp,
              ),
              'lastTurn': turnDiagnostic(
                execution?.value?.recentTerminalTurn,
                material: execution?.value?.activeTurn == null
                    ? status?.turnRead
                    : null,
                origin: execution?.stamp,
              ),
            },
      'plan': publishedPlan == null
          ? null
          : {
              'state': publishedPlan.state.name,
              'documentVersion': publishedPlan.document?.version,
              'contentHash': publishedPlan.document?.contentHash,
              'markdown':
                  plan?.document?.contentHash ==
                          publishedPlan.document?.contentHash &&
                      plan?.document?.version == publishedPlan.document?.version
                  ? plan?.document?.markdown
                  : null,
            },
      'workflow': workflowDiagnostic(this),
      'conversationActivity': activity == null
          ? null
          : {
              'identity': status?.activityRead.textOf(
                status?.activityRead.header?.identity,
              ),
              'kind': activity.kind.name,
              'summary': status?.activityRead.textOf(
                status?.activityRead.header?.summary,
              ),
              'activeToolCount': activity.activeCount,
              'backgroundToolCount': activity.backgroundCount,
              'errorMessage': status?.activityRead.error?.code.name,
              // The current ThreadStatusView exposes a details builder for every
              // published status value. This is presentation capability, not state.
              'expandable': status == null ? null : true,
              'expanded': status?.detailsVisible,
              'detailsLoading': status?.activityRead.loading,
              'detailsError': status?.activityRead.error?.code.name,
              'details': status == null
                  ? null
                  : [
                      for (final item in status!.activityRead.items)
                        {
                          'id': status!.activityRead.textOf(item.callId),
                          'title': status!.activityRead.textOf(item.name),
                          'body': status!.activityRead.textOf(item.summary),
                        },
                    ],
            },
      'storageRecovery': storage == null
          ? null
          : [
              {
                'threadId': selection.threadId,
                'title': thread?.title,
                'fault': storage.fault?.name,
                'faultGeneration': storage.faultGeneration,
                'acceptedSequence': storage.acceptedSequence,
                'durableSequence': storage.durableSequence,
                'execution': storage.execution.name,
                'pressurePaused': storage.pressurePaused,
                'resumeRequired': storage.resumeRequired,
                'canResume': storage.canResume,
                'blocksContinuation': null,
                'lastError': null,
              },
            ],
      'settings': settingsDiagnostic(this),
      'persistence': persistenceDiagnostic(persistence),
      'recoveryIssues': recoveryRows == null
          ? null
          : [
              for (final issue in recoveryRows)
                {
                  'id': issue.id,
                  'category': issue.category.name,
                  'actions': [issue.action.name],
                  'threadId': issue.threadId,
                  'detail': issue.message,
                },
            ],
      'updates': updatesDiagnostic(updates),
      'startup': startupDiagnostic(startup),
      'bots': botsDiagnostic(bots),
    };
  }
}

Map<String, Object?> draftDiagnostic({
  required String text,
  required List<AttachmentMetadata> attachments,
  required DraftSubmissionState submission,
  required int revision,
  required int generation,
}) => {
  'draft': text,
  'phase': switch (submission) {
    IdleDraftSubmission() => 'idle',
    SubmittingDraft() => 'submitting',
    FailedDraftSubmission() => 'failed',
    UnknownDraftSubmission() => 'unknownOutcome',
  },
  'submissionPending': submission is SubmittingDraft,
  'submissionRevision': revision,
  'attachmentGeneration': generation,
  'error': switch (submission) {
    FailedDraftSubmission(:final error) ||
    UnknownDraftSubmission(:final error) => error.code.name,
    _ => null,
  },
  'attachments': [
    for (final item in attachments)
      {
        'id': item.id,
        'filename': item.filename,
        'modality': item.modality.name,
        'byteSize': item.byteSize,
      },
  ],
};

Map<String, Object?> agentDiagnostic(AgentDirectoryEntry agent) => {
  'id': agent.id,
  'threadId': agent.threadId,
  'rootThreadId': agent.rootThreadId,
  'path': agent.path,
  'parentPath': agent.parentPath,
  'role': agent.role,
  'task': agent.task,
  'status': switch (agent.state) {
    IdleAgentState() => 'idle',
    QueuedAgentState() => 'queued',
    RunningAgentState() => 'running',
    WaitingToolAgentState() => 'waitingTool',
    WaitingInteractionAgentState() => 'waitingInteraction',
    CancellingAgentState() => 'cancelling',
    ClosingAgentState() => 'closing',
    ClosedAgentState() => 'closed',
    FaultedAgentState() => 'faulted',
  },
  'error': switch (agent.state) {
    FaultedAgentState(:final error) => error.code,
    ClosingAgentState(:final error) => error?.code,
    _ => null,
  },
};

Map<String, Object?>? turnDiagnostic(
  TurnBrief? turn, {
  ReadMaterial<TurnReadHeader, Never>? material,
  ThreadFacetStamp? origin,
}) {
  if (turn == null) return null;
  final read = material?.header;
  final matching =
      origin != null &&
      read != null &&
      read.revision == turn.revision &&
      read.scope.runtimeEpoch == origin.runtimeEpoch &&
      read.scope.incarnation == origin.incarnation;
  final failure = matching
      ? switch (read.state) {
          FailedTurnRead(:final failure) => failure,
          _ => null,
        }
      : null;
  return {
    // Business IDs exist only when the same current public read already loaded them.
    'id': matching ? material?.textOf(read.id) : null,
    'inputId': matching ? material?.textOf(read.inputId) : null,
    'reference': {
      'entry': turn.reference.entry,
      'revision': turn.reference.revision,
    },
    'revision': turn.revision,
    'status': switch (turn.state) {
      QueuedTurnBrief() => 'queued',
      RunningTurnBrief() => 'running',
      CompletedTurnBrief() => 'completed',
      CancelledTurnBrief() => 'cancelled',
      FailedTurnBrief() => 'failed',
      BudgetLimitedTurnBrief() => 'budgetLimited',
    },
    'activity': switch (turn.state) {
      RunningTurnBrief(:final phase) => phase.name,
      _ => null,
    },
    'reason': failure == null ? null : material?.textOf(failure.message),
    if (failure != null)
      'failure': {
        'category': failure.category.name,
        'retryable': failure.retry is RetryableDisposition,
        'message': material?.textOf(failure.message),
        'providerKind': failure.providerKind?.name,
        'code': material?.textOf(failure.code),
        'httpStatus': failure.httpStatus,
        'retryAfterMs': switch (failure.retry) {
          RetryableDisposition(:final retryAfterMs) => retryAfterMs,
          _ => null,
        },
      },
    'updatedAt': DateTime.fromMillisecondsSinceEpoch(
      turn.updatedAt * 1000,
      isUtc: true,
    ).toIso8601String(),
  };
}

Map<String, Object?>? workflowDiagnostic(DriverSnapshot snapshot) {
  final brief = snapshot.authoring?.value?.workflow;
  if (brief == null) return null;
  final read = snapshot.status?.workflowRead;
  final header = read?.header;
  final origin = snapshot.authoring?.stamp;
  final run =
      header?.revision == brief.revision &&
          header?.scope.runtimeEpoch == origin?.runtimeEpoch &&
          header?.scope.incarnation == origin?.incarnation
      ? header?.currentRun
      : null;
  return {
    'revision': brief.revision,
    'currentRun': run == null
        ? null
        : {
            'lineageId': read?.textOf(run.lineageId),
            'runId': read?.textOf(run.runId),
            'modeId': read?.textOf(run.modeId),
            'graphRevision': run.graphRevision,
            'graphHash': read?.textOf(run.graphHash),
            'currentStateId': read?.textOf(run.currentStateId),
            'currentStateTitle': read?.textOf(run.currentStateTitle),
            'modeDisplayName': read?.textOf(run.modeDisplayName),
            'modeDeleted': run.modeDeleted,
            'terminal': run.lifecycle == WorkflowLifecycle.terminal,
          },
  };
}

Map<String, Object?> settingsDiagnostic(DriverSnapshot snapshot) {
  final config = snapshot.configuration;
  final origin = config.projection.sync.phase == ResourceSyncPhase.ready
      ? config.projection.stamp?.origin
      : null;
  final reference = config.projection.header?.reference;
  final general = currentDriverRead(
    config.general,
    origin,
    reference: reference,
  );
  final models = snapshot.catalogAccounts;
  return {
    'revision': config.projection.header?.configurationRevision,
    'sidebarWidth': general?.sidebarWidth,
    'modelCatalogRevision': snapshot.models.projection.header?.catalogRevision,
    'accounts': snapshot.configuredAccounts == null
        ? null
        : [
            for (final account in snapshot.configuredAccounts!)
              {
                'id': account.accountId,
                'name': account.name,
                'templateId': account.templateId,
                'protocol': account.protocol,
                'pricingEnabled': account.pricingEnabled,
                'hasBearerToken': account.hasBearerToken,
                'billingKind': account.billingKind.name,
                'billingKindOverride': account.billingKindOverride?.name,
                'usageQueryRevision': account.usageQueryRevision,
                ...accountCatalogDiagnostic(
                  models
                      ?.where((row) => row.accountId == account.accountId)
                      .firstOrNull,
                ),
                'autoCompactLimits': models
                    ?.where((row) => row.accountId == account.accountId)
                    .firstOrNull
                    ?.effectiveModels
                    .map(
                      (model) => {
                        'modelId': model.modelId,
                        'override': account.modelAutoCompactLimits
                            .where((limit) => limit.modelId == model.modelId)
                            .firstOrNull
                            ?.overrideLimit,
                        'effective': model.context.autoCompactLimit,
                        'adjustment': model.context.adjustment?.name,
                        'unavailable': model.context.unavailable?.name,
                      },
                    )
                    .toList(),
              },
          ],
    'roles': currentDriverRead(config.roles, origin, reference: reference)
        ?.map(
          (role) => {
            'key': role.key,
            'accountId': role.accountId,
            'modelId': role.modelId,
            'effort': role.effort,
          },
        )
        .toList(),
    'modeModelRoutes':
        currentDriverRead(config.modeRoutes, origin, reference: reference)
            ?.map(
              (route) => {
                'modeId': route.modeId,
                'accountId': route.accountId,
                'modelId': route.modelId,
                'effort': route.effort,
              },
            )
            .toList(),
    // Original application operation records, not guessed canonical completion.
    'mutations': [
      for (final operation in snapshot.operations)
        if (operation.isPending)
          {
            'key': operation.target,
            'operationId': operation.id.value,
            'phase': operation.failurePhase?.name ?? 'pending',
            'error': operation.error?.code.name,
          },
    ],
  };
}

Map<String, Object?> accountCatalogDiagnostic(AccountCatalogEntry? catalog) => {
  'defaultModelId': catalog?.defaultModelId,
  'status': catalog?.modelCatalog.error?.runtimeType.toString(),
  'models': catalog == null
      ? null
      : [for (final model in catalog.effectiveModels) model.modelId],
  'textModels': catalog == null
      ? null
      : [
          for (final model in catalog.effectiveModels)
            if (model.typeSupport.any(
              (support) =>
                  support.modelType == ModelType.text &&
                  support.exclusions.isEmpty,
            ))
              model.modelId,
        ],
  'modelDetails': catalog == null
      ? null
      : [for (final model in catalog.effectiveModels) modelDiagnostic(model)],
  'modelCatalog': catalog == null
      ? null
      : {
          'supported': catalog.modelCatalog.supported,
          'source': catalog.modelCatalog.source.name,
          'probing': catalog.modelCatalog.probing,
          'error': catalog.modelCatalog.error?.runtimeType.toString(),
          'cacheWarning': catalog.modelCatalog.cacheWarning?.name,
          'lastSuccessAt': catalog.modelCatalog.lastSuccessAt,
        },
};

Map<String, Object?> modelDiagnostic(ModelDescriptor model) => {
  'modelId': model.modelId,
  'name': model.displayName,
  'enabled': model.enabled,
  'origin': model.origin.name,
  'contextWindow': model.contextWindow,
  'maxContextWindow': model.maxContextWindow,
  'maxOutputTokens': model.maxOutputTokens,
  'reasoningEfforts': model.reasoning?.candidates,
  'defaultReasoningEffort': model.reasoning?.defaultValue,
  'inputCapabilities': [
    for (final input in model.capabilities.input) input.modality.name,
  ],
  'priced': model.pricing?.tiers.isNotEmpty,
  'typeSupport': [
    for (final support in model.typeSupport)
      {
        'modelType': support.modelType.name,
        'exclusions': [for (final reason in support.exclusions) reason.name],
      },
  ],
};

Map<String, Object?>? persistenceDiagnostic(PersistenceState state) {
  final header = state.projection.sync.phase == ResourceSyncPhase.ready
      ? state.projection.header
      : null;
  if (header == null) return null;
  return {
    'revision': header.revision,
    'kind': switch (header.state) {
      ReadyPersistenceBrief() => 'ready',
      FlushingPersistenceBrief() => 'flushing',
      DegradedPersistenceBrief() => 'degraded',
      RecoveringPersistenceBrief() => 'recovering',
      BlockedPersistenceBrief() => 'blocked',
    },
    'pendingCommits': switch (header.state) {
      ReadyPersistenceBrief(:final pendingCommits) ||
      FlushingPersistenceBrief(:final pendingCommits) ||
      DegradedPersistenceBrief(:final pendingCommits) ||
      RecoveringPersistenceBrief(:final pendingCommits) ||
      BlockedPersistenceBrief(:final pendingCommits) => pendingCommits,
    },
  };
}

Map<String, Object?> updatesDiagnostic(UpdatesState state) {
  final brief = state.projection.sync.phase == ResourceSyncPhase.ready
      ? state.projection.header?.brief
      : null;
  final value = brief == null
      ? null
      : currentDriverRead(
          state.value,
          state.projection.stamp?.origin,
          reference: state.projection.header?.reference,
        );
  return {
    'state': switch (brief) {
      null => null,
      DisabledUpdatesBrief() => 'disabled',
      IdleUpdatesBrief() => 'idle',
      CheckingUpdatesBrief() => 'checking',
      UpToDateUpdatesBrief() => 'upToDate',
      AvailableUpdatesBrief() => 'available',
      DownloadingUpdatesBrief() => 'downloading',
      VerifyingUpdatesBrief() => 'verifying',
      ReadyUpdatesBrief() => 'ready',
      InstallerLaunchedUpdatesBrief() => 'installerLaunched',
      CheckFailedUpdatesBrief() => 'checkFailed',
      InstallFailedUpdatesBrief() => 'installFailed',
    },
    'revision': state.projection.stamp?.revision,
    'version': switch (value) {
      AvailableUpdatesValue(:final update) ||
      DownloadingUpdatesValue(:final update) ||
      VerifyingUpdatesValue(:final update) ||
      ReadyUpdatesValue(:final update) ||
      InstallerLaunchedUpdatesValue(:final update) => update.version,
      _ => null,
    },
    'downloaded': switch (brief) {
      DownloadingUpdatesBrief(:final downloaded) ||
      VerifyingUpdatesBrief(:final downloaded) => downloaded,
      _ => null,
    },
    'total': switch (brief) {
      DownloadingUpdatesBrief(:final total) ||
      VerifyingUpdatesBrief(:final total) => total,
      _ => null,
    },
  };
}

Map<String, Object?> startupDiagnostic(StartupState state) => {
  'phase': switch (state) {
    IdleStartupState() => 'idle',
    StartingStartupState(:final phase) => switch (phase) {
      LoadingLibraryStartupPhase() => 'loadingLibrary',
      PreparingAttemptStartupPhase() => 'preparingAttempt',
      NativeStartupPhase(:final stage) => stage.name,
    },
    ReadyStartupState() => 'ready',
    FailedStartupState() => 'failed',
  },
  'failureCode': switch (state) {
    FailedStartupState(:final error) => error.code.name,
    _ => null,
  },
  'correlationId': switch (state) {
    FailedStartupState(:final error) => error.correlationId,
    _ => null,
  },
};

Map<String, Object?>? botsDiagnostic(DriverBotsObservation observation) =>
    switch (observation) {
      DriverBotsUnknown() => null,
      DriverBotsValue() => {
        'revision': observation.revision,
        'bots': [
          for (final bot in observation.bots)
            {
              'id': bot.id,
              'name': bot.name,
              'enabled': bot.enabled,
              'credential': bot.credential,
              'connectionKind': bot.connectionKind,
              'pendingKind': bot.pendingKind,
              'configCommitted': bot.configCommitted,
              'configRevision': bot.configRevision,
              'trustedUserCount': bot.trustedUserCount,
              'trustedGroupCount': bot.trustedGroupCount,
              'pairingCount': bot.pairingCount,
              'canChangeProject': bot.canChangeProject,
              'canChangeAppId': bot.canChangeAppId,
            },
        ],
        'pending': [
          for (final operation in observation.pending)
            {
              'botId': operation.botId,
              'kind': operation.kind,
              'configCommitted': operation.configCommitted,
            },
        ],
        'registrationAttemptId': observation.registrationAttemptId,
        'registrationKind': observation.registrationKind,
        'registrationBotId': observation.registrationBotId,
        'completedBotId': observation.completedBotId,
      },
    };
