import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart';
import 'support/recording_demo_transport.dart';
import 'support/timeline_environment.dart';

/// 内容连接的 readiness 信号：首帧未到之前，观察者不能看到候选基线；
/// 首帧到达后同一 attempt 只交付一次基线，唯一消费路径才继续接收推送。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'concurrent baselines cannot be observed before the first frame arrives',
    () async {
      final initialEntered = Completer<void>();
      final releaseInitial = Completer<void>();
      final native = _HeldInitialTransport(initialEntered, releaseInitial);
      final transport = RecordingDemoTransport(timeline: native);
      final environment = TimelineTestEnvironment(timeline: transport);
      addTearDown(() async {
        if (!releaseInitial.isCompleted) releaseInitial.complete();
        await environment.close();
      });
      final session = environment.select('thread-main')!;
      final delivered = <StudioTimelineFrame>[];
      final consumer = session.timeline.attachConsumer(delivered.add);
      addTearDown(consumer.close);
      await initialEntered.future;

      // 首帧未到：连接在打开阶段，没有任何已交付基线。
      expect(
        session.timeline.state.value.phase,
        TimelineConnectionPhase.opening,
      );
      expect(session.timeline.state.value.lastStamp, isNull);
      expect(delivered, isEmpty);
      expect(transport.timelines, hasLength(1));
      expect(transport.timelines.single.nextCalls, 0);

      final first = session.timeline.ready;
      final second = session.timeline.ready;
      releaseInitial.complete();
      final baselines = await Future.wait([first, second]);
      await transport.timelines.single.nextEntered.future;
      await native.acknowledged.future;
      await pumpEventQueue();

      expect(baselines, hasLength(2));
      expect(
        baselines.first.baseline.subscriptionId,
        baselines.last.baseline.subscriptionId,
        reason: '两路等待都属于同一个 attempt 的同一次首帧',
      );
      expect(transport.timelines, hasLength(1));
      expect(transport.timelines.single.initialCalls, 1);
      expect(
        transport.timelines.single.nextCalls,
        1,
        reason: '基线处理完成并确认一次；后续帧须等待本次消费结束',
      );
      expect(transport.timelines.single.acks.single, 1);
      expect(delivered, hasLength(1));
      expect(delivered.single, isA<StudioTimelineBaselineFrame>());
    },
  );
}

final class _HeldInitialTransport implements TimelineTransport {
  _HeldInitialTransport(this.entered, this.release);
  final Completer<void> entered;
  final Completer<void> release;
  final acknowledged = Completer<void>();
  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) async =>
      _HeldNativeConnection(threadId, entered, release, acknowledged);
}

/// Holds only native delivery. Readiness and fan-in remain the real Timeline
/// owner; the fixture never completes those production Futures itself.
final class _HeldNativeConnection implements StudioTimelineConnection {
  _HeldNativeConnection(
    String threadId,
    this.entered,
    this.release,
    this.acknowledged,
  ) : inner = TestTimelineConnection(
        initial: baseline(1, items: [timelineItem(1, threadId: threadId)]),
      );
  final TestTimelineConnection inner;
  final Completer<void> entered;
  final Completer<void> release;
  final Completer<void> acknowledged;
  @override
  Stream<StudioTimelineFeedFrame> get events async* {
    entered.complete();
    await release.future;
    yield* inner.events;
  }

  @override
  Future<void> ackThrough(int deliverySequence) async {
    await inner.ackThrough(deliverySequence);
    if (!acknowledged.isCompleted) acknowledged.complete();
  }

  @override
  void requestClose() => inner.requestClose();
  @override
  Future<FeedCloseReport> close() => inner.close();
  @override
  Future<FeedCloseReport> retryClose() => inner.retryClose();
  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) =>
      inner.page(before: before, limit: limit);
  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) => inner.readDetail(itemId: itemId, query: query);
}
