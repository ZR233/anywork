import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/handlers/chat.dart' as native;
import '../../../rust/api/studio/types/chat.dart' as wire;
import '../shared/adapter_failure.dart';
import '../shared/bridge_failure.dart';
import '../shared/close_converters.dart';
import '../shared/exact_numbers.dart';
import '../shared/feed_connection.dart';
import 'timeline_converters.dart';
import 'timeline_field_converters.dart';

final class FrbTimelineTransport implements TimelineTransport {
  const FrbTimelineTransport();

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) => bridgeQuery(() async {
    final handle = await native.openTimeline(threadId: threadId);
    return FrbTimelineConnection(threadId: threadId, handle: handle);
  });
}

/// One original Thread/content handle. No pull pump, baseline cache, reducer
/// or selection lookup is introduced in the adapter.
final class FrbTimelineConnection implements StudioTimelineConnection {
  FrbTimelineConnection({required this.threadId, required native.BridgeTimeline handle})
      : _handle = handle {
    _connection = AdapterFeedConnection<wire.BridgeTimelineFrame, StudioTimelineFeedFrame>(
      resource: 'timeline',
      openNativeStream: handle.stream,
      convert: (frame) => timelineFrameFromBridge(frame, threadId: threadId),
      failureFrame: (failure) => StudioTimelineFeedFrame.failure(error: failure),
      isTerminal: (frame) => frame is! StudioTimelineFeedData,
      identity: (frame) => switch (frame) {
        StudioTimelineFeedData(event: StudioTimelineFeedBaseline(:final baseline)) => baseline.subscriptionId,
        StudioTimelineFeedData(event: StudioTimelineFeedUpdate(:final update)) => switch (update) {
          StudioTimelinePatch(:final subscriptionId) => subscriptionId,
          StudioTimelineResync(:final subscriptionId) => subscriptionId,
        },
        _ => null,
      },
      acknowledgeNative: (sequence) => handle.ackThrough(deliverySequence: sequence),
      requestNativeClose: handle.requestClose,
      closeNative: () async => feedCloseReportFromBridge(await handle.close()),
      retryNativeClose: () async => feedCloseReportFromBridge(await handle.retryClose()),
      disposeNative: handle.dispose,
      mapFailure: bridgeFailure,
    );
  }

  final String threadId;
  final native.BridgeTimeline _handle;
  late final AdapterFeedConnection<wire.BridgeTimelineFrame, StudioTimelineFeedFrame> _connection;

  @override
  Stream<StudioTimelineFeedFrame> get events => _connection.events;
  @override
  Future<void> ackThrough(int deliverySequence) => _connection.ackThrough(deliverySequence);

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) => _connection.owner.query(() async {
    if (limit != null && (limit < 1 || limit > 100)) throw _argumentFailure;
    final page = await _handle.page(before: before, limit: limit);
    return timelinePageFromBridge(page, threadId: threadId);
  });

  @override
  Future<StudioTimelineDetailChunk> readDetail({required String itemId, required StudioTimelineDetailQuery query}) => _connection.owner.query(() async {
    final maxBytes = query.maxBytes;
    if (maxBytes != null && (maxBytes < 4 || maxBytes > 256 * 1024)) throw _argumentFailure;
    final chunk = await _handle.readDetail(itemId: itemId, query: wire.BridgeTimelineDetailQuery(
      field: contentFieldToBridge(query.field), revision: nativeU64(query.revision, 'Timeline detail revision'),
      continuation: query.continuation, maxBytes: maxBytes,
    ));
    final converted = timelineDetailFromBridge(chunk);
    if (converted.itemId != itemId || converted.field != query.field || converted.revision != query.revision) {
      throw adapterProtocol('timeline-detail-query-identity');
    }
    return converted;
  });

  @override
  void requestClose() => _connection.requestClose();
  @override
  Future<FeedCloseReport> close() => _connection.close();
  @override
  Future<FeedCloseReport> retryClose() => _connection.retryClose();
}

const _argumentFailure = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'The Timeline page or text limit is outside its supported range',
  retryable: false,
  correlationId: 'adapter-timeline-query-limit',
);
