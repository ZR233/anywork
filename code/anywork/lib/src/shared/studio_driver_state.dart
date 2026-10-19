import 'dart:convert';

import 'package:anywork_client/studio_client.dart';

import '../domain/models/agent_workspace_view.dart';
import '../domain/models/timeline_commands.dart';

/// 一个展示代次的只读事实（design/26 §26.9）。
///
/// 身份与数量来自当前 stock controller 的真实消息集合，不从状态流猜测；`items` 是同一批
/// Message 的轻量 typed 预览诊断，只用于验收旅程，不是第二份业务事实源。
final class TimelineDisplayFacts {
  TimelineDisplayFacts({
    required this.threadId,
    required this.generation,
    required this.ready,
    required this.mode,
    required this.connection,
    required this.appliedVersion,
    required this.olderCursor,
    required this.hasOlder,
    required this.loadingOlder,
    required this.olderError,
    required this.olderErrorCode,
    required this.hasNewOutput,
    required this.preparingLive,
    List<TimelineItemFacts> items = const [],
    List<TimelinePresentationFacts> presentationItems = const [],
  }) : items = List.unmodifiable(items),
       presentationItems = List.unmodifiable(presentationItems);

  final String threadId;
  final int generation;
  final bool ready;
  final TimelineDisplayMode mode;
  final TimelineConnectionPhase connection;
  final int? appliedVersion;
  final String? olderCursor;
  final bool hasOlder;
  final bool loadingOlder;
  final String? olderError;
  final StudioFailureCode? olderErrorCode;
  final bool hasNewOutput;
  final bool preparingLive;
  final List<TimelineItemFacts> items;
  final List<TimelinePresentationFacts> presentationItems;
}

/// GUI groups have their own identity; members still denote individual canonical records.
final class TimelinePresentationFacts {
  TimelinePresentationFacts({
    required this.id,
    required this.kind,
    required this.ordinal,
    required List<String> memberIds,
    required this.expanded,
    required this.activeCount,
    required this.issueCount,
  }) : memberIds = List.unmodifiable(memberIds);
  final String id;
  final String kind;
  final int ordinal;
  final List<String> memberIds;
  final bool expanded;
  final int activeCount;
  final int issueCount;
}

/// 一条 canonical item 的轻量 typed 预览诊断。
final class TimelineItemFacts {
  TimelineItemFacts({
    required this.id,
    required this.ordinal,
    required this.revision,
    required this.saved,
    required this.terminal,
    required this.omittedBytes,
    required this.kind,
    required this.status,
    required this.text,
    required this.channel,
    List<TimelineDetailFacts> details = const [],
    List<TimelineAttachmentFacts> attachments = const [],
    this.tool,
    this.userInput,
  }) : details = List.unmodifiable(details),
       attachments = List.unmodifiable(attachments);

  final String id;
  final int ordinal;
  final int revision;
  final bool saved;
  final bool terminal;
  final int omittedBytes;
  final String kind;
  final String status;

  /// 已脱敏的预览正文（工具行是命令摘要，不是完整参数）。
  final String text;

  /// 文本条目的权威频道（commentary / finalAnswer / user / parentAgent）；
  /// 非文本条目为 null。它来自 `ThreadTextItemStateView.channel`，不从 kind 或文本推测：
  /// `agentMessage` 同时覆盖 commentary 与 finalAnswer。
  final ThreadTextChannel? channel;
  final List<TimelineDetailFacts> details;
  final List<TimelineAttachmentFacts> attachments;
  final TimelineToolFacts? tool;
  final TimelineUserInputFacts? userInput;
}

/// 一条工具调用的预览诊断：不展开全文，也不为 Driver 额外读取详情。
final class TimelineToolFacts {
  TimelineToolFacts({
    required this.name,
    required this.status,
    required this.callId,
    required this.arguments,
    required this.result,
    required this.progressBytes,
    required this.itemRevision,
    this.denialReason,
    this.workingDirectory,
    this.exitCode,
    List<TimelineAttachmentFacts> attachments = const [],
  }) : attachments = List.unmodifiable(attachments);

  final String name;
  final String status;
  final String callId;
  final String arguments;
  final String? result;

