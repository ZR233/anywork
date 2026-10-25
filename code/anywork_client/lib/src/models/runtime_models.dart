import 'agent_models.dart';
import 'collection_equality.dart';

/// 继续点存在的原因。只有中断本身能证明的原因才会记录。
enum ContinuationReason {
  userStop,
  hostShutdown,
  processInterrupted,
  stepLimit,
  executionFailed;

  /// Canonical wire 标签。
  String get label => name;
}

/// 会话当前继续点的只读投影。
///
/// 它只回答「这个会话还有哪些因中断未完成的工作」，不复制任务正文；`claimed` 区分
/// 「可以继续」与「继续已受理、仍在准备或等待准入」。客户端不从轮次终态或最后一条
/// 消息推断能否继续，也不在本地生成这个身份。
final class ContinuationView {
  const ContinuationView({
    required this.id,
    required this.createdAt,
    required this.claimed,
    this.sourceTurnId,
    this.reason,
  });

  final String id;

  /// 被中断的轮次；尚未创建轮次就停止时为空。
  final String? sourceTurnId;

  /// 已知中断原因；无法证明具体原因时为空，不伪造「用户点击停止」。
  final ContinuationReason? reason;
  final DateTime createdAt;

  /// 本次继续意图已被认可（或已被另一次受理认领），不能再发起新的继续。
  final bool claimed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContinuationView &&
          id == other.id &&
          sourceTurnId == other.sourceTurnId &&
          reason == other.reason &&
          createdAt == other.createdAt &&
          claimed == other.claimed;

  @override
  int get hashCode => Object.hash(id, sourceTurnId, reason, createdAt, claimed);
}

class RuntimeCostView {
  const RuntimeCostView({required this.currency, required this.amount});

  final String currency;
  final double amount;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RuntimeCostView &&
            currency == other.currency &&
            amount == other.amount;
  }

  @override
  int get hashCode => Object.hash(currency, amount);
}

/// 已知币种显示为货币符号；未知币种回退为币种代码前缀。
const Map<String, String> _runtimeCurrencySymbols = {'CNY': '￥', 'USD': r'$'};

/// 费用金额显示：四舍五入并固定保留 2 位小数。
String formatRuntimeCostAmount(String currency, double amount) {
  final rounded = amount.toStringAsFixed(2);
  final display = rounded == '-0.00' ? '0.00' : rounded;
  final symbol = _runtimeCurrencySymbols[currency.toUpperCase()];
  if (symbol != null) {
    return '$symbol$display';
  }
  return '$currency $display'.trim();
}

/// 多币种实际花费合并显示，如 `￥1.20 + $2.60`；不做汇率换算。
String formatRuntimeCosts(Iterable<RuntimeCostView> costs) {
  return costs
      .map((cost) => formatRuntimeCostAmount(cost.currency, cost.amount))
      .where((label) => label.isNotEmpty)
      .join(' + ');
}

/// 只格式化吞吐数值；单位由展示层按 locale 追加，避免在领域模型内写死文案。
String? formatTokenThroughputValue(double? tokensPerSecond) {
  if (tokensPerSecond == null || !tokensPerSecond.isFinite) return null;
  return tokensPerSecond >= 10
      ? tokensPerSecond.round().toString()
      : tokensPerSecond.toStringAsFixed(1);
}

class PurposeCostView {
  const PurposeCostView({
    this.purpose,
    required this.estimatedCosts,
    required this.hasUnpricedUsage,
  });

  final String? purpose;
  final List<RuntimeCostView> estimatedCosts;
  final bool hasUnpricedUsage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PurposeCostView &&
          purpose == other.purpose &&
          listEquals(estimatedCosts, other.estimatedCosts) &&
          hasUnpricedUsage == other.hasUnpricedUsage;

  @override
  int get hashCode =>
      Object.hash(purpose, Object.hashAll(estimatedCosts), hasUnpricedUsage);

  String get label {
    final value = formatRuntimeCosts(estimatedCosts);
    return value.isEmpty ? '-' : value;
  }
}

class SessionCostView {
  const SessionCostView({
    this.purposeCosts = const [],
    required this.rootThreadId,
    required this.estimatedCosts,
    required this.hasUnpricedUsage,
  });

