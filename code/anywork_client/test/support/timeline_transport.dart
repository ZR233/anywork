import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/studio_client.dart';

ConversationItem timelineItem(
  int appendSeq, {
  String id = 'item',
  String body = 'body',
  String threadId = 'thread',
  int? totalBytes,
}) => ConversationItem(
  header: ConversationItemHeader(
    id: id,
    threadId: threadId,
    turnId: 'turn',
    appendSeq: appendSeq,
  ),
  descriptor: ConversationTextDescriptor(
    channel: ThreadTextChannel.finalAnswer,
    attachments: const [],
    outcome: ConversationContentCompleted(
      CompletedThreadContentView(DateTime.utc(2026)),
    ),
  ),
  source: const ConversationContentSource(),
  fields: [
    ConversationFieldPreview(
      field: const ThreadTextFieldView(),
      text: body,
      totalBytes: totalBytes ?? utf8.encode(body).length,
    ),
  ],
);
ConversationBaseline baseline(
  int appendSeq, {
  String subscriptionId = 'sub',
  String timelineEpoch = 'epoch',
  List<ConversationItem>? items,
  ConversationQueryCursor? before,
  bool hasOlder = false,
}) => ConversationBaseline(
  subscriptionId: subscriptionId,
  timelineEpoch: timelineEpoch,
  completedCursor: ConversationCompletionCursor(
    timelineEpoch: timelineEpoch,
    appendSeq: appendSeq,
  ),
  items: items ?? [timelineItem(appendSeq)],
  before: before,
  hasOlder: hasOlder,
);

/// A scripted external source, never an alternate reducer. It allows malformed
/// envelopes for rejection tests. Normal producers wait for acknowledgement.
class TestConversationFeed implements ConversationFeed {
  TestConversationFeed({this.threadId = 'thread', this.subscriptionId = 'sub'});
  @override
  final String threadId;
  @override
  final String subscriptionId;
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
    await closeGate?.future;
    if (closeFailure case final failure?) throw failure;
    if (!closeCompleted.isCompleted) closeCompleted.complete();
  }
}

class TestConversationTransport implements StudioTransport {
  final List<({String threadId, Completer<ConversationFeed> result})> opens =
      [];
  final Map<int, Completer<void>> _opening = {};
  final List<ConversationCompletionCursor?> resumes = [];
  Future<ConversationPage> Function(String, ConversationQueryCursor?, int?)?
  onPage;
  Future<ConversationDetailChunk> Function(
    String,
    String,
    ConversationDetailQuery,
  )?
  onDetail;
  final List<TestHistoryReader> readers = [];
  Future<ConversationHistoryReader> Function(String)? onOpenReader;
  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    ConversationCompletionCursor? resumeAfter,
  }) {
    resumes.add(resumeAfter);
    final result = Completer<ConversationFeed>();
    final index = opens.length;
    opens.add((threadId: threadId, result: result));
    _opening.remove(index)?.complete();
    return result.future;
  }

  @override
  Future<ConversationHistoryReader> openHistoryReader(String threadId) {
    final custom = onOpenReader;
    if (custom != null) return custom(threadId);
    final reader = TestHistoryReader(this, threadId);
    readers.add(reader);
    return Future.value(reader);
  }

  Future<void> opened(int index) => opens.length > index
      ? Future.value()
      : (_opening[index] ??= Completer<void>()).future;
  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) =>
      const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted transport capability: ${invocation.memberName}',
  );
}

final class TestHistoryReader implements ConversationHistoryReader {
  TestHistoryReader(
    this.transport,
    this.threadId, {
    this.timelineEpoch = 'epoch',
  });
  final TestConversationTransport transport;
  @override
  final String threadId;
  @override
  final String timelineEpoch;
  int closeCalls = 0;
  bool requested = false;
  Completer<void>? closeGate;
  Object? closeFailure;
  @override
  Future<ConversationPage> page({
    ConversationQueryCursor? before,
    int? limit,
  }) =>
      transport.onPage?.call(threadId, before, limit) ??
      Future.error(UnsupportedError('Unscripted page'));
  @override
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  }) =>
      transport.onDetail?.call(threadId, itemId, query) ??
      Future.error(UnsupportedError('Unscripted detail'));
  @override
  void requestClose() {
    requested = true;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    await closeGate?.future;
    if (closeFailure case final failure?) throw failure;
  }
}

class ConversationFixture {
  ConversationFixture({
    ResourceBudget? budget,
    TestConversationTransport? transport,
  }) : transport = transport ?? TestConversationTransport() {
    client = AnyworkClient(
      transport: this.transport,
      clientId: 'conversation-test',
      budget: budget,
    );
  }
  final TestConversationTransport transport;
  late final AnyworkClient client;
  final Map<String, TestCompletionConsumer> consumers = {};
  ConversationRepository get repository => client.conversations;
  ConversationSession session([String id = 'thread']) => repository.session(id);
  TestCompletionConsumer attach(String id) => consumers.putIfAbsent(id, () {
    final consumer = TestCompletionConsumer();
    session(id).content.attachConsumer(consumer);
    return consumer;
  });
  Future<TestConversationFeed> open({
    String threadId = 'thread',
    ConversationBaseline? initial,
    int index = 0,
  }) async {
    attach(threadId);
    repository.setVisibleThread(threadId);
    await transport.opened(index);
    final feed = TestConversationFeed(
      threadId: threadId,
      subscriptionId: initial?.subscriptionId ?? 'sub',
    );
    transport.opens[index].result.complete(feed);
    await feed.deliver(
      ConversationBaselineEvent(baseline: initial ?? baseline(1)),
    );
    return feed;
  }

  Future<CloseReport> close({DateTime? deadline}) =>
      client.close(deadline: deadline);
}

final class TestCompletionConsumer implements ConversationCompletionConsumer {
  final List<ConversationContentFrame> frames = [];
  final Map<int, Completer<void>> _waiters = {};
  Future<void> waitForCount(int count) => frames.length >= count
      ? Future.value()
      : (_waiters[count] ??= Completer<void>()).future;
  @override
  Future<void> accept(ConversationContentFrame frame) async {
    frames.add(frame);
    _waiters.remove(frames.length)?.complete();
  }
}