  /// 预览结果的 UTF-8 字节数：逐次增长即在途真实产出。
  final int progressBytes;
  final int itemRevision;
  final String? denialReason;
  final String? workingDirectory;
  final int? exitCode;
  final List<TimelineAttachmentFacts> attachments;
}

/// 一个内容字段的详情引用诊断（字段身份 + revision + 完整/预览字节数）。
final class TimelineDetailFacts {
  const TimelineDetailFacts({
    required this.field,
    required this.revision,
    required this.totalBytes,
    required this.previewBytes,
  });

  final String field;
  final int revision;
  final int totalBytes;
  final int previewBytes;
}

final class TimelineAttachmentFacts {
  const TimelineAttachmentFacts({
    required this.id,
    required this.modality,
    required this.filename,
    required this.byteSize,
    this.source,
  });

  final String id;
  final String modality;
  final String filename;
  final int byteSize;
  final String? source;
}

/// 普通问答/计划确认的只读回执事实；来自公开 typed 投影，不解析私有载荷。
final class TimelineUserInputFacts {
  const TimelineUserInputFacts({
    required this.interactionId,
    required this.state,
    required this.isPlanConfirmation,
    this.planDecision,
  });

  final String interactionId;
  final String state;

  /// 这条问答是否就是计划确认：来自唯一 public typed `planReceipt != null`。
  ///
  /// 待确认（pending）的计划同样是计划确认；它不是“已决才为真”。
  final bool isPlanConfirmation;

  /// 权威决定（`pending`/`approved`/`revisionRequested`/`cancelled`/`resolved`）；
  /// 普通问答为 null。
  final String? planDecision;
}

/// One immutable, synchronous read of the Client's current mirrors. Driver keeps
/// no copy after serialization and cannot write these values back to the Client.
final class StudioDriverFacts {
  StudioDriverFacts({
    this.timeline,
    this.timelineScroll,
    Map<String, ThreadWorkspace> workspacesByThread = const {},
    List<StudioThread> rootThreads = const [],
    this.directoryHasMore = false,
    this.selectedProjectId,
    this.selectedThreadId,
    this.newThreadMode = ThreadModeId.simple,
    this.newThreadWorkspaceMode = ThreadWorkspaceMode.local,
    this.newThreadComposer = const ComposerThreadState.idle(),
    this.threadComposer = const ComposerThreadState.idle(),
    this.settingsRevision = 0,
    this.sidebarWidth,
    this.modelCatalogRevision = 0,
    List<ModeModelRouteView> modeModelRoutes = const [],
    List<RoleSettingsView> roles = const [],
    List<ProviderSettingsView> providers = const [],
    List<CommandStatus> commands = const [],
    this.settingsReady = false,
    this.persistence = const PersistenceStateSnapshot.ready(),
    List<StudioRecoveryIssue> recoveryIssues = const [],
    this.project,
    this.workspace,
  }) : workspacesByThread = Map.unmodifiable(workspacesByThread),
       rootThreads = List.unmodifiable(rootThreads),
       modeModelRoutes = List.unmodifiable(modeModelRoutes),
       roles = List.unmodifiable(roles),
       providers = List.unmodifiable(providers),
       commands = List.unmodifiable(commands),
       recoveryIssues = List.unmodifiable(recoveryIssues);

  /// 当前展示代次的只读事实；没有展示时为 null。
  final TimelineDisplayFacts? timeline;

  /// 滚动几何：**由每次诊断请求现场读取**当前展示 lease 实测挂载的标准 controller。
  ///
  /// 没有挂载代次时为 null；不保留上一代几何，也没有任何通知发布的快照可读
  /// （design/26 §26.9）。
  final TimelineScrollDiagnostic? timelineScroll;
  final Map<String, ThreadWorkspace> workspacesByThread;
  final List<StudioThread> rootThreads;
  final bool directoryHasMore;
  final String? selectedProjectId;
  final String? selectedThreadId;
  final ThreadModeId newThreadMode;
  final ThreadWorkspaceMode newThreadWorkspaceMode;
  final ComposerThreadState newThreadComposer;
  final ComposerThreadState threadComposer;
  final int settingsRevision;
  final int? sidebarWidth;
  final int modelCatalogRevision;
  final List<ModeModelRouteView> modeModelRoutes;
  final List<RoleSettingsView> roles;
  final List<ProviderSettingsView> providers;
  final List<CommandStatus> commands;
  final bool settingsReady;
  final PersistenceStateSnapshot persistence;
  final List<StudioRecoveryIssue> recoveryIssues;
  final StudioProject? project;
  final AgentWorkspaceView? workspace;
}

