import 'test_app_lifecycle.dart';

import 'dart:async';

import 'package:anywork_client/studio_client.dart';

import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';

/// Lifecycle instrumentation around the real Demo transport; it does not reduce content.
class RecordingDemoTransport extends TestDemoStudioTransport {
  RecordingDemoTransport({super.lifecycleRoot, super.lspActivityLoop});
  final Map<String, Completer<RecordingCurrentReader>> _currentWaiters = {};
  final bootstrapDelivered = Completer<void>();
  int bootstrapCalls = 0;
  Object? failNextCurrentInitial;

  Future<void> publishWorkspace(ThreadWorkspace workspace) async {
    var readers = currentReaders
        .where(
          (reader) =>
              reader.threadId == workspace.thread.id && !reader.requested,
        )
        .toList();
    if (readers.isEmpty) {
      readers = [
        await (_currentWaiters[workspace.thread.id] ??= Completer()).future,
      ];
    }
    final frame = ThreadSnapshotFrame(
      workspace: workspace,
      schemaVersion: threadSchemaVersion,
    );
    await Future.wait([
      for (final reader in readers) reader.emitStateAndWait(frame),
    ]);
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
      demand: demand,
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
  Future<HistoryTimelinePage> Function(HistoryCut?, String?, HistoryDemand)?
  onTimelinePage;

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
    return onTimelinePage?.call(cut, cursor, demand) ??
        inner.timelinePage(cut: cut, cursor: cursor, demand: demand);
  }

