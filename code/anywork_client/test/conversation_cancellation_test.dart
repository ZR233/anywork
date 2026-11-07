import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 20, maxBytes: 65536);

/// A real Dart cancellation callback. Native close and Dart subscription cancel
/// are independent obligations even when a controller delegates cancel to close.
final class _CoupledFeed extends TestConversationFeed {
  _CoupledFeed({this.cancelFailure}) {
    controller = StreamController<ConversationFrame>(
      sync: true,
      onListen: () => listening.complete(),
      onCancel: () {
        cancelCalls++;
        final failure = cancelFailure;
        return failure == null ? close() : Future<void>.error(failure);
      },
    );
  }

  final Object? cancelFailure;
  late final StreamController<ConversationFrame> controller;
  final listening = Completer<void>();
  final nativeCloseEntered = Completer<void>();
  int cancelCalls = 0;

  Future<void> dispose() => controller.close();

  @override
  Stream<ConversationFrame> get events => controller.stream;

  @override
  void requestClose() {
    requestCloseCalls++;
    if (!requestCloseStarted.isCompleted) requestCloseStarted.complete();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    if (!nativeCloseEntered.isCompleted) nativeCloseEntered.complete();
    await closeGate?.future;
    if (closeFailure case final failure?) throw failure;
    if (!closeCompleted.isCompleted) closeCompleted.complete();
  }
}

Future<ConversationFixture> _start(_CoupledFeed feed) async {
  final fixture = ConversationFixture();
  fixture.attach('thread', demand: _demand);
  fixture.repository.setVisibleThread('thread');
  await fixture.transport.opened(0);
  fixture.transport.opens[0].result.complete(feed);
  await feed.listening.future;
  return fixture;
}

void main() {
  test('native close precedes a real controller cancellation delegated back to close', () async {
    final feed = _CoupledFeed();
    final fixture = await _start(feed);
    addTearDown(feed.dispose);
    expect((await fixture.close()).complete, isTrue);
    expect(feed.nativeCloseEntered.isCompleted, isTrue);
    expect(feed.cancelCalls, 1);
    expect(feed.closeCalls, 2);
  });

  test('close deadline retains delegated native join and releases only after actual cancellation', () async {
    final feed = _CoupledFeed()..closeGate = Completer<void>();
    final fixture = await _start(feed);
    addTearDown(feed.dispose);
    final report = await fixture.close(deadline: DateTime.now());
    expect(report.complete, isFalse);
    await feed.nativeCloseEntered.future;
    expect(feed.cancelCalls, 0);
    feed.closeGate!.complete();
    expect((await fixture.client.retryCleanup()).complete, isTrue);
    expect(feed.cancelCalls, 1);
  });

  test('independent Dart cancellation failure remains unresolved after successful native close', () async {
    final failure = StateError('controller failed to cancel');
    final feed = _CoupledFeed(cancelFailure: failure);
    final fixture = await _start(feed);
    addTearDown(feed.dispose);
    final first = await fixture.close();
    expect(first.complete, isFalse);
    expect(
      first.unresolved.any((entry) => identical(entry.reason, failure)),
      isTrue,
    );
    expect(feed.closeCompleted.isCompleted, isTrue);
    expect(feed.cancelCalls, 1);
    final retried = await fixture.client.retryCleanup();
    expect(retried.complete, isFalse);
    expect(
      feed.cancelCalls,
      1,
      reason: 'The original failed cancellation still owns its result',
    );
  });
}
