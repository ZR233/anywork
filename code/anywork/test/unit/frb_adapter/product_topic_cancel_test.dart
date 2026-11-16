import 'dart:async';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/subscription.dart' as native;
import 'package:anywork/src/rust/api/studio/types/product_topic.dart' as wire;
import 'package:anywork/src/rust/api/studio/types/event.dart' as shutdown;
import 'package:anywork/src/rust/frb_generated.dart' show RustLib, RustLibApi;
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

final class _TopicApi implements RustLibApi {
  late Future<native.BridgeEventSubscription> Function() open;
  late _NativeProgress progress;
  int opens = 0;

  @override
  Future<native.BridgeEventSubscription>
  crateApiStudioSubscriptionProductTopicCreateProductTopicSubscription({
    required wire.BridgeProductTopic topic,
  }) {
    opens++;
    return open();
  }

  @override
  Future<native.BridgeEventSubscription>
  crateApiStudioSubscriptionShutdownSubscribeShutdownProgress() async =>
      progress;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected ${invocation.memberName}');
}

final class _NativeTopic extends Fake
    implements native.BridgeEventSubscription {
  final subscribed = Completer<void>();
  final failure = StateError('native cancellation failed');
  final events = StreamController<wire.BridgeProductTopicStreamEnvelope>();
  final calls = <String>[];
  bool failCancel = false;
  bool failAttach = false;
  bool failDartCancel = false;
  Completer<void>? cancelGate;
  int cancels = 0;
  int disposals = 0;
  int dartCancels = 0;

  @override
  Stream<wire.BridgeProductTopicStreamEnvelope> productTopicStream() {
    if (failAttach) throw StateError('stream attachment failed');
    subscribed.complete();
    return _RawStream(events.stream, () {
      calls.add('dart');
      dartCancels++;
      if (failDartCancel) throw failure;
    });
  }

  @override
  Future<void> cancel() async {
    calls.add('native');
    cancels++;
    if (failCancel) throw failure;
    await cancelGate?.future;
  }

  @override
  void dispose() {
    calls.add('dispose');
    disposals++;
  }
}

/// Only the original native Dart-listener boundary is replaceable. This allows
/// retrying that layer independently after native ACK/dispose already succeeded.
final class _RawStream<T> extends Stream<T> {
  _RawStream(this.source, this.beforeCancel);
  final Stream<T> source;
  final void Function() beforeCancel;
  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _RawSubscription(
    source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
    beforeCancel,
  );
}

final class _RawSubscription<T> implements StreamSubscription<T> {
  _RawSubscription(this.source, this.beforeCancel);
  final StreamSubscription<T> source;
  final void Function() beforeCancel;
  @override
  Future<void> cancel() async {
    beforeCancel();
    await source.cancel();
  }

  @override
  void onData(void Function(T)? handler) => source.onData(handler);
  @override
  void onError(Function? handler) => source.onError(handler);
  @override
  void onDone(void Function()? handler) => source.onDone(handler);
  @override
  void pause([Future<void>? resumeSignal]) => source.pause(resumeSignal);
  @override
  void resume() => source.resume();
  @override
  bool get isPaused => source.isPaused;
  @override
  Future<E> asFuture<E>([E? futureValue]) => source.asFuture(futureValue);
}

final class _NativeProgress extends Fake
    implements native.BridgeEventSubscription {
  final subscribed = Completer<void>();
  final events = StreamController<shutdown.BridgeShutdownProgress>();
  final failure = const StudioFailure(
    code: StudioFailureCode.internal,
    message: 'progress native cancellation failed',
    retryable: true,
    correlationId: 'progress-cancel-failure',
  );
  bool failCancel = false;
  int cancels = 0;
  int disposals = 0;
  @override
  Stream<shutdown.BridgeShutdownProgress> shutdownStream() {
    subscribed.complete();
    return events.stream;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    if (failCancel) throw failure;
  }

  @override
  void dispose() => disposals++;
}

final class _TopicLease implements ClientLease {
  _TopicLease(this.acquisition);
  final ClientAcquisition<ProductTopicObservation> acquisition;
  @override
  List<ClientResourceId> retirementResourceIds = const [];
  @override
  Future<void> release() {
    retirementResourceIds = [acquisition.resourceId];
    return acquisition.close();
  }
}

