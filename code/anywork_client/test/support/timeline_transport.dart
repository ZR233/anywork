import 'dart:async';

import 'product_topic_owner.dart';

import 'dart:convert';

import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';

import 'directory_feed.dart';

ChatAtom fixtureMember(String id) => ChatAtom(
  id: id,
  completionItemId: id,
  source: ReceiptChatSource(receiptId: id),
  sourceOrder: null,
  kind: ChatAtomKind.receipt,
  delivery: ChatDeliveryKind.independent,
  lifecycle: const TerminalChatAtom(
    started: null,
    ended: null,
    outcome: ChatTerminalOutcome.completed,
  ),
  contents: const [],
);

CompletedEntry completedFixture(String id, {int seq = 1, ChatAtom? atom}) =>
    CompletedEntry(
      recordId: id,
      completionSeq: seq,
      atom: atom ?? fixtureMember(id),
    );

CompletedEntry fixtureItem({
  required String id,
  required PayloadData payload,
  int seq = 2,
}) => completedFixture(
  id,
  seq: seq,
  atom: ChatAtom(
    id: id,
    completionItemId: id,
    source: ReceiptChatSource(receiptId: id),
    sourceOrder: null,
    kind: ChatAtomKind.receipt,
    delivery: ChatDeliveryKind.independent,
    lifecycle: const TerminalChatAtom(
      started: null,
      ended: null,
      outcome: ChatTerminalOutcome.completed,
    ),
    contents: const [],
    payload: payload,
  ),
);

CompletedEntry chatMessage({
  String id = 'item',
  String body = 'body',
  String? turnId = 'turn',
  String channel = 'final',
  int seq = 1,
}) => fixtureItem(
  id: id,
  seq: seq,
  payload: InlinePayload(
    bytes: utf8.encode(
      jsonEncode({
        'contract': 'anywork.chat/1',
        'type': 'text',
        if (turnId != null) 'turnId': turnId,
        'data': {
          'channel': channel,
          'attachments': <Object?>[],
          'outcome': {
            'kind': 'completed',
            'data': {'completedAt': 0},
          },
        },
        'bodies': [
          {
            'key': 'body',
            'byteLength': utf8.encode(body).length,
            'inline': utf8.encode(body),
          },
        ],
      }),
    ),
  ),
);

ChatBatch chatSet({List<CompletedEntry>? messages, String? before}) =>
    ChatBatch(
      placement: ChatPlacement.set,
      entries: messages ?? [chatMessage()],
      before: before,
      throughSeq: messages == null || messages.isEmpty
          ? 1
          : messages.last.completionSeq,
    );

/// A scripted external source, never an alternate reducer. It allows malformed
/// envelopes for rejection tests. Normal producers wait for acknowledgement.
class TestConversationFeed implements ConversationFeed {
  TestConversationFeed({
    this.threadId = 'thread',
    this.subscriptionId = 'sub',
    TestConversationReader? reader,
  }) : reader = reader ?? TestConversationReader(threadId: threadId);
  @override
  final String threadId;
  @override
  final String subscriptionId;
  @override
  final TestConversationReader reader;
  final StreamController<ConversationFrame> _events = StreamController(
    sync: true,
  );
  final List<int> acknowledgements = [];
  final Map<int, Completer<void>> _acked = {};
  final Map<int, Completer<void>> _ackStarted = {};
  int _sequence = 0;
  bool _requested = false;
  final requestCloseStarted = Completer<void>();
  final closeStarted = Completer<void>();
  final closeCompleted = Completer<void>();
  Completer<void>? closeGate;
  Object? closeFailure;
  Object? ackFailure;
  Completer<void>? ackGate;
  int closeCalls = 0;
  int requestCloseCalls = 0;
  int eventConsumers = 0;
  @override
  Stream<ConversationFrame> get events {
    if (++eventConsumers != 1) throw StateError('A feed permits one consumer');
    return _events.stream;
  }

  int send(
    ConversationEvent event, {
    int? sequence,
    String? frameThread,
    String? frameSubscription,
  }) {
    final terminal =
        event is ConversationClosedEvent || event is ConversationFailureEvent;
    final number = sequence ?? (terminal ? _sequence : ++_sequence);
    if (_requested) return number;
    _events.add(
      ConversationFrame(
        threadId: frameThread ?? threadId,
        subscriptionId: frameSubscription ?? subscriptionId,
        deliverySequence: number,
        event: event,
      ),
    );
    return number;
  }

  Future<void> deliver(ConversationEvent event) async {
    if (_requested) throw StateError('Cannot deliver to a closed feed');
    if (event is ConversationClosedEvent || event is ConversationFailureEvent) {
      send(event);
      return;
    }
    final number = _sequence + 1;
    final ack = acknowledged(number);
    send(event);
    await ack;
  }