  final String rootThreadId;
  final List<PurposeCostView> purposeCosts;
  final List<RuntimeCostView> estimatedCosts;
  final bool hasUnpricedUsage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionCostView &&
          rootThreadId == other.rootThreadId &&
          listEquals(purposeCosts, other.purposeCosts) &&
          listEquals(estimatedCosts, other.estimatedCosts) &&
          hasUnpricedUsage == other.hasUnpricedUsage;

  @override
  int get hashCode => Object.hash(
    rootThreadId,
    Object.hashAll(purposeCosts),
    Object.hashAll(estimatedCosts),
    hasUnpricedUsage,
  );

  String get label {
    final value = formatRuntimeCosts(estimatedCosts);
    return value.isEmpty ? '-' : value;
  }
}

/// 由已报告输入样本累计出的 prompt cache 有效用量。
///
/// 只有 input 与 cache read 同时报告、且 cache read（连同可选的 cache write）
/// 不超过 input 的样本才计入累计；缺失或矛盾的样本只置 [hasIncompleteUsage]。
/// 命中率分母是累计 input，因为它已经包含 cache read。
class CacheUsageView {
  const CacheUsageView({
    this.inputTokens = 0,
    this.cacheReadTokens = 0,
    this.hitRate,
    this.hasIncompleteUsage = false,
  });

  /// 计入累计的有效样本 input 总量，已包含 cache read。
  final int inputTokens;

  /// 计入累计的有效样本 cache read 总量。
  final int cacheReadTokens;

  /// `cacheReadTokens / inputTokens`；累计 input 为零时为 null。
  final double? hitRate;

  /// 是否存在被排除在累计之外的缺失或矛盾样本。
  final bool hasIncompleteUsage;

  /// 累计分母为正时命中率才有意义。
  bool get hasPositiveDenominator => inputTokens > 0;

  /// 命中率同口径的未命中 token；有效样本保证不出现负值。
  int get missTokens => inputTokens - cacheReadTokens;

  @override
  bool operator ==(Object other) =>
      other is CacheUsageView &&
      inputTokens == other.inputTokens &&
      cacheReadTokens == other.cacheReadTokens &&
      hitRate == other.hitRate &&
      hasIncompleteUsage == other.hasIncompleteUsage;

  @override
  int get hashCode =>
      Object.hash(inputTokens, cacheReadTokens, hitRate, hasIncompleteUsage);
}

enum ThreadRuntimeUsageState { live, authoritative }

class ThreadRuntimeLiveUsageView {
  const ThreadRuntimeLiveUsageView({
    required this.turnId,
    required this.attemptId,
    this.completionTokens,
    this.responseMillis,
    this.latestContextTokens,
    required this.state,
    required this.observationSequence,
  });

  final String turnId;
  final String attemptId;
  final int? completionTokens;

  /// 本次 attempt 起点的单调总响应耗时；透明重试换代后从零重新计时。
  final int? responseMillis;
  final int? latestContextTokens;
  final ThreadRuntimeUsageState state;
  final int observationSequence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThreadRuntimeLiveUsageView &&
          turnId == other.turnId &&
          attemptId == other.attemptId &&
          completionTokens == other.completionTokens &&
          responseMillis == other.responseMillis &&
          latestContextTokens == other.latestContextTokens &&
          state == other.state &&
          observationSequence == other.observationSequence;

  @override
  int get hashCode => Object.hash(
    turnId,
    attemptId,
    completionTokens,
    responseMillis,
    latestContextTokens,
    state,
    observationSequence,
  );
}

const _threadRuntimeUnset = Object();

class ThreadRuntimeView {
  const ThreadRuntimeView({
    required this.modelId,
    required this.contextTokens,
    required this.contextWindow,
    required this.totalTokens,
    required this.costLabel,
    required this.activeSkills,
    required this.activeMcpServers,
    required this.activeLspServers,
    this.maxContextWindow,
    this.autoCompactLimit,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cachedPromptTokens = 0,
    this.cacheWriteTokens = 0,
    this.reasoningTokens = 0,
    this.inferenceCount = 0,
    this.cacheUsage = const CacheUsageView(),
    this.estimatedCosts = const [],
    this.estimatedCacheSavings = const [],
    this.hasUnpricedUsage = false,
    this.hasIncompleteUsage = false,
    this.promptGeneration,
    this.promptCachePolicy,
    this.prefixChangedReason,
    this.turnCompletionTokens = 0,
    this.turnResponseMillis = 0,
    this.liveUsage,
    this.workflow,
    this.plan,
    this.modelRoute,
    this.execution,
    this.continuation,
  });

