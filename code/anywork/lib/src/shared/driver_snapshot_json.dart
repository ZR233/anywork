import 'package:anywork_client/acp.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/updates.dart';
import 'package:anywork_client/workspace.dart';

import '../diagnostics/conversation_status_diagnostics.dart';
import '../diagnostics/timeline_diagnostics_json.dart';
import '../features/conversation/state/interaction_view_state.dart';
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
    final activeInteractions = interactionEditors == null
        ? null
        : [
            for (final editor in interactionEditors!)
              _interactionDiagnostic(editor),
          ];
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
              'isBusy':
                  execution?.sync.phase == FacetSyncPhase.ready &&
                      execution?.value != null
                  ? execution!.value!.execution != null
                  : null,
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
              // Partial mounted facts cannot establish a unique active target.
              // The full index and its single current editor must both agree.
              'activeInteraction':
                  conversation?.interactions?.current?.complete == true &&
                      conversation?.currentEditors.length == 1 &&
                      activeInteractions?.length == 1
                  ? activeInteractions!.single
                  : null,
              'activeInteractions': activeInteractions,
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
                  'availableActions': [
                    for (final action in issue.availableActions) action.name,
                  ],
                  'threadId': issue.threadId,
                  'detail': issue.message,
                  'worktree': _worktreeRecoveryDiagnostic(issue.worktree),
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
  'execution': agentExecutionDiagnostic(agent.execution),
  'canStop': agent.canStop,
  'awaitingScheduling': agent.awaitingScheduling,
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

Map<String, Object?> _interactionDiagnostic(InteractionViewState editor) {
  final header = editor.header!;
  final content = header.content;
  final questions = editor.questions.values.toList()
    ..sort(
      (left, right) => left.question.index.compareTo(right.question.index),
    );
  return {
    'id': editor.textOf(header.interactionId),
    'threadId': editor.textOf(header.threadId),
    'hostThreadId': editor.key.threadId,
    'turnId': editor.textOf(header.turnId),
    'revision': header.revision,
    'kind': switch (content) {
      UserInputContentRead() => 'userInput',
      ToolApprovalContentRead() => 'toolApproval',
    },
    'title': switch (content) {
      UserInputContentRead() => editor.textOf(
        editor.questions[0]?.question.header,
      ),
      ToolApprovalContentRead(:final name) => editor.textOf(name),
    },
    'body': switch (content) {
      UserInputContentRead(:final questionCount) => _interactionQuestionBody(
        editor,
        questionCount,
      ),
      ToolApprovalContentRead(:final arguments) => editor.textOf(arguments),
    },
    'purpose': switch (header.purpose) {
      GeneralInteractionPurposeRead() => {'kind': 'general'},
      PlanConfirmationPurposeRead(
        :final expectedRevision,
        :final operationId,
        :final argumentHash,
        :final planHash,
      ) =>
        {
          'kind': 'planConfirmation',
          'expectedRevision': expectedRevision,
          'operationId': editor.textOf(operationId),
          'argumentHash': editor.textOf(argumentHash),
          'planHash': editor.textOf(planHash),
        },
    },
    'state': switch (header.state) {
      PendingInteractionRead() => 'pending',
      ResolvedUserInputRead() || ResolvedApprovalRead() => 'resolved',
      CancelledInteractionRead() => 'cancelled',
      ExpiredInteractionRead() => 'expired',
    },
    'content': switch (content) {
      UserInputContentRead(:final questionCount) => {
        'questionCount': questionCount,
        'questions': [
          for (final progress in questions)
            _interactionQuestionDiagnostic(editor, progress),
        ],
      },
      ToolApprovalContentRead(
        :final name,
        :final arguments,
        :final workingDirectory,
        :final parentAgentId,
      ) =>
        {
          'name': editor.textOf(name),
          'arguments': editor.textOf(arguments),
          'workingDirectory': editor.textOf(workingDirectory),
          'parentAgentId': editor.textOf(parentAgentId),
        },
    },
  };
}

Map<String, Object?> _interactionQuestionDiagnostic(
  InteractionViewState editor,
  QuestionReadProgress progress,
) {
  final count = progress.question.optionsCount;
  final options = progress.options.toList()
    ..sort((left, right) => left.index.compareTo(right.index));
  var complete =
      !progress.optionsLoading &&
      progress.optionsError == null &&
      progress.nextOptionOffset == null &&
      options.length == count;
  if (complete) {
    for (final (index, option) in options.indexed) {
      if (option.index != index ||
          editor.textOf(option.label) == null ||
          editor.textOf(option.description) == null) {
        complete = false;
        break;
      }
    }
  }
  return {
    'index': progress.question.index,
    'id': editor.textOf(progress.question.id),
    'header': editor.textOf(progress.question.header),
    'question': editor.textOf(progress.question.question),
    'isOther': progress.question.isOther,
    'isSecret': progress.question.isSecret,
    'optionsCount': count,
    'options': count == null
        ? null
        : [
            for (final option in options)
              {
                'index': option.index,
                'label': editor.textOf(option.label),
                'description': editor.textOf(option.description),
              },
          ],
    'optionsComplete': count == null ? null : complete,
  };
}

