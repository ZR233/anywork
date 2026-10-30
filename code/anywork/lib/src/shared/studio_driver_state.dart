import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/model_directory.dart';

import '../domain/models/agent_workspace_view.dart';
import '../domain/models/timeline_commands.dart';

/// 一个展示代次的只读事实（design/26 §26.9）。
///
/// `items` 来自当前 lease 的完整原子集合；可见 owner 来自 stock controller 的真实消息，
/// hidden owner 从同一 lease 读取。只用于验收，不保留第二份业务事实源。
final class TimelineDisplayFacts {
  TimelineDisplayFacts({
    required this.threadId,
    required this.generation,
    required this.ready,
    required this.mode,
    required this.connection,
    required this.timelineEpoch,
    required this.completedThrough,
    required this.loadedCount,
    required this.olderCursor,
    required this.hasOlder,
    required this.loadingOlder,
    required this.olderError,
    required this.olderErrorCode,
    required this.olderErrorCorrelationId,
    required this.hasNewOutput,
    List<TimelineItemFacts> items = const [],
    List<TimelinePresentationFacts> presentationItems = const [],
    List<TimelinePresentationFacts> hiddenPresentationItems = const [],
  }) : items = List.unmodifiable(items),
       presentationItems = List.unmodifiable(presentationItems),
       hiddenPresentationItems = List.unmodifiable(hiddenPresentationItems);

  final String threadId;
  final int generation;
  final bool ready;
  final TimelineDisplayMode mode;
  final TimelineConnectionPhase connection;
  final String? timelineEpoch;
  final int? completedThrough;
  final int? loadedCount;
  final String? olderCursor;
  final bool hasOlder;
  final bool loadingOlder;
  final String? olderError;
  final StudioFailureCode? olderErrorCode;
  final String? olderErrorCorrelationId;
  final bool hasNewOutput;
  final List<TimelineItemFacts> items;
  final List<TimelinePresentationFacts> presentationItems;
  final List<TimelinePresentationFacts> hiddenPresentationItems;
}

/// GUI groups have their own identity; members still denote individual canonical records.
///
/// `memberIds` 始终是全部 canonical 成员，视觉去重只体现在 [visibleMemberIds] 与
/// [skillPairs]：被技能行接管的原调用仍可按自己的身份查询，同时诊断能说清当前只有一条
/// 可见技能行（design/26 §26.8、§26.9）。
final class TimelinePresentationFacts {
  TimelinePresentationFacts({
    required this.id,
    required this.kind,
    required this.firstAppendSeq,
    required List<String> memberIds,
    required List<String> visibleMemberIds,
    required Map<String, String> skillPairs,
    required this.expanded,
    required this.issueCount,
  }) : memberIds = List.unmodifiable(memberIds),
       visibleMemberIds = List.unmodifiable(visibleMemberIds),
       skillPairs = Map.unmodifiable(skillPairs);

  final String id;
  final String kind;
  final int firstAppendSeq;
  final List<String> memberIds;

  /// 当前组内可见活动行的成员身份，按 canonical 顺序。
  final List<String> visibleMemberIds;

  /// 可见技能行接管的原调用：技能成员身份 → `skill_view` 调用条目身份。
  final Map<String, String> skillPairs;

  final bool expanded;
  final int issueCount;
}

/// 一条 canonical item 的轻量 typed 预览诊断。
final class TimelineItemFacts {
  TimelineItemFacts({
    required this.id,
    required this.appendSeq,
    required this.sourceEffectSeq,
    required this.sealedAt,
    required this.omittedBytes,
    required this.kind,
    required this.status,
    required this.text,
    required this.channel,
    List<TimelineDetailFacts> details = const [],
    List<TimelineAttachmentFacts> attachments = const [],
    this.tool,
    this.userInput,
    this.plan,
  }) : details = List.unmodifiable(details),
       attachments = List.unmodifiable(attachments);

  final String id;
  final int appendSeq;
  final int? sourceEffectSeq;
  final int? sealedAt;
  final int omittedBytes;
  final String kind;
  final String status;

  /// 已脱敏的预览正文（工具行是命令摘要，不是完整参数）。
  final String text;

