import 'dart:async';

import 'package:anywork/src/infrastructure/frb/shared/adapter_failure.dart';
import 'package:anywork/src/infrastructure/frb/shared/feed_connection.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources.dart';

/// A recording decorator for the demo's concrete Timeline port, not a fake
/// Studio facade. Composition supplies the demo content owner explicitly.
final class RecordingDemoTransport implements TimelineTransport {
  RecordingDemoTransport({required TimelineTransport timeline})
    : _timeline = timeline;

  final TimelineTransport _timeline;
  final List<RecordingTimelineConnection> timelines = [];
  Object? failNextInitial;

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) async {
    final failure = failNextInitial;
    failNextInitial = null;
    final connection = RecordingTimelineConnection(
      threadId: threadId,
      inner: await _timeline.openTimeline(threadId),
      initialFailure: failure,
    );
    timelines.add(connection);
    return connection;
  }
}

/// Injects only transport gates/failures. The inner demo remains the sole
/// source of content; real native FRB behavior is not claimed by this fixture.
final class RecordingTimelineConnection implements StudioTimelineConnection {
  RecordingTimelineConnection({
    required this.threadId,
    required this.inner,
    this.initialFailure,
    this.onFirstFrameHeld,
  }) {
    _connection = AdapterFeedConnection<
      StudioTimelineFeedFrame, StudioTimelineFeedFrame
    >(
      resource: 'recording-timeline',
      openNativeStream: _openRecordedStream,
      convert: (frame) => frame,
      failureFrame: (failure) => StudioTimelineFeedFrame.failure(error: failure),
      isTerminal: (frame) => frame is! StudioTimelineFeedData,
      identity: (frame) => switch (frame) {
        StudioTimelineFeedData(event: StudioTimelineFeedBaseline(:final baseline)) =>
          baseline.subscriptionId,
        _ => null,
      },
      acknowledgeNative: (sequence) async {
        final value = sequence.toInt();
        // AdapterFeedConnection already verified this exact int on admission.
        await inner.ackThrough(value);
        acks.add(value);
      },
      requestNativeClose: inner.requestClose,
      closeNative: inner.close,
      retryNativeClose: inner.retryClose,
      // The inner connection disposes its own native handle after its Clean.
      disposeNative: () {},
      mapFailure: _recordingFailure,
    );
  }

  final String threadId;
  final StudioTimelineConnection inner;
  late final AdapterFeedConnection<
    StudioTimelineFeedFrame, StudioTimelineFeedFrame
  > _connection;
  Object? initialFailure;
  void Function(Completer<void> gate)? onFirstFrameHeld;
  Completer<void>? initialGate;
  final nextEntered = Completer<void>();
  final joined = Completer<void>();
  int initialCalls = 0;
  int pageCalls = 0;
  int detailCalls = 0;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  int retryCloseCalls = 0;
  final List<int> acks = [];
  Completer<StudioTimelinePage>? scriptedPage;

  int get nextCalls => acks.length;
  bool get wasSubscribed => nextEntered.isCompleted;

  @override
  Stream<StudioTimelineFeedFrame> get events => _connection.events;

  Stream<StudioTimelineFeedFrame> _openRecordedStream() {
    initialCalls++;
    final controller = StreamController<StudioTimelineFeedFrame>();
    final openingSettled = Completer<void>();
    StreamSubscription<StudioTimelineFeedFrame>? source;
    controller.onListen = () {
      nextEntered.complete();
      // Async setup is a resource responsibility, not a detached callback.
      // Cancellation below waits its settlement even when the first gate is held.
      unawaited(Future<void>.sync(() async {
        try {
          final gate = initialGate;
          if (gate != null) {
            onFirstFrameHeld?.call(gate);
            await gate.future;
          }
          if (_connection.owner.isClosing) return;
          final failure = initialFailure;
          initialFailure = null;
          if (failure != null) throw failure;
          source = inner.events.listen(
            controller.add,
            onError: controller.addError,
            onDone: () {
              if (!controller.isClosed) unawaited(controller.close());
            },
          );
        } on Object catch (error, stack) {
          if (!_connection.owner.isClosing) {
            controller.addError(_recordingFailure(error), stack);
            if (!controller.isClosed) unawaited(controller.close());
          }
        } finally {
          openingSettled.complete();
        }
      }));
    };
    controller.onCancel = () async {
      await openingSettled.future;
      await source?.cancel();
    };
    return controller.stream;
  }

  @override
  Future<void> ackThrough(int deliverySequence) =>
      _connection.ackThrough(deliverySequence);

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) =>
      _connection.owner.query(() {
        pageCalls++;
        return scriptedPage?.future ?? inner.page(before: before, limit: limit);
      });

  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) => _connection.owner.query(() {
    detailCalls++;
    return inner.readDetail(itemId: itemId, query: query);
  });

  @override
  void requestClose() {
    requestCloseCalls++;
    _connection.requestClose();
  }

  @override
  Future<FeedCloseReport> close() {
    closeCalls++;
    return _observeJoined(_connection.close());
  }

  @override
  Future<FeedCloseReport> retryClose() {
    retryCloseCalls++;
    return _observeJoined(_connection.retryClose());
  }

  Future<FeedCloseReport> _observeJoined(Future<FeedCloseReport> result) =>
      result.then((report) {
        if (!joined.isCompleted) joined.complete();
        return report;
      });
}

StudioFailure _recordingFailure(Object error) =>
    adapterFailure(error, operation: 'recording-timeline');