  final String modelId;
  final int contextTokens;
  final int contextWindow;

  /// 绑定模型自身声明的最大上下文；未知为 `null`，不由 `contextWindow` 推断。
  final int? maxContextWindow;

  /// 最终生效的自动压缩阈值；未知为 `null`，不在展示端按当前设置重算。
  final int? autoCompactLimit;
  final int totalTokens;
  final String costLabel;
  final List<String> activeSkills;
  final List<String> activeMcpServers;
  final List<String> activeLspServers;
  final int promptTokens;
  final int completionTokens;
  final int cachedPromptTokens;
  final int cacheWriteTokens;
  final int reasoningTokens;
  final int inferenceCount;
  final CacheUsageView cacheUsage;
  final List<RuntimeCostView> estimatedCosts;
  final List<RuntimeCostView> estimatedCacheSavings;
  final bool hasUnpricedUsage;
  final bool hasIncompleteUsage;
  final int? promptGeneration;
  final String? promptCachePolicy;
  final String? prefixChangedReason;
  final int turnCompletionTokens;
  final int turnResponseMillis;
  final ThreadRuntimeLiveUsageView? liveUsage;
  final WorkflowRuntimeView? workflow;
  final PlanRuntimeView? plan;
  final ThreadModelRouteView? modelRoute;

  /// 主会话自己的当前执行身份；精确停止的目标来自它，而不是当前轮次投影。
  final AgentExecutionView? execution;

  /// 当前继续点；为空表示没有因中断而未完成的工作。
  ///
  /// 无内容继续只认这个规范投影给出的身份，不在本地重建「继续」资格。
  final ContinuationView? continuation;

