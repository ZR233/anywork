import 'package:anywork_client/conversation.dart';

/// Request-local projections of two independent canonical facets. They do not
/// share a publication watermark, create demand or materialize an identity ref.
Map<String, Object?> conversationStatusDiagnostics(
  ConversationSession? session,
) {
  final metrics = session?.metrics.value;
  final context = session?.context.value;
  final live = metrics?.value?.live;
  final authoritative = metrics?.value?.authoritative;
  final liveContext = context?.value?.liveContext;
  final usage = context?.value?.usage;
  return Map.unmodifiable({
    'metrics': Map<String, Object?>.unmodifiable({
      'threadId': session?.threadId,
      'stamp': _stamp(metrics?.stamp),
      'sync': _sync(metrics?.sync),
      'live': live == null
          ? null
          : Map<String, Object?>.unmodifiable({
              'state': live.state.name,
              'observationSequence': live.observationSequence,
              'completionTokens': live.completionTokens,
              'responseMillis': live.responseMillis,
            }),
      'authoritative': authoritative == null
          ? null
          : Map<String, Object?>.unmodifiable({
              'completionTokens': authoritative.completionTokens,
              'responseMillis': authoritative.responseMillis,
            }),
    }),
    'context': Map<String, Object?>.unmodifiable({
      'threadId': session?.threadId,
      'stamp': _stamp(context?.stamp),
      'sync': _sync(context?.sync),
      'liveContext': liveContext == null
          ? null
          : Map<String, Object?>.unmodifiable({
              'state': liveContext.state.name,
              'latestContextTokens': liveContext.latestContextTokens,
            }),
      'usage': usage == null
          ? null
          : Map<String, Object?>.unmodifiable({
              'latestContextTokens': usage.latestContextTokens,
              'contextWindow': usage.contextWindow,
              'maxContextWindow': usage.maxContextWindow,
              'autoCompactLimit': usage.autoCompactLimit,
              'promptTokens': usage.promptTokens,
              'completionTokens': usage.completionTokens,
              'totalTokens': usage.totalTokens,
              'cachedPromptTokens': usage.cachedPromptTokens,
              'cacheWriteTokens': usage.cacheWriteTokens,
              'reasoningTokens': usage.reasoningTokens,
              'inferenceCount': usage.inferenceCount,
              'hasIncompleteUsage': usage.hasIncompleteUsage,
              'hasUnpricedUsage': usage.hasUnpricedUsage,
              'estimatedCostCount': usage.estimatedCostCount,
              'estimatedCacheSavingCount': usage.estimatedCacheSavingCount,
              'promptGeneration': usage.promptGeneration,
              'prefixChangedReason': usage.prefixChangedReason?.name,
              'updatedAt': usage.updatedAt,
              'cacheUsage': Map<String, Object?>.unmodifiable({
                'inputTokens': usage.cacheUsage.inputTokens,
                'cacheReadTokens': usage.cacheUsage.cacheReadTokens,
                'hitRate': usage.cacheUsage.hitRate,
                'hasIncompleteUsage': usage.cacheUsage.hasIncompleteUsage,
              }),
            }),
    }),
  });
}

Map<String, Object?>? _stamp(ThreadFacetStamp? stamp) => stamp == null
    ? null
    : Map.unmodifiable({
        'runtimeEpoch': stamp.runtimeEpoch,
        'incarnation': stamp.incarnation,
        'facet': stamp.facet.name,
        'revision': stamp.revision,
      });
Map<String, Object?>? _sync(FacetSyncState? sync) => sync == null
    ? null
    : Map.unmodifiable({
        'phase': sync.phase.name,
        'retryExhausted': sync.retryExhausted,
        'errorType': sync.error?.runtimeType.toString(),
        'errorCode': sync.error?.code.name,
        'errorRetryable': sync.error?.retryable,
        'errorCorrelationId': sync.error?.correlationId,
      });
