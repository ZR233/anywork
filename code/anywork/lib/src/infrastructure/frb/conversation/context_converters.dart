import 'package:anywork_client/conversation.dart';

import '../../../rust/api/studio/conversation/context.dart' as native;
import '../../../rust/api/studio/conversation/identity.dart' as identity;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';
import 'scalar_converters.dart';

ThreadContextFrame contextFrameFromBridge(
  native.BridgeContextFrame value,
) => switch (value) {
  native.BridgeContextFrame_Data(:final deliverySequence, :final event) =>
    ThreadContextFrame.data(
      deliverySequence: exactU64(deliverySequence, 'context delivery sequence'),
      event: switch (event) {
        native.BridgeContextEvent_Baseline(
          :final identity,
          :final stamp,
          :final value,
        ) =>
          ThreadContextEvent.baseline(
            identity: feedIdentityFromBridge(identity),
            stamp: facetStampFromBridge(stamp),
            value: contextValueFromBridge(value),
          ),
        native.BridgeContextEvent_Replace(:final stamp, :final value) =>
          ThreadContextEvent.replace(
            stamp: facetStampFromBridge(stamp),
            value: contextValueFromBridge(value),
          ),
      },
    ),
  native.BridgeContextFrame_ResyncRequired(:final identity, :final reason) =>
    ThreadContextFrame.resyncRequired(
      identity: feedIdentityFromBridge(identity),
      reason: resyncReasonFromBridge(reason),
    ),
  native.BridgeContextFrame_Failure(:final identity, :final error) =>
    ThreadContextFrame.failure(
      identity: feedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  native.BridgeContextFrame_Closed(:final identity, :final reason) =>
    ThreadContextFrame.closed(
      identity: feedIdentityFromBridge(identity),
      reason: closedReasonFromBridge(reason),
    ),
};

ThreadContextValue contextValueFromBridge(native.BridgeContextValue value) =>
    ThreadContextValue(
      usage: value.usage == null ? null : contextUsageFromBridge(value.usage!),
      liveContext: value.liveContext == null
          ? null
          : LiveContext(
              identity: metricsIdentityRefFromBridge(
                value.liveContext!.identity,
              ),
              latestContextTokens: nullableU64(
                value.liveContext!.latestContextTokens,
                'live context tokens',
              ),
              state: observationStateFromBridge(value.liveContext!.state),
            ),
      currentPolicy: value.currentPolicy == null
          ? null
          : currentPolicyFromBridge(value.currentPolicy!),
      details: contextRefFromBridge(value.details),
    );

ContextUsage contextUsageFromBridge(
  native.BridgeContextUsage value,
) => ContextUsage(
  hasIncompleteUsage: value.hasIncompleteUsage,
  contextWindow: nullableU64(
    value.contextWindow,
    'frozen context window tokens',
  ),
  maxContextWindow: nullableU64(
    value.maxContextWindow,
    'frozen maximum context window tokens',
  ),
  autoCompactLimit: nullableU64(
    value.autoCompactLimit,
    'frozen compact limit tokens',
  ),
  latestContextTokens: exactU64(
    value.latestContextTokens,
    'latest context tokens',
  ),
  promptTokens: exactU64(value.promptTokens, 'prompt tokens'),
  completionTokens: exactU64(value.completionTokens, 'completion tokens'),
  cachedPromptTokens: exactU64(
    value.cachedPromptTokens,
    'cached prompt tokens',
  ),
  cacheWriteTokens: exactU64(value.cacheWriteTokens, 'cache write tokens'),
  reasoningTokens: exactU64(value.reasoningTokens, 'reasoning tokens'),
  inferenceCount: exactU64(value.inferenceCount, 'inference count'),
  totalTokens: exactU64(value.totalTokens, 'total tokens'),
  cacheUsage: CacheUsageSummary(
    inputTokens: exactU64(value.cacheUsage.inputTokens, 'cache input tokens'),
    cacheReadTokens: exactU64(
      value.cacheUsage.cacheReadTokens,
      'cache read tokens',
    ),
    hitRate: value.cacheUsage.hitRate,
    hasIncompleteUsage: value.cacheUsage.hasIncompleteUsage,
  ),
  estimatedCostCount: exactU64(
    value.estimatedCostCount,
    'estimated cost count',
  ),
  estimatedCacheSavingCount: exactU64(
    value.estimatedCacheSavingCount,
    'estimated cache saving count',
  ),
  hasUnpricedUsage: value.hasUnpricedUsage,
  promptGeneration: nullableU64(value.promptGeneration, 'prompt generation'),
  prefixChangedReason: value.prefixChangedReason == null
      ? null
      : prefixReasonFromBridge(value.prefixChangedReason!),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'context updated Unix seconds',
  ),
);

CurrentContextPolicy currentPolicyFromBridge(
  native.BridgeCurrentContextPolicy value,
) => CurrentContextPolicy(
  sources: configSourcesFromBridge(value.sources),
  modeRevision: exactU64(value.modeRevision, 'policy Mode source revision'),
  routeRevision: exactU64(value.routeRevision, 'policy route revision'),
  contextWindow: nullableU64(
    value.contextWindow,
    'current context window tokens',
  ),
  maxContextWindow: nullableU64(
    value.maxContextWindow,
    'current maximum context window tokens',
  ),
  inputTokenLimit: nullableU64(
    value.inputTokenLimit,
    'current input limit tokens',
  ),
  autoCompactLimit: nullableU64(
    value.autoCompactLimit,
    'current compact limit tokens',
  ),
  unavailable: value.unavailable == null
      ? null
      : contextUnavailableFromBridge(value.unavailable!),
  adjustment: value.adjustment == null
      ? null
      : contextAdjustmentFromBridge(value.adjustment!),
);

identity.BridgeContextReadRef contextRefToBridge(ContextReadRef value) =>
    identity.BridgeContextReadRef(
      entry: nativeU64(value.entry, 'Context read entry'),
      revision: nativeU64(value.revision, 'Context read revision'),
    );
