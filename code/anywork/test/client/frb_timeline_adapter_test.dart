import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/handlers/chat.dart' as wire;
import 'package:anywork/src/rust/api/studio/types/chat.dart' as dto;
import 'package:anywork/src/rust/api/studio/types/error.dart' as err;
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_fixtures.dart';

void main() {
  for (final placement in dto.BridgeChatPlacement.values) {
    test(
      'FRB $placement maps inline/deferred bytes and opaque before without ACK',
      () async {
        final native = _GeneratedFeed();
        final feed = FrbConversationFeed(native);
        final iterator = StreamIterator(feed.events);
        final bytes = Uint8List.fromList(utf8.encode('中文 🐱 opaque JSON'));
        native.send(
          dto.BridgeConversationEvent.chat(
            batch: dto.BridgeChatBatch(
              placement: placement,
              before: 'opaque:中文:before',
              messages: [
                dto.BridgeChatMessage(
                  id: 'inline',
                  payload: dto.BridgePayloadData.inline(bytes: bytes),
                ),
                dto.BridgeChatMessage(
                  id: 'deferred',
                  payload: dto.BridgePayloadData.deferred_(
                    reference: _reference,
                    byteLength: BigInt.from(400000),
                  ),
                ),
              ],
            ),
          ),
        );
        expect(await iterator.moveNext(), isTrue);
        final frame = iterator.current;
        final batch = (frame.event as ConversationChatEvent).batch;
        expect(frame.threadId, 'thread-A');
        expect(frame.subscriptionId, 'sub-1');
        expect(batch.placement, ChatPlacement.values[placement.index]);
        expect(batch.before, 'opaque:中文:before');
        expect(
          batch.current,
          isNull,
          reason: 'None must not become an empty projection',
        );
        expect(batch.messages.map((message) => message.id), [
          'inline',
          'deferred',
        ]);
        expect((batch.messages.first.payload as InlinePayload).bytes, bytes);
        final deferred = batch.messages.last.payload as DeferredPayload;
        expect(deferred.byteLength, 400000);
        expect(deferred.reference.databaseId, 'database');
        expect(
          (deferred.reference.target as ItemPayloadTarget).itemId,
          'deferred',
        );
        expect(
          native.acks,
          isEmpty,
          reason: 'adapter never ACKs on behalf of a consumer',
        );
        await feed.acknowledge(frame.deliverySequence);
        expect(native.acks, [BigInt.one]);
        await feed.close();
        await iterator.cancel();
      },
    );
  }

  test('original facade reader maps Prepend demand, manifest, and byte windows independently of events', () async {
    final native = _GeneratedFeed();
    final feed = FrbConversationFeed(native);
    final reader = feed.reader;
    expect(feed.reader, same(reader));
    final batch = await reader.loadOlder(
      before: 'opaque:before',
      demand: chatDemand,
    );
    expect(native.olderRequests.single, (
      'opaque:before',
      const dto.BridgeReadDemand(maxItems: 20, maxBytes: 65536),
    ));
    expect(batch.placement, ChatPlacement.prepend);
    expect(batch.messages.single.id, 'older');
    expect(batch.before, 'next:older');
    final manifest = await reader.listContents(
      itemId: 'deferred',
      continuation: 'manifest-next',
      demand: chatDemand,
    );
    expect(native.manifestRequests.single, ('deferred', 'manifest-next'));
    expect(manifest.continuation, 'more');
    expect(manifest.entries.single.key, 'body');
    expect(manifest.entries.single.payload, [123, 125]);
    final window = await reader.readContent(
      reference: _domainReference,
      range: const ContentRange(offset: 2, maxBytes: 16),
    );
    expect(native.contentRequests.single.$1, _reference);
    expect(native.contentRequests.single.$2.offset, BigInt.from(2));
    expect(native.contentRequests.single.$2.maxBytes, 16);
    expect(window.offset, 2);
    expect(window.bytes, utf8.encode('中文'));
    expect(window.availableThrough, 8);
    expect(window.generation, 'generation-1');
    expect(window.sealed, isTrue);
    expect(
      native.eventConsumers,
      0,
      reason: 'query I/O does not acquire the event consumer',
    );
    expect(native.acks, isEmpty);
    await feed.close();
    expect(native.disposals, 1);
  });

  test(
    'typed query failures retain classification and correlation identity',
    () async {
      final native = _GeneratedFeed()..queryFailure = _failure;
      final feed = FrbConversationFeed(native);
      await expectLater(
        feed.reader.loadOlder(before: 'before', demand: chatDemand),
        throwsA(_typedFailure),
      );
      expect(native.acks, isEmpty);
      await feed.close();
    },
  );

  test('terminal sequence zero and reused sequence pass through without adapter ACK', () async {
    for (final sequence in [0, 3]) {
      final native = _GeneratedFeed();
      final feed = FrbConversationFeed(native);
      final iterator = StreamIterator(feed.events);
      native.send(
        const dto.BridgeConversationEvent.closed(),
        sequence: sequence,
      );
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.deliverySequence, sequence);
      expect(iterator.current.event, isA<ConversationClosedEvent>());
      expect(native.acks, isEmpty);
      await feed.close();
      await iterator.cancel();
    }
  });

  test('facade close joins every content watch despite feed and one watch failure, then retries retained owner', () async {
    final native = _GeneratedFeed()
      ..closeFailure = _failure
      ..failedWatch = 'watch-1';
    final feed = FrbConversationFeed(native);
    final errors = <Object>[];
    final first = feed.reader
        .watchContent(
          reference: _domainReference,
          range: const ContentRange(offset: 0, maxBytes: 16),
        )
        .windows
        .listen((_) {}, onError: errors.add);
    final second = feed.reader
        .watchContent(
          reference: _domainReference,
          range: const ContentRange(offset: 16, maxBytes: 16),
        )
        .windows
        .listen((_) {}, onError: errors.add);
    await native.twoWatchesWaiting.future;
    feed.requestClose();
    expect(
      native.closeCalls,
      0,
      reason: 'requestClose is cancellation, not native join',
    );
    await expectLater(feed.close(), throwsA(_typedFailure));
    expect(native.closeCalls, 1);
    expect(native.watchCloseCalls, containsAll(['watch-1', 'watch-2']));
    expect(native.watchRequests, containsAll(['watch-1', 'watch-2']));
    expect(
      native.disposals,
      0,
      reason: 'failed close retains the native facade',
    );
    native.closeFailure = null;
    native.failedWatch = null;
    await feed.close();
    expect(native.closeCalls, 2);
    expect(native.watchCloseCalls.where((id) => id == 'watch-1'), hasLength(2));
    expect(native.watchCloseCalls.where((id) => id == 'watch-2'), hasLength(1));
    expect(native.disposals, 1);
    expect(native.acks, isEmpty);
    await first.cancel();
    await second.cancel();
    expect(errors, isEmpty);
  });
}

