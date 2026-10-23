import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../configuration.dart';
import '../../../models.dart';
import 'metrics_values.dart';
import 'thread_identity.dart';

part 'context_values.freezed.dart';

enum PromptPrefixChangedReason {
  initial, promptScopeChanged, accountChanged, modelChanged, baseInstructionsChanged,
  globalInstructionsChanged, modeRoleChanged, skillCatalogChanged, workspaceInstructionsChanged,
  requestPropertiesChanged, fixedPrefixChanged, toolSchemaChanged, contextCompacted,
  contextAppended, contextRecovered,
}

@freezed
abstract class CacheUsageSummary with _$CacheUsageSummary {
  const factory CacheUsageSummary({required int inputTokens, required int cacheReadTokens, required double? hitRate, required bool hasIncompleteUsage}) = _CacheUsageSummary;
}

@freezed
abstract class ContextUsage with _$ContextUsage {
  const factory ContextUsage({
    required bool hasIncompleteUsage,
    required int? contextWindow,
    required int? maxContextWindow,
    required int? autoCompactLimit,
    required int latestContextTokens,
    required int promptTokens,
    required int completionTokens,
    required int cachedPromptTokens,
    required int cacheWriteTokens,
    required int reasoningTokens,
    required int inferenceCount,
    required int totalTokens,
    required CacheUsageSummary cacheUsage,
    required int estimatedCostCount,
    required int estimatedCacheSavingCount,
    required bool hasUnpricedUsage,
    required int? promptGeneration,
    required PromptPrefixChangedReason? prefixChangedReason,
    required int updatedAt,
  }) = _ContextUsage;
}

@freezed
abstract class LiveContext with _$LiveContext {
  const factory LiveContext({required MetricsIdentityRef identity, required int? latestContextTokens, required TurnObservationState state}) = _LiveContext;
}

@freezed
abstract class CurrentContextPolicy with _$CurrentContextPolicy {
  const factory CurrentContextPolicy({
    required ConfigProjectionStamp sources,
    required int modeRevision,
    required int routeRevision,
    required int? contextWindow,
    required int? maxContextWindow,
    required int? inputTokenLimit,
    required int? autoCompactLimit,
    required ModelContextUnavailable? unavailable,
    required ModelContextAdjustment? adjustment,
  }) = _CurrentContextPolicy;
}

@freezed
abstract class ThreadContextValue with _$ThreadContextValue {
  const factory ThreadContextValue({required ContextUsage? usage, required LiveContext? liveContext, required CurrentContextPolicy? currentPolicy, required ContextReadRef details}) = _ThreadContextValue;
}
