import 'package:anywork_client/conversation.dart';

import '../../../rust/api/studio/conversation/metrics.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';
import 'scalar_converters.dart';

ThreadMetricsFrame metricsFrameFromBridge(native.BridgeMetricsFrame value) => switch (value) {
  native.BridgeMetricsFrame_Data(:final deliverySequence, :final event) =>
    ThreadMetricsFrame.data(deliverySequence: exactU64(deliverySequence, 'metrics delivery sequence'), event: switch (event) {
      native.BridgeMetricsEvent_Baseline(:final identity, :final stamp, :final value) =>
        ThreadMetricsEvent.baseline(identity: feedIdentityFromBridge(identity), stamp: facetStampFromBridge(stamp), value: metricsValueFromBridge(value)),
      native.BridgeMetricsEvent_Replace(:final stamp, :final value) =>
        ThreadMetricsEvent.replace(stamp: facetStampFromBridge(stamp), value: metricsValueFromBridge(value)),
    }),
  native.BridgeMetricsFrame_ResyncRequired(:final identity, :final reason) =>
    ThreadMetricsFrame.resyncRequired(identity: feedIdentityFromBridge(identity), reason: resyncReasonFromBridge(reason)),
  native.BridgeMetricsFrame_Failure(:final identity, :final error) =>
    ThreadMetricsFrame.failure(identity: feedIdentityFromBridge(identity), error: bridgeFailure(error)),
  native.BridgeMetricsFrame_Closed(:final identity, :final reason) =>
    ThreadMetricsFrame.closed(identity: feedIdentityFromBridge(identity), reason: closedReasonFromBridge(reason)),
};

ThreadMetricsValue metricsValueFromBridge(native.BridgeMetricsValue value) => ThreadMetricsValue(
  live: value.live == null ? null : LiveTurnMetrics(
    identity: metricsIdentityRefFromBridge(value.live!.identity),
    completionTokens: nullableU64(value.live!.completionTokens, 'live completion tokens'),
    responseMillis: nullableU64(value.live!.responseMillis, 'live response milliseconds'),
    state: observationStateFromBridge(value.live!.state),
    observationSequence: exactU64(value.live!.observationSequence, 'metrics observation sequence'),
  ),
  authoritative: value.authoritative == null ? null : AuthoritativeTurnMetrics(
    identity: metricsIdentityRefFromBridge(value.authoritative!.identity),
    completionTokens: exactU64(value.authoritative!.completionTokens, 'authoritative completion tokens'),
    responseMillis: exactU64(value.authoritative!.responseMillis, 'authoritative response milliseconds'),
  ),
);