/// Preserve the original Driver body shape without mistaking a partial page or
/// a deferred text prefix for the complete question/Plan document.
String? _interactionQuestionBody(InteractionViewState editor, int count) {
  if (count == 0 ||
      editor.nextQuestionOffset != null ||
      editor.questions.length != count) {
    return null;
  }
  final parts = <String>[];
  for (var index = 0; index < count; index++) {
    final question = editor.questions[index]?.question;
    if (question == null || question.index != index) return null;
    final body = editor.textOf(question.question);
    if (body == null) return null;
    if (body.isNotEmpty) parts.add(body);
  }
  return parts.join('\n');
}

Map<String, Object?>? _worktreeRecoveryDiagnostic(
  WorktreeRecoveryPreview? worktree,
) => worktree == null
    ? null
    : {
        'inspection': worktree.inspection.name,
        'ownerKind': worktree.ownerKind.name,
        'ownerThreadId': worktree.ownerThreadId,
        'leaseRevision': worktree.leaseRevision,
        'state': worktree.state,
        'repositoryRoot': worktree.repositoryRoot,
        'path': worktree.path,
        'branch': worktree.branch,
        'baseCommit': worktree.baseCommit,
        'headCommit': worktree.headCommit,
        'dirty': worktree.dirty,
        'changedFiles': worktree.changedFiles,
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
    // ACP 认证与安装是两个独立事实源，各自 `loaded` 都由 canonical 镜像是否存在
    // 决定；未加载时不给空集合，也不伪造 revision 0 的“已加载”水位。
    'acpAuthLoaded': snapshot.acpAuth != null,
    // 原 main 的 accounts/auth 字段：认证按“账号 + 连接代次”发布，配置身份单独发布。
    'acpAuth': acpAuthDiagnostic(snapshot.acpAuth),
    'acpAccounts': acpAccountRows(snapshot.acpAccounts),
    'nativeTemplates': snapshot.templates == null
        ? null
        : [for (final template in snapshot.templates!.templates) template.id],
    'acpInstall': acpInstallDiagnostic(snapshot.acpInstall),
  };
}

/// ACP 认证的只读投影：`kind` 是认证状态变体的固定名字。
///
/// 未加载时 `accounts` 为 `null`（不是空列表冒充）；`connectionRevision` 与配置
/// 身份必须同时匹配才算同一目标，调用方据此拒绝旧代次的观察。
Map<String, Object?> acpAuthDiagnostic(AcpAuthSnapshot? auth) => {
  'loaded': auth != null,
  'revision': auth?.revision,
  'updatedAt': auth?.updatedAt,
  'accounts': auth == null
      ? null
      : [
          for (final account in auth.accounts)
            {
              'accountId': account.accountId,
              'connectionRevision': account.connectionRevision,
              'state': acpAuthStateDiagnostic(account.state),
            },
        ],
};

/// ACP 接入配置行；`null` 表示本 graph 尚未读到该目录。
List<Map<String, Object?>>? acpAccountRows(AcpAccountDirectory? directory) =>
    directory == null
    ? null
    : [
        for (final account in directory.accounts)
          {
            'accountId': account.accountId,
            'name': account.name,
            'provider': account.provider.name,
            'connectionRevision': account.connectionRevision,
          },
      ];

/// 认证状态变体与其携带的 typed 事实；不合成 server/method 缺失时的占位。
Map<String, Object?> acpAuthStateDiagnostic(AcpAuthState state) =>
    switch (state) {
      AcpAuthUnchecked() => {'kind': 'unchecked'},
      AcpAuthChecking(:final operationId) => {
        'kind': 'checking',
        'operationId': operationId,
      },
      AcpAuthRequired(:final server, :final methods) => {
        'kind': 'required',
        'server': acpServerDiagnostic(server),
        'methods': [
          for (final method in methods)
            {
              'id': method.id,
              'name': method.name,
              'kind': method.kind.name,
              'description': method.description,
            },
        ],
      },
      AcpAuthAuthenticating(:final operationId, :final methodId) => {
        'kind': 'authenticating',
        'operationId': operationId,
        'methodId': methodId,
      },
      AcpAuthVerifying(:final operationId) => {
        'kind': 'verifying',
        'operationId': operationId,
      },
      AcpAuthClosing(:final operationId, :final failure) => {
        'kind': 'closing',
        'operationId': operationId,
        'failure': acpAuthFailureDiagnostic(failure),
      },
      AcpAuthVerified(:final checkedAt, :final server) => {
        'kind': 'verified',
        'checkedAt': checkedAt,
        'server': acpServerDiagnostic(server),
      },
      AcpAuthCancelling(:final operationId) => {
        'kind': 'cancelling',
        'operationId': operationId,
      },
      AcpAuthCancelled() => {'kind': 'cancelled'},
      AcpAuthFailed(:final failure) => {
        'kind': 'failed',
        'failure': acpAuthFailureDiagnostic(failure),
      },
    };

