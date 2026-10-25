import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../rust/api/studio/conversation/identity.dart' as wire;
import '../../../rust/api/studio/conversation/metrics_feed.dart' as native;
import '../../../rust/api/studio/conversation/read/metrics.dart' as read;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import 'identity_converters.dart';
import 'metrics_connection.dart';
import 'metrics_identity_connection.dart';

/// The actual Metrics implementation of ConversationObservationPort's named
/// factory signature. The other four native facet owners are not fabricated.
Future<FeedConnection<ThreadMetricsFrame>> openFrbThreadMetrics(
  String threadId, {
  required ThreadObservationMode mode,
}) {
  final nativeMode = observationModeToBridge(mode);
  return bridgeQuery(
    () async => FrbThreadMetricsConnection(
      threadId: threadId,
      handle: await native.openThreadMetrics(
        threadId: threadId,
        mode: nativeMode,
      ),
    ),
  );
}

/// The exact immutable read signature consumed by MetricsIdentityScopeOwner.
/// The original opening Future remains owned by the calling Session/read owner.
Future<MetricsIdentityReadConnection> openFrbMetricsIdentityRead(
  String threadId,
  MetricsIdentityRef reference, {
  required ThreadFacetStamp origin,
}) {
  if (origin.facet != ThreadFacet.metrics) throw _originArguments;
  final nativeRef = wire.BridgeMetricsIdentityRef(
    entry: nativeU64(reference.entry, 'metrics identity entry'),
  );
  final nativeOrigin = facetStampToBridge(origin);
  return bridgeQuery(
    () async => FrbMetricsIdentityReadConnection(
      handle: await read.openMetricsIdentityRead(
        threadId: threadId,
        reference: nativeRef,
        origin: nativeOrigin,
      ),
      origin: origin,
    ),
  );
}

const _originArguments = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'A Metrics identity read requires its original Metrics facet',
  retryable: false,
  correlationId: 'adapter-metrics-identity-origin',
);