const _failure = err.BridgeError(
  code: err.BridgeErrorCode.storage,
  message: 'read/close failed',
  retryable: true,
  correlationId: 'chat-native-failure',
);
Matcher get _typedFailure => isA<StudioFailure>()
    .having((failure) => failure.code, 'code', StudioFailureCode.storage)
    .having((failure) => failure.retryable, 'retryable', isTrue)
    .having(
      (failure) => failure.correlationId,
      'correlationId',
      'chat-native-failure',
    );
const _reference = dto.BridgeContentRef(
  databaseId: 'database',
  target: dto.BridgeContentTarget.itemPayload(itemId: 'deferred'),
);
const _domainReference = ContentRef(
  databaseId: 'database',
  target: ItemPayloadTarget(itemId: 'deferred'),
);

// Only the generated/native seam is stubbed. All mapping, cancellation, retained
// failure responsibility and retries above execute the production adapter.
final class _GeneratedFeed implements wire.BridgeConversationFeed {
  final _frames = StreamController<dto.BridgeConversationFrame>();
  final acks = <BigInt>[];
  final olderRequests = <(String, dto.BridgeReadDemand)>[];
  final manifestRequests = <(String, String?)>[];
  final contentRequests = <(dto.BridgeContentRef, dto.BridgeContentRange)>[];
  final watchCloseCalls = <String>[];
  final watchRequests = <String>[];
  final windows = <String, Completer<dto.BridgeContentWindow?>>{};
  final twoWatchesWaiting = Completer<void>();
  Object? queryFailure;
  Object? closeFailure;
  String? failedWatch;
  int closeCalls = 0;
  int disposals = 0;
  int eventConsumers = 0;
  int _sequence = 0;
  @override
  String threadId() => 'thread-A';
  @override
  String subscriptionId() => 'sub-1';
  @override
  Stream<dto.BridgeConversationFrame> events() {
    eventConsumers++;
    return _frames.stream;
  }