Map<String, Object?>? acpServerDiagnostic(AcpServerInfo? server) =>
    server == null
    ? null
    : {'name': server.name, 'title': server.title, 'version': server.version};

/// 认证失败：`code`/`stage` 是 typed 枚举的固定名字，`message` 是后端脱敏原文。
Map<String, Object?>? acpAuthFailureDiagnostic(AcpAuthFailure? failure) =>
    failure == null
    ? null
    : {
        'code': failure.code.name,
        'stage': failure.stage.name,
        'message': failure.message,
        'retryable': failure.retryable,
      };

/// `acpInstall` 的只读投影：只搬运 typed 状态已经发布的事实。
///
/// `loaded` 为 `false` 时 `revision`/`installations` 都是 `null`，因为“没有加载”
/// 不等于“没有任何安装”或“全部未准备”；`loaded` 为 `true` 时 `revision` 即使为
/// 0 也是合法的已加载水位。
Map<String, Object?> acpInstallDiagnostic(AcpInstallSnapshot? install) => {
  'loaded': install != null,
  'revision': install?.revision,
  'installations': install == null
      ? null
      : [
          for (final entry in install.installations)
            {
              'provider': entry.provider.name,
              'phase': acpInstallPhase(entry.state),
              // 终态没有“当前阶段”；失败发生在哪一步由 failure 自己携带。
              'stage': entry.state.stage?.name,
              'operationId': entry.state.operationId,
              // 进度/重试只在对应阶段有真实字节与计数，其余为 null。
              'progress': acpInstallProgressDiagnostic(entry.state.progress),
              'retryCount': entry.state.retryCount,
              // 冻结的发行描述符：解析前与未准备时为 null。
              'release': acpInstallReleaseDiagnostic(entry.state.release),
              // 就绪结果只由就绪状态携带：program 是只读诊断，不是可编辑启动配置。
              'program': entry.state.server?.program,
              'reused': entry.state.server?.reused,
              'failure': acpInstallFailureDiagnostic(entry.state.failure),
            },
        ],
};

Map<String, Object?>? acpInstallProgressDiagnostic(
  AcpInstallProgress? progress,
) => progress == null
    ? null
    : {
        'completedBytes': progress.completedBytes,
        'totalBytes': progress.totalBytes,
        'bytesPerSecond': progress.bytesPerSecond,
      };

Map<String, Object?>? acpInstallReleaseDiagnostic(AcpInstallRelease? release) =>
    release == null
    ? null
    : {
        'version': release.version,
        'target': release.target,
        'archiveUrl': release.archiveUrl,
        'sha256': release.sha256,
      };

/// 安装状态变体的固定名字，静态解析自 sealed 状态；不按 message 或字符串猜阶段。
String acpInstallPhase(AcpInstallState state) => switch (state) {
  AcpInstallIdleState() => 'idle',
  AcpInstallResolving() => 'resolving',
  AcpInstallWaiting() => 'waiting',
  AcpInstallDownloading() => 'downloading',
  AcpInstallVerifying() => 'verifying',
  AcpInstallExtracting() => 'extracting',
  AcpInstallPublishing() => 'publishing',
  AcpInstallClosing() => 'closing',
  AcpInstallReady() => 'ready',
  AcpInstallCancelling() => 'cancelling',
  AcpInstallCancelled() => 'cancelled',
  AcpInstallFailed() => 'failed',
};

/// 失败只发布安全类别：`code` 是 typed 枚举的固定名字，`retryable` 是已发布值。
///
/// 这里直接访问枚举成员，不经过 `dynamic` 分发，也不解析脱敏 message。
Map<String, Object?>? acpInstallFailureDiagnostic(AcpInstallFailure? failure) =>
    failure == null
    ? null
    : {
        'code': failure.code.name,
        'stage': failure.stage.name,
        'message': failure.message,
        'retryable': failure.retryable,
      };

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