/// Read-only Client queries and bounded UI/host diagnostics for Driver builds.
abstract final class StudioDriverState {
  static StudioDriverFacts Function()? _query;
  static final List<StudioShutdownProgress> _shutdownProgress = [];
  static StudioShutdownReport? _shutdownReport;
  static int? _nativeExitRemainingMs;
  static int? _nativeCleanupBudgetMs;
  static int _exitRequests = 0;
  static String? _startupFailureCode;
  static String? _startupFailureCorrelationId;
  static ConversationActivityView? _conversationActivity;
  static bool _activityExpanded = false;

  /// Application assembly lends a query; binding never creates an observer or
  /// changes resource demand. Each request reads current Client facts directly.
  static void bindSnapshotQuery(StudioDriverFacts Function() query) {
    _query = query;
  }

  static StudioDriverFacts readFacts() => _query?.call() ?? StudioDriverFacts();

  static void publishConversationActivity(ConversationActivityView? view) {
    _conversationActivity = view;
  }

  /// 固定活动条的**实际展开态**（用户此刻是否展开详情）。
  ///
  /// 与快照里的 `expandable`（该活动是否有可展开的完整内容）语义不同：`expandable` 是
  /// 能力，`expanded` 是当前状态。仅由活动条在展开/收起或身份变化时上报。
  static void publishActivityExpanded(bool expanded) {
    _activityExpanded = expanded;
  }

  static void publishShutdownProgress(StudioShutdownProgress progress) {
    _shutdownProgress.add(progress);
    if (_shutdownProgress.length > 256) _shutdownProgress.removeAt(0);
  }

  static List<StudioShutdownProgress> get shutdownProgress =>
      List.unmodifiable(_shutdownProgress);

  /// 上一次 typed 退出报告（只读诊断投影，不是第二份业务状态）。
  static void publishShutdownReport(StudioShutdownReport? report) {
    _shutdownReport = report;
  }

  /// native 首次期限的剩余毫秒与派生出的清理预算；null 表示尚未武装。
  static void publishNativeExitBudget({
    required int remainingMs,
    required int cleanupBudgetMs,
  }) {
    _nativeExitRemainingMs = remainingMs;
    _nativeCleanupBudgetMs = cleanupBudgetMs;
  }

  /// 记录一次应用退出请求（托盘退出 / 系统会话结束 / 无托盘窗口关闭 /
  /// ServicesBinding / Driver / dispose）。
  static void markExitRequested() {
    _exitRequests++;
  }

  /// 记录启动致命失败（如第二实例 instanceBusy）的 typed code 与 correlation，供
  /// Driver-only 验收可靠判定，而不是从 UI 文本猜测。
  static void publishStartupFailure(StudioFailure failure) {
    _startupFailureCode = failure.code.name;
    _startupFailureCorrelationId = failure.correlationId;
  }

  /// Driver-only 只读退出诊断：native 剩余期限、清理预算、退出请求次数、typed 报告与
  /// 已观察阶段。验收据此对齐 remaining/stage，无需从长请求的断开推断。
  static Map<String, Object?> exitDiagnosticsJson() => <String, Object?>{
    'nativeExit': _nativeExitJson(),
    'shutdownReport': _shutdownReportJson(),
    'shutdownPhases': _shutdownPhasesJson(),
    'startup': _startupJson(),
  };

  static Map<String, Object?> _startupJson() => <String, Object?>{
    'failureCode': _startupFailureCode,
    'correlationId': _startupFailureCorrelationId,
  };

  static Map<String, Object?> _nativeExitJson() => <String, Object?>{
    'remainingMs': _nativeExitRemainingMs,
    'cleanupBudgetMs': _nativeCleanupBudgetMs,
    'requests': _exitRequests,
  };

