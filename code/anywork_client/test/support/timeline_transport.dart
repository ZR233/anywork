import 'dart:async';

import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';

import 'directory_feed.dart';
import 'product_topic_owner.dart';

CurrentView currentViewForWorkspace(
  ThreadWorkspace workspace, {
  String ownerId = 'owner',
  CurrentProjection? projection,
}) => CurrentView(
  revision: CurrentRevision(ownerId: ownerId, revision: workspace.revision),
  state: ThreadSnapshotFrame(
    workspace: workspace,
    schemaVersion: threadSchemaVersion,
  ),
  projection: projection ?? emptyCurrentProjection(workspace.thread.status),
);

ThreadWorkspace emptyCurrentWorkspace(String threadId) {
  final thread = StudioThread(
    id: threadId,
    workspaceId: 'workspace',
    title: 'Thread',
    mode: ThreadModeId.auto,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    updatedAt: DateTime.utc(2026),
    workspacePath: '/workspace',
    status: ThreadStatusView.idle,
  );
  return ThreadWorkspace(
    businessRefs: const ThreadBusinessRefs(plan: null, interactions: null),
    thread: thread,
    revision: 0,
    interactions: const [],
    runtime: const ThreadRuntimeView(
      modelId: 'model',
      contextTokens: 0,
      contextWindow: 1,
      totalTokens: 0,
      costLabel: '',
      activeSkills: [],
      activeMcpServers: [],
      activeLspServers: [],
    ),
  );
}

CurrentProjection emptyCurrentProjection(ThreadStatusView status) =>
    CurrentProjection(
      logicalStatus: status,
      executionPresent: false,
      sources: const [],
      atoms: const [],
      previews: const [],
      collections: const [],
    );

CurrentFrame testCurrentEvent({
  required ThreadStreamFrame frame,
  String ownerId = 'owner',
  CurrentProjection? projection,
}) => switch (frame) {
  ThreadSnapshotFrame() => ResetCurrentFrame(
    currentViewForWorkspace(
      frame.workspace,
      ownerId: ownerId,
      projection: projection,
    ),
  ),
  ThreadNotificationFrame() => NotificationCurrentFrame(
    revision: CurrentRevision(ownerId: ownerId, revision: frame.revision),
    notification: frame,
  ),
};

final class _CurrentFixtureFailure {
  const _CurrentFixtureFailure(this.error);
  final Object error;
}

class TestCurrentReader implements CurrentReader {
  TestCurrentReader({
    this.threadId = 'thread',
    this.currentOwnerId = 'owner',
    this.protocolVersion = currentProtocolVersion,
    this.initialFailure,
    CurrentView? initialView,
  }) : _initialView =
           initialView ??
           currentViewForWorkspace(
             emptyCurrentWorkspace(threadId),
             ownerId: currentOwnerId,
           ) {
    current = _initialView;
  }

  @override
  final String threadId;
  final String currentOwnerId;
  final int protocolVersion;
  final CurrentView _initialView;
  final Object? initialFailure;
  @override
  CurrentView get initialView {
    if (initialFailure case final failure?) throw failure;
    return _initialView;
  }

  late CurrentView current;
  StreamController<CurrentFrame>? get _frames => openedWatch?._frames;
  final Completer<void> watchListening = Completer<void>();
  final List<Object> _queued = [];
  TestCurrentWatch? openedWatch;
  bool _requested = false;
  bool get requested => _requested;
  int _sequence = 0;
  int closeCalls = 0;
  int requestCloseCalls = 0;
  final requestCloseStarted = Completer<void>();
  final closeStarted = Completer<void>();
  final closeCompleted = Completer<void>();
  Completer<void>? closeGate;
  Object? closeFailure;
  Future<CurrentCollectionPage> Function(
    CurrentCollectionRef reference,
    String? continuation,
    ReadDemand demand,
  )?
  onPage;
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

