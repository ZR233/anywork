import 'dart:async';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/subscription.dart' as native;
import 'package:anywork/src/rust/api/studio/types/product_topic.dart' as wire;
import 'package:anywork/src/rust/frb_generated.dart' show RustLib, RustLibApi;
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

final class _TopicApi implements RustLibApi {
  _TopicApi(this.handle);

  final _NativeTopic handle;
  int opens = 0;

  @override
  Future<native.BridgeEventSubscription>
  crateApiStudioSubscriptionProductTopicCreateProductTopicSubscription({
    required wire.BridgeProductTopic topic,
  }) async {
    opens++;
    return handle;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected ${invocation.memberName}');
}

final class _NativeTopic extends Fake
    implements native.BridgeEventSubscription {
  final subscribed = Completer<void>();
  final failure = StateError('native cancellation failed');
  final events = StreamController<wire.BridgeProductTopicStreamEnvelope>();
  int cancels = 0;
  int disposals = 0;

  @override
  Stream<wire.BridgeProductTopicStreamEnvelope> productTopicStream() {
    subscribed.complete();
    return events.stream;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    throw failure;
  }

  @override
  void dispose() => disposals++;
}

void main() {
  test('native cancel failure reaches the client and retains the original topic', () async {
    final native = _NativeTopic();
    final api = _TopicApi(native);
    RustLib.initMock(api: api);
    FrbStudioTransport.debugOverrideInitialization(() async {});
    final transport = FrbStudioTransport();
    final client = AnyworkClient(transport: transport, clientId: 'test');

    final lease = client.channels.acquireTopic(const UpdaterTopic());
    await native.subscribed.future;
    await expectLater(
      lease.release(),
      throwsA(
        isA<BridgeTopicCleanupBlocked>().having(
          (error) => error.cause,
          'native error',
          same(native.failure),
        ),
      ),
    );
    expect(native.cancels, 1);
    expect(native.disposals, 0);

    client.channels.acquireTopic(const UpdaterTopic());
    client.channels.retryTopic(const UpdaterTopic());
    final report = await client.channels.retryCleanup();
    expect(report.complete, isFalse);
    expect(client.channels.unresolvedResources, isNotEmpty);
    expect(api.opens, 1, reason: 'A failed native owner blocks a replacement');
    expect(
      native.cancels,
      1,
      reason: 'Stream cancellation is not a native retry',
    );
    expect(native.disposals, 0);

    final issues = await transport.cancelDartSubscriptions(budgetMs: 1000);
    expect(issues, isNotEmpty);
    // The fake intentionally remains retained after the failed native ACK.
    // This test has its own isolate and must not reset the live-owner guard or
    // dispose the mocked library while that owner is still unresolved.
  });
}
