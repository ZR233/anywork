import 'dart:async';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/conversation_ports.dart';

/// Lifecycle instrumentation around the real Demo transport; it does not reduce content.
class RecordingDemoTransport extends DemoStudioTransport {
  final List<RecordingConversationFeed> feeds = [];
  final Map<String, Completer<RecordingConversationFeed>> _feedWaiters = {};
  final bootstrapDelivered = Completer<void>();
  int bootstrapCalls = 0;
  Object? failNextInitial;

  /// 在当前实际 feed 投递状态事实，并等待 SDK 处理后的显式 ACK。
  Future<void> publishWorkspace(ThreadWorkspace workspace) async {
    final feed = await _activeFeed(workspace.thread.id);
    await feed.emitStateAndWait(ThreadSnapshotFrame(workspace: workspace));
  }

  /// Waits for the actual visible-demand feed; it never opens or fabricates one.
  Future<RecordingConversationFeed> _activeFeed(String threadId) async {
    final current = feeds
        .where((feed) => feed.threadId == threadId && !feed._closed)
        .lastOrNull;
    if (current != null) return current;
    return (_feedWaiters[threadId] ??= Completer<RecordingConversationFeed>())
        .future;
  }

  @override
  Duration get shutdownPhaseDelay => Duration.zero;
  @override
  Future<StudioBootstrap> readBootstrap() async {
    bootstrapCalls++;
    final result = await super.readBootstrap();
    if (!bootstrapDelivered.isCompleted) bootstrapDelivered.complete();
    return result;
  }

  @override
  Future<ConversationFeed> openConversationFeed(String threadId) async {
    final failure = failNextInitial;
    failNextInitial = null;
    final feed = RecordingConversationFeed(
      inner: await super.openConversationFeed(threadId),
      initialFailure: failure,
    );
    feeds.add(feed);
    _feedWaiters.remove(threadId)?.complete(feed);
    return feed;
  }
}

/// Gating/error injection is confined to the external transport seam. Real Demo facts,
/// preview budgeting, typed DTOs and production SDK reduction remain on the normal path.
class RecordingConversationFeed implements ConversationFeed {
  RecordingConversationFeed({required this.inner, this.initialFailure});
  final ConversationFeed inner;
  @override
  String get threadId => inner.threadId;
  @override
  String get subscriptionId => inner.subscriptionId;
  Object? initialFailure;
  void Function(ThreadStreamFrame)? onState;
  void Function()? onClosed;
  Completer<void>? initialGate;
  final initialEntered = Completer<void>();
  final nextEntered = Completer<void>();
  final joined = Completer<void>();
  int initialCalls = 0;
  int nextCalls = 0;
  int pageCalls = 0;
  int detailCalls = 0;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  final acknowledgements = <int>[];
  bool scriptFrames = false;
  Completer<ConversationPage>? scriptedPage;
  bool _closed = false;
  bool _claimed = false;
  int _sequence = 0;
  int get deliveredFrames => _sequence;
  final Map<int, int> _nativeSequences = {};
  final Map<int, Completer<void>> _ackWaiters = {};
  StreamSubscription<ConversationFrame>? _subscription;
  Future<void>? _closing;
  final Set<Future<void>> _pending = {};
  late final StreamController<ConversationFrame> _events = StreamController(
    onListen: _listen,
    onCancel: () {
      requestClose();
      return close();
    },
  );
  @override
  Stream<ConversationFrame> get events {
    if (_claimed) throw StateError('Recording feed already has a consumer');
    _claimed = true;
    return _events.stream;
  }

  void _listen() {
    if (_closed) {
      unawaited(_events.close());
      return;
    }
    _subscription = inner.events.listen(
      (frame) {
        if (_closed) return;
        // Retain the actual in-flight conversion/gate work so close can join it.
        final work = _forward(frame);
        _pending.add(work);
        unawaited(
          work.then<void>(
            (_) {
              _pending.remove(work);
            },
            onError: (Object error, StackTrace stack) {
              _pending.remove(work);
              if (!_closed) _events.addError(error, stack);
            },
          ),
        );
      },
      onError: (Object error, StackTrace stack) {
        if (!_closed) _events.addError(error, stack);
      },
      onDone: () {
        if (!_closed) unawaited(_events.close());
      },
    );
  }