  @override
  OpenCurrent get metadata => OpenCurrent(
    readerId: 'current-reader-${currentOwnerId}',
    currentProtocolVersion: protocolVersion,
    currentOwnerId: currentOwnerId,
  );

  @override
  Future<CurrentView> snapshot(ReadDemand demand) async => current;

  @override
  Future<CurrentWatch> watch({
    CurrentRevision? after,
    required ReadDemand demand,
  }) async {
    if (openedWatch != null) throw StateError('Current watch already opened');
    final watch = TestCurrentWatch(
      onListen: () {
        if (!watchListening.isCompleted) watchListening.complete();
        for (final event in _queued) {
          _add(event);
        }
        _queued.clear();
      },
    );
    return openedWatch = watch;
  }

  int sendCurrentFrame(Object event) {
    final number = ++_sequence;
    if (_requested) return number;
    if (_frames == null) {
      _queued.add(event);
    } else {
      _add(event);
    }
    return number;
  }

  int send(Object event) => sendCurrentFrame(event);

  void sendError(Object error) =>
      sendCurrentFrame(_CurrentFixtureFailure(error));

  void _add(Object event) {
    final controller = _frames;
    if (controller == null || controller.isClosed) return;
    if (event case _CurrentFixtureFailure(:final error)) {
      controller.addError(error);
      return;
    }
    final frame = event as CurrentFrame;
    if (frame case ResetCurrentFrame(:final view)) current = view;
    controller.add(frame);
  }

  Future<void> deliver(Object event) async {
    await watchListening.future.timeout(const Duration(seconds: 2));
    sendCurrentFrame(event);
    await Future<void>.value();
    await Future<void>.value();
  }

  @override
  Future<CurrentCollectionPage> pageCollection({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) =>
      onPage?.call(reference, continuation, demand) ??
      Future.error(UnsupportedError('Unscripted pageCollection'));

  @override
  Future<ContentWindow> readBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) =>
      onReadBody?.call(reference, range) ??
      Future.error(UnsupportedError('Unscripted readBody'));

  @override
  Future<CurrentBodyWatch> watchBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) async {
    final stream = onWatchBody?.call(reference, range);
    if (stream == null) throw UnsupportedError('Unscripted watchBody');
    return TestCurrentBodyWatch(stream);
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    if (_requested) return;
    _requested = true;
    openedWatch?.requestClose();
    if (!requestCloseStarted.isCompleted) requestCloseStarted.complete();
    if (!closeStarted.isCompleted) closeStarted.complete();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    await closeGate?.future;
    if (closeFailure case final failure?) throw failure;
    await openedWatch?.close();
    if (!closeCompleted.isCompleted) closeCompleted.complete();
  }
}

final class TestCurrentWatch implements CurrentWatch {
  TestCurrentWatch({void Function()? onListen})
    : _frames = StreamController<CurrentFrame>.broadcast(onListen: onListen);
  final StreamController<CurrentFrame> _frames;
  Future<void>? _closing;
  @override
  Stream<CurrentFrame> get frames => _frames.stream;
  @override
  void requestClose() {
    if (!_frames.isClosed) unawaited(_frames.close());
  }

  @override
  Future<void> close() => _closing ??= () async {
    requestClose();
    await _frames.done;
  }();
}

final class TestCurrentBodyWatch implements CurrentBodyWatch {
  TestCurrentBodyWatch(this._source)
    : _controller = StreamController<ContentWindow>.broadcast();
  final Stream<ContentWindow> _source;
  final StreamController<ContentWindow> _controller;
  StreamSubscription<ContentWindow>? _subscription;
  Future<void>? _cancelling;

  @override
  Stream<ContentWindow> get windows {
    _subscription ??= _source.listen(
      _controller.add,
      onError: _controller.addError,
      onDone: () {
        if (!_controller.isClosed) unawaited(_controller.close());
      },
    );
    return _controller.stream;
  }