  /// 文本条目的权威频道（commentary / finalAnswer / user / parentAgent）；
  /// 非文本条目为 null。它来自 `ConversationTextDescriptor.channel`，不从 kind 或文本推测：
  /// `agentMessage` 同时覆盖 commentary 与 finalAnswer。
  final ThreadTextChannel? channel;
  final List<TimelineDetailFacts> details;
  final List<TimelineAttachmentFacts> attachments;
  final TimelineToolFacts? tool;
  final TimelineUserInputFacts? userInput;
  final TimelinePlanFacts? plan;
}

/// 已完成 Plan 自己的身份和有界字段预览，不读取或回填当前 Plan。
/// 完整字段长度仍由同一 item 的 details 给出；缺失来源保持 null。
final class TimelinePlanFacts {
  const TimelinePlanFacts({
    required this.interactionId,
    required this.decision,
    required this.documentVersion,
    required this.contentHash,
    required this.document,
    required this.feedback,
  });

  final String interactionId;
  final String decision;
  final int? documentVersion;
  final String? contentHash;
  final String? document;
  final String? feedback;
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
    required this.appendSeq,
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
  final int appendSeq;
  final String? denialReason;
  final String? workingDirectory;
  final int? exitCode;
  final List<TimelineAttachmentFacts> attachments;
}

/// 一个内容字段的详情引用诊断（字段身份 + 完整/预览字节数）。
final class TimelineDetailFacts {
  const TimelineDetailFacts({
    required this.field,
    required this.totalBytes,
    required this.previewBytes,
  });

  final String field;
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

  /// 这条问答是否就是计划确认：只有归属工具为 `plan_submit` 且 public typed
  /// `planReceipt != null` 时成立；普通问答复用了保留的问题 ID 也仍为 false。
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
    this.visibleThreadId,
    this.presentationThreadId,
    this.newThreadMode = ThreadModeId.simple,
    this.newThreadWorkspaceMode = ThreadWorkspaceMode.local,
    this.newThreadComposer = const ComposerThreadState.idle(),
    this.threadComposer = const ComposerThreadState.idle(),
    this.settingsRevision = 0,
    this.sidebarWidth,
    List<ModeModelRouteView> modeModelRoutes = const [],
    List<RoleSettingsView> roles = const [],
    List<ModelSelectionAccount> accounts = const [],
    this.accountSummaries,
    this.modelDirectory,
    this.accountUsage,
    Map<NativeAccountIdentity, StudioFailure> accountUsageQueryFailures =
        const {},
    Map<AccountIdentity, AccountResource<AccountDetails>> accountDetails =
        const {},
    List<String> accountTemplates = const [],
    this.acpAuth = const AcpAuthSnapshotView.empty(),
    this.acpAuthResource,
    this.acpInstallResource,
    required this.acpAuthLoaded,
    this.acpInstall,
    List<CommandStatus> commands = const [],
    this.settingsReady = false,
    this.persistence = const PersistenceStateSnapshot.ready(),
    List<StudioRecoveryIssue> recoveryIssues = const [],
    this.project,
    this.workspace,
    this.bots,
  }) : workspacesByThread = Map.unmodifiable(workspacesByThread),
       rootThreads = List.unmodifiable(rootThreads),
       modeModelRoutes = List.unmodifiable(modeModelRoutes),
       roles = List.unmodifiable(roles),
       accounts = List.unmodifiable(accounts),
       accountUsageQueryFailures = Map.unmodifiable(accountUsageQueryFailures),
       accountDetails = Map.unmodifiable(accountDetails),
       accountTemplates = List.unmodifiable(accountTemplates),
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
  final String? visibleThreadId;
  final String? presentationThreadId;
  final ThreadModeId newThreadMode;
  final ThreadWorkspaceMode newThreadWorkspaceMode;
  final ComposerThreadState newThreadComposer;
  final ComposerThreadState threadComposer;
  final int settingsRevision;
  final int? sidebarWidth;

  final List<ModeModelRouteView> modeModelRoutes;
  final List<RoleSettingsView> roles;
  final List<ModelSelectionAccount> accounts;
  final AccountsState? accountSummaries;
  final ModelDirectoryState? modelDirectory;
  final AccountResource<Map<NativeAccountIdentity, AccountUsageObservation>>?
  accountUsage;

  /// Client query/transport diagnostics, never a canonical usage phase.
  final Map<NativeAccountIdentity, StudioFailure> accountUsageQueryFailures;
  final Map<AccountIdentity, AccountResource<AccountDetails>> accountDetails;

  /// ACP 接入配置与认证观察：与 Native 账号并列的独立事实源。
  /// Only already observed target details; Driver never opens a detail demand.
  Iterable<AcpAccountSettingsView> get acpAccounts => [
    for (final resource in accountDetails.values)
      if (resource.value case AcpAccountDetails(:final account)) account,
  ];
  final List<String> accountTemplates;
  final AcpAuthSnapshotView acpAuth;
  final AccountResource<AcpAuthSnapshotView>? acpAuthResource;
  final AccountResource<AcpInstallSnapshotView>? acpInstallResource;

  /// `acpAuth` 是否来自**已加载**的 canonical 观察。
  ///
  /// 未加载时 [acpAuth] 只是空占位（revision 0 也是合法已加载水位），因此必须用
  /// 独立事实区分；证据不得由占位快照或缺失条目推断成"未检查"。
  final bool acpAuthLoaded;

  /// `acpInstall` 的准备观察快照（含 loaded/revision 与各 provider 阶段）。
  ///
  /// 与 `acpAuth` 分开：准备事实不能替代认证事实，下载完成也不是已保存。
  final StudioDriverAcpInstallFacts? acpInstall;
  final List<CommandStatus> commands;
  final bool settingsReady;
  final PersistenceStateSnapshot persistence;
  final List<StudioRecoveryIssue> recoveryIssues;
  final StudioProject? project;
  final AgentWorkspaceView? workspace;
  final StudioDriverBotsFacts? bots;
}