  Future<void> _forward(ConversationFrame frame) async {
    final event = frame.event;
    if (event case ConversationStateEvent(:final frame)) onState?.call(frame);
    if (event is ConversationBaselineEvent) {
      initialCalls++;
      if (!initialEntered.isCompleted) initialEntered.complete();
      await initialGate?.future;
      if (_closed) return;
      if (initialFailure case final error?) {
        initialFailure = null;
        throw error;
      }
      nextCalls++;
      if (!nextEntered.isCompleted) nextEntered.complete();
    }
    if (scriptFrames && event is ConversationUpdateEvent) return;
    final terminal =
        event is ConversationClosedEvent || event is ConversationFailureEvent;
    final sequence = terminal ? _sequence : ++_sequence;
    if (!terminal) _nativeSequences[sequence] = frame.deliverySequence;
    if (!_closed) {
      _events.add(
        ConversationFrame(
          threadId: threadId,
          subscriptionId: subscriptionId,
          deliverySequence: sequence,
          event: event,
        ),
      );
    }
  }

  /// An explicit scripted transport fault/value, not a second business reducer.
  void emit(ConversationUpdate? update) {
    if (_closed) return;
    if (update == null) {
      _events.add(
        ConversationFrame(
          threadId: threadId,
          subscriptionId: subscriptionId,
          deliverySequence: _sequence,
          event: const ConversationClosedEvent(),
        ),
      );
      return;
    }
    _events.add(
      ConversationFrame(
        threadId: threadId,
        subscriptionId: subscriptionId,
        deliverySequence: ++_sequence,
        event: ConversationUpdateEvent(update: update),
      ),
    );
  }

  void emitError(Object error) {
    if (!_closed) _events.addError(error);
  }

  void emitState(ThreadStreamFrame frame) {
    if (_closed) return;
    onState?.call(frame);
    _events.add(
      ConversationFrame(
        threadId: threadId,
        subscriptionId: subscriptionId,
        deliverySequence: ++_sequence,
        event: ConversationStateEvent(frame: frame),
      ),
    );
  }

  Future<void> emitStateAndWait(ThreadStreamFrame frame) {
    if (_closed) return Future.error(StateError('Recording feed is closed'));
    final accepted = Completer<void>();
    _ackWaiters[_sequence + 1] = accepted;
    emitState(frame);
    return accepted.future;
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    acknowledgements.add(deliverySequence);
    final native = _nativeSequences[deliverySequence];
    if (native != null) await inner.acknowledge(native);
    _nativeSequences.removeWhere((key, _) => key <= deliverySequence);
    _ackWaiters.remove(deliverySequence)?.complete();
  }

  @override
  Future<ConversationPage> page({String? before, int? limit}) {
    pageCalls++;
    return scriptedPage?.future ?? inner.page(before: before, limit: limit);
  }

  @override
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  }) {
    detailCalls++;
    return inner.readDetail(itemId: itemId, query: query);
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    if (_closed) return;
    _closed = true;
    onClosed?.call();
    inner.requestClose();
    for (final waiter in _ackWaiters.values) {
      waiter.completeError(StateError('Feed closed before state ACK'));
    }
    _ackWaiters.clear();
    if (initialGate case final gate? when !gate.isCompleted) gate.complete();
  }

  @override
  Future<void> close() {
    requestClose();
    return _closing ??= _join();
  }

  Future<void> _join() async {
    closeCalls++;
    try {
      await inner.close();
      await Future.wait(_pending.toList());
      await _subscription?.cancel();
      if (_claimed) unawaited(_events.close());
      if (!joined.isCompleted) joined.complete();
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }
}
