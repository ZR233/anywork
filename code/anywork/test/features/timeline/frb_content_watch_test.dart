import 'dart:async';
import 'dart:typed_data';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/handlers/chat.dart' as wire;
import 'package:anywork/src/rust/api/studio/types/chat.dart' as types;
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _ref = ContentRef(
  databaseId: 'database',
  target: ItemPayloadTarget(itemId: 'item'),
);
const _range = ContentRange(offset: 0, maxBytes: 32);

void main() {
  test('transport cancellation only wakes; original watch join retries after cancellation and pause claims no successor', () async {
    final native = _Native();
    final feed = FrbConversationFeed(native);
    final watch = feed.reader.watchContent(reference: _ref, range: _range);
    final received = Completer<void>();
    late StreamSubscription<ContentWindow> subscription;
    subscription = watch.windows.listen((window) {
      subscription.pause();
      expect(window.bytes, [65]);
      received.complete();
    });
    await native.nextRequested(1);
    native.next.single.complete(
      types.BridgeContentWindow(
        offset: BigInt.zero,
        bytes: Uint8List.fromList([65]),
        generation: 'g',
        availableThrough: BigInt.from(200),
        sealed: false,
      ),
    );
    await received.future;
    await Future<void>.delayed(Duration.zero);
    expect(native.next.length, 1);
    subscription.resume();
    await native.nextRequested(2);
    await subscription.cancel();
    expect(
      native.closeWatchIds,
      isEmpty,
      reason: 'Stream cancellation is not the native join owner',
    );
    native.watchFailure = StateError('native join failed');
    await expectLater(watch.close(), throwsA(isA<StudioFailure>()));
    expect(native.closeWatchIds, ['original']);
    native.watchFailure = null;
    await watch.close();
    expect(native.closeWatchIds, ['original', 'original']);
    await feed.close();
    expect(native.disposes, 1);
  });

  test(
    'late open cannot grant delivery and close joins that original ID',
    () async {
      final native = _Native()..openGate = Completer<String>();
      final feed = FrbConversationFeed(native);
      final watch = feed.reader.watchContent(reference: _ref, range: _range);
      final deliveries = <ContentWindow>[];
      final subscription = watch.windows.listen(deliveries.add);
      await native.opened.future;
      await subscription.cancel();
      final joined = watch.close();
      expect(native.closeWatchIds, isEmpty);
      native.openGate!.complete('late-original');
      await joined;
      expect(native.closeWatchIds, ['late-original']);
      expect(native.next, isEmpty);
      expect(deliveries, isEmpty);
      await feed.close();
    },
  );

  test('EOF keeps facade cleanup responsibility; one failed side cannot skip other sides or dispose', () async {
    final native = _Native();
    final feed = FrbConversationFeed(native);
    final watch = feed.reader.watchContent(reference: _ref, range: _range);
    final done = Completer<void>();
    watch.windows.listen((_) {}, onDone: done.complete);
    await native.nextRequested(1);
    native.next.single.complete(null);
    await done.future;
    expect(native.closeWatchIds, isEmpty);
    native.watchFailure = StateError('watch join failed');
    native.feedFailure = StateError('feed close failed');
    await expectLater(feed.close(), throwsA(isA<StudioFailure>()));
    expect(native.feedCloses, 1);
    expect(native.closeWatchIds, ['original']);
    expect(native.disposes, 0);
    native.watchFailure = null;
    native.feedFailure = null;
    await feed.close();
    expect(native.feedCloses, 2);
    expect(native.closeWatchIds, ['original', 'original']);
    expect(native.disposes, 1);
  });
}

final class _Native extends Fake implements wire.BridgeConversationFeed {
  final opened = Completer<void>();
  Completer<String>? openGate;
  final next = <Completer<types.BridgeContentWindow?>>[];
  final requested = <int, Completer<void>>{};
  final closeWatchIds = <String>[];
  Object? watchFailure, feedFailure;
  int feedCloses = 0, disposes = 0;
  Future<void> nextRequested(int count) => next.length >= count
      ? Future.value()
      : (requested[count] ??= Completer<void>()).future;
  @override
  String threadId() => 'thread';
  @override
  String subscriptionId() => 'subscription';
  @override
  Future<String> openContentWatch({
    required types.BridgeContentRef reference,
    required types.BridgeContentRange range,
  }) async {
    expect(range.maxBytes, 32);
    opened.complete();
    return await (openGate?.future ?? Future.value('original'));
  }

  @override
  Future<types.BridgeContentWindow?> nextContentWindow({
    required String watchId,
  }) {
    final completion = Completer<types.BridgeContentWindow?>();
    next.add(completion);
    requested.remove(next.length)?.complete();
    return completion.future;
  }

  @override
  void requestCloseContentWatch({required String watchId}) {
    for (final completion in next) {
      if (!completion.isCompleted) completion.complete(null);
    }
  }

  @override
  Future<void> closeContentWatch({required String watchId}) async {
    closeWatchIds.add(watchId);
    if (watchFailure case final error?) throw error;
  }

  @override
  void requestClose() {}
  @override
  Future<void> close() async {
    feedCloses++;
    if (feedFailure case final error?) throw error;
  }

  @override
  void dispose() {
    disposes++;
  }
}