  bool get hasActiveWorkflow => workflow?.isActive ?? false;
  bool get hasUsage =>
      inferenceCount > 0 || promptTokens > 0 || completionTokens > 0;
  double? get turnTokensPerSecond =>
      turnCompletionTokens > 0 && turnResponseMillis > 0
      ? turnCompletionTokens * 1000 / turnResponseMillis
      : null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ThreadRuntimeView &&
            modelId == other.modelId &&
            contextTokens == other.contextTokens &&
            contextWindow == other.contextWindow &&
            maxContextWindow == other.maxContextWindow &&
            autoCompactLimit == other.autoCompactLimit &&
            totalTokens == other.totalTokens &&
            costLabel == other.costLabel &&
            listEquals(activeSkills, other.activeSkills) &&
            listEquals(activeMcpServers, other.activeMcpServers) &&
            listEquals(activeLspServers, other.activeLspServers) &&
            promptTokens == other.promptTokens &&
            completionTokens == other.completionTokens &&
            cachedPromptTokens == other.cachedPromptTokens &&
            cacheWriteTokens == other.cacheWriteTokens &&
            reasoningTokens == other.reasoningTokens &&
            inferenceCount == other.inferenceCount &&
            cacheUsage == other.cacheUsage &&
            listEquals(estimatedCosts, other.estimatedCosts) &&
            listEquals(estimatedCacheSavings, other.estimatedCacheSavings) &&
            hasUnpricedUsage == other.hasUnpricedUsage &&
            hasIncompleteUsage == other.hasIncompleteUsage &&
            promptGeneration == other.promptGeneration &&
            promptCachePolicy == other.promptCachePolicy &&
            prefixChangedReason == other.prefixChangedReason &&
            turnCompletionTokens == other.turnCompletionTokens &&
            turnResponseMillis == other.turnResponseMillis &&
            liveUsage == other.liveUsage &&
            workflow == other.workflow &&
            plan == other.plan &&
            modelRoute == other.modelRoute &&
            execution == other.execution &&
            continuation == other.continuation;
  }

  @override
  int get hashCode => Object.hashAll([
    modelId,
    contextTokens,
    contextWindow,
    maxContextWindow,
    autoCompactLimit,
    totalTokens,
    costLabel,
    Object.hashAll(activeSkills),
    Object.hashAll(activeMcpServers),
    Object.hashAll(activeLspServers),
    promptTokens,
    completionTokens,
    cachedPromptTokens,
    cacheWriteTokens,
    reasoningTokens,
    inferenceCount,
    cacheUsage,
    Object.hashAll(estimatedCosts),
    Object.hashAll(estimatedCacheSavings),
    hasUnpricedUsage,
    hasIncompleteUsage,
    promptGeneration,
    promptCachePolicy,
    prefixChangedReason,
    turnCompletionTokens,
    turnResponseMillis,
    liveUsage,
    workflow,
    plan,
    modelRoute,
    execution,
    continuation,
  ]);

  ThreadRuntimeView copyWith({
    String? modelId,
    int? contextTokens,
    int? contextWindow,
    Object? maxContextWindow = _threadRuntimeUnset,
    Object? autoCompactLimit = _threadRuntimeUnset,
    int? totalTokens,
    String? costLabel,
    List<String>? activeSkills,
    List<String>? activeMcpServers,
    List<String>? activeLspServers,
    int? promptTokens,
    int? completionTokens,
    int? cachedPromptTokens,
    int? cacheWriteTokens,
    int? reasoningTokens,
    int? inferenceCount,
    CacheUsageView? cacheUsage,
    List<RuntimeCostView>? estimatedCosts,
    List<RuntimeCostView>? estimatedCacheSavings,
    bool? hasUnpricedUsage,
    bool? hasIncompleteUsage,
    int? promptGeneration,
    String? promptCachePolicy,
    String? prefixChangedReason,
    int? turnCompletionTokens,
    int? turnResponseMillis,
    Object? liveUsage = _threadRuntimeUnset,
    WorkflowRuntimeView? workflow,
    Object? plan = _threadRuntimeUnset,
    ThreadModelRouteView? modelRoute,
    Object? execution = _threadRuntimeUnset,
    Object? continuation = _threadRuntimeUnset,
  }) {
    return ThreadRuntimeView(
      modelId: modelId ?? this.modelId,
      contextTokens: contextTokens ?? this.contextTokens,
      contextWindow: contextWindow ?? this.contextWindow,
      maxContextWindow: identical(maxContextWindow, _threadRuntimeUnset)
          ? this.maxContextWindow
          : maxContextWindow as int?,
      autoCompactLimit: identical(autoCompactLimit, _threadRuntimeUnset)
          ? this.autoCompactLimit
          : autoCompactLimit as int?,
      totalTokens: totalTokens ?? this.totalTokens,
      costLabel: costLabel ?? this.costLabel,
      activeSkills: activeSkills ?? this.activeSkills,
      activeMcpServers: activeMcpServers ?? this.activeMcpServers,
      activeLspServers: activeLspServers ?? this.activeLspServers,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      cachedPromptTokens: cachedPromptTokens ?? this.cachedPromptTokens,
      cacheWriteTokens: cacheWriteTokens ?? this.cacheWriteTokens,
      reasoningTokens: reasoningTokens ?? this.reasoningTokens,
      inferenceCount: inferenceCount ?? this.inferenceCount,
      cacheUsage: cacheUsage ?? this.cacheUsage,
      estimatedCosts: estimatedCosts ?? this.estimatedCosts,
      estimatedCacheSavings:
          estimatedCacheSavings ?? this.estimatedCacheSavings,
      hasUnpricedUsage: hasUnpricedUsage ?? this.hasUnpricedUsage,
      hasIncompleteUsage: hasIncompleteUsage ?? this.hasIncompleteUsage,
      promptGeneration: promptGeneration ?? this.promptGeneration,
      promptCachePolicy: promptCachePolicy ?? this.promptCachePolicy,
      prefixChangedReason: prefixChangedReason ?? this.prefixChangedReason,
      turnCompletionTokens: turnCompletionTokens ?? this.turnCompletionTokens,
      turnResponseMillis: turnResponseMillis ?? this.turnResponseMillis,
      liveUsage: identical(liveUsage, _threadRuntimeUnset)
          ? this.liveUsage
          : liveUsage as ThreadRuntimeLiveUsageView?,
      workflow: workflow ?? this.workflow,
      plan: identical(plan, _threadRuntimeUnset)
          ? this.plan
          : plan as PlanRuntimeView?,
      modelRoute: modelRoute ?? this.modelRoute,
      execution: identical(execution, _threadRuntimeUnset)
          ? this.execution
          : execution as AgentExecutionView?,
      continuation: identical(continuation, _threadRuntimeUnset)
          ? this.continuation
          : continuation as ContinuationView?,
    );
  }
}

