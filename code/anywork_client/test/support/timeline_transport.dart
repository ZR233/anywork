import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/studio_client.dart';

ConversationItem timelineItem(
  int revision, {
  String id = 'item',
  String body = 'body',
  String threadId = 'thread',
  int ordinal = 0,
  bool saved = false,
  ConversationLifecycle lifecycle = ConversationLifecycle.streaming,
  int? totalBytes,
}) => ConversationItem(
  header: ConversationItemHeader(
    id: id,
    threadId: threadId,
    turnId: 'turn',
    ordinal: ordinal,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  revision: revision,
  descriptor: ConversationTextDescriptor(
    channel: ThreadTextChannel.finalAnswer,
    attachments: const [],
    lifecycle: lifecycle == ConversationLifecycle.terminal
        ? CompletedThreadContentView(DateTime.utc(2026))
        : const StreamingThreadContentView(),
  ),
  saved: saved,
  lifecycle: lifecycle,
  fields: [
    ConversationFieldPreview(
      field: const ThreadTextFieldView(),
      text: body,
      totalBytes: totalBytes ?? utf8.encode(body).length,
    ),
  ],
);
ConversationBaseline baseline(
  int version, {
  String subscriptionId = 'sub',
  List<ConversationItem>? items,
  String? before,
  bool hasOlder = false,
}) => ConversationBaseline(
  subscriptionId: subscriptionId,
  version: version,
  items: items ?? [timelineItem(version)],
  before: before,
  hasOlder: hasOlder,
);
ConversationPatch patch(
  int from,
  int to, {
  String subscriptionId = 'sub',
  List<ConversationChange> changes = const [],
}) => ConversationPatch(
  subscriptionId: subscriptionId,
  from: from,
  to: to,
  changes: changes,
  priority: ConversationPriority.coalesced,
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
  Future<ConversationPage> Function(String?, int?)? onPage;
  Future<ConversationDetailChunk> Function(String, ConversationDetailQuery)?
  onDetail;
  final List<({String? before, int? limit})> pageRequests = [];
  final List<({String itemId, ConversationDetailQuery query})> detailRequests =
      [];

  /// 同步查询注入：恰在 page/detail 返回受控 future 之前调用，回调里可以
  /// 同步退役/关闭 scope；每次请求各自持有独立 future，不复用同一 Completer。
  void Function()? onQuery;
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

  @override
  Future<void> acknowledge(int deliverySequence) async {
    await ackGate?.future;
    if (ackFailure case final failure?) throw failure;
    acknowledgements.add(deliverySequence);
    _acked.remove(deliverySequence)?.complete();
  }

  @override
  Future<ConversationPage> page({String? before, int? limit}) {
    pageRequests.add((before: before, limit: limit));
    onQuery?.call();
    return onPage?.call(before, limit) ??
        Future.value(
          const ConversationPage(items: [], before: null, hasOlder: false),
        );
  }

  @override
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  }) {
    detailRequests.add((itemId: itemId, query: query));
    onQuery?.call();
    return onDetail?.call(itemId, query) ??
        Future.error(UnsupportedError('Unscripted detail'));
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
  @override
  Future<ConversationFeed> openConversationFeed(String threadId) {
    final result = Completer<ConversationFeed>();
    final index = opens.length;
    opens.add((threadId: threadId, result: result));
    _opening.remove(index)?.complete();
    return result.future;
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
  ConversationRepository get repository => client.conversations;
  ConversationSession session([String id = 'thread']) => repository.session(id);
  Future<TestConversationFeed> open({
    String threadId = 'thread',
    ConversationBaseline? initial,
    int index = 0,
  }) async {
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