/// `acpInstall` 的只读取证事实。
///
/// 阶段、进度与失败类别全部来自 typed 状态；[phase] 只是稳定 token，供 Driver
/// 与验收编排等待真实可见状态，不做业务判定。
final class StudioDriverAcpInstallFacts {
  StudioDriverAcpInstallFacts({
    required this.loaded,
    required this.revision,
    required List<StudioDriverAcpInstallEntryFacts> installations,
  }) : installations = List.unmodifiable(installations);

  final bool loaded;
  final int revision;
  final List<StudioDriverAcpInstallEntryFacts> installations;
}

final class StudioDriverAcpInstallEntryFacts {
  const StudioDriverAcpInstallEntryFacts({
    required this.provider,
    required this.phase,
    this.operationId,
    this.stage,
    this.completedBytes = 0,
    this.totalBytes,
    this.bytesPerSecond,
    this.retryCount = 0,
    this.version,
    this.target,
    this.archiveUrl,
    this.sha256,
    this.hasPublisherChecksum = false,
    this.program,
    this.reused = false,
    this.failureCode,
    this.failureRetryable,
  });

  final String provider;

  /// 稳定阶段 token：`idle`/`resolving`/`waiting`/`downloading`/`verifying`/
  /// `extracting`/`publishing`/`closing`/`ready`/`cancelling`/`cancelled`/`failed`。
  final String phase;

  final String? operationId;
  final String? stage;
  final int completedBytes;
  final int? totalBytes;
  final int? bytesPerSecond;
  final int retryCount;
  final String? version;
  final String? target;

  /// 冻结的分发地址：官方 canonical 值，不含 userinfo/临时凭据。
  final String? archiveUrl;

  /// 发行方摘要（可空）；retry/resume 用它核对同一冻结描述符，不以布尔替代身份。
  final String? sha256;

  final bool hasPublisherChecksum;

  /// 安装后的只读诊断路径；受管启动 argv 由产品固定发行决定，不再对外投影。
  final String? program;
  final bool reused;
  final String? failureCode;
  final bool? failureRetryable;
}

final class StudioDriverBotsFacts {
  StudioDriverBotsFacts({
    required this.revision,
    required List<StudioDriverBotFacts> bots,
    required List<StudioDriverPendingCredentialFacts> pending,
    this.registrationAttemptId,
    this.registrationKind,
    this.registrationBotId,
    this.completedBotId,
  }) : bots = List.unmodifiable(bots),
       pending = List.unmodifiable(pending);

  final int revision;
  final List<StudioDriverBotFacts> bots;
  final List<StudioDriverPendingCredentialFacts> pending;
  final String? registrationAttemptId;
  final String? registrationKind;
  final String? registrationBotId;
  final String? completedBotId;
}

final class StudioDriverBotFacts {
  const StudioDriverBotFacts({
    required this.id,
    required this.name,
    required this.enabled,
    required this.credential,
    required this.connectionKind,
    required this.pendingKind,
    required this.configCommitted,
    required this.configRevision,
    required this.trustedUserCount,
    required this.trustedGroupCount,
    required this.pairingCount,
    required this.canChangeProject,
    required this.canChangeAppId,
  });