  static List<String> _shutdownPhasesJson() => <String>[
    for (final progress in _shutdownProgress)
      '${progress.phase.name}:${switch (progress) {
        FlushingPersistenceProgress(:final pendingCommits) => pendingCommits,
        StoppingSubscriptionsProgress() || CancellingTurnsProgress() || StoppingAgentsProgress() || StoppingMcpProgress() || StoppingLspProgress() || StoppedProgress() => 0,
      }}',
  ];

  static Map<String, Object?>? _shutdownReportJson() {
    final report = _shutdownReport;
    if (report == null) return null;
    return <String, Object?>{
      'outcome': report.outcome.name,
      'persistence': switch (report.persistence) {
        UnknownStudioPendingPersistence() => 'unknown',
        PendingStudioPendingPersistence(:final count) => 'pending:$count',
        DrainedStudioPendingPersistence() => 'drained',
      },
      'issues': [
        for (final issue in report.issues)
          {
            'stage': issue.stage,
            'code': issue.code,
            'message': issue.message,
            'retryable': issue.retryable,
            'correlationId': issue.correlationId,
          },
      ],
    };
  }

  static String snapshotJson({StudioDriverFacts? observed}) {
    final facts = observed ?? readFacts();
    final workspace = facts.workspace;
    final lastTurn = workspace?.lastTurn;
    return jsonEncode({
      'recoveryIssues': [
        for (final issue in facts.recoveryIssues)
          {
            'id': issue.id,
            'category': issue.category.name,
            'actions': issue.availableActions
                .map((action) => action.name)
                .toList(),
            'threadId': issue.threadId,
            'detail': issue.detail,
          },
      ],
      // 唯一展示代次的只读事实：身份与数量来自当前 stock controller 的真实消息集合。
      'timeline': _timelineJson(facts.timeline),
      // 只读滚动几何：查询时现场读取当前挂在屏幕上的标准 controller/position，
      // 没有挂载时为 null，不回放上一代快照（见 TimelineScrollDiagnostic）。
      'timelineScroll': facts.timelineScroll?.toJson(),
      'sidebarDirectory': {
        'count': facts.rootThreads.length,
        'hasMore': facts.directoryHasMore,
        'ids': [for (final thread in facts.rootThreads) thread.id],
        'titles': {
          for (final thread in facts.rootThreads) thread.id: thread.title,
        },
        'workspaceModes': {
          for (final thread in facts.rootThreads)
            thread.id: thread.workspaceMode.id,
        },
        'workspacePaths': {
          for (final thread in facts.rootThreads)
            thread.id: thread.workspacePath,
        },
      },
      'navigation': {
        'selectedProjectId': facts.selectedProjectId,
        'selectedThreadId': facts.selectedThreadId,
        'isStartPage': facts.selectedThreadId == null,
        'newThreadMode': facts.newThreadMode.name,
        'newThreadWorkspaceMode': facts.newThreadWorkspaceMode.id,
        'newThreadComposer': {
          'draft': facts.newThreadComposer.draft,
          'phase': switch (facts.newThreadComposer) {
            IdleComposerThreadState() => 'idle',
            SubmittingComposerThreadState() => 'submitting',
            FailedComposerThreadState() => 'failed',
          },
          'submissionRevision': facts.newThreadComposer.submissionRevision,
          'error': facts.newThreadComposer.error,
          'attachments': [
            for (final attachment in facts.newThreadComposer.attachments)
              {
                'id': attachment.id,
                'modality': attachment.modality.name,
                'filename': attachment.filename,
                'byteSize': attachment.byteSize,
              },
          ],
        },
      },
      'shutdownPhases': _shutdownPhasesJson(),
      // typed 退出报告与 native 期限预算：只读诊断投影，供验收断言真实结局（不伪 Stopped）。
      'shutdownReport': _shutdownReportJson(),
      'nativeExit': _nativeExitJson(),
      'settings': {
        'revision': facts.settingsRevision,
        'sidebarWidth': facts.sidebarWidth,
        'modelCatalogRevision': facts.modelCatalogRevision,
        'providers': [
          for (final provider in facts.providers)
            {
              'id': provider.id,
              'preset': provider.templateKind,
              'defaultModel': provider.defaultModel,
              'pricingEnabled': provider.pricingEnabled,
              'hasBearerToken': provider.hasBearerToken,
              'status': provider.status,
              'models': [for (final model in provider.models) model.modelId],
              'textModels': [
                for (final model in provider.modelsFor(type: ModelType.text))
                  model.modelId,
              ],
              'modelDetails': [
                for (final model in provider.models)
                  {
                    'modelId': model.modelId,
                    'contextWindow': model.contextWindow,
                    'maxContextWindow': model.maxContextWindow,
                    'typeSupport': [
                      for (final support in model.typeSupport)
                        {
                          'modelType': support.modelType.name,
                          'exclusions': support.exclusions
                              .map((reason) => reason.name)
                              .toList(),
                        },
                    ],
                    'maxOutputTokens': model.maxOutputTokens,
                    'reasoningEfforts': model.reasoningEfforts,
                    'defaultReasoningEffort': model.defaultReasoningEffort,
                    'priced': model.priceTiers.isNotEmpty,
                  },
              ],
              'modelCatalog': {
                'supported': provider.modelCatalog.supported,
                'source': provider.modelCatalog.source.name,
                'probing': provider.modelCatalog.probing,
                'error': provider.modelCatalog.error?.kind.name,
                'cacheWarning': provider.modelCatalog.cacheWarning?.name,
                'lastSuccessAt': provider.modelCatalog.lastSuccessAt,
              },
              // 压缩阈值四层视图：modelId → {default, override, effective, safe}。
              // 缺失值保持 null，便于 Driver 断言未知容量与覆盖归一化。
              'autoCompactLimits': [
                for (final model in provider.models)
                  {
                    'modelId': model.modelId,
                    'default': provider.autoCompactLimitFor(model).defaultLimit,
                    'override': provider
                        .autoCompactLimitFor(model)
                        .overrideLimit,
                    'effective': provider
                        .autoCompactLimitFor(model)
                        .effectiveLimit,
                    'safe': provider.autoCompactLimitFor(model).safeLimit,
                  },
              ],
            },
        ],
        'roles': [
          for (final role in facts.roles)
            {
              'key': role.key,
              'providerId': role.providerId,
              'model': role.model,
              'effort': role.effort,
            },
        ],
        'modeModelRoutes': [
          for (final route in facts.modeModelRoutes)
            {
              'modeId': route.modeId.id,
              'providerId': route.providerId,
              'model': route.model,
              'effort': route.effort,
            },
        ],
        'mutations': [
          for (final command in facts.commands)
            {
              'key': command.key,
              // 新命令 lane 没有 operation id 或开始时间。保留 key，不发明第二事实源。
              'operationId': null,
              'phase': command.phase.name,
              'startedAt': null,
              'providerId': command.target.providerId,
              'model': command.target.model,
              'effort': command.target.effort,
              'error': command.error?.message,
            },
        ],
        // 双时钟合并诊断没有新的事实源。保留 key，值固定为 null。
        'lastMerge': null,
      },
      'persistence': {
        'revision': facts.persistence.revision,
        'kind': switch (facts.persistence.state) {
          ReadyPersistenceState() => 'ready',
          FlushingPersistenceState() => 'flushing',
          DegradedPersistenceState() => 'degraded',
          RecoveringPersistenceState() => 'recovering',
          BlockedPersistenceState() => 'blocked',
        },
        'pendingCommits': facts.persistence.state.pendingCommits,
        'oldestPendingRevision': facts.persistence.state.oldestPendingRevision,
        'firstFailedAt': facts.persistence.state.firstFailedAt,
        'needsAttention': facts.persistence.needsAttention,
        'errorCode': facts.persistence.state.error?.code,
      },
      'project': facts.project == null
          ? null
          : {'id': facts.project!.id, 'path': facts.project!.path},
      'workspace': workspace == null
          ? null
          : {
              'threadId': workspace.thread.id,
              'syncState': workspace.syncState.name,
              'loadError': workspace.loadError,
              'title': workspace.rootThread.title,
              'projectId': workspace.thread.projectId,
              'rootThreadId': workspace.rootThread.id,
              'threadMode': workspace.thread.mode.name,
              'threadStatus': workspace.thread.status.name,
              'isBusy': workspace.isBusy,
              'model': workspace.runtime.model,
              'modelRoute': workspace.runtime.modelRoute == null
                  ? null
                  : {
                      'providerId': workspace.runtime.modelRoute!.providerId,
                      'model': workspace.runtime.modelRoute!.model,
                      'effort': workspace.runtime.modelRoute!.effort,
                      'revision': workspace.runtime.modelRoute!.revision,
                      'available': workspace.runtime.modelRoute!.available,
                      'unavailableReason':
                          workspace.runtime.modelRoute!.unavailableReason,
                    },
              'usage': {
                'inputTokens': workspace.runtime.promptTokens,
                'outputTokens': workspace.runtime.completionTokens,
                'cacheReadTokens': workspace.runtime.cachedPromptTokens,
                'hasIncompleteUsage': workspace.runtime.hasIncompleteUsage,
              },
              'modelCapabilities': _modelCapabilities(workspace),
              'modelProvider': _modelProvider(workspace),
              'composer': {
                'mode': workspace.composerMode.name,
                'draft': workspace.composer.draft,
                'submissionPending': workspace.composer.isSubmissionPending,
                'lockedByInteraction': workspace.activeInteraction != null,
                'attachments': [
                  for (final attachment in workspace.composer.attachments)
                    {
                      'id': attachment.id,
                      'modality': _attachmentModalityName(attachment.modality),
                      'filename': attachment.filename,
                      'byteSize': attachment.byteSize,
                    },
                ],
              },
              'agents': [
                for (final agent in workspace.agents)
                  {
                    'id': agent.id,
                    'threadId': agent.threadId,
                    'rootThreadId': agent.rootThreadId,
                    'path': agent.path,
                    'parentPath': agent.parentPath,
                    'role': agent.role,
                    'task': agent.task,
                    'status': agent.status,
                    'error': agent.error,
                  },
              ],
              'historyAttachments': [
                for (final item
                    in facts.timeline?.items ?? const <TimelineItemFacts>[])
                  for (final attachment in item.attachments)
                    {
                      'id': attachment.id,
                      'modality': attachment.modality,
                      'filename': attachment.filename,
                      'byteSize': attachment.byteSize,
                      if (attachment.source != null)
                        'source': attachment.source,
                    },
              ],
              'interactionCount': workspace.activeInteraction == null ? 0 : 1,
              'activeInteraction': workspace.activeInteraction == null
                  ? null
                  : {
                      'id': workspace.activeInteraction!.id,
                      'turnId': workspace.activeInteraction!.turnId,
                      'kind': workspace.activeInteraction!.kind.name,
                      'title': workspace.activeInteraction!.title,
                      'body': workspace.activeInteraction!.body,
                    },
              'turn': workspace.turn == null
                  ? null
                  : {
                      'id': workspace.turn!.turnId,
                      'status': workspace.turn!.state.status.name,
                      'activity': workspace.turn!.state.activity?.name,
                      'reason': workspace.turn!.state.reason,
                      'updatedAt': workspace.turn!.updatedAt
                          .toUtc()
                          .toIso8601String(),
                    },
              'lastTurn': lastTurn == null ? null : _turnJson(lastTurn),
            },
      // Workflow and Plan are the lifecycle projections exposed to acceptance
      // drivers. Product-specific orchestration payloads are intentionally not
      // serialized.
      'workflow': workspace?.runtime.workflow == null
          ? null
          : _workflowJson(workspace!.runtime.workflow!),
      'plan': workspace?.runtime.plan == null
          ? null
          : _planJson(workspace!.runtime.plan!),
      // 固定活动条投影：阶段/摘要/并行工具数/完整详情身份。
      'conversationActivity': _conversationActivity == null
          ? null
          : {
              'identity': _conversationActivity!.identity,
              'kind': _conversationActivity!.kind.name,
              'summary': _conversationActivity!.summary,
              'activeToolCount': _conversationActivity!.activeToolCount,
              'backgroundToolCount': _conversationActivity!.backgroundToolCount,
              'errorMessage': _conversationActivity!.errorMessage,
              'expandable': _conversationActivity!.expandable,
              // `expandable` 是能力；`expanded` 是用户此刻的实际展开态。
              'expanded': _activityExpanded,
              'detailsLoading': _conversationActivity!.detailsLoading,
              'detailsError': _conversationActivity!.detailsError,
              'details': [
                for (final detail in _conversationActivity!.details)
                  {'id': detail.id, 'title': detail.title, 'body': detail.body},
              ],
            },
      // 保存故障/恢复的 typed 诊断（只读投影，不是第二份业务状态）。
      //
      // 每个已观测到存储事实的 Thread 一条：typed 故障类别、代数与水位、执行阶段、
      // 硬故障闩 `resumeRequired` 与后端核验的 `canResume`。fixture 用 `history-retry-<id>`
      // 与 `history-resume-<id>`（本块给出与其一致的事实）校验“重试保存 / 继续执行”分离。
      // `null` 一律表示未知，不折叠成 0/健康。
      'storageRecovery': [
        for (final entry in facts.workspacesByThread.entries)
          if (entry.value.storage case final storage?)
            {
              'threadId': entry.key,
              'title': entry.value.thread.title,
              'fault': storage.fault?.name,
              'faultGeneration': storage.faultGeneration,
              'acceptedSequence': storage.acceptedSequence,
              'durableSequence': storage.durableSequence,
              'execution': storage.execution.name,
              'pressurePaused': storage.pressurePaused,
              'resumeRequired': storage.resumeRequired,
              'canResume': storage.canResume,
              'blocksContinuation': storage.blocksContinuation,
              'lastError': storage.lastError,
            },
      ],
    });
  }

  static Map<String, Object?> _planJson(PlanRuntimeView plan) {
    final document = plan.document;
    return {
      'state': plan.state.name,
      'documentVersion': document?.version,
      'contentHash': document?.contentHash,
      'markdown': document?.markdown,
    };
  }

  static Map<String, Object?> _workflowJson(WorkflowRuntimeView workflow) {
    final run = workflow.currentRun;
    return {
      'revision': workflow.revision,
      'currentRun': run == null
          ? null
          : {
              'lineageId': run.lineageId,
              'runId': run.runId,
              'modeId': run.modeId,
              'graphRevision': run.graphRevision,
              'graphHash': run.graphHash,
              'currentStateId': run.currentStateId,
              'terminal': run.terminal,
            },
    };
  }

  static List<String> _modelCapabilities(AgentWorkspaceView workspace) {
    for (final provider in workspace.providers) {
      for (final model in provider.models) {
        if (model.modelId == workspace.runtime.model) {
          return [
            for (final capability in model.inputCapabilities)
              capability.modality.name,
          ];
        }
      }
    }
    return const [];
  }

  static Map<String, Object?>? _modelProvider(AgentWorkspaceView workspace) {
    for (final provider in workspace.providers) {
      if (provider.models.any(
        (model) => model.modelId == workspace.runtime.model,
      )) {
        return {
          'id': provider.id,
          'hasBearerToken': provider.hasBearerToken,
          'credentialEnv': provider.credentialEnv,
        };
      }
    }
    return null;
  }

  /// 展示代次诊断：身份、数量与模式全部来自当前展示真相。
  static Map<String, Object?>? _timelineJson(TimelineDisplayFacts? timeline) {
    if (timeline == null) return null;
    return {
      'threadId': timeline.threadId,
      'generation': timeline.generation,
      'ready': timeline.ready,
      'mode': timeline.mode.name,
      'connection': timeline.connection.name,
      'appliedVersion': timeline.appliedVersion,
      'itemCount': timeline.items.length,
      'itemIds': [for (final item in timeline.items) item.id],
      'presentationItemCount': timeline.presentationItems.length,
      'presentationItems': [
        for (final item in timeline.presentationItems)
          {
            'id': item.id,
            'kind': item.kind,
            'ordinal': item.ordinal,
            'memberIds': item.memberIds,
            'expanded': item.expanded,
            'activeCount': item.activeCount,
            'issueCount': item.issueCount,
          },
      ],
      'olderCursor': timeline.olderCursor,
      'hasOlder': timeline.hasOlder,
      'loadingOlder': timeline.loadingOlder,
      'olderError': timeline.olderError,
      'olderErrorCode': timeline.olderErrorCode?.name,
      'hasNewOutput': timeline.hasNewOutput,
      'preparingLive': timeline.preparingLive,
      'items': [
        for (final item in timeline.items)
          {
            'id': item.id,
            'ordinal': item.ordinal,
            'revision': item.revision,
            'saved': item.saved,
            'terminal': item.terminal,
            'omittedBytes': item.omittedBytes,
            'kind': item.kind,
            'status': item.status,
            'text': item.text,
            'channel': item.channel?.name,
            'details': [
              for (final detail in item.details)
                {
                  'field': detail.field,
                  'revision': detail.revision,
                  'totalBytes': detail.totalBytes,
                  'previewBytes': detail.previewBytes,
                },
            ],
            'attachments': [
              for (final attachment in item.attachments)
                {
                  'id': attachment.id,
                  'modality': attachment.modality,
                  'filename': attachment.filename,
                  'byteSize': attachment.byteSize,
                  if (attachment.source != null) 'source': attachment.source,
                },
            ],
            if (item.tool case final tool?)
              'tool': {
                'name': tool.name,
                'status': tool.status,
                'callId': tool.callId,
                'arguments': tool.arguments,
                'result': tool.result,
                // 在途工具的只读采样字段（同一 typed 事实的派生视图）。
                'output': tool.result,
                'progressBytes': tool.progressBytes,
                'itemRevision': tool.itemRevision,
                'denialReason': tool.denialReason,
                'workingDirectory': tool.workingDirectory,
                'exitCode': tool.exitCode,
                'attachments': [
                  for (final attachment in tool.attachments)
                    {
                      'id': attachment.id,
                      'modality': attachment.modality,
                      'filename': attachment.filename,
                      'byteSize': attachment.byteSize,
                    },
                ],
              },
            if (item.userInput case final userInput?)
              'userInput': {
                'interactionId': userInput.interactionId,
                'state': userInput.state,
                // 计划确认是 typed 判别事实：任何问答都给出真实 bool 与权威决定。
                'isPlanConfirmation': userInput.isPlanConfirmation,
                'planDecision': userInput.planDecision,
              },
          },
      ],
    };
  }

  static Map<String, Object?> _turnJson(StudioTurnView turn) => {
    'id': turn.turnId,
    'inputId': turn.inputId,
    'threadId': turn.threadId,
    'revision': turn.revision,
    'status': turn.state.status.name,
    'activity': turn.state.activity?.name,
    'reason': turn.state.reason,
    if (turn.state case FailedStudioTurnState(:final failure))
      'failure': {
        'category': failure.category,
        'retryable': failure.retryable,
        'message': failure.message,
        'providerKind': failure.providerKind,
        'code': failure.code,
        'httpStatus': failure.httpStatus,
        'retryAfterMs': failure.retryAfterMs,
      },
    'updatedAt': turn.updatedAt.toUtc().toIso8601String(),
  };

  static String _attachmentModalityName(AttachmentModalityView modality) =>
      switch (modality) {
        AttachmentModalityView.image => 'image',
        AttachmentModalityView.video => 'video',
        AttachmentModalityView.file => 'file',
      };
}