  void send(dto.BridgeConversationEvent event, {int? sequence}) => _frames.add(
    dto.BridgeConversationFrame(
      threadId: 'thread-A',
      subscriptionId: 'sub-1',
      deliverySequence: BigInt.from(sequence ?? ++_sequence),
      event: event,
    ),
  );
  @override
  void acknowledge({
    required String subscriptionId,
    required BigInt deliverySequence,
  }) => acks.add(deliverySequence);
  @override
  Future<dto.BridgeChatBatch> loadOlder({
    required String before,
    required dto.BridgeReadDemand demand,
  }) async {
    olderRequests.add((before, demand));
    if (queryFailure case final failure?) throw failure;
    return dto.BridgeChatBatch(
      placement: dto.BridgeChatPlacement.prepend,
      messages: [
        dto.BridgeChatMessage(
          id: 'older',
          payload: dto.BridgePayloadData.inline(
            bytes: Uint8List.fromList([123, 125]),
          ),
        ),
      ],
      before: 'next:older',
    );
  }

  @override
  Future<dto.BridgeContentManifestPage> listContents({
    required String itemId,
    String? continuation,
    required dto.BridgeReadDemand demand,
  }) async {
    manifestRequests.add((itemId, continuation));
    return dto.BridgeContentManifestPage(
      entries: [
        dto.BridgeContentManifestEntry(
          key: 'body',
          payload: Uint8List.fromList([123, 125]),
          reference: _reference,
        ),
      ],
      continuation: 'more',
    );
  }

  @override
  Future<dto.BridgeContentWindow> readContent({
    required dto.BridgeContentRef reference,
    required dto.BridgeContentRange range,
  }) async {
    contentRequests.add((reference, range));
    return dto.BridgeContentWindow(
      offset: BigInt.from(2),
      bytes: Uint8List.fromList(utf8.encode('中文')),
      generation: 'generation-1',
      availableThrough: BigInt.from(8),
      sealed: true,
    );
  }

  @override
  Future<String> openContentWatch({
    required dto.BridgeContentRef reference,
    required dto.BridgeContentRange range,
  }) async {
    final id = 'watch-${windows.length + 1}';
    windows[id] = Completer<dto.BridgeContentWindow?>();
    return id;
  }

  @override
  Future<dto.BridgeContentWindow?> nextContentWindow({
    required String watchId,
  }) {
    if (windows.length == 2 && !twoWatchesWaiting.isCompleted) {
      twoWatchesWaiting.complete();
    }
    return windows[watchId]!.future;
  }

  @override
  void requestCloseContentWatch({required String watchId}) {
    watchRequests.add(watchId);
    final window = windows[watchId]!;
    if (!window.isCompleted) window.complete(null);
  }

  @override
  Future<void> closeContentWatch({required String watchId}) async {
    watchCloseCalls.add(watchId);
    if (watchId == failedWatch) throw _failure;
  }

  @override
  void requestClose() {}
  @override
  Future<void> close() async {
    closeCalls++;
    if (closeFailure case final failure?) throw failure;
  }

  @override
  void dispose() {
    disposals++;
    unawaited(_frames.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
