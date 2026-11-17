import 'test_app_lifecycle.dart';

import 'dart:async';

import 'package:anywork_client/studio_client.dart';

import 'mapped_conversation_feed.dart';

import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';

/// Lifecycle instrumentation around the real Demo transport; it does not reduce content.
class RecordingDemoTransport extends TestDemoStudioTransport {
  RecordingDemoTransport({super.lifecycleRoot});
  final List<RecordingConversationFeed> feeds = [];
  final Map<String, Completer<RecordingCurrentReader>> _currentWaiters = {};
  final bootstrapDelivered = Completer<void>();
  int bootstrapCalls = 0;
  Object? failNextInitial;
  Object? failNextCurrentInitial;

  Future<void> publishWorkspace(ThreadWorkspace workspace) async {
    final reader = await _activeCurrent(workspace.thread.id);
    await reader.emitStateAndWait(
      ThreadSnapshotFrame(
        workspace: workspace,
        completedHistoryVersion: completedHistoryVersion,
        schemaVersion: threadSchemaVersion,
      ),
    );
  }

  Future<RecordingCurrentReader> _activeCurrent(String threadId) {
    final existing = currentReaders
        .where((reader) => reader.threadId == threadId && !reader.requested)
        .lastOrNull;
    if (existing != null) return Future.value(existing);
    return (_currentWaiters[threadId] ??= Completer()).future;
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

  final List<RecordingHistoryReader> historyReaders = [];
  final List<RecordingCurrentReader> currentReaders = [];
  Completer<void>? nextHistoryOpenGate;
  Completer<void>? nextCurrentOpenGate;
  void Function(String threadId)? testCurrentOpenEntered;

  /// Test-only projection of the same Current frame. Subclasses may alter typed
  /// fields for a scenario, but cannot inject a second State source.
  ThreadStreamFrame testMapCurrentState(ThreadStreamFrame frame) => frame;

  @override
  Future<HistoryReader> openHistoryReader(
    String threadId, {
    required int historyProtocolVersion,
  }) async {
    final inner = await super.openHistoryReader(
      threadId,
      historyProtocolVersion: historyProtocolVersion,
    );
    final reader = RecordingHistoryReader(inner: inner);
    historyReaders.add(reader);
    final gate = nextHistoryOpenGate;
    nextHistoryOpenGate = null;
    await gate?.future;
    return reader;
  }

  @override
  Future<CurrentReader> openCurrentReader(
    String threadId, {
    required int currentProtocolVersion,
    required ReadDemand demand,
  }) async {
    final inner = await super.openCurrentReader(
      threadId,
      currentProtocolVersion: currentProtocolVersion,
      demand: demand,
    );
    final failure = failNextCurrentInitial;
    failNextCurrentInitial = null;
    final reader = RecordingCurrentReader(
      inner: inner,
      initialFailure: failure,
      mapState: testMapCurrentState,
    );
    currentReaders.add(reader);
    _currentWaiters.remove(threadId)?.complete(reader);
    testCurrentOpenEntered?.call(threadId);
    final gate = nextCurrentOpenGate;
    nextCurrentOpenGate = null;
    await gate?.future;
    return reader;
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

final class RecordingHistoryReader implements HistoryReader {
  RecordingHistoryReader({required this.inner});

  final HistoryReader inner;
  int timelineCalls = 0;
  int groupCalls = 0;
  int turnsCalls = 0;
  int eventCalls = 0;
  int bodyCalls = 0;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  final joined = Completer<void>();
  Future<void>? _closing;
  bool _requested = false;
  void Function()? onClosed;

  @override
  OpenHistory get metadata => inner.metadata;
  @override
  String get threadId => inner.threadId;
  @override
  Future<HistoryCut> capture() => inner.capture();
  @override
  Future<HistoryTimelinePage> timelinePage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) {
    timelineCalls++;
    return inner.timelinePage(cut: cut, cursor: cursor, demand: demand);
  }

  @override
  Future<HistoryGroupPage> groupPage({
    required String groupId,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) {
    groupCalls++;
    return inner.groupPage(
      groupId: groupId,
      cut: cut,
      cursor: cursor,
      demand: demand,
    );
  }

  @override
  Future<HistoryTimelinePage> turnsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) {
    turnsCalls++;
    return inner.turnsPage(cut: cut, cursor: cursor, demand: demand);
  }

  @override
  Future<HistoryEventsPage> eventsPage({
    required HistoryEventsQuery query,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) =>
      inner.eventsPage(query: query, cut: cut, cursor: cursor, demand: demand);
  @override
  Future<HistoryEventDetail> readEvent({
    required String eventId,
    required HistoryDemand demand,
  }) {
    eventCalls++;
    return inner.readEvent(eventId: eventId, demand: demand);
  }

  @override
  Future<HistoryBodyPage> listBodies({
    required String eventId,
    String? cursor,
    required HistoryDemand demand,
  }) => inner.listBodies(eventId: eventId, cursor: cursor, demand: demand);
  @override
  Future<HistoryBodyWindow> readBody({
    required HistoryEventBodyRef reference,
    required int offset,
    required int maxBytes,
  }) {
    bodyCalls++;
    return inner.readBody(
      reference: reference,
      offset: offset,
      maxBytes: maxBytes,
    );
  }

  @override
  Future<HistoryAccounting?> accounting({HistoryCut? cut}) =>
      inner.accounting(cut: cut);
  @override
  Future<HistoryTimelinePage> costsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => inner.costsPage(cut: cut, cursor: cursor, demand: demand);
  @override
  Future<HistoryCut> waitChanged(HistoryCut after) => inner.waitChanged(after);

  @override
  void requestClose() {
    requestCloseCalls++;
    if (_requested) return;
    _requested = true;
    onClosed?.call();
    inner.requestClose();
  }

  @override
  Future<void> close() {
    requestClose();
    return _closing ??= () async {
      try {
        closeCalls++;
        await inner.close();
        if (!joined.isCompleted) joined.complete();
      } catch (_) {
        _closing = null;
        rethrow;
      }
    }();
  }
}

final class RecordingCurrentReader implements CurrentReader {
  RecordingCurrentReader({
    required this.inner,
    this.initialFailure,
    this.mapState,
  });

  final CurrentReader inner;
  Object? initialFailure;
  final ThreadStreamFrame Function(ThreadStreamFrame)? mapState;
  int snapshotCalls = 0;
  int watchCalls = 0;
  int initialViewReads = 0;
  int pageCalls = 0;
  int bodyCalls = 0;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  final joined = Completer<void>();
  Future<void>? _closing;
  bool _requested = false;
  void Function()? onClosed;
  final StreamController<CurrentFrame> _injected =
      StreamController<CurrentFrame>.broadcast(sync: true);
  final watchEntered = Completer<void>();
  int deliveredFrames = 0;

  bool get requested => _requested;

  @override
  OpenCurrent get metadata => inner.metadata;
  @override
  String get threadId => inner.threadId;
  @override
  CurrentView get initialView {
    initialViewReads++;
    if (initialFailure case final failure?) throw failure;
    return inner.initialView;
  }

  @override
  Future<CurrentView> snapshot(ReadDemand demand) {
    snapshotCalls++;
    return inner.snapshot(demand);
  }

  @override
  Future<CurrentWatch> watch({
    CurrentRevision? after,
    required ReadDemand demand,
  }) {
    watchCalls++;
    return inner.watch(after: after, demand: demand).then((watch) {
      if (!watchEntered.isCompleted) watchEntered.complete();
      return _RecordingCurrentWatch(watch, _injected.stream);
    });
  }

  Future<void> emitStateAndWait(ThreadStreamFrame frame) async {
    emitState(frame);
    // The injected controller is synchronous. Completion here means every Current
    // watch listener received the frame; SDK application remains owned by the
    // production serial queue and is awaited through the session source.
    await Future<void>.value();
  }

  void emitState(ThreadStreamFrame frame) {
    if (_requested) return;
    final ownerId = metadata.currentOwnerId;
    final mapped = mapState?.call(frame) ?? frame;
    final event = switch (mapped) {
      ThreadSnapshotFrame(:final workspace) => ResetCurrentFrame(
        CurrentView(
          revision: CurrentRevision(
            ownerId: ownerId,
            revision: workspace.revision,
          ),
          state: mapped,
          projection: CurrentProjection(
            logicalStatus: workspace.thread.status,
            executionPresent: workspace.runtime.execution != null,
            sources: const [],
            atoms: const [],
            plan: workspace.businessRefs.plan,
            interactions: workspace.businessRefs.interactions,
            previews: const [],
            collections: const [],
          ),
        ),
      ),
      ThreadNotificationFrame() => NotificationCurrentFrame(
        revision: CurrentRevision(ownerId: ownerId, revision: mapped.revision),
        notification: mapped,
      ),
      ThreadResyncRequiredFrame(:final dropped) =>
        throw ConversationContinuityError(
          'scripted Current gap dropped $dropped',
        ),
    };
    deliveredFrames++;
    _injected.add(event);
  }

  @override
  Future<CurrentCollectionPage> pageCollection({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) {
    pageCalls++;
    return inner.pageCollection(
      reference: reference,
      continuation: continuation,
      demand: demand,
    );
  }

  @override
  Future<ContentWindow> readBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) {
    bodyCalls++;
    return inner.readBody(reference: reference, range: range);
  }

  @override
  Future<CurrentBodyWatch> watchBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) => inner.watchBody(reference: reference, range: range);

  @override
  void requestClose() {
    requestCloseCalls++;
    if (_requested) return;
    _requested = true;
    onClosed?.call();
    unawaited(_injected.close());
    inner.requestClose();
  }

  @override
  Future<void> close() {
    requestClose();
    return _closing ??= () async {
      try {
        closeCalls++;
        await inner.close();
        if (!joined.isCompleted) joined.complete();
      } catch (_) {
        _closing = null;
        rethrow;
      }
    }();
  }
}

final class _RecordingCurrentWatch implements CurrentWatch {
  _RecordingCurrentWatch(this.inner, Stream<CurrentFrame> injected)
    : _output = StreamController<CurrentFrame>(sync: true) {
    _innerSubscription = inner.frames.listen(
      _output.add,
      onError: _output.addError,
      onDone: _endFromInner,
    );
    _injectedSubscription = injected.listen(
      _output.add,
      onError: _output.addError,
      onDone: _endFromInjected,
    );
  }

  final CurrentWatch inner;
  final StreamController<CurrentFrame> _output;
  StreamSubscription<CurrentFrame>? _innerSubscription;
  StreamSubscription<CurrentFrame>? _injectedSubscription;
  Future<void>? _closing;
  bool _innerDone = false;
  bool _injectedDone = false;

  @override
  Stream<CurrentFrame> get frames => _output.stream;

  void _endFromInner() {
    _innerDone = true;
    requestClose();
  }

  void _endFromInjected() {
    _injectedDone = true;
    if (!_innerDone) unawaited(_innerSubscription?.cancel());
    _innerDone = true;
    if (!_output.isClosed) unawaited(_output.close());
  }

  @override
  void requestClose() {
    inner.requestClose();
    unawaited(_injectedSubscription?.cancel());
    if (!_output.isClosed) unawaited(_output.close());
  }

  @override
  Future<void> close() => _closing ??= () async {
    requestClose();
    Object? error;
    try {
      await inner.close();
    } catch (failure) {
      error = failure;
    }
    await _innerSubscription?.cancel();
    await _injectedSubscription?.cancel();
    await _output.done;
    if (error != null) throw error;
  }();
}

/// Await the actual GUI application boundary, independently of completion consumers.
Future<void> timelineReady(TimelineSessionOwner owner, String threadId) async {
  final state = await owner.source.waitFor(
    (value) =>
        value?.threadId == threadId &&
        (value?.connection == TimelineConnectionPhase.ready ||
            value?.connection == TimelineConnectionPhase.failed),
  );
  if (state?.connection == TimelineConnectionPhase.failed) {
    throw state!.connectionError!;
  }
}