/// 当前代次标准 `ScrollController` 的真实几何（design/26 §26.9）。
///
/// 每次诊断请求都**现场**从当前展示 lease 实测挂载的 controller 读取，`isScrolling` 直接
/// 反映该 `ScrollPosition.isScrollingNotifier` 的此刻取值：`ScrollEndNotification` 与
/// activity/notifier 的提交不同步，不能被当成一份可缓存的几何快照。
///
/// `atLiveEdge` 是反向列表 offset 0 的**几何**事实，不等于 Live 模式；History 滚到本地
/// 底端仍然是 History。这里没有 anchor/restore/pin/settling/programmaticScroll/hasNewer
/// 等恢复状态，也不猜测可见行：挂载行位置由 Driver 在请求时扫描真实 element/render tree。
final class TimelineScrollDiagnostic {
  const TimelineScrollDiagnostic({
    required this.threadId,
    required this.generation,
    required this.pixels,
    required this.minScrollExtent,
    required this.maxScrollExtent,
    required this.viewportDimension,
    required this.extentBefore,
    required this.extentAfter,
    required this.atLiveEdge,
    required this.isScrolling,
  });

  final String? threadId;
  final int generation;
  final double? pixels;
  final double? minScrollExtent;
  final double? maxScrollExtent;
  final double? viewportDimension;
  final double? extentBefore;
  final double? extentAfter;
  final bool atLiveEdge;
  final bool isScrolling;

  Map<String, Object?> toJson() => {
    'threadId': threadId,
    'generation': generation,
    'pixels': pixels,
    'minScrollExtent': minScrollExtent,
    'maxScrollExtent': maxScrollExtent,
    'viewportDimension': viewportDimension,
    'extentBefore': extentBefore,
    'extentAfter': extentAfter,
    'atLiveEdge': atLiveEdge,
    'isScrolling': isScrolling,
  };
}
