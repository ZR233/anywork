import 'dart:async';

import 'package:anywork_client/studio_client.dart';

import 'timeline_transport.dart';

// Scripted environment delivery, not SDK state mutation. Each helper waits for
// the real feed ACK, so synchronous freeze assertions observe actual reduction.
final Map<String, TestConversationFeed> _feeds = {};
final Map<String, Completer<TestConversationFeed>> _waiting = {};
void registerScriptedFeed(TestConversationFeed feed) {
  _feeds[feed.threadId] = feed;
  _waiting.remove(feed.threadId)?.complete(feed);
}

Future<TestConversationFeed> scriptedFeed(String threadId) {
  final current = _feeds[threadId];
  return current != null && !current.requestCloseStarted.isCompleted
      ? Future.value(current)
      : (_waiting[threadId] ??= Completer()).future;
}

extension ConversationTestDelivery on ConversationSession {
  Future<void> deliverWorkspace(ThreadWorkspace workspace) async {
    final feed = await scriptedFeed(threadId);
    await feed.deliver(
      ConversationStateEvent(frame: ThreadSnapshotFrame(workspace: workspace)),
    );
  }

  Future<void> deliverNotification(ThreadNotificationFrame frame) async {
    final feed = await scriptedFeed(threadId);
    await feed.deliver(ConversationStateEvent(frame: frame));
  }
}

class ScriptedConversationFeed extends TestConversationFeed {
  ScriptedConversationFeed({
    String threadId = 'thread',
    ConversationBaseline? initial,
    Stream<ThreadStreamFrame>? states,
    this.resumeAfter,
  }) : initial = initial ?? baseline(1),
       states = states,
       super(
         threadId: threadId,
         subscriptionId: initial?.subscriptionId ?? 'sub',
       );
  final ConversationBaseline initial;
  final Stream<ThreadStreamFrame>? states;
  final ConversationCompletionCursor? resumeAfter;
  StreamSubscription<ThreadStreamFrame>? _states;
  @override
  Stream<ConversationFrame> get events {
    final stream = super.events;
    // Native creation captures a baseline before subsequent publication.
    scheduleMicrotask(() {
      if (requestCloseStarted.isCompleted) return;
      if (resumeAfter == null) {
        send(ConversationBaselineEvent(baseline: initial));
      }
      _states = states?.listen(
        (state) => send(ConversationStateEvent(frame: state)),
        onError: (Object error, StackTrace stack) => send(
          ConversationFailureEvent(
            failure: StudioFailure(
              code: StudioFailureCode.internal,
              message: error.toString(),
              retryable: false,
              correlationId: 'scripted-state',
            ),
          ),
        ),
      );
      registerScriptedFeed(this);
    });
    return stream;
  }

  @override
  Future<void> close() async {
    await _states?.cancel();
    await super.close();
  }
}