class ThreadModelRouteView {
  const ThreadModelRouteView({
    required this.accountId,
    required this.modelId,
    required this.effort,
    required this.revision,
    required this.available,
    this.unavailableReason,
    this.botId,
  });

  final String accountId;
  final String modelId;
  final String? effort;
  final int revision;
  final bool available;
  final String? unavailableReason;
  final String? botId;

  @override
  bool operator ==(Object other) =>
      other is ThreadModelRouteView &&
      botId == other.botId &&
      accountId == other.accountId &&
      modelId == other.modelId &&
      effort == other.effort &&
      revision == other.revision &&
      available == other.available &&
      unavailableReason == other.unavailableReason;

  @override
  int get hashCode => Object.hash(
    accountId,
    modelId,
    effort,
    revision,
    available,
    unavailableReason,
  );
}

class WorkflowRuntimeView {
  const WorkflowRuntimeView({required this.revision, this.currentRun});

  final int revision;
  final WorkflowRunView? currentRun;

  bool get isActive => currentRun?.terminal == false;

  @override
  bool operator ==(Object other) =>
      other is WorkflowRuntimeView &&
      revision == other.revision &&
      currentRun == other.currentRun;

  @override
  int get hashCode => Object.hash(revision, currentRun);
}

class WorkflowRunView {
  const WorkflowRunView({
    required this.lineageId,
    required this.runId,
    required this.modeId,
    required this.graphRevision,
    required this.graphHash,
    required this.currentStateId,
    required this.terminal,
    required this.startedAt,
    required this.updatedAt,
    this.currentStateTitle = '',
    this.modeDisplayName = '',
    this.modeDeleted = false,
  });

  final String lineageId;
  final String runId;
  final String modeId;
  final int graphRevision;
  final String graphHash;
  final String currentStateId;
  final bool terminal;
  final DateTime startedAt;
  final DateTime updatedAt;
  final String currentStateTitle;
  final String modeDisplayName;
  final bool modeDeleted;

  @override
  bool operator ==(Object other) =>
      other is WorkflowRunView &&
      runId == other.runId &&
      currentStateId == other.currentStateId &&
      updatedAt == other.updatedAt &&
      currentStateTitle == other.currentStateTitle &&
      modeDisplayName == other.modeDisplayName &&
      modeDeleted == other.modeDeleted;

  @override
  int get hashCode => Object.hash(
    runId,
    currentStateId,
    updatedAt,
    currentStateTitle,
    modeDisplayName,
    modeDeleted,
  );
}

enum PlanRuntimePhase {
  drafting,
  awaitingConfirmation,
  revisionRequested,
  approved,
}

class PlanDocumentView {
  const PlanDocumentView({
    required this.version,
    required this.markdown,
    required this.contentHash,
  });

  final int version;
  final String markdown;
  final String contentHash;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanDocumentView &&
          version == other.version &&
          markdown == other.markdown &&
          contentHash == other.contentHash;

  @override
  int get hashCode => Object.hash(version, markdown, contentHash);

  PlanDocumentView copyWith({
    int? version,
    String? markdown,
    String? contentHash,
  }) {
    return PlanDocumentView(
      version: version ?? this.version,
      markdown: markdown ?? this.markdown,
      contentHash: contentHash ?? this.contentHash,
    );
  }
}

class PlanRuntimeView {
  const PlanRuntimeView({
    required this.revision,
    required this.state,
    required this.updatedAt,
    this.document,
  });

  final int revision;
  final PlanRuntimePhase state;
  final PlanDocumentView? document;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanRuntimeView &&
          revision == other.revision &&
          state == other.state &&
          document == other.document &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(revision, state, document, updatedAt);

  PlanRuntimeView copyWith({
    int? revision,
    PlanRuntimePhase? state,
    Object? document = _threadRuntimeUnset,
    DateTime? updatedAt,
  }) {
    return PlanRuntimeView(
      revision: revision ?? this.revision,
      state: state ?? this.state,
      document: identical(document, _threadRuntimeUnset)
          ? this.document
          : document as PlanDocumentView?,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
