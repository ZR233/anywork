import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

enum RuntimeEvidencePhase { idle, starting, recording, stopping, stopped, failed }
enum RuntimePublishFactKind { baseline, live, cleared }

final class RuntimeObservedIdentity {
  const RuntimeObservedIdentity(this.turnId, this.attemptId);
  final String turnId;
  final String attemptId;
  Map<String, Object?> toJson() => Map.unmodifiable({'turnId': turnId, 'attemptId': attemptId});
}

final class RuntimeClearedLiveReference {
  const RuntimeClearedLiveReference({required this.identity,
    required this.lastObservationSequence, required this.lastMetricsRevision});
  final RuntimeObservedIdentity identity;
  final int lastObservationSequence;
  final int lastMetricsRevision;
  Map<String, Object?> toJson() => Map.unmodifiable({
    ...identity.toJson(), 'lastObservationSequence': lastObservationSequence,
    'lastMetricsRevision': lastMetricsRevision,
  });
}

/// Only immutable identity, source and numeric evidence. No Context/body data.
final class RuntimePublishFact {
  const RuntimePublishFact({required this.kind, required this.threadId,
    required this.metricsStamp, required this.atUnixMillis, this.observedIdentity,
    this.observationSequence, this.completionTokens, this.responseMillis,
    this.clearedPreviousLive});
  final RuntimePublishFactKind kind;
  final String threadId;
  final ThreadFacetStamp metricsStamp;
  final int atUnixMillis;
  final RuntimeObservedIdentity? observedIdentity;
  final int? observationSequence;
  final int? completionTokens;
  final int? responseMillis;
  final RuntimeClearedLiveReference? clearedPreviousLive;
  Map<String, Object?> toJson() => Map.unmodifiable({
    'kind': kind.name, 'threadId': threadId, 'metricsStamp': metricsStampJson(metricsStamp),
    'atUnixMillis': atUnixMillis, 'observedIdentity': observedIdentity?.toJson(),
    'live': observationSequence == null ? null : Map<String, Object?>.unmodifiable({
      'observationSequence': observationSequence, 'completionTokens': completionTokens,
      'responseMillis': responseMillis,
    }),
    'clearedPreviousLive': clearedPreviousLive?.toJson(),
  });
}

Map<String, Object?> metricsStampJson(ThreadFacetStamp stamp) => Map.unmodifiable({
  'runtimeEpoch': stamp.runtimeEpoch, 'incarnation': stamp.incarnation,
  'facet': stamp.facet.name, 'revision': stamp.revision,
});

/// Runtime type is safe metadata; never call the exception's toString().
Map<String, Object?> runtimeEvidenceFailure(Object error) => Map.unmodifiable({
  'type': error.runtimeType.toString(),
  'code': error is StudioFailure ? error.code.name : null,
  'retryable': error is StudioFailure ? error.retryable : null,
  'correlationId': error is StudioFailure ? error.correlationId : null,
});

List<Object?> runtimeCloseJson(CloseReport report) => List.unmodifiable([
  for (final resource in report.unresolved) Map<String, Object?>.unmodifiable({
    'owner': resource.owner, 'attemptId': resource.attemptId.value,
    'issues': List<Object?>.unmodifiable([
      for (final issue in resource.issues) Map<String, Object?>.unmodifiable({
        'code': issue.diagnostic.code, 'retryable': issue.diagnostic.retryable,
        'correlationId': issue.diagnostic.correlationId, 'recovery': issue.recovery.name,
      }),
    ]),
  }),
]);
