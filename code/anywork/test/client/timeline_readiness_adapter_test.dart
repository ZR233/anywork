import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';
import 'support/test_statistics_feed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('共享feed首个内容基线到达前，两个ready等待不能提前观察候选基线或ACK', () async {
    var diagnosticSequence = 0;
    void record(Map<String, Object?> facts) => debugPrintSynchronously(
      jsonEncode({'sequence': ++diagnosticSequence, ...facts}),
    );
    final transport = RecordingDemoTransport();
    final opened = Completer<_AckObservedFeed>();
    final release = Completer<void>();
    transport.conversationFeedFactory = (threadId, inner) async {
      final held = _AckObservedFeed(inner: inner, record: record)
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
    var publications = 0;
    void diagnose(String stage) {
      final view = graph.timeline.source.value;
      final display = graph.timeline.lease('thread-main');
      record({
        'readinessStage': stage,
        'ownerPublications': publications,
        'selectedThread': graph.client.selection.state.selectedThreadId,
        'visibleThread': repository.visibleThreadId.value,
        'sameSession': identical(
          repository.existingSession('thread-main'),
          session,
        ),
        'contentState': session.content.state.value.runtimeType.toString(),
        'contentSnapshot': session.content.state.value.snapshot,
        'hasDemand': session.content.hasDemand,
        'attemptId': session.content.currentAttemptId?.value,
        'ownedAttempts': session.content.ownedAttemptCount,
        'ownerView': view?.toString(),
        'leaseIdentity': display == null ? null : identityHashCode(display),
        'leaseGeneration': display?.generation,
        'leaseEpoch': display?.timelineEpoch,
        'leaseRetired': display?.isRetired,
        'leaseReleased': display?.isReleased,
        'atomIds': display?.items.map((item) => item.id).toList(),
        'completedThrough': display?.completedCursor?.appendSeq,
        'budget': {
          for (final kind in ResourceKind.values)
            kind.name: graph.client.budget.used(kind),
        },
      });
    }

    final ownerObservation = graph.timeline.source.watch((_) {
      publications++;
      diagnose('owner.publish');
    });
    final contentObservation = session.content.state.watch(
      (_) => diagnose('content.publish'),
    );
    addTearDown(() {
      ownerObservation.cancel();
      contentObservation.cancel();
    });
    expect(transport.feeds, isEmpty, reason: '读取session不隐式声明内容需求');
    final thread = graph.client.threadDirectory.state.window.threads
        .singleWhere((thread) => thread.id == 'thread-main');
    graph.setConversationPageVisible(true);
    await graph.client.directoryCommands.selectThread(thread.id);
    final held = await opened.future;
    await held.initialEntered.future;
    await held.stateAckCompleted.future;
    expect(session.content.state.value, isA<ChatOpening<bool>>());
    expect(graph.timeline.lease('thread-main'), isNull);
    expect(held.initialCalls, 1);
    expect(held.acknowledgements, [1], reason: '状态已归约；内容尚未交付，不能提前ACK其序号');
    diagnose('before release');
    final first = session.content.ready;
    final second = session.content.ready;
    unawaited(first.then<void>((_) => diagnose('first ready completed')));
    unawaited(second.then<void>((_) => diagnose('second ready completed')));
    record({
      'feedStage': 'before release',
      'initialCalls': held.initialCalls,
      'nextCalls': held.nextCalls,
      'deliveredFrames': held.deliveredFrames,
      'acknowledgements': [...held.acknowledgements],
    });
    release.complete();
    await Future.wait([first, second]);
    diagnose('both ready completed');
    record({
      'heldFeed': held.subscriptionId,
      'initialCalls': held.initialCalls,
      'nextCalls': held.nextCalls,
      'deliveredFrames': held.deliveredFrames,
      'acknowledgements': [...held.acknowledgements],
    });
    expect(transport.feeds, hasLength(1));
    expect(held.initialCalls, 1);
    final display = graph.timeline.lease('thread-main');
    expect(display, isNotNull, reason: 'ready 只能在真实展示接纳完成基线后完成');
    expect(display!.items, isNotEmpty);
    expect(display.completedCursor, isNotNull);
    graph.setConversationPageVisible(false);
    await transport.feeds.single.joined.future;
    expect(transport.feeds.single.closeCalls, 1);
    expect(session.content.hasDemand, isFalse);
  });
}

final class _AckObservedFeed extends RecordingConversationFeed {
  _AckObservedFeed({required super.inner, required this.record});

  final void Function(Map<String, Object?>) record;
  final stateAckCompleted = Completer<void>();

  @override
  Stream<ConversationFrame> get events => super.events.map((frame) {
    record({
      'feedStage': 'delivered',
      'subscriptionId': frame.subscriptionId,
      'deliverySequence': frame.deliverySequence,
      'event': frame.event.runtimeType.toString(),
      if (frame.event case ConversationBaselineEvent(:final baseline)) ...{
        'epoch': baseline.timelineEpoch,
        'completedThrough': baseline.completedCursor.appendSeq,
        'atomIds': baseline.items.map((item) => item.id).toList(),
      },
    });
    return frame;
  });

  @override
  Future<void> acknowledge(int deliverySequence) async {
    await super.acknowledge(deliverySequence);
    record({
      'feedStage': 'ACK completed',
      'deliverySequence': deliverySequence,
      'acknowledgements': [...acknowledgements],
    });
    if (deliverySequence == 1 && !stateAckCompleted.isCompleted) {
      stateAckCompleted.complete();
    }
  }
}

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