void main() {
  late ClientScope root;
  late ClientScope sdk;
  late FrbStudioTransport transport;
  late _TopicApi api;
  late _NativeTopic handle;
  _NativeProgress? progressHandle;
  ClientCloseBudget budget() => ClientCloseBudget(const Duration(seconds: 2));

  setUp(() {
    root = ClientScope(owner: 'test');
    sdk = root.child('sdk');
    final runtime = FrbRuntimeOwner(startupScope: root.child('startup'));
    runtime.debugOverrideInitialization(() async {}, runtimeOwnerPresent: true);
    transport = FrbStudioTransport(
      runtime: runtime,
      contentScope: root.child('content'),
      progressScope: root.child('progress'),
    );
    handle = _NativeTopic();
    progressHandle = null;
    api = _TopicApi()..open = (() async => handle);
    RustLib.initMock(api: api);
  });

  tearDown(() async {
    handle.failCancel = false;
    handle.failDartCancel = false;
    progressHandle?.failCancel = false;
    handle.cancelGate?.complete();
    await root.close(budget: budget());
    expect((await root.retryCleanup(budget: budget())).complete, isTrue);
    RustLib.dispose();
  });

  Future<ProductTopicObservation> openTopic() => sdk
      .open<ProductTopicObservation>(
        'direct-topic-proxy',
        (operation) => transport.openProductTopic(
          const UpdaterTopic(),
          resourceId: operation.resourceId,
        ),
        ownership: ClientOwnership.proxy,
      )
      .ready;

  test('listener cancellation is not a native ACK', () async {
    final port = await openTopic();
    final listener = port.frames.listen((_) {});
    await listener.cancel();
    expect(handle.cancels, 0);
    await port.close();
    expect(handle.calls, ['native', 'dispose', 'dart']);
  });

  test(
    'SDK proxy and actual owner join one failure and one retry per pass',
    () async {
      handle.failCancel = true;
      final acquisition = sdk.open<ProductTopicObservation>(
        'topic-consumer',
        (op) => transport.openProductTopic(
          const UpdaterTopic(),
          resourceId: op.resourceId,
        ),
        ownership: ClientOwnership.proxy,
        consume: (port, op) async {
          await for (final _ in port.frames) {
            if (op.closeRequested) break;
          }
        },
      );
      final port = await acquisition.ready;
      final startupAlias = transport.runtime.startupScope
          .open<ProductTopicObservation>(
            'startup-alias',
            (_) async => port,
            identity: port.resourceId,
            ownership: ClientOwnership.proxy,
          );
      await startupAlias.ready;
      final ui = root.child('ui');
      ui.acquireLease('topic-lease', () => _TopicLease(acquisition));
      await expectLater(acquisition.close(), throwsA(same(handle.failure)));
      await expectLater(port.close(), throwsA(same(handle.failure)));
      await expectLater(acquisition.close(), throwsA(same(handle.failure)));
      expect(handle.cancels, 1);
      expect(handle.disposals, 0);
      final sharedBudget = budget();
      final content = await transport.cancelDartSubscriptions(
        budget: sharedBudget,
      );
      expect(content.issues, isEmpty);
      expect(content.resources.unresolved, hasLength(1));
      final contentFailure = content.resources.unresolved.single;
      expect(contentFailure.resourceId, acquisition.resourceId);
      expect(contentFailure.reason, same(handle.failure));
      expect(
        contentFailure.stages,
        contains(
          isA<ClientResourceStage>()
              .having(
                (stage) => stage.owner,
                'startup alias owner',
                'startup-alias',
              )
              .having(
                (stage) => stage.error,
                'original alias failure',
                same(handle.failure),
              ),
        ),
      );
      final sdkReport = await sdk.close(budget: sharedBudget);
      final uiReport = await ui.close(budget: sharedBudget);
      final rootReport = await root.close(budget: sharedBudget);
      final report = CloseReport(
        unresolved: [
          ...content.resources.unresolved,
          ...sdkReport.unresolved,
          ...uiReport.unresolved,
          ...rootReport.unresolved,
        ],
      );
      expect(report.unresolved, hasLength(1));
      expect(report.unresolved.single.resourceId, acquisition.resourceId);
      expect(report.unresolved.single.reason, same(handle.failure));
      expect(
        report.unresolved.single.stages,
        containsAll([
          isA<ClientResourceStage>()
              .having(
                (stage) => stage.ownership,
                'actual ownership',
                ClientOwnership.owned,
              )
              .having(
                (stage) => stage.error,
                'original actual failure',
                same(handle.failure),
              )
              .having((stage) => stage.stackTrace, 'original stack', isNotNull),
          isA<ClientResourceStage>()
              .having(
                (stage) => stage.owner,
                'SDK proxy owner',
                'topic-consumer',
              )
              .having(
                (stage) => stage.error,
                'original proxy failure',
                same(handle.failure),
              ),
          isA<ClientResourceStage>()
              .having(
                (stage) => stage.phase,
                'lease release',
                ClientClosePhase.leaseRelease,
              )
              .having(
                (stage) => stage.error,
                'original lease failure',
                same(handle.failure),
              ),
        ]),
      );
      expect(
        handle.cancels,
        1,
        reason: 'merging stage reports cannot retry cleanup',
      );
      expect((await root.retryCleanup(budget: budget())).complete, isFalse);
      expect(
        handle.cancels,
        2,
        reason: 'aliases must not each retry native cancel',
      );
      handle.failCancel = false;
      expect((await root.retryCleanup(budget: budget())).complete, isTrue);
      expect(handle.cancels, 3);
      expect(handle.disposals, 1);
      expect(api.opens, 1);
    },
  );

  test('zero budget retains an in-flight native ACK', () async {
    handle.cancelGate = Completer<void>();
    final port = await openTopic();
    final report = await root.close(budget: ClientCloseBudget(Duration.zero));
    expect(report.complete, isFalse);
    expect(report.unresolved.single.resourceId, port.resourceId);
    expect(handle.disposals, 0);
    handle.cancelGate!.complete();
    handle.cancelGate = null;
    expect((await root.close(budget: budget())).complete, isTrue);
    expect(handle.cancels, 1);
    expect(handle.disposals, 1);
  });

  test(
    'late creation is owned and closed without attaching a consumer',
    () async {
      final entered = Completer<void>();
      final created = Completer<native.BridgeEventSubscription>();
      api.open = () {
        entered.complete();
        return created.future;
      };
      final opening = openTopic();
      await entered.future;
      final rejected = expectLater(
        opening,
        throwsA(isA<ClientResourceClosed>()),
      );
      expect(
        (await root.close(budget: ClientCloseBudget(Duration.zero))).complete,
        isFalse,
      );
      created.complete(handle);
      await rejected;
      expect((await root.close(budget: budget())).complete, isTrue);
      expect(handle.subscribed.isCompleted, isFalse);
      expect(handle.cancels, 1);
      expect(handle.disposals, 1);
    },
  );

  test(
    'an attach failure cannot lose the already-created raw handle',
    () async {
      handle.failAttach = true;
      await expectLater(openTopic(), throwsA(isA<StudioFailure>()));
      expect((await root.close(budget: budget())).complete, isTrue);
      expect(handle.cancels, 1);
      expect(handle.disposals, 1);
      expect(handle.dartCancels, 0);
    },
  );

  test('Dart cleanup retry does not repeat successful native layers', () async {
    handle.failDartCancel = true;
    final port = await openTopic();
    await expectLater(port.close(), throwsA(same(handle.failure)));
    await expectLater(port.close(), throwsA(same(handle.failure)));
    expect(handle.calls, ['native', 'dispose', 'dart']);
    handle.failDartCancel = false;
    await port.retryClose();
    expect(handle.calls, ['native', 'dispose', 'dart', 'dart']);
  });

  test(
    'content closure and listener cancellation leave progress to its scope',
    () async {
      final progress = api.progress = progressHandle = _NativeProgress();
      final listener = transport.subscribeShutdownProgress().listen((_) {});
      await progress.subscribed.future;
      final sharedBudget = budget();
      final content = await transport.cancelDartSubscriptions(
        budget: sharedBudget,
      );
      expect(content.resources.complete, isTrue);
      expect(content.issues, isEmpty);
      expect(progress.cancels, 0);
      await listener.cancel();
      expect(progress.cancels, 0);
      final result = await transport.closeShutdownProgress(
        budget: sharedBudget,
      );
      expect(result.resources.complete, isTrue);
      expect(result.issues, isEmpty);
      expect(progress.cancels, 1);
      expect(progress.disposals, 1);
    },
  );

  test(
    'progress retains typed native error and identity until root reports merge',
    () async {
      final progress = api.progress = progressHandle = _NativeProgress();
      progress.failCancel = true;
      final listener = transport.subscribeShutdownProgress().listen((_) {});
      await progress.subscribed.future;
      final sharedBudget = budget();
      final content = await transport.cancelDartSubscriptions(
        budget: sharedBudget,
      );
      expect(content.resources.complete, isTrue);
      expect(content.issues, isEmpty);
      expect(progress.cancels, 0);
      await listener.cancel();
      expect(progress.cancels, 0);
      final result = await transport.closeShutdownProgress(
        budget: sharedBudget,
      );
      expect(result.issues, isEmpty);
      expect(result.resources.unresolved, hasLength(1));
      final original = result.resources.unresolved.single;
      expect(original.resourceId, isNotNull);
      expect(original.reason, same(progress.failure));
      expect(
        original.stages,
        contains(
          isA<ClientResourceStage>()
              .having(
                (stage) => stage.ownership,
                'actual ownership',
                ClientOwnership.owned,
              )
              .having(
                (stage) => stage.error,
                'original typed failure',
                same(progress.failure),
              )
              .having((stage) => stage.stackTrace, 'original stack', isNotNull),
        ),
      );
      final rootReport = await root.close(budget: sharedBudget);
      final merged = CloseReport(
        unresolved: [
          ...content.resources.unresolved,
          ...result.resources.unresolved,
          ...rootReport.unresolved,
        ],
      );
      expect(merged.unresolved, hasLength(1));
      expect(merged.unresolved.single.resourceId, original.resourceId);
      expect(merged.unresolved.single.reason, same(progress.failure));
      expect(merged.unresolved.single.stages, containsAll(original.stages));
      expect(progress.cancels, 1);
      expect(progress.disposals, 0);
      progress.failCancel = false;
      expect((await root.retryCleanup(budget: budget())).complete, isTrue);
      expect(progress.cancels, 2);
      expect(progress.disposals, 1);
    },
  );
}