  @override
  void requestClose() {
    if (_cancelling != null) return;
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
    unawaited(
      _cancelling = Future<void>.sync(() async {
        await _subscription?.cancel();
      }),
    );
  }

  @override
  Future<void> close() async {
    requestClose();
    await _cancelling;
    await _controller.done;
  }
}

class TestHistoryReader implements HistoryReader {
  TestHistoryReader({
    this.threadId = 'thread',
    this.protocolVersion = historyProtocolVersion,
    HistoryCut? cut,
  }) : cut = cut ?? HistoryCut('cut-0');

  @override
  final String threadId;
  final int protocolVersion;
  HistoryCut cut;
  Future<HistoryTimelinePage> Function(HistoryCut?, String?, HistoryDemand)?
  onTimeline;
  Future<HistoryWorkRangePage> Function(
    int?,
    int?,
    HistoryCut?,
    String?,
    HistoryDemand,
  )?
  onWorkRange;
  Future<HistoryEventsPage> Function(
    HistoryEventsQuery,
    HistoryCut?,
    String?,
    HistoryDemand,
  )?
  onEvents;
  Future<HistoryCut> Function(HistoryCut)? onWaitChanged;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  final Set<void Function()> _pendingReads = {};
  final Set<Completer<HistoryCut>> _pendingWaits = {};
  bool _closed = false;
  bool get requested => requestCloseCalls > 0;

  @override
  OpenHistory get metadata => OpenHistory(
    readerId: 'history-reader-$threadId',
    historyProtocolVersion: protocolVersion,
  );

  @override
  Future<HistoryCut> capture() async => cut;

