import 'dart:async';

import 'package:anywork/src/app/studio_host_lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repeated exit joins the first native deadline and all custom cleanup owners', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final arming = Completer<void>();
    final armed = Completer<int>();
    var beginCalls = 0;
    messenger.setMockMethodCallHandler(StudioHostLifecycle.channel, (
      call,
    ) async {
      if (call.method == 'beginExit') {
        beginCalls++;
        arming.complete();
        return armed.future;
      }
      return null;
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(StudioHostLifecycle.channel, null),
    );
    final custom = Completer<void>();
    final client = Completer<CloseReport>();
    final clientEntered = Completer<DateTime>();
    var closes = 0;
    final coordinator = StudioExitCoordinator(
      RecordingDemoTransport(),
      (_) {},
      shutdownOverride: () => custom.future,
      closeClient: (deadline) {
        closes++;
        clientEntered.complete(deadline);
        return client.future;
      },
    );
    final first = coordinator.cleanupOnly();
    await arming.future;
    expect(coordinator.cleanupOnly(), same(first));
    armed.complete(30000);
    final deadline = await clientEntered.future;
    expect(deadline.isAfter(DateTime.now()), isTrue);
    expect(
      deadline.difference(DateTime.now()) <= const Duration(seconds: 28),
      isTrue,
    );
    var finished = false;
    unawaited(
      first.then((_) {
        finished = true;
      }),
    );
    custom.complete();
    await Future<void>.value();
    expect(
      finished,
      isFalse,
      reason: 'Custom cleanup cannot bypass the Client owner',
    );
    client.complete(CloseReport());
    expect((await first).isClean, isTrue);
    expect(coordinator.cleanupOnly(), same(first));
    expect(beginCalls, 1);
    expect(closes, 1);
  });
}
