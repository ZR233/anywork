import 'package:anywork_client/models.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart' show ModelRouteQueries;
import 'package:flutter/foundation.dart' show listEquals;

/// Context values are split from the Thread runtime so the context
/// ring/detail does not rebuild for a throughput-only runtime update.
class StudioContextProjection {
  const StudioContextProjection({
    required this.threadId,
    required this.modelId,
    required this.contextTokens,
    required this.contextWindow,
    required this.maxContextWindow,
    required this.autoCompactLimit,
    required this.totalTokens,
    required this.costLabel,
    required this.promptTokens,
    required this.completionTokens,
    required this.cachedPromptTokens,
    required this.cacheWriteTokens,
    required this.reasoningTokens,
    required this.inferenceCount,
    required this.cacheUsage,
    required this.estimatedCosts,
    required this.estimatedCacheSavings,
    required this.hasUnpricedUsage,
    required this.hasIncompleteUsage,
    this.usageDiagnostics = const ThreadUsageDiagnostics.empty(),
  });

  factory StudioContextProjection.fromRuntime(
    String? threadId,
    ThreadRuntimeView runtime, {
    required ThreadModelRouteView? modelRoute,
    required List<ModelSelectionAccount> accounts,
    required bool isBusy,
  }) {
    final live = runtime.liveUsage;
    final route = modelRoute;
    // Idle status follows the backend's current directory. Running requests and history
    // retain their frozen binding; this projection never calculates a capacity or limit.
    final currentModel = isBusy || route == null
        ? null
        : ModelRouteQueries.model(accounts, route.accountId, route.modelId);
    return StudioContextProjection(
      threadId: threadId,
      modelId: currentModel?.modelId ?? runtime.modelId,
      contextTokens: live?.latestContextTokens ?? runtime.contextTokens,
      contextWindow: currentModel == null
          ? runtime.contextWindow
          : currentModel.context.contextWindow ?? 0,
      maxContextWindow: currentModel == null
          ? runtime.maxContextWindow
          : currentModel.maxContextWindow,
      autoCompactLimit: currentModel == null
          ? runtime.autoCompactLimit
          : currentModel.context.autoCompactLimit,
      totalTokens: runtime.totalTokens,
      costLabel: runtime.costLabel,
      promptTokens: runtime.promptTokens,
      completionTokens: runtime.completionTokens,
      cachedPromptTokens: runtime.cachedPromptTokens,
      cacheWriteTokens: runtime.cacheWriteTokens,
      reasoningTokens: runtime.reasoningTokens,
      inferenceCount: runtime.inferenceCount,
      cacheUsage: runtime.cacheUsage,
      estimatedCosts: runtime.estimatedCosts,
      estimatedCacheSavings: runtime.estimatedCacheSavings,
      hasUnpricedUsage: runtime.hasUnpricedUsage,
      hasIncompleteUsage: runtime.hasIncompleteUsage,
      usageDiagnostics: runtime.usageDiagnostics,
    );
  }

  final String? threadId;
  final String modelId;
  final int contextTokens;
  final int contextWindow;

  /// 绑定模型自身声明的最大上下文；未知为 `null`。
  final int? maxContextWindow;

  /// 最终生效的自动压缩阈值，上下文进度的分母；未知为 `null`。
  final int? autoCompactLimit;
  final int totalTokens;
  final String costLabel;
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
  final ThreadUsageDiagnostics usageDiagnostics;

  bool get hasUsage =>
      inferenceCount > 0 || promptTokens > 0 || completionTokens > 0;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is StudioContextProjection &&
            threadId == other.threadId &&
            modelId == other.modelId &&
            contextTokens == other.contextTokens &&
            contextWindow == other.contextWindow &&
            maxContextWindow == other.maxContextWindow &&
            autoCompactLimit == other.autoCompactLimit &&
            totalTokens == other.totalTokens &&
            costLabel == other.costLabel &&
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
            usageDiagnostics == other.usageDiagnostics;
  }

  @override
  int get hashCode => Object.hash(
    threadId,
    modelId,
    contextTokens,
    contextWindow,
    maxContextWindow,
    autoCompactLimit,
    totalTokens,
    costLabel,
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
    usageDiagnostics,
  );
}

class StudioThroughputProjection {
  const StudioThroughputProjection({
    required this.threadId,
    required this.completionTokens,
    required this.responseMillis,
  });

  final String? threadId;
  final int completionTokens;
  final int responseMillis;

  double? get tokensPerSecond => completionTokens > 0 && responseMillis > 0
      ? completionTokens * 1000 / responseMillis
      : null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is StudioThroughputProjection &&
            threadId == other.threadId &&
            completionTokens == other.completionTokens &&
            responseMillis == other.responseMillis;
  }

  @override
  int get hashCode => Object.hash(threadId, completionTokens, responseMillis);
}
