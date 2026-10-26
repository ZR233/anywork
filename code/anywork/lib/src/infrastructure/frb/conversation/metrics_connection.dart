import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../rust/api/studio/conversation/metrics.dart' as wire;
import '../../../rust/api/studio/conversation/metrics_feed.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/bridge_failure.dart';
import '../shared/close_converters.dart';
import '../shared/feed_connection.dart';
import 'metrics_converters.dart';

/// Owns the original Metrics listener only, not the Thread or a metrics mirror.
final class FrbThreadMetricsConnection
    implements FeedConnection<ThreadMetricsFrame> {
  FrbThreadMetricsConnection({
    required this.threadId,
    required native.BridgeThreadMetrics handle,
  }) {
    _connection =
        AdapterFeedConnection<wire.BridgeMetricsFrame, ThreadMetricsFrame>(
          resource: 'thread-metrics',
          openNativeStream: handle.stream,
          convert: _convert,
          failureFrame: _failureFrame,
          isTerminal: (frame) => frame is! ThreadMetricsData,
          identity: (_) => _identity?.feedId,
          acknowledgeNative: (sequence) =>
              handle.ackThrough(deliverySequence: sequence),
          requestNativeClose: handle.requestClose,
          closeNative: () async =>
              feedCloseReportFromBridge(await handle.close()),
          retryNativeClose: () async =>
              feedCloseReportFromBridge(await handle.retryClose()),
          disposeNative: handle.dispose,
          mapFailure: bridgeFailure,
        );
  }

  final String threadId;
  late final AdapterFeedConnection<wire.BridgeMetricsFrame, ThreadMetricsFrame>
  _connection;
  // Resource identity only. Numeric samples remain solely in the Repository.
  ThreadFeedIdentity? _identity;

  ThreadMetricsFrame _convert(wire.BridgeMetricsFrame value) {
    final frame = metricsFrameFromBridge(value);
    final incoming = switch (frame) {
      ThreadMetricsData(event: ThreadMetricsBaselineEvent(:final identity)) =>
        identity,
      ThreadMetricsResyncRequired(:final identity) => identity,
      ThreadMetricsFailure(:final identity) => identity,
      ThreadMetricsClosed(:final identity) => identity,
      _ => null,
    };
    if (incoming != null) {
      if (incoming.facet != ThreadFacet.metrics ||
          _identity != null && incoming != _identity) {
        throw adapterProtocol('metrics-feed-identity');
      }
      _identity = incoming;
    }
    final stamp = switch (frame) {
      ThreadMetricsData(event: ThreadMetricsBaselineEvent(:final stamp)) =>
        stamp,
      ThreadMetricsData(event: ThreadMetricsReplaceEvent(:final stamp)) =>
        stamp,
      _ => null,
    };
    if (stamp != null) {
      final identity = _identity;
      if (identity == null ||
          stamp.facet != ThreadFacet.metrics ||
          stamp.runtimeEpoch != identity.runtimeEpoch ||
          stamp.incarnation != identity.incarnation) {
        throw adapterProtocol('metrics-feed-stamp');
      }
    }
    return frame;
  }

  ThreadMetricsFrame _failureFrame(StudioFailure failure) {
    final identity = _identity;
    // Before an actual identity arrives there is no legitimate Failure frame.
    // The shared adapter forwards this exact typed error and closes the owner.
    if (identity == null) throw failure;
    return ThreadMetricsFrame.failure(identity: identity, error: failure);
  }

  @override
  Stream<ThreadMetricsFrame> get events => _connection.events;
  @override
  Future<void> ackThrough(int deliverySequence) =>
      _connection.ackThrough(deliverySequence);
  @override
  void requestClose() => _connection.requestClose();
  @override
  Future<FeedCloseReport> close() => _connection.close();
  @override
  Future<FeedCloseReport> retryClose() => _connection.retryClose();
}
