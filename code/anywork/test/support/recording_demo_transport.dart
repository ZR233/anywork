import 'dart:async';

import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork_client/studio_client.dart';

/// Lifecycle instrumentation around the real Demo transport; it does not reduce content.
class RecordingDemoTransport extends DemoStudioTransport {
  final List<RecordingConversationFeed> feeds = [];
  final List<RecordingConversationStateFeed> stateFeeds = [];
  final Map<String, Completer<RecordingConversationStateFeed>>
  _stateFeedWaiters = {};
  final bootstrapDelivered = Completer<void>();
  int bootstrapCalls = 0;
  Object? failNextInitial;

  /// 在当前实际状态订阅投递状态事实，并等待 SDK 处理后的显式 ACK。
  Future<void> publishWorkspace(ThreadWorkspace workspace) async {
    final feed = await _activeStateFeed(workspace.thread.id);
    await feed.emitStateAndWait(
      ThreadSnapshotFrame(
        workspace: workspace,
        completedHistoryVersion: feed.completedHistoryVersion,
        schemaVersion: feed.schemaVersion,
      ),
    );
  }

  /// Waits for the actual visible-demand state feed; it never fabricates one.
  Future<RecordingConversationStateFeed> _activeStateFeed(
    String threadId,
  ) async {
    final current = stateFeeds
        .where((feed) => feed.threadId == threadId && !feed._closed)
        .lastOrNull;
    if (current != null) return current;
    return (_stateFeedWaiters[threadId] ??=
            Completer<RecordingConversationStateFeed>())
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
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    required ChatScope scope,
    required ReadDemand demand,
  }) async {
    final failure = failNextInitial;
    failNextInitial = null;
    final feed = RecordingConversationFeed(
      inner: await super.openConversationFeed(
        threadId,
        scope: scope,
        demand: demand,
      ),
      initialFailure: failure,
    );
    feeds.add(feed);
    return feed;
  }

  @override
  Future<ConversationStateFeed> openConversationStateFeed(
    String threadId,
  ) async {
    final feed = RecordingConversationStateFeed(
      inner: await super.openConversationStateFeed(threadId),
    );
    stateFeeds.add(feed);
    _stateFeedWaiters.remove(threadId)?.complete(feed);
    return feed;
  }

  final List<RecordingTimelineFeed> timelineFeeds = [];

  @override
  Future<TimelineFeed> openTimelineFeed(
    String threadId, {
    required ReadDemand demand,
  }) async {
    final failure = failNextInitial;
    failNextInitial = null;
    final feed = RecordingTimelineFeed(
      inner: await super.openTimelineFeed(threadId, demand: demand),
      initialFailure: failure,
    );
    timelineFeeds.add(feed);
    feeds.add(feed);
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
  @override
  ConversationReader get reader => inner.reader;
  Object? initialFailure;
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
  bool _closed = false;
  bool _claimed = false;
  int _sequence = 0;
  int get deliveredFrames => _sequence;
  final Map<int, int> _nativeSequences = {};
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
    if (switch (event) {
      ConversationChatEvent(batch: ChatBatch(placement: ChatPlacement.set)) =>
        true,
      ConversationTimelineEvent(
        batch: TimelineBatch(placement: ChatPlacement.set),
      ) =>
        true,
      _ => false,
    }) {
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
    if (scriptFrames &&
        switch (event) {
          ConversationChatEvent(
            batch: ChatBatch(placement: ChatPlacement.append),
          ) =>
            true,
          ConversationTimelineEvent(
            batch: TimelineBatch(placement: ChatPlacement.append),
          ) =>
            true,
          _ => false,
        }) {
      return;
    }
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
  void emit(ChatBatch? batch) {
    if (_closed) return;
    if (batch == null) {
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
        event: ConversationChatEvent(batch: batch),
      ),
    );
  }

  void emitActivity(ActivitySnapshot snapshot) {
    if (_closed) return;
    _events.add(
      ConversationFrame(
        threadId: threadId,
        subscriptionId: subscriptionId,
        deliverySequence: ++_sequence,
        event: ConversationActivityEvent(snapshot: snapshot),
      ),
    );
  }

  void emitError(Object error) {
    if (!_closed) _events.addError(error);
  }

  void emitTimeline(TimelineBatch batch) {
    if (_closed) return;
    _events.add(
      ConversationFrame(
        threadId: threadId,
        subscriptionId: subscriptionId,
        deliverySequence: ++_sequence,
        event: ConversationTimelineEvent(batch: batch),
      ),
    );
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    acknowledgements.add(deliverySequence);
    final native = _nativeSequences[deliverySequence];
    if (native != null) await inner.acknowledge(native);
    _nativeSequences.removeWhere((key, _) => key <= deliverySequence);
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    if (_closed) return;
    _closed = true;
    onClosed?.call();
    inner.requestClose();
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

class RecordingTimelineFeed extends RecordingConversationFeed
    implements TimelineFeed {
  RecordingTimelineFeed({required TimelineFeed inner, super.initialFailure})
    : super(inner: inner);
  TimelineFeed get timeline => inner as TimelineFeed;

  @override
  Future<TimelineBatch> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) {
    pageCalls++;
    return timeline.loadTimelineOlder(before: before, demand: demand);
  }

  @override
  Future<LiveDisplayWindow> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  }) => timeline.loadLiveOlder(before: before, demand: demand);

  @override
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) {
    detailCalls++;
    return timeline.openDisplayMembers(
      reference: reference,
      window: window,
      demand: demand,
    );
  }
}

/// The state-channel recorder: identity, sequence and ACK stay on the
/// independent state subscription; content never flows through it.
class RecordingConversationStateFeed implements ConversationStateFeed {
  RecordingConversationStateFeed({required this.inner});
  final ConversationStateFeed inner;
  @override
  String get threadId => inner.threadId;
  @override
  String get subscriptionId => inner.subscriptionId;
  void Function(ThreadStreamFrame)? onState;
  void Function()? onClosed;
  final joined = Completer<void>();
  int requestCloseCalls = 0;
  int closeCalls = 0;
  final acknowledgements = <int>[];
  int? completedHistoryVersion;
  int? schemaVersion;
  int _sequence = 0;
  int get deliveredFrames => _sequence;
  final Map<int, int> _nativeSequences = {};
  final Map<int, Completer<void>> _ackWaiters = {};
  StreamSubscription<ConversationFrame>? _subscription;
  bool _closed = false;
  bool _claimed = false;
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
    if (_claimed) throw StateError('Recording state feed already consumed');
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
    if (event case ConversationStateEvent(
      frame: ThreadSnapshotFrame(
        completedHistoryVersion: final historyVersion,
        schemaVersion: final stateVersion,
      ),
    )) {
      completedHistoryVersion = historyVersion;
      schemaVersion = stateVersion;
    }
    if (event case ConversationStateEvent(:final frame)) onState?.call(frame);
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

  /// An explicit scripted state frame, not a second reducer.
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
    if (_closed) return Future.error(StateError('Recording state feed closed'));
    final accepted = Completer<void>();
    _ackWaiters[_sequence + 1] = accepted;
    emitState(frame);
    return accepted.future;
  }

  void emitError(Object error) {
    if (!_closed) _events.addError(error);
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