  Future<void> acknowledged(int sequence) {
    if (acknowledgements.contains(sequence)) return Future.value();
    return (_acked[sequence] ??= Completer<void>()).future;
  }

  Future<void> ackStarted(int sequence) =>
      (_ackStarted[sequence] ??= Completer<void>()).future;

  @override
  Future<void> acknowledge(int deliverySequence) async {
    final started = _ackStarted.putIfAbsent(
      deliverySequence,
      Completer<void>.new,
    );
    if (!started.isCompleted) started.complete();
    await ackGate?.future;
    if (ackFailure case final failure?) throw failure;
    acknowledgements.add(deliverySequence);
    _acked.remove(deliverySequence)?.complete();
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    reader.requestClose();
    if (_requested) return;
    _requested = true;
    if (!requestCloseStarted.isCompleted) requestCloseStarted.complete();
    unawaited(_events.close());
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    if (!closeStarted.isCompleted) closeStarted.complete();
    Object? feedError;
    try {
      await closeGate?.future;
      if (closeFailure case final failure?) throw failure;
    } catch (error) {
      feedError = error;
    }
    Object? readerError;
    try {
      await reader.close();
    } catch (error) {
      readerError = error;
    }
    if (feedError == null && readerError == null) {
      if (!closeCompleted.isCompleted) closeCompleted.complete();
    }
    if (feedError != null) throw feedError;
    if (readerError != null) throw readerError;
  }
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

ThreadWorkspace emptyCurrentWorkspace(String threadId) => ThreadWorkspace(
  thread: StudioThread(
    id: threadId,
    workspaceId: 'workspace',
    title: 'Thread',
    mode: ThreadModeId.simple,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    updatedAt: DateTime.utc(2026),
    workspacePath: '/workspace',
  ),
  revision: 1,
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
  businessRefs: const ThreadBusinessRefs(plan: null, interactions: null),
);

CurrentView currentViewForWorkspace(
  ThreadWorkspace workspace, {
  String ownerId = 'owner',
  CurrentProjection? projection,
}) => CurrentView(
  revision: CurrentRevision(ownerId: ownerId, revision: workspace.revision),
  state: ThreadSnapshotFrame(
    workspace: workspace,
    completedHistoryVersion: completedHistoryVersion,
    schemaVersion: threadSchemaVersion,
  ),
  projection: projection ?? emptyCurrentProjection(workspace.thread.status),
);

Object testCurrentEvent({
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
  ThreadResyncRequiredFrame() => _CurrentFixtureFailure(
    ConversationContinuityError(
      'lagged current metadata: dropped ${frame.dropped}',
    ),
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

class TestConversationReader implements ConversationReader {
  TestConversationReader({this.threadId = 'thread'});
  @override
  final String threadId;
  Future<ChatBatch> Function(String before, ReadDemand demand)? onOlder;
  Future<ContentManifestPage> Function(
    String itemId,
    String? continuation,
    ReadDemand demand,
  )?
  onManifest;
  Future<ContentWindow> Function(ContentRef reference, ContentRange range)?
  onContent;
  Stream<ContentWindow> Function(ContentRef reference, ContentRange range)?
  onWatch;
  ConversationContentWatch Function(ContentRef reference, ContentRange range)?
  onWatchHandle;
  int closeCalls = 0;
  int requestCloseCalls = 0;
  bool requested = false;
  Completer<void>? closeGate;
  Object? closeFailure;

  @override
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  }) =>
      onOlder?.call(before, demand) ??
      Future.error(UnsupportedError('Unscripted loadOlder'));

  @override
  Future<ContentManifestPage> listContents({
    required String itemId,
    String? continuation,
    required ReadDemand demand,
  }) =>
      onManifest?.call(itemId, continuation, demand) ??
      Future.error(UnsupportedError('Unscripted listContents'));

  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) =>
      onContent?.call(reference, range) ??
      Future.error(UnsupportedError('Unscripted readContent'));

  @override
  ConversationContentWatch watchContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    final injected = onWatchHandle;
    if (injected != null) return injected(reference, range);
    final callback = onWatch;
    if (callback == null) {
      throw UnsupportedError('Unscripted watchContent');
    }
    return TestContentWatch(source: callback(reference, range));
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    requested = true;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    await closeGate?.future;
    if (closeFailure case final failure?) throw failure;
  }
}

