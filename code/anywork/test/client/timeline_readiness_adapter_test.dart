import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';
import 'support/test_statistics_feed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('共享feed首个内容基线到达前，两个ready等待不能提前观察候选基线或ACK', () async {
    final transport = RecordingDemoTransport();
    final opened = Completer<RecordingConversationFeed>();
    final release = Completer<void>();
    transport.conversationFeedFactory = (threadId, inner) async {
      final held = RecordingConversationFeed(inner: inner)
        ..initialGate = release;
      opened.complete(held);
      return held;
    };
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'feed-readiness',
    );
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await graph.close(deadline: _deadline());
    });
    await graph.client.bootstrap();
    final repository = graph.client.conversations;
    final session = repository.session('thread-main');
    expect(transport.feeds, isEmpty, reason: '读取session不隐式声明内容需求');
    final thread = graph.client.threadDirectory.state.window.threads
        .singleWhere((thread) => thread.id == 'thread-main');
    graph.client.workspace.selectThread(thread.id, projectId: thread.projectId);
    repository.setVisibleThread('thread-main');
    final held = await opened.future;
    await held.initialEntered.future;
    expect(
      session.content.state.value,
      isA<ChatOpening<ConversationContentFrame>>(),
    );
    expect(session.content.lastDeliveredFrame, isNull);
    expect(held.initialCalls, 1);
    expect(held.acknowledgements, [1], reason: '状态已归约；内容尚未交付，不能提前ACK其序号');
    final first = session.content.ready;
    final second = session.content.ready;
    release.complete();
    final baselines = await Future.wait([first, second]);
    expect(
      baselines.first.baseline.subscriptionId,
      baselines.last.baseline.subscriptionId,
    );
    expect(transport.feeds, hasLength(1));
    expect(held.initialCalls, 1);
    expect(baselines.first.baseline.items, isNotEmpty);
    repository.setVisibleThread(null);
    await transport.feeds.single.joined.future;
    expect(transport.feeds.single.closeCalls, 1);
    expect(session.content.hasDemand, isFalse);
  });
}

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
