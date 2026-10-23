import '../../../resources_ports.dart';
import '../domain/timeline_models.dart';

abstract interface class TimelineTransport {
  Future<StudioTimelineConnection> openTimeline(String threadId);
}

abstract interface class StudioTimelineConnection implements FeedConnection<StudioTimelineFeedFrame> {
  Future<StudioTimelinePage> page({String? before, int? limit});
  Future<StudioTimelineDetailChunk> readDetail({required String itemId,
    required StudioTimelineDetailQuery query});
}
