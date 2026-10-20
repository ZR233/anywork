import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

/// 内容连接的 readiness 信号：首帧未到之前，观察者不能看到候选基线；
/// 首帧到达后同一 attempt 只交付一次基线，唯一内容泵才继续取帧。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'concurrent baselines cannot be observed before the first frame arrives',
    () async {
      final transport = RecordingDemoTransport();
      final initialEntered = Completer<void>();
      final releaseInitial = Completer<void>();
      transport.timelineFactory = (threadId, inner) async =>
          _HeldInitialConnection(
            threadId: threadId,
            inner: inner,
            entered: initialEntered,
            release: releaseInitial,
          );
      final graph = AppGraph(
        transport: transport,
        clientId: 'initial-readiness',
      );
      addTearDown(() async {
        if (!releaseInitial.isCompleted) releaseInitial.complete();
        await graph.close(deadline: _deadline());
      });
      await graph.client.bootstrap();
      await graph.client.directoryCommands.selectThread('thread-main');
      final session = graph.client.session('thread-main');
      await initialEntered.future;

      // 首帧未到：连接在打开阶段，没有任何已交付基线。
      expect(
        session.timeline.state.value,
        isA<ChatOpening<StudioTimelineFrame>>(),
      );
      expect(session.timeline.lastDeliveredFrame, isNull);
      expect(transport.timelines, hasLength(1));
      expect(transport.timelines.single.nextCalls, 0);

      final first = session.timeline.ready;
      final second = session.timeline.ready;
      releaseInitial.complete();
      final baselines = await Future.wait([first, second]);
      await transport.timelines.single.nextEntered.future;

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
        reason: 'reduce 完首帧才取下一帧，同一时刻只有一个 next',
      );
    },
  );
}

class _HeldInitialConnection extends RecordingTimelineConnection {
  _HeldInitialConnection({
    required super.threadId,
    required super.inner,
    required this.entered,
    required this.release,
  });
  final Completer<void> entered;
  final Completer<void> release;

  @override
  Future<StudioTimelineBaseline> initial() async {
    entered.complete();
    await release.future;
    return super.initial();
  }
}

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