final class TestHistoryReader implements HistoryReader {
  TestHistoryReader({
    this.threadId = 'thread',
    this.protocolVersion = historyProtocolVersion,
  });
  @override
  final String threadId;
  final String readerId = 'history-reader';
  final int protocolVersion;
  int closeCalls = 0;
  int requestCloseCalls = 0;
  bool requested = false;
  Completer<void>? closeGate;
  Object? closeFailure;
  Future<HistoryCut> Function()? onCapture;
  Future<HistoryTimelinePage> Function(
    HistoryCut? cut,
    String? cursor,
    HistoryDemand demand,
  )?
  onTimeline;
  Future<HistoryTimelinePage> Function(
    HistoryCut? cut,
    String? cursor,
    HistoryDemand demand,
  )?
  onTurns;
  Future<HistoryGroupPage> Function(
    String groupId,
    HistoryCut? cut,
    String? cursor,
    HistoryDemand demand,
  )?
  onGroup;
  Future<HistoryEventsPage> Function(
    HistoryEventsQuery query,
    HistoryCut? cut,
    String? cursor,
    HistoryDemand demand,
  )?
  onEvents;
  Future<HistoryEventDetail> Function(String eventId, HistoryDemand demand)?
  onEvent;
  Future<HistoryBodyPage> Function(
    String eventId,
    String? cursor,
    HistoryDemand demand,
  )?
  onBodies;
  Future<HistoryBodyWindow> Function(
    HistoryEventBodyRef reference,
    int offset,
    int maxBytes,
  )?
  onBody;
  Future<HistoryAccounting?> Function(HistoryCut? cut)? onAccounting;
  Future<HistoryTimelinePage> Function(
    HistoryCut? cut,
    String? cursor,
    HistoryDemand demand,
  )?
  onCosts;
  Future<HistoryCut> Function(HistoryCut after)? onChanged;

  @override
  OpenHistory get metadata =>
      OpenHistory(readerId: readerId, historyProtocolVersion: protocolVersion);
  @override
  Future<HistoryCut> capture() =>
      onCapture?.call() ??
      Future.error(UnsupportedError('Unscripted history capture'));
  @override
  Future<HistoryTimelinePage> timelinePage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) =>
      onTimeline?.call(cut, cursor, demand) ??
      Future.error(UnsupportedError('Unscripted history timeline'));
  @override
  Future<HistoryGroupPage> groupPage({
    required String groupId,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) =>
      onGroup?.call(groupId, cut, cursor, demand) ??
      Future.error(UnsupportedError('Unscripted history group'));
  @override
  Future<HistoryTimelinePage> turnsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) =>
      onTurns?.call(cut, cursor, demand) ??
      Future.error(UnsupportedError('Unscripted history turns'));
  @override
  Future<HistoryEventsPage> eventsPage({
    required HistoryEventsQuery query,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) =>
      onEvents?.call(query, cut, cursor, demand) ??
      Future.error(UnsupportedError('Unscripted history events'));
  @override
  Future<HistoryEventDetail> readEvent({
    required String eventId,
    required HistoryDemand demand,
  }) =>
      onEvent?.call(eventId, demand) ??
      Future.error(UnsupportedError('Unscripted history event'));
  @override
  Future<HistoryBodyPage> listBodies({
    required String eventId,
    String? cursor,
    required HistoryDemand demand,
  }) =>
      onBodies?.call(eventId, cursor, demand) ??
      Future.error(UnsupportedError('Unscripted history bodies'));
  @override
  Future<HistoryBodyWindow> readBody({
    required HistoryEventBodyRef reference,
    required int offset,
    required int maxBytes,
  }) =>
      onBody?.call(reference, offset, maxBytes) ??
      Future.error(UnsupportedError('Unscripted history body'));
  @override
  Future<HistoryAccounting?> accounting({HistoryCut? cut}) =>
      onAccounting?.call(cut) ??
      Future.error(UnsupportedError('Unscripted history accounting'));
  @override
  Future<HistoryTimelinePage> costsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) =>
      onCosts?.call(cut, cursor, demand) ??
      Future.error(UnsupportedError('Unscripted history costs'));
  @override
  Future<HistoryCut> waitChanged(HistoryCut after) =>
      onChanged?.call(after) ??
      Future.error(UnsupportedError('Unscripted history change watch'));
  @override
  void requestClose() {
    requestCloseCalls++;
    requested = true;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    await closeGate?.future;
    if (closeFailure case final failure?) throw failure;
  }
}

/// Scripted transport watch handle. Cancelling [windows] only stops local
/// delivery and requests cancellation; [close] joins and may be retried.
class TestContentWatch implements ConversationContentWatch {
  TestContentWatch({Stream<ContentWindow>? source})
    : _source = source ?? const Stream.empty();
  final Stream<ContentWindow> _source;
  StreamController<ContentWindow>? _output;
  StreamSubscription<ContentWindow>? _subscription;
  Future<void>? _stopping;
  bool _requested = false;
  int closeCalls = 0;
  int requestCloseCalls = 0;
  Completer<void>? closeGate;
  Object? closeFailure;

