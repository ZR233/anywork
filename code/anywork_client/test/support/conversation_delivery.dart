import 'dart:async';

import 'package:anywork_client/studio_client.dart';

import 'timeline_transport.dart';

// Scripted environment delivery, not SDK state mutation. Each helper waits for
// the real feed ACK, so synchronous freeze assertions observe actual reduction.
final Map<String, TestCurrentReader> _stateFeeds = {};
final Map<String, Completer<TestCurrentReader>> _stateWaiting = {};
void registerScriptedCurrentReader(TestCurrentReader feed) {
  _stateFeeds[feed.threadId] = feed;
  _stateWaiting.remove(feed.threadId)?.complete(feed);
}

Future<TestCurrentReader> scriptedCurrentReader(String threadId) {
  final current = _stateFeeds[threadId];
  return current != null && !current.requestCloseStarted.isCompleted
      ? Future.value(current)
      : (_stateWaiting[threadId] ??= Completer()).future;
}

extension ConversationTestDelivery on ConversationSession {
  Future<void> deliverWorkspace(ThreadWorkspace workspace) async {
    final feed = await scriptedCurrentReader(threadId);
    await feed.deliver(
      testCurrentEvent(
        frame: ThreadSnapshotFrame(
          schemaVersion: threadSchemaVersion,
          completedHistoryVersion: completedHistoryVersion,
          workspace: workspace,
        ),
      ),
    );
  }

  Future<void> deliverNotification(ThreadNotificationFrame frame) async {
    final feed = await scriptedCurrentReader(threadId);
    await feed.deliver(testCurrentEvent(frame: frame));
  }
}

/// Content-only scripted feed: it pumps the initial Chat set and never carries
/// state frames; state scripts attach to [ScriptedCurrentReader].
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

/// Current-only scripted reader. Each Thread event is wrapped into the
/// corresponding CurrentFrame; gaps become explicit watch errors.
class ScriptedCurrentReader extends TestCurrentReader {
  ScriptedCurrentReader({
    String threadId = 'thread',
    Stream<ThreadStreamFrame>? states,
    CurrentView? initialView,
  }) : states = states,
       super(threadId: threadId, initialView: initialView);
  final Stream<ThreadStreamFrame>? states;
  StreamIterator<ThreadStreamFrame>? _states;
  Future<void>? _pump;

  @override
  Future<CurrentWatch> watch({
    CurrentRevision? after,
    required ReadDemand demand,
  }) async {
    final watch = await super.watch(after: after, demand: demand);
    registerScriptedCurrentReader(this);
    _pump ??= () {
      final done = Completer<void>();
      scheduleMicrotask(() => done.complete(_pumpEvents()));
      return done.future;
    }();
    return watch;
  }

  Future<void> _pumpEvents() async {
    if (requestCloseStarted.isCompleted) return;
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
        sendCurrentFrame(testCurrentEvent(frame: iterator.current));
        await Future<void>.value();
      }
    } catch (error) {
      if (requestCloseStarted.isCompleted) return;
      sendError(ConversationContinuityError('scripted current: $error'));
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