  @override
  Future<HistoryTimelinePage> timelinePage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) {
    final read = onTimeline;
    if (read == null) {
      return Future.error(UnsupportedError('Unscripted history timelinePage'));
    }
    final actualCut = cut ?? this.cut;
    return _read(() async {
      final page = await read(actualCut, cursor, demand);
      if (_closed) throw const ClientResourceClosed();
      this.cut = page.cut;
      return page;
    });
  }

  @override
  Future<HistoryWorkRangePage> workRangePage({
    int? afterSeq,
    int? beforeSeq,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) {
    final read = onWorkRange;
    if (read == null) {
      return Future.error(UnsupportedError('Unscripted history workRangePage'));
    }
    return _read(
      () => read(afterSeq, beforeSeq, cut ?? this.cut, cursor, demand),
    );
  }

  @override
  Future<HistoryBusinessPage> turnsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => throw UnsupportedError('Unscripted history turnsPage');

  @override
  Future<HistoryEventsPage> eventsPage({
    required HistoryEventsQuery query,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) {
    final read = onEvents;
    if (read == null) {
      return Future.error(UnsupportedError('Unscripted history eventsPage'));
    }
    return _read(() => read(query, cut, cursor, demand));
  }

  @override
  Future<HistoryEventRecord> readEvent({
    required String eventId,
    required HistoryDemand demand,
  }) => throw UnsupportedError('Unscripted history readEvent');

  @override
  Future<HistoryBodyPage> listBodies({
    required String eventId,
    String? cursor,
    required HistoryDemand demand,
  }) => throw UnsupportedError('Unscripted history listBodies');

  @override
  Future<HistoryBodyWindow> readBody({
    required HistoryEventBodyRef reference,
    required int offset,
    required int maxBytes,
  }) => throw UnsupportedError('Unscripted history readBody');

  @override
  Future<HistoryAccounting?> accounting({HistoryCut? cut}) async => null;

  @override
  Future<HistoryBusinessPage> costsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => throw UnsupportedError('Unscripted history costsPage');

  @override
  Future<HistoryCut> waitChanged(HistoryCut after) {
    if (_closed) return Future.error(const ClientResourceClosed());
    final waiter = Completer<HistoryCut>();
    _pendingWaits.add(waiter);
    final source =
        onWaitChanged?.call(after) ??
        Future<HistoryCut>.error(
          UnsupportedError('Unscripted history waitChanged'),
        );
    unawaited(
      source.then<void>(
        (cut) {
          if (!waiter.isCompleted) waiter.complete(cut);
        },
        onError: (Object error, StackTrace stack) {
          if (!waiter.isCompleted) waiter.completeError(error, stack);
        },
      ),
    );
    return waiter.future.whenComplete(() {
      _pendingWaits.remove(waiter);
    });
  }

  Future<T> _read<T>(Future<T> Function() operation) {
    if (_closed) return Future.error(const ClientResourceClosed());
    final waiter = Completer<T>();
    void cancel() {
      if (!waiter.isCompleted) {
        waiter.completeError(const ClientResourceClosed());
      }
    }

    _pendingReads.add(cancel);
    late final Future<T> source;
    try {
      source = operation();
    } catch (error, stack) {
      waiter.completeError(error, stack);
      _pendingReads.remove(cancel);
      return waiter.future;
    }
    unawaited(
      source
          .then<void>(
            (value) {
              if (!waiter.isCompleted) waiter.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              if (!waiter.isCompleted) waiter.completeError(error, stack);
            },
          )
          .whenComplete(() {
            _pendingReads.remove(cancel);
          }),
    );
    return waiter.future;
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    if (_closed) return;
    _closed = true;
    for (final cancel in _pendingReads.toList()) {
      cancel();
    }
    _pendingReads.clear();
    for (final waiter in _pendingWaits.toList()) {
      if (!waiter.isCompleted) {
        waiter.completeError(const ClientResourceClosed());
      }
    }
    _pendingWaits.clear();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
  }
}

class TestConversationTransport extends StudioTransport
    with DirectoryFeedFixture {
  final List<({String threadId, Completer<CurrentReader> result})>
  currentOpens = [];
  final List<({String threadId, Completer<HistoryReader> result})>
  historyOpens = [];
  TestCurrentReader Function(String threadId, int index)? currentReaderFactory;
  TestHistoryReader Function(String threadId, int index)? historyReaderFactory;
  final List<ProductTopic> productTopics = [];
  final List<TestProductTopicOwner> productTopicOwners = [];
  final Map<ProductTopic, Completer<void>> _topicOpening = {};
  final Map<ProductTopic, StreamController<ProductTopicFrame>> _topicStreams =
      {};
  final Map<int, Completer<void>> _currentOpening = {};
  final Map<int, Completer<void>> _historyOpening = {};
  @override
  Future<CurrentReader> openCurrentReader(
    String threadId, {
    required int currentProtocolVersion,
    required ReadDemand demand,
  }) {
    final result = Completer<CurrentReader>();
    final index = currentOpens.length;
    currentOpens.add((threadId: threadId, result: result));
    _currentOpening.remove(index)?.complete();
    final factory = currentReaderFactory;
    if (factory == null) return result.future;
    try {
      result.complete(factory(threadId, index));
    } catch (error, stackTrace) {
      result.completeError(error, stackTrace);
    }
    return result.future;
  }

  Future<void> currentOpened(int index) => currentOpens.length > index
      ? Future.value()
      : (_currentOpening[index] ??= Completer<void>()).future;

  @override
  Future<HistoryReader> openHistoryReader(
    String threadId, {
    required int historyProtocolVersion,
  }) {
    final result = Completer<HistoryReader>();
    final index = historyOpens.length;
    historyOpens.add((threadId: threadId, result: result));
    _historyOpening.remove(index)?.complete();
    final factory = historyReaderFactory;
    if (factory == null) return result.future;
    try {
      result.complete(factory(threadId, index));
    } catch (error, stackTrace) {
      result.completeError(error, stackTrace);
    }
    return result.future;
  }

  Future<void> historyOpened(int index) => historyOpens.length > index
      ? Future.value()
      : (_historyOpening[index] ??= Completer<void>()).future;

  Future<void> productTopicOpened(ProductTopic topic) =>
      _topicStreams.containsKey(topic)
      ? Future.value()
      : (_topicOpening[topic] ??= Completer<void>()).future;

  @override
  Future<ProductTopicObservation> openProductTopic(
    ProductTopic topic, {
    required ClientResourceId resourceId,
  }) async {
    productTopics.add(topic);
    final stream = StreamController<ProductTopicFrame>();
    stream.onCancel = () {
      unawaited(stream.close());
    };
    _topicStreams[topic] = stream;
    final observation = await openTestProductTopic(
      lifecycleScope.child('topic-owner'),
      resourceId,
      stream,
    );
    productTopicOwners.add(observation.source);
    _topicOpening.remove(topic)?.complete();
    return observation;
  }

  void emitProductTopicFrame(ProductTopicFrame frame) {
    final topic = switch (frame) {
      ProductTopicBaselineFrame(:final topic) => topic,
      ProductTopicDataFrame(:final topic) => topic,
      ProductTopicLaggedFrame(:final topic) => topic,
      ProductTopicFailureFrame(:final topic) => topic,
    };
    _topicStreams[topic]?.add(frame);
  }

  Future<CloseReport> closeProductTopicStreams({
    required ClientCloseBudget budget,
  }) async {
    // The scope owns each actual topic source and its cleanup ACK. Awaiting a
    // second close() on a never-listened controller would never complete.
    final report = await lifecycleScope.close(budget: budget);
    if (report.complete) _topicStreams.clear();
    return report;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted transport capability: ${invocation.memberName}',
  );
}

class ConversationFixture {
  ConversationFixture({TestConversationTransport? transport})
    : transport = transport ?? TestConversationTransport() {
    this.transport.currentReaderFactory = (threadId, index) {
      final reader = TestCurrentReader(threadId: threadId);
      currentReaders[threadId] = reader;
      return reader;
    };
    this.transport.historyReaderFactory = (threadId, index) {
      final reader = TestHistoryReader(threadId: threadId);
      historyReaders[threadId] = reader;
      return reader;
    };
    client = AnyworkClient(
      transport: this.transport,
      scope: this.transport.lifecycleScope.child('client'),
      clientId: 'conversation-test',
    );
  }

  final TestConversationTransport transport;
  late final AnyworkClient client;
  final Map<String, TestCurrentReader> currentReaders = {};
  final Map<String, TestHistoryReader> historyReaders = {};
  ConversationRepository get repository => client.conversations;
  ConversationSession session([String id = 'thread']) => repository.session(id);
  TestCurrentReader currentReader([String id = 'thread']) =>
      currentReaders[id] ??
      (throw StateError('No Current reader opened for $id yet'));
  TestHistoryReader historyReader([String id = 'thread']) =>
      historyReaders[id] ??
      (throw StateError('No History reader opened for $id yet'));

  Future<TestCurrentReader> open({
    String threadId = 'thread',
    int index = 0,
    required ReadDemand demand,
  }) async {
    repository.setVisibleThread(threadId);
    await transport.currentOpened(index);
    final opened = await transport.currentOpens[index].result.future;
    if (opened is! TestCurrentReader) {
      throw StateError('Conversation fixture opened an unsupported reader');
    }
    final reader = opened;
    currentReaders[threadId] = reader;
    reader.onReadBody ??= (_, _) async => ContentWindow(
      offset: 0,
      bytes: const [],
      generation: 'empty',
      availableThrough: 0,
      sealed: true,
    );
    return reader;
  }

  Future<CloseReport> close({ClientCloseBudget? budget}) async {
    final closeBudget =
        budget ?? ClientCloseBudget(const Duration(seconds: 30));
    final report = await client.close(budget: closeBudget);
    final transportReport = await transport.closeProductTopicStreams(
      budget: closeBudget,
    );
    return CloseReport(
      unresolved: [...report.unresolved, ...transportReport.unresolved],
    );
  }
}