  @override
  Future<HistoryWorkRangePage> workRangePage({
    int? afterSeq,
    int? beforeSeq,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) {
    groupCalls++;
    return inner.workRangePage(
      afterSeq: afterSeq,
      beforeSeq: beforeSeq,
      cut: cut,
      cursor: cursor,
      demand: demand,
    );
  }

  @override
  Future<HistoryBusinessPage> turnsPage({
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
  Future<HistoryEventRecord> readEvent({
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
  Future<HistoryBusinessPage> costsPage({
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
    required this.demand,
    this.initialFailure,
    this.mapState,
  });

  final CurrentReader inner;
  final ReadDemand demand;
  Object? initialFailure;
  final ThreadStreamFrame Function(ThreadStreamFrame)? mapState;
  int snapshotCalls = 0;
  int watchCalls = 0;
  int initialViewReads = 0;
  int pageCalls = 0;
  int bodyCalls = 0;
  Future<ContentWindow> Function(
    CurrentContentRef reference,
    ContentRange range,
  )?
  onReadBody;
  Stream<ContentWindow> Function(
    CurrentContentRef reference,
    ContentRange range,
  )?
  onWatchBody;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  final joined = Completer<void>();
  Future<void>? _closing;
  bool _requested = false;
  void Function()? onClosed;
  final StreamController<CurrentFrame> _injected =
      StreamController<CurrentFrame>.broadcast(sync: true);
  Future<void>? _injectedClosing;
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
    return _mapView(inner.initialView);
  }

  CurrentView _mapView(CurrentView view) {
    final state = mapState?.call(view.state) ?? view.state;
    if (state is! ThreadSnapshotFrame) {
      throw StateError('A scripted Current baseline must remain a snapshot');
    }
    return CurrentView(
      revision: view.revision,
      state: state,
      projection: view.projection,
    );
  }

  CurrentFrame _mapFrame(CurrentFrame frame) => switch (frame) {
    ResetCurrentFrame(:final view) => ResetCurrentFrame(_mapView(view)),
    NotificationCurrentFrame(:final revision, :final notification) =>
      NotificationCurrentFrame(
        revision: revision,
        notification:
            mapState?.call(notification) as ThreadNotificationFrame? ??
            notification,
      ),
    ProjectionCurrentFrame() => frame,
  };

  @override
  Future<CurrentView> snapshot(ReadDemand demand) {
    snapshotCalls++;
    return inner.snapshot(demand).then(_mapView);
  }

  @override
  Future<CurrentWatch> watch({
    CurrentRevision? after,
    required ReadDemand demand,
  }) {
    watchCalls++;
    return inner.watch(after: after, demand: demand).then((watch) {
      if (!watchEntered.isCompleted) watchEntered.complete();
      if (_requested) {
        watch.requestClose();
        return watch;
      }
      return _RecordingCurrentWatch(watch, _injected.stream, _mapFrame);
    });
  }

  Future<void> emitStateAndWait(ThreadStreamFrame frame) async {
    emitState(frame);
    // The injected controller is synchronous. Completion here means every Current
    // watch listener received the frame; SDK application remains owned by the
    // production serial queue and is awaited through the session source.
    await Future<void>.value();
  }

  void emitCurrentFrame(CurrentFrame frame) {
    if (_requested) return;
    deliveredFrames++;
    _injected.add(frame);
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
    return onReadBody?.call(reference, range) ??
        inner.readBody(reference: reference, range: range);
  }

  @override
  Future<CurrentBodyWatch> watchBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) {
    final source = onWatchBody;
    if (source == null) {
      return inner.watchBody(reference: reference, range: range);
    }
    return Future.value(_FixtureCurrentBodyWatch(source(reference, range)));
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    if (_requested) return;
    _requested = true;
    onClosed?.call();
    _injectedClosing ??= _injected.close();
    inner.requestClose();
  }

  @override
  Future<void> close() {
    requestClose();
    return _closing ??= () async {
      try {
        closeCalls++;
        Object? error;
        StackTrace? stack;
        final injectedClosing = _injectedClosing;
        if (injectedClosing != null) {
          try {
            await injectedClosing;
          } catch (failure, trace) {
            error = failure;
            stack = trace;
          }
        }
        try {
          await inner.close();
        } catch (failure, trace) {
          error ??= failure;
          stack ??= trace;
        }
        if (error != null) Error.throwWithStackTrace(error, stack!);
        if (!joined.isCompleted) joined.complete();
      } catch (_) {
        _closing = null;
        rethrow;
      }
    }();
  }
}

final class _FixtureCurrentBodyWatch implements CurrentBodyWatch {
  const _FixtureCurrentBodyWatch(this.windows);
  @override
  final Stream<ContentWindow> windows;
  @override
  void requestClose() {}
  @override
  Future<void> close() async {}
}

final class _RecordingCurrentWatch implements CurrentWatch {
  _RecordingCurrentWatch(
    this.inner,
    Stream<CurrentFrame> injected,
    CurrentFrame Function(CurrentFrame) mapFrame,
  ) : _output = StreamController<CurrentFrame>(sync: true) {
    try {
      _innerSubscription = inner.frames
          .map(mapFrame)
          .listen(_addFrame, onError: _addError, onDone: _endFromInner);
      if (!_output.isClosed) {
        _injectedSubscription = injected.listen(
          _addFrame,
          onError: _addError,
          onDone: _endFromInjected,
        );
      }
    } catch (error, stack) {
      requestClose();
      Error.throwWithStackTrace(error, stack);
    }
  }

  final CurrentWatch inner;
  final StreamController<CurrentFrame> _output;
  StreamSubscription<CurrentFrame>? _innerSubscription;
  StreamSubscription<CurrentFrame>? _injectedSubscription;
  Future<void>? _closing;
  bool _innerDone = false;
  bool _requested = false;
  Future<void>? _outputClosing;

  @override
  Stream<CurrentFrame> get frames => _output.stream;

  void _addFrame(CurrentFrame frame) {
    if (!_output.isClosed) _output.add(frame);
  }

  void _addError(Object error, StackTrace stack) {
    if (!_output.isClosed) _output.addError(error, stack);
  }

  void _endFromInner() {
    _innerDone = true;
    requestClose();
  }

  void _endFromInjected() {
    if (!_innerDone) unawaited(_innerSubscription?.cancel());
    _innerDone = true;
    _closeOutput();
  }

  void _closeOutput() {
    if (_output.isClosed) {
      _outputClosing ??= Future<void>.value();
      return;
    }
    final listened = _output.hasListener;
    final closed = _output.close();
    // A late watch can be retired before its output is ever transferred to
    // the SDK. Such a controller has no listener that could acknowledge done.
    _outputClosing = listened ? closed : Future<void>.value();
  }

  @override
  void requestClose() {
    if (_requested) return;
    _requested = true;
    inner.requestClose();
    unawaited(_injectedSubscription?.cancel());
    _closeOutput();
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
    await _outputClosing;
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