  @override
  Stream<ContentWindow> get windows {
    return (_output ??= StreamController<ContentWindow>(
      onListen: _listen,
      onPause: () => _subscription?.pause(),
      onResume: () => _subscription?.resume(),
      onCancel: () {
        requestClose();
      },
    )).stream;
  }

  void _listen() {
    final output = _output;
    if (output == null || output.isClosed) return;
    if (_requested) {
      unawaited(output.close());
      return;
    }
    _subscription ??= _source.listen(
      output.add,
      onError: output.addError,
      onDone: () {
        if (!output.isClosed) unawaited(output.close());
      },
    );
  }

  Future<void> _stopDelivery() {
    return _stopping ??= Future<void>.sync(() async {
      final subscription = _subscription;
      _subscription = null;
      if (subscription != null) await subscription.cancel();
    });
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    if (_requested) return;
    _requested = true;
    final work = _stopDelivery();
    unawaited(work.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    Object? joinError;
    try {
      await closeGate?.future;
      if (closeFailure case final failure?) throw failure;
    } catch (error) {
      joinError = error;
    }
    Object? cancelError;
    try {
      await _stopDelivery();
    } catch (error) {
      cancelError = error;
    }
    if (_output?.isClosed == false) {
      try {
        await _output!.close();
      } catch (error) {
        cancelError ??= error;
      }
    }
    if (joinError != null) throw joinError;
    if (cancelError != null) throw cancelError;
  }
}

class TestConversationTransport extends StudioTransport
    with DirectoryFeedFixture {
  final List<
    ({
      String threadId,
      ChatScope scope,
      ReadDemand demand,
      Completer<ConversationFeed> result,
    })
  >
  opens = [];
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
  final Map<int, Completer<void>> _opening = {};
  final Map<int, Completer<void>> _currentOpening = {};
  final Map<int, Completer<void>> _historyOpening = {};
  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    required ChatScope scope,
    required ReadDemand demand,
  }) {
    final result = Completer<ConversationFeed>();
    final index = opens.length;
    opens.add((
      threadId: threadId,
      scope: scope,
      demand: demand,
      result: result,
    ));
    _opening.remove(index)?.complete();
    return result.future;
  }

  Future<void> opened(int index) => opens.length > index
      ? Future.value()
      : (_opening[index] ??= Completer<void>()).future;

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
  final Map<String, TestCompletionConsumer> consumers = {};

  /// Latest auto-wired state feed per thread; state delivery goes through it.
  /// The transport call is synchronous, so the entry exists right after
  /// `setVisibleThread` recorded the open.
  final Map<String, TestCurrentReader> currentReaders = {};
  final Map<String, TestHistoryReader> historyReaders = {};
  ConversationRepository get repository => client.conversations;
  ConversationSession session([String id = 'thread']) => repository.session(id);
  TestCurrentReader currentReader([String id = 'thread']) =>
      currentReaders[id] ??
      (throw StateError('No state feed opened for $id yet'));
  TestHistoryReader historyReader([String id = 'thread']) =>
      historyReaders[id] ??
      (throw StateError('No history reader opened for $id yet'));
  TestCompletionConsumer attach(String id, {required ReadDemand demand}) =>
      consumers.putIfAbsent(id, () {
        final consumer = TestCompletionConsumer();
        session(id).content.attachConsumer(consumer, demand: demand);
        return consumer;
      });
  Future<TestConversationFeed> open({
    String threadId = 'thread',
    ChatBatch? initial,
    String subscriptionId = 'sub',
    int index = 0,
    required ReadDemand demand,
  }) async {
    attach(threadId, demand: demand);
    repository.setVisibleThread(threadId);
    await Future.wait([
      transport.opened(index),
      transport.currentOpened(index),
    ]);
    final feed = TestConversationFeed(
      threadId: threadId,
      subscriptionId: subscriptionId,
    );
    transport.opens[index].result.complete(feed);
    await feed.deliver(ConversationChatEvent(batch: initial ?? chatSet()));
    return feed;
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

final class TestCompletionConsumer implements ConversationBatchConsumer {
  final List<ActivitySnapshot> activities = [];
  @override
  Future<void> applyActivity(ActivitySnapshot snapshot) async {
    activities.add(snapshot);
  }

  final List<ChatBatch> batches = [];
  final Map<int, Completer<void>> _waiters = {};
  Future<void> waitForCount(int count) => batches.length >= count
      ? Future.value()
      : (_waiters[count] ??= Completer<void>()).future;
  @override
  Future<void> applyBatch(ChatBatch batch) async {
    batches.add(batch);
    _waiters.remove(batches.length)?.complete();
  }
}
