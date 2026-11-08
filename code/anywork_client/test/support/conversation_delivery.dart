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
      ConversationStateEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: 17,
          completedHistoryVersion: 1,
          workspace: workspace,
        ),
      ),
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
    String subscriptionId = 'sub',
    ChatBatch? initial,
    Stream<ThreadStreamFrame>? states,
    TestConversationReader? reader,
  }) : initial = initial ?? chatSet(),
       states = states,
       super(
         threadId: threadId,
         subscriptionId: subscriptionId,
         reader: reader,
       );
  final ChatBatch initial;
  final Stream<ThreadStreamFrame>? states;
  StreamIterator<ThreadStreamFrame>? _states;
  Future<void>? _pump;
  @override
  Stream<ConversationFrame> get events {
    final stream = super.events;
    _pump ??= () {
      final done = Completer<void>();
      scheduleMicrotask(() => done.complete(_pumpEvents()));
      return done.future;
    }();
    return stream;
  }

  Future<void> _pumpEvents() async {
    if (requestCloseStarted.isCompleted) return;
    registerScriptedFeed(this);
    await _deliverCredited(ConversationChatEvent(batch: initial));
    final source = states;
    if (source == null || requestCloseStarted.isCompleted) return;
    final iterator = StreamIterator(source);
    _states = iterator;
    if (requestCloseStarted.isCompleted) {
      await iterator.cancel();
      if (identical(_states, iterator)) _states = null;
      return;
    }
    try {
      while (!requestCloseStarted.isCompleted) {
        final hasNext = await _moveNext(iterator);
        if (!hasNext || requestCloseStarted.isCompleted) return;
        await _deliverCredited(ConversationStateEvent(frame: iterator.current));
      }
    } catch (error) {
      if (requestCloseStarted.isCompleted) return;
      await _deliverCredited(
        ConversationFailureEvent(
          failure: StudioFailure(
            code: StudioFailureCode.internal,
            message: error.toString(),
            retryable: false,
            correlationId: 'scripted-state',
          ),
        ),
      );
    } finally {
      await iterator.cancel();
      if (identical(_states, iterator)) _states = null;
    }
  }

  Future<bool> _moveNext(StreamIterator<ThreadStreamFrame> iterator) async {
    if (requestCloseStarted.isCompleted) return false;
    final next = iterator.moveNext();
    try {
      final progressed = await Future.any<bool>([
        next,
        requestCloseStarted.future.then((_) => false),
      ]);
      if (requestCloseStarted.isCompleted) {
        unawaited(next.catchError((_, __) => false));
        return false;
      }
      return progressed;
    } catch (error) {
      if (requestCloseStarted.isCompleted) {
        unawaited(next.catchError((_, __) => false));
        return false;
      }
      rethrow;
    }
  }

  Future<void> _deliverCredited(ConversationEvent event) async {
    if (requestCloseStarted.isCompleted) return;
    final sequence = send(event);
    if (requestCloseStarted.isCompleted) return;
    if (event is ConversationClosedEvent || event is ConversationFailureEvent) {
      return;
    }
    await Future.any<void>([
      acknowledged(sequence),
      requestCloseStarted.future,
    ]);
  }

  @override
  Future<void> close() async {
    Object? closeError;
    try {
      await super.close();
    } catch (error) {
      closeError = error;
    }
    Object? pumpError;
    final pump = _pump;
    if (pump != null) {
      try {
        await pump;
      } catch (error) {
        pumpError = error;
      }
    }
    if (closeError != null) throw closeError;
    if (pumpError != null) throw pumpError;
  }
}