  final String id;
  final String name;
  final bool enabled;
  final String credential;
  final String connectionKind;
  final String? pendingKind;
  final bool? configCommitted;
  final int configRevision;
  final int trustedUserCount;
  final int trustedGroupCount;
  final int pairingCount;
  final bool canChangeProject;
  final bool canChangeAppId;
}

final class StudioDriverPendingCredentialFacts {
  const StudioDriverPendingCredentialFacts({
    required this.botId,
    required this.kind,
    required this.configCommitted,
  });

  final String botId;
  final String kind;
  final bool? configCommitted;
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

  /// 没有装配 query 时没有任何 canonical 观察：明确标记未加载。
  static StudioDriverFacts readFacts() =>
      _query?.call() ?? StudioDriverFacts(acpAuthLoaded: false);

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

  /// 记录启动致命失败的 typed code 与 correlation，供
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
    // Static templates are observed independently of account summaries. Only
    // their own revision distinguishes a loaded directory from empty().
    final catalog = facts.accountSummaries?.templates;
    final templates = catalog != null && catalog.revision.isNotEmpty
        ? catalog
        : null;
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
      'bots': _botsJson(facts.bots),
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
        'visibleThreadId': facts.visibleThreadId,
        'presentationThreadId': facts.presentationThreadId,
        'isStartPage':
            facts.selectedThreadId == null &&
            facts.presentationThreadId == null,
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
        'accountDomains': {
          'schemaVersion': 2,
          'summaries': studioDriverSummariesJson(facts.accountSummaries),
          'templates': {
            'loaded': templates != null,
            'revision': templates?.revision,
            'usable': templates?.isUsable,
          },
          'accounts': [
            for (final summary
                in facts.accountSummaries?.accounts ?? const <AccountSummary>[])
              {
                'kind': summary.identity is NativeAccountIdentity
                    ? 'native'
                    : 'acp',
                'id': summary.identity.accountId,
                'name': summary.name,
                'isDefault': summary.isDefault,
                'credentialReady': summary.credentialReady,
                'billingKind': summary.billingKind?.name,
                'billingKindOverride': summary.billingKindOverride?.name,
                'usageQueryRevision': summary.usageQueryRevision,
                'acpConnectionRevision': summary.acpConnectionRevision,
                'details': studioDriverResourceJson(
                  facts.accountDetails[summary.identity],
                ),
              },
          ],
          'catalogs': [
            for (final entry
                in facts.modelDirectory?.accounts.entries ??
                    const <
                      MapEntry<
                        NativeAccountIdentity,
                        AccountResource<AccountModelCatalog>
                      >
                    >[])
              {
                'accountId': entry.key.accountId,
                ...studioDriverResourceJson(entry.value),
              },
          ],
          'configurations': [
            for (final entry
                in facts.modelDirectory?.configurations.entries ??
                    const <
                      MapEntry<
                        NativeAccountIdentity,
                        AccountResource<AccountModelConfiguration>
                      >
                    >[])
              {
                'accountId': entry.key.accountId,
                ...studioDriverResourceJson(entry.value),
                'modelEnabledOverrides':
                    entry.value.value?.modelEnabledOverrides,
                'connections': entry.value.value?.connections.map(
                  (key, value) => MapEntry(key, value.name),
                ),
                'autoCompactLimits': entry.value.value?.autoCompactLimits,
              },
          ],
          'usage': {
            ...studioDriverResourceJson(facts.accountUsage),
            'queryFailures': [
              for (final entry in facts.accountUsageQueryFailures.entries)
                {
                  'accountId': entry.key.accountId,
                  'code': entry.value.code.name,
                  'retryable': entry.value.retryable,
                  'correlationId': entry.value.correlationId,
                },
            ],
            'accounts': [
              for (final observation
                  in facts.accountUsage?.value?.values ??
                      const <AccountUsageObservation>[])
                _usageJson(observation),
            ],
          },
        },
        'accounts': [
          for (final account in facts.accounts)
            {
              'id': account.id,
              'templateId': _nativeDetails(facts, account.id)?.templateId,
              'protocol': _nativeDetails(facts, account.id)?.protocol,
              'billingKind': account.billingKind?.name,
              'billingKindOverride': facts.accountSummaries
                  ?.account(NativeAccountIdentity(account.id))
                  ?.billingKindOverride
                  ?.name,
              'hasBearerToken': _nativeDetails(
                facts,
                account.id,
              )?.hasBearerToken,
              'credentialReady': facts.accountSummaries
                  ?.account(NativeAccountIdentity(account.id))
                  ?.credentialReady,
              'models': [for (final model in account.models) model.modelId],
              'textModels': [
                for (final model in account.modelsFor(type: ModelType.text))
                  model.modelId,
              ],
              'modelDetails': [
                for (final model in account.models)
                  {
                    'modelId': model.modelId,
                    'enabled': model.enabled,
                    'origin': model.origin.name,
                    'connectionMode': model.connectionMode,
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
              'modelCatalog': _catalogJson(facts, account.id),
              // 配置意图与模型层最终解析结果，Driver 不派生阈值。
              // 缺失值保持 null，便于 Driver 断言未知容量与覆盖归一化。
              'autoCompactLimits': [
                for (final model in account.models)
                  {
                    'modelId': model.modelId,
                    'override': facts
                        .modelDirectory
                        ?.configurations[NativeAccountIdentity(account.id)]
                        ?.value
                        ?.autoCompactLimits[model.modelId],
                    'effective': model.context.autoCompactLimit,
                    'adjustment': model.context.adjustment?.name,
                    'unavailable': model.context.unavailable?.name,
                  },
              ],
            },
        ],
        // 同一“添加账号”入口的 typed 模板 token：Native 用模板 id，ACP 用 provider wire。
        'nativeTemplates': templates == null
            ? null
            : [for (final template in templates.templates) template.id],
        'acpAccounts': [
          for (final account
              in facts.accountSummaries?.accounts ?? const <AccountSummary>[])
            if (account.identity is AcpAccountIdentity)
              {
                'accountId': account.identity.accountId,
                'name': account.name,
                'provider': _acpDetails(facts, account.identity)?.provider.wire,
                'connectionRevision': account.acpConnectionRevision,
              },
        ],
        'acpAuth': {
          ...studioDriverResourceJson(facts.acpAuthResource),
          'loaded': facts.acpAuthLoaded,
          'revision': facts.acpAuth.revision,
          'updatedAt': facts.acpAuth.updatedAt,
          'accounts': [
            for (final account in facts.acpAuth.accounts)
              {
                'accountId': account.accountId,
                'connectionRevision': account.connectionRevision,
                'state': _acpAuthStateJson(account.state),
              },
          ],
        },
        'acpInstall': facts.acpInstall == null
            ? studioDriverResourceJson(facts.acpInstallResource)
            : {
                ...studioDriverResourceJson(facts.acpInstallResource),
                ..._acpInstallFactsJson(facts.acpInstall)!,
              },
        'roles': [
          for (final role in facts.roles)
            {
              'key': role.key,
              'accountId': role.accountId,
              'modelId': role.modelId,
              'effort': role.effort,
            },
        ],
        'modeModelRoutes': [
          for (final route in facts.modeModelRoutes)
            {
              'modeId': route.modeId.id,
              'accountId': route.accountId,
              'modelId': route.modelId,
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
              'accountId': command.target.accountId,
              'modelId': command.target.modelId,
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
          : {
              'id': facts.project!.id,
              'kind': facts.project!.kind.name,
              'path': facts.project!.path,
            },
      'workspace': workspace == null
          ? null
          : {
              'threadId': workspace.thread.id,
              'syncState': workspace.syncState.name,
              'loadError': workspace.loadError,
              'title': workspace.rootThread.title,
              'workspaceId': workspace.thread.workspaceId,
              'rootThreadId': workspace.rootThread.id,
              'threadMode': workspace.thread.mode.name,
              'threadStatus': workspace.thread.status.name,
              'isBusy': workspace.isBusy,
              'model': workspace.runtime.modelId,
              'modelRoute': workspace.runtime.modelRoute == null
                  ? null
                  : {
                      'accountId': workspace.runtime.modelRoute!.accountId,
                      'modelId': workspace.runtime.modelRoute!.modelId,
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
              'modelAccount': _modelAccount(workspace, facts),
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
              'turnId': _conversationActivity!.turnId,
              'executionId': _conversationActivity!.executionId,
              'summary': _conversationActivity!.summary,
              'reasoningParts': [
                for (final part in _conversationActivity!.reasoningParts)
                  {
                    'itemId': part.itemId,
                    'complete': part.complete,
                    'text': part.text,
                    'byteLength': utf8.encode(part.text).length,
                  },
              ],
              'reasoningBytes': _conversationActivity!.reasoningParts.fold(
                0,
                (total, part) => total + utf8.encode(part.text).length,
              ),
              'responseParts': [
                for (final part in _conversationActivity!.responseParts)
                  {
                    'itemId': part.itemId,
                    'complete': part.complete,
                    'text': part.text,
                    'byteLength': utf8.encode(part.text).length,
                  },
              ],
              'responseBytes': _conversationActivity!.responseParts.fold(
                0,
                (total, part) => total + utf8.encode(part.text).length,
              ),
              'activeToolCount': _conversationActivity!.activeToolCount,
              'backgroundToolCount': _conversationActivity!.backgroundToolCount,
              'errorMessage': _conversationActivity!.errorMessage,
              'expandable': _conversationActivity!.expandable,
              // `expandable` 是能力；`expanded` 是用户此刻的实际展开态。
              'expanded': _activityExpanded,
              'toolDetails': [
                for (final tool in _conversationActivity!.toolDetails)
                  {
                    'callId': tool.callId,
                    'taskId': tool.taskId,
                    'name': tool.name,
                    'state': tool.state.name,
                    'outputParts': [
                      for (final part in tool.outputParts ?? const [])
                        {
                          'partId': part.partId,
                          'text': part.text,
                          'byteLength': utf8.encode(part.text).length,
                        },
                    ],
                    'outputBytes': (tool.outputParts ?? const []).fold(
                      0,
                      (total, part) => total + utf8.encode(part.text).length,
                    ),
                  },
              ],
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

  /// 展示用模型身份一律来自已解析的 Thread 路由 `(accountId, modelId)`。
  ///
  /// 同名模型可同时存在于多个账号，裸 model id 不足以定位账号：路由缺失、账号未知或
  /// 该账号目录不含此模型时返回 `null` 保持 unknown，不按 model id 猜另一个账号。
  static ({ModelSelectionAccount account, AccountModelView model})?
  _routedAccountModel(AgentWorkspaceView workspace) {
    final route = workspace.runtime.modelRoute;
    if (route == null) return null;
    for (final account in workspace.accounts) {
      if (account.id != route.accountId) continue;
      for (final model in account.models) {
        if (model.modelId == route.modelId) {
          return (account: account, model: model);
        }
      }
      return null;
    }
    return null;
  }

  static List<String> _modelCapabilities(AgentWorkspaceView workspace) {
    final routed = _routedAccountModel(workspace);
    if (routed == null) return const [];
    return [
      for (final capability in routed.model.inputCapabilities)
        capability.modality.name,
    ];
  }

  static Map<String, Object?>? _modelAccount(
    AgentWorkspaceView workspace,
    StudioDriverFacts facts,
  ) {
    final routed = _routedAccountModel(workspace);
    if (routed == null) return null;
    return {
      'id': routed.account.id,
      'hasBearerToken': _nativeDetails(
        facts,
        routed.account.id,
      )?.hasBearerToken,
      'credentialReady': facts.accountSummaries
          ?.account(NativeAccountIdentity(routed.account.id))
          ?.credentialReady,
      'credentialEnv': null,
    };
  }

  static Map<String, Object?>? _botsJson(StudioDriverBotsFacts? bots) {
    if (bots == null) return null;
    return {
      'revision': bots.revision,
      'bots': [
        for (final bot in bots.bots)
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
        for (final pending in bots.pending)
          {
            'botId': pending.botId,
            'kind': pending.kind,
            'configCommitted': pending.configCommitted,
          },
      ],
      'registrationAttemptId': bots.registrationAttemptId,
      'registrationKind': bots.registrationKind,
      'registrationBotId': bots.registrationBotId,
      'completedBotId': bots.completedBotId,
    };
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
      'timelineEpoch': timeline.timelineEpoch,
      'completedThrough': timeline.completedThrough,
      'loadedCount': timeline.loadedCount,
      'itemCount': timeline.items.length,
      'itemIds': [for (final item in timeline.items) item.id],
      'presentationItemCount': timeline.presentationItems.length,
      'presentationItems': [
        for (final item in timeline.presentationItems)
          {
            'id': item.id,
            'kind': item.kind,
            'firstAppendSeq': item.firstAppendSeq,
            'memberIds': item.memberIds,
            'visibleMemberIds': item.visibleMemberIds,
            'skillPairs': item.skillPairs,
            'expanded': item.expanded,
            'issueCount': item.issueCount,
          },
      ],
      'hiddenPresentationItems': [
        for (final item in timeline.hiddenPresentationItems)
          {
            'id': item.id,
            'kind': item.kind,
            'firstAppendSeq': item.firstAppendSeq,
            'memberIds': item.memberIds,
            'visibleMemberIds': item.visibleMemberIds,
            'skillPairs': item.skillPairs,
            'expanded': item.expanded,
            'issueCount': item.issueCount,
          },
      ],
      'olderCursor': timeline.olderCursor,
      'hasOlder': timeline.hasOlder,
      'loadingOlder': timeline.loadingOlder,
      'olderError': timeline.olderError,
      'olderErrorCode': timeline.olderErrorCode?.name,
      'olderErrorCorrelationId': timeline.olderErrorCorrelationId,
      'hasNewOutput': timeline.hasNewOutput,
      'items': [
        for (final item in timeline.items)
          {
            'id': item.id,
            'appendSeq': item.appendSeq,
            'sourceEffectSeq': item.sourceEffectSeq,
            'sealedAt': item.sealedAt,
            'omittedBytes': item.omittedBytes,
            'kind': item.kind,
            'status': item.status,
            'text': item.text,
            'channel': item.channel?.name,
            'details': [
              for (final detail in item.details)
                {
                  'field': detail.field,
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
                'appendSeq': tool.appendSeq,
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
            if (item.plan case final plan?)
              'plan': {
                'interactionId': plan.interactionId,
                'decision': plan.decision,
                'documentVersion': plan.documentVersion,
                'contentHash': plan.contentHash,
                'document': plan.document,
                'feedback': plan.feedback,
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

/// Resource identity is kept intact: no settings watermark substitutes for it.
Map<String, Object?>? studioDriverStampJson(ResourceStamp? stamp) =>
    stamp == null
    ? null
    : {
        'resourceKey': stamp.resourceKey,
        'ownerEpoch': stamp.ownerEpoch,
        'revision': stamp.revision,
      };

Map<String, Object?> studioDriverSummariesJson(AccountsState? state) => {
  'loaded': state?.loaded ?? false,
  'stale': state?.stale ?? false,
  'loading': state?.loading ?? false,
  'stamp': studioDriverStampJson(state?.stamp),
  'error': state?.failure?.code.name,
};

Map<String, Object?> studioDriverResourceJson<T>(
  AccountResource<T>? resource,
) => {
  'loaded': resource?.loaded ?? false,
  'stale': resource?.stale ?? false,
  'hasValue': resource?.value != null,
  'loading': resource?.loading ?? false,
  'stamp': studioDriverStampJson(resource?.stamp),
  'error': resource?.failure?.code.name,
};

NativeAccountDetails? _nativeDetails(StudioDriverFacts facts, String id) =>
    switch (facts.accountDetails[NativeAccountIdentity(id)]?.value) {
      NativeAccountDetails details => details,
      _ => null,
    };

AcpAccountSettingsView? _acpDetails(
  StudioDriverFacts facts,
  AccountIdentity identity,
) => switch (facts.accountDetails[identity]?.value) {
  AcpAccountDetails(:final account) => account,
  _ => null,
};

Map<String, Object?>? _catalogJson(StudioDriverFacts facts, String id) {
  final catalog = facts.modelDirectory?.accounts[NativeAccountIdentity(id)];
  final status = catalog?.value?.status;
  if (status == null) return null;
  return {
    ...studioDriverResourceJson(catalog),
    'supported': status.supported,
    'source': status.source.name,
    'probing': status.probing,
    'error': status.error?.kind.name,
    'cacheWarning': status.cacheWarning?.name,
    'lastSuccessAt': status.lastSuccessAt,
    'checkedAt': status.checkedAt,
  };
}

Map<String, Object?> _usageJson(AccountUsageObservation observation) => {
  'accountId': observation.identity.accountId,
  'queryRevision': observation.queryRevision,
  'revision': observation.revision,
  'phase': observation.phase.name,
  'operationId': observation.operationId,
  'checkedAt': observation.checkedAt,
  'failure': observation.failure == null
      ? null
      : {
          'code': observation.failure!.code.name,
          'retryable': observation.failure!.retryable,
        },
  'lastGood': observation.lastGood == null
      ? null
      : {
          'checkedAt': observation.lastGood!.checkedAt,
          'value': switch (observation.lastGood!.value) {
            AccountBalance(:final available, :final balances) => {
              'kind': 'balance',
              'available': available,
              'balances': [
                for (final balance in balances)
                  {
                    'currency': balance.currency,
                    'total': balance.total,
                    'granted': balance.granted,
                    'toppedUp': balance.toppedUp,
                  },
              ],
            },
            AccountSubscription(:final level, :final quotas) => {
              'kind': 'subscription',
              'level': level,
              'quotas': [
                for (final quota in quotas)
                  {
                    'window': quota.window.kind.name,
                    'name': quota.window.name,
                    'percentage': quota.percentage,
                    'used': quota.used,
                    'total': quota.total,
                    'remaining': quota.remaining,
                    'resetAt': quota.resetAt,
                    'details': [
                      for (final detail in quota.details)
                        {
                          'name': detail.name,
                          'used': detail.used,
                          'total': detail.total,
                          'percentage': detail.percentage,
                        },
                    ],
                  },
              ],
            },
          },
        },
};

/// ACP 认证状态的只读投影：`kind` 与界面阶段 token 一致，便于 Driver 断言。
Map<String, Object?> _acpAuthStateJson(AcpAuthStateView state) =>
    switch (state) {
      AcpUncheckedState() => {'kind': 'unchecked'},
      AcpCheckingState(:final operationId) => {
        'kind': 'checking',
        'operationId': operationId,
      },
      AcpRequiredState(:final server, :final methods) => {
        'kind': 'required',
        'server': server == null ? null : _acpServerJson(server),
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
      AcpAuthenticatingState(:final operationId, :final methodId) => {
        'kind': 'authenticating',
        'operationId': operationId,
        'methodId': methodId,
      },
      AcpVerifyingState(:final operationId) => {
        'kind': 'verifying',
        'operationId': operationId,
      },
      AcpVerifiedState(:final checkedAt, :final server) => {
        'kind': 'verified',
        'checkedAt': checkedAt,
        'server': server == null ? null : _acpServerJson(server),
      },
      AcpClosingState(:final operationId, :final failure) => {
        'kind': 'closing',
        'operationId': operationId,
        'failure': failure == null
            ? null
            : {
                'code': failure.code.name,
                'stage': failure.stage.name,
                'retryable': failure.retryable,
              },
      },
      AcpCancellingState(:final operationId) => {
        'kind': 'cancelling',
        'operationId': operationId,
      },
      AcpCancelledState() => {'kind': 'cancelled'},
      AcpFailedState(:final failure) => {
        'kind': 'failed',
        'failure': {
          'code': failure.code.name,
          'stage': failure.stage.name,
          'retryable': failure.retryable,
        },
      },
    };

Map<String, Object?> _acpServerJson(AcpServerInfoView server) => {
  'name': server.name,
  'title': server.title,
  'version': server.version,
};

/// ACP 服务器准备事实的只读投影。
///
/// [StudioDriverAcpInstallFacts.loaded] 与 `revision` 是 Driver 判断“是否已加载”
/// 的唯一依据；revision 0 也是合法已加载水位，不能当成缺失。
Map<String, Object?>? _acpInstallFactsJson(StudioDriverAcpInstallFacts? facts) {
  if (facts == null) return null;
  return {
    'loaded': facts.loaded,
    'revision': facts.revision,
    'installations': [
      for (final entry in facts.installations)
        {
          'provider': entry.provider,
          'phase': entry.phase,
          'operationId': entry.operationId,
          'stage': entry.stage,
          'progress': {
            'completedBytes': entry.completedBytes,
            'totalBytes': entry.totalBytes,
            'bytesPerSecond': entry.bytesPerSecond,
          },
          'retryCount': entry.retryCount,
          'release': entry.version == null
              ? null
              : {
                  'version': entry.version,
                  'target': entry.target,
                  'archiveUrl': entry.archiveUrl,
                  'sha256': entry.sha256,
                  'hasPublisherChecksum': entry.hasPublisherChecksum,
                },
          'program': entry.program,
          'reused': entry.reused,
          'failure': entry.failureCode == null
              ? null
              : {
                  'code': entry.failureCode,
                  'retryable': entry.failureRetryable,
                },
        },
    ],
  };
}
