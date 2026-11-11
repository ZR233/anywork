import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_demo_transport.dart';
import '../support/chat_fixtures.dart';
import '../support/test_statistics_feed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('首Timeline Set实际接纳前，两个ready等待不能提前完成或ACK', () async {
    var diagnosticSequence = 0;
    void record(Map<String, Object?> facts) => debugPrintSynchronously(
      jsonEncode({'sequence': ++diagnosticSequence, ...facts}),
    );
    final transport = RecordingDemoTransport();
    final opened = Completer<_AckObservedFeed>();
    final stateOpened = Completer<_AckObservedStateFeed>();
    final release = Completer<void>();
    transport.conversationStateFeedFactory = (threadId, inner) async {
      final observed = _AckObservedStateFeed(inner: inner);
      stateOpened.complete(observed);
      return observed;
    };
    transport.timelineFeedFactory = (threadId, inner) async {
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
        'leaseRetired': display?.isRetired,
        'leaseReleased': display?.isReleased,
        'messageIds': display?.controller.messages
            .map((message) => message.id)
            .toList(),
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
    expect(transport.timelineFeeds, isEmpty, reason: '读取session不隐式声明内容需求');
    graph.timeline.updateReadDemand(chatDemand);
    final metadata = graph.client.threadDirectory.observeThread('thread-main');
    final metadataState = await metadata.state
        .waitFor((state) => state.frame != null)
        .timeout(const Duration(seconds: 5));
    final row = metadataState.frame!.row!;
    await metadata.release();
    graph.setConversationPageVisible(true);
    await graph.client.directoryCommands.selectThread(row.threadId);
    final held = await opened.future;
    await held.initialEntered.future;
    final stateFeed = await stateOpened.future;
    await stateFeed.stateAckCompleted.future;
    expect(session.content.state.value, isA<ChatOpening<bool>>());
    expect(graph.timeline.lease('thread-main'), isNull);
    expect(held.initialCalls, 1);
    expect(stateFeed.acknowledgements, [1]);
    expect(held.acknowledgements, isEmpty, reason: '独立状态已确认；尚未交付的内容不能提前ACK');
    diagnose('before release');
    final first = session.content.ready;
    final second = session.content.ready;
    var firstCompleted = false;
    var secondCompleted = false;
    unawaited(
      first.then<void>((_) {
        firstCompleted = true;
        diagnose('first ready completed');
      }),
    );
    unawaited(
      second.then<void>((_) {
        secondCompleted = true;
        diagnose('second ready completed');
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(firstCompleted, isFalse);
    expect(secondCompleted, isFalse);
    expect(held.acknowledgements, isEmpty);
    record({
      'feedStage': 'before release',
      'initialCalls': held.initialCalls,
      'nextCalls': held.nextCalls,
      'deliveredFrames': held.deliveredFrames,
      'acknowledgements': [...held.acknowledgements],
    });
    release.complete();
    await Future.wait([first, second]);
    await held.firstAckCompleted.future;
    expect(held.acknowledgements, [1]);
    diagnose('both ready completed');
    record({
      'heldFeed': held.subscriptionId,
      'initialCalls': held.initialCalls,
      'nextCalls': held.nextCalls,
      'deliveredFrames': held.deliveredFrames,
      'acknowledgements': [...held.acknowledgements],
    });
    expect(transport.timelineFeeds, hasLength(1));
    expect(held.initialCalls, 1);
    final display = graph.timeline.lease('thread-main');
    expect(display, isNotNull, reason: 'ready 只能在真实展示接纳完成基线后完成');
    expect(display!.controller.messages, isNotEmpty);
    expect(session.state.businessRefs, isNotNull);
    graph.setConversationPageVisible(false);
    await transport.timelineFeeds.single.joined.future;
    expect(transport.timelineFeeds.single.closeCalls, 1);
    expect(session.content.hasDemand, isFalse);
  });
}

final class _AckObservedFeed extends RecordingTimelineFeed {
  _AckObservedFeed({required super.inner, required this.record});

  final void Function(Map<String, Object?>) record;
  final firstAckCompleted = Completer<void>();

  @override
  Stream<ConversationFrame> get events => super.events.map((frame) {
    record({
      'feedStage': 'delivered',
      'subscriptionId': frame.subscriptionId,
      'deliverySequence': frame.deliverySequence,
      'event': frame.event.runtimeType.toString(),
      if (frame.event case ConversationTimelineEvent(:final batch)) ...{
        'placement': batch.placement.name,
        'entries': [
          for (final entry in batch.blocks)
            {'blockId': entry.id, 'historyPos': entry.historyPos},
        ],
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
    if (deliverySequence == 1 && !firstAckCompleted.isCompleted) {
      firstAckCompleted.complete();
    }
  }
}

final class _AckObservedStateFeed extends RecordingConversationStateFeed {
  _AckObservedStateFeed({required super.inner});

  final stateAckCompleted = Completer<void>();

  @override
  Future<void> acknowledge(int deliverySequence) async {
    await super.acknowledge(deliverySequence);
    if (deliverySequence == 1 && !stateAckCompleted.isCompleted) {
      stateAckCompleted.complete();
    }
  }
}

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
