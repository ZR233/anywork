import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_demo_transport.dart';
import '../support/chat_fixtures.dart';
import '../support/test_statistics_feed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('GUI readiness follows component application while State and originals remain independent', () async {
    final transport = RecordingDemoTransport();
    final opened = Completer<RecordingTimelineReader>();
    final release = Completer<void>();
    transport.timelineReaderFactory = (_, inner) async {
      final held = RecordingTimelineReader(inner: inner)..initialGate = release;
      opened.complete(held);
      return held;
    };
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'reader-readiness',
    );
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await graph.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      );
    });
    await graph.client.bootstrap();
    graph.timeline.updateReadDemand(chatDemand);
    graph.setConversationPageVisible(true);
    await graph.client.directoryCommands.selectThread('thread-main');
    final held = await opened.future;
    await held.initialEntered.future;
    final session = graph.client.conversations.session('thread-main');
    await session.source.waitFor((value) => value.businessRefs != null);
    expect(graph.timeline.lease('thread-main'), isNull);
    expect(held.acceptedCursors, isEmpty);
    expect(
      session.content.currentAttemptId,
      isNull,
      reason: 'GUI does not start a completion producer',
    );
    expect(transport.feeds, isEmpty);
    final first = timelineReady(graph.timeline, 'thread-main');
    final second = timelineReady(graph.timeline, 'thread-main');
    release.complete();
    await Future.wait([first, second]);
    expect(
      graph.timeline.lease('thread-main')!.controller.messages,
      isNotEmpty,
    );
    expect(transport.timelineReaders, hasLength(1));
    graph.setConversationPageVisible(false);
    await transport.timelineReaders.single.joined.future;
    expect(graph.timeline.lease('thread-main'), isNull);
  });
}
