import 'dart:async';

import 'package:anywork_client/studio_client.dart';

import 'timeline_transport.dart';

// Scripted environment delivery, not SDK state mutation. Each helper waits for
// the real feed ACK, so synchronous freeze assertions observe actual reduction.
final Map<String, TestConversationStateFeed> _stateFeeds = {};
final Map<String, Completer<TestConversationStateFeed>> _stateWaiting = {};
void registerScriptedStateFeed(TestConversationStateFeed feed) {
  _stateFeeds[feed.threadId] = feed;
  _stateWaiting.remove(feed.threadId)?.complete(feed);
}

Future<TestConversationStateFeed> scriptedStateFeed(String threadId) {
  final current = _stateFeeds[threadId];
  return current != null && !current.requestCloseStarted.isCompleted
      ? Future.value(current)
      : (_stateWaiting[threadId] ??= Completer()).future;
}

extension ConversationTestDelivery on ConversationSession {
  Future<void> deliverWorkspace(ThreadWorkspace workspace) async {
    final feed = await scriptedStateFeed(threadId);
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
    final feed = await scriptedStateFeed(threadId);
    await feed.deliver(ConversationStateEvent(frame: frame));
  }
}

/// Content-only scripted feed: it pumps the initial Chat set and never carries
/// state frames; state scripts attach to [ScriptedConversationStateFeed].
class ScriptedConversationFeed extends TestConversationFeed {
  ScriptedConversationFeed({
    String threadId = 'thread',
    String subscriptionId = 'sub',
    ChatBatch? initial,
    TestConversationReader? reader,
  }) : initial = initial ?? chatSet(),
       super(
         threadId: threadId,
         subscriptionId: subscriptionId,
         reader: reader,
       );
  final ChatBatch initial;
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
    await _deliverCredited(ConversationChatEvent(batch: initial));
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

/// State-only scripted feed: it pumps explicit state frames with real credit
/// waits; content never flows here.
class ScriptedConversationStateFeed extends TestConversationStateFeed {
  ScriptedConversationStateFeed({
    String threadId = 'thread',
    String subscriptionId = 'state-sub',
    Stream<ThreadStreamFrame>? states,
  }) : states = states,
       super(threadId: threadId, subscriptionId: subscriptionId);
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
    registerScriptedStateFeed(this);
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
