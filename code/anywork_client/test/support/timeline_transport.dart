import 'dart:async';
import 'dart:convert';

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

TimelineItem fixtureItem({required String id, required PayloadData payload}) =>
    TimelineItem(
      id: id,
      contentItemId: id,
      source: ReceiptChatSource(receiptId: id),
      kind: TimelineItemKind.status,
      atomKind: ChatAtomKind.receipt,
      delivery: ChatDeliveryKind.independent,
      outcome: ChatTerminalOutcome.completed,
      admissionClosed: true,
      contents: const [],
      payload: payload,
    );

TimelineItem chatMessage({
  String id = 'item',
  String body = 'body',
  String? turnId = 'turn',
  String channel = 'final',
}) {
  final inline = utf8.encode(body);
  return TimelineItem(
    id: id,
    contentItemId: id,
    source: ReceiptChatSource(receiptId: id),
    kind: TimelineItemKind.text,
    atomKind: ChatAtomKind.text,
    delivery: ChatDeliveryKind.independent,
    outcome: ChatTerminalOutcome.completed,
    admissionClosed: true,
    contents: const [],
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
            {'key': 'body', 'byteLength': inline.length, 'inline': inline},
          ],
        }),
      ),
    ),
  );
}

CurrentProjection emptyCurrent() => CurrentProjection(
  sourceEffectSeq: 0,
  logicalStatus: ThreadStatusView.idle,
  executionPresent: false,
  sources: const [],
  items: const [],
  atoms: const [],
  previews: const [],
  collections: const [],
);

ChatBatch chatSet({
  List<TimelineItem>? messages,
  String? before,
  CurrentProjection? current,
}) => ChatBatch(
  placement: ChatPlacement.set,
  entries: (messages ?? [chatMessage()]).map(ItemChatEntry.new).toList(),
  before: before,
  current: current ?? emptyCurrent(),
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
  Future<CurrentCollectionPage> Function(
    CurrentCollectionRef reference,
    String? continuation,
    ReadDemand demand,
  )?
  onCurrent;
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
  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) =>
      onCurrent?.call(reference, continuation, demand) ??
      Future.error(UnsupportedError('Unscripted pageCurrent'));

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
  final List<ProductTopic> productTopics = [];
  final Map<ProductTopic, Completer<void>> _topicOpening = {};
  final Map<ProductTopic, StreamController<ProductTopicFrame>> _topicStreams =
      {};
  final Map<int, Completer<void>> _opening = {};
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

  Future<void> productTopicOpened(ProductTopic topic) =>
      _topicStreams.containsKey(topic)
      ? Future.value()
      : (_topicOpening[topic] ??= Completer<void>()).future;

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) {
    productTopics.add(topic);
    final stream = StreamController<ProductTopicFrame>();
    stream.onCancel = () {
      unawaited(stream.close());
    };
    _topicStreams[topic] = stream;
    _topicOpening.remove(topic)?.complete();
    return stream.stream;
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

  Future<void> closeProductTopicStreams() async {
    for (final stream in _topicStreams.values) {
      await stream.close();
    }
    _topicStreams.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted transport capability: ${invocation.memberName}',
  );
}

class ConversationFixture {
  ConversationFixture({TestConversationTransport? transport})
    : transport = transport ?? TestConversationTransport() {
    client = AnyworkClient(
      transport: this.transport,
      clientId: 'conversation-test',
    );
  }
  final TestConversationTransport transport;
  late final AnyworkClient client;
  final Map<String, TestCompletionConsumer> consumers = {};
  ConversationRepository get repository => client.conversations;
  ConversationSession session([String id = 'thread']) => repository.session(id);
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
    await transport.opened(index);
    final feed = TestConversationFeed(
      threadId: threadId,
      subscriptionId: subscriptionId,
    );
    transport.opens[index].result.complete(feed);
    await feed.deliver(ConversationChatEvent(batch: initial ?? chatSet()));
    return feed;
  }

  Future<CloseReport> close({DateTime? deadline}) async {
    final report = await client.close(deadline: deadline);
    await transport.closeProductTopicStreams();
    return report;
  }
}

final class TestCompletionConsumer implements ConversationBatchConsumer {
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
