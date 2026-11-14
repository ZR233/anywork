import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026);
final _update = StudioUpdateInfoView(
  version: '2.0.0',
  publishedAt: _now,
  notesUrl: 'https://example.test/releases/2',
);

UpdaterStateSnapshot _available(int revision) => UpdaterStateSnapshot(
  activity: AvailableUpdaterActivity(
    revision: revision,
    checkedAt: _now,
    update: _update,
  ),
);

final class _UpdateApi implements StudioUpdateApi {
  Completer<StudioUpdateOperation> opened = Completer();
  late UpdaterStore store;
  int currentCancels = 0;
  int automaticStarts = 0;
  int automaticCancels = 0;
  int checkCalls = 0;
  Completer<void>? checkReply;
  Object? automaticCancelFailure;
  int installCalls = 0;
  int? expectedRevision;
  String? version;

  @override
  Future<void> check() {
    checkCalls++;
    return checkReply?.future ?? Future.value();
  }

  @override
  Future<void> startAutomaticUpdate() async {
    automaticStarts++;
  }

  @override
  Future<void> stopAutomaticUpdate() async {
    automaticCancels++;
    if (automaticCancelFailure case final error?) throw error;
  }

  @override
  Future<void> cancelCurrentPreparation() async {
    currentCancels++;
  }

  @override
  Future<StudioUpdateOperation> startPreparation({
    required int expectedRevision,
    required String version,
  }) {
    installCalls++;
    this.expectedRevision = expectedRevision;
    this.version = version;
    return opened.future;
  }
}

final class _UpdateOperation implements StudioUpdateOperation {
  _UpdateOperation({
    this.cancelFailure,
    this.result = const ReadyStudioUpdatePreparation('2.0.0'),
  });
  final StudioUpdatePreparationResult result;
  final Completer<void> listened = Completer();
  final Completer<void> handoffRequested = Completer();
  final Completer<void> handoff = Completer();
  final Completer<void> disposed = Completer();
  final Object? cancelFailure;
  int disposeCalls = 0;
  int cancelCalls = 0;
  bool cancelled = false;

  @override
  Future<void> cancel() async {
    cancelCalls++;
    if (cancelFailure case final error?) throw error;
    cancelled = true;
    if (!handoff.isCompleted) handoff.complete();
  }

  @override
  Future<StudioUpdatePreparationResult> finishPreparation() async {
    if (!listened.isCompleted) listened.complete();
    if (!handoffRequested.isCompleted) handoffRequested.complete();
    await handoff.future;
    return cancelled ? const CancelledStudioUpdatePreparation() : result;
  }

  @override
  void dispose() {
    disposeCalls++;
    if (!disposed.isCompleted) disposed.complete();
  }
}

StudioUpdateClient _client(_UpdateApi api, UpdaterStore store) =>
    StudioUpdateClient(api: api..store = store, updater: store, enabled: true);

void main() {
  test(
    'Rust disabled capability prevents both automatic and manual checks',
    () async {
      final api = _UpdateApi();
      final store = UpdaterStore()
        ..apply(
          UpdaterStateSnapshot(
            activity: DisabledUpdaterActivity(revision: 7, updatedAt: _now),
          ),
        );
      final client = _client(api, store)..attach();
      await client.check();
      expect(api.automaticStarts, 0);
      expect(api.checkCalls, 0);
      expect((await client.close()).complete, isTrue);
    },
  );

  test('preparation receipt never backfills canonical state or waits for UI delivery', () async {
    final api = _UpdateApi();
    final store = UpdaterStore()..apply(_available(7));
    final client = _client(api, store);
    final install = client.install();
    final operation = _UpdateOperation();
    api.opened.complete(operation);
    await operation.handoffRequested.future;
    operation.handoff.complete();
    expect((await install).readyVersion, '2.0.0');
    expect(store.state.value?.activity, isA<AvailableUpdaterActivity>());
    expect(store.state.value?.revision, 7);
    expect((await client.close()).complete, isTrue);
  });

  test(
    'cancel current preparation never stops or restarts the scheduler',
    () async {
      final api = _UpdateApi();
      final store = UpdaterStore()..apply(_available(7));
      final client = _client(api, store)..attach();
      await client.cancelInstall();
      expect(api.currentCancels, 1);
      expect(api.automaticCancels, 0);
      store.apply(_available(8));
      expect(api.automaticStarts, 1);
      expect((await client.close()).complete, isTrue);
      expect(api.automaticCancels, 1);
    },
  );

  test('a confirmed pre-admission rejection can be retried without leaking an owner', () async {
    final api = _UpdateApi();
    final client = _client(api, UpdaterStore()..apply(_available(7)));
    final rejected = client.install();
    final failure = expectLater(
      rejected,
      throwsA(isA<StudioUpdatePreparationRejected>()),
    );
    api.opened.completeError(
      const StudioUpdatePreparationRejected('Update state changed'),
    );
    await failure;
    expect(client.unresolvedResources, isEmpty);
    api.opened = Completer();
    final retry = client.install();
    expect(api.installCalls, 2);
    final operation = _UpdateOperation();
    api.opened.complete(operation);
    await operation.listened.future;
    api.store.apply(
      UpdaterStateSnapshot(
        activity: ReadyUpdaterActivity(
          revision: 8,
          readyAt: _now,
          update: _update,
        ),
      ),
    );
    await operation.handoffRequested.future;
    operation.handoff.complete();
    expect((await retry).readyVersion, _update.version);
    expect((await client.close()).complete, isTrue);
  });
  test(
    'request feedback is immediate, repeated clicks share one preparation',
    () async {
      final api = _UpdateApi();
      final client = _client(api, UpdaterStore()..apply(_available(7)));
      final observed = <StudioUpdateRequestPhase>[];
      final observation = client.request.watch(
        (value) => observed.add(value.phase),
      );
      final first = client.install();
      expect(client.request.value.phase, StudioUpdateRequestPhase.preparing);
      expect(client.install(), same(first));
      expect(api.installCalls, 1);
      final operation = _UpdateOperation();
      api.opened.complete(operation);
      await operation.listened.future;
      api.store.apply(
        UpdaterStateSnapshot(
          activity: ReadyUpdaterActivity(
            revision: 8,
            readyAt: _now,
            update: _update,
          ),
        ),
      );
      await operation.handoffRequested.future;
      expect(
        client.request.value.pending,
        isTrue,
        reason: 'Ready alone is not a resource completion ACK',
      );
      expect(operation.disposeCalls, 0);
      operation.handoff.complete();
      expect((await first).readyVersion, _update.version);
      expect(observed, [
        StudioUpdateRequestPhase.preparing,
        StudioUpdateRequestPhase.ready,
      ]);
      observation.cancel();
      expect((await client.close()).complete, isTrue);
    },
  );

  test('cancel before the native handle arrives cancels its owner and clears restart intent', () async {
    final api = _UpdateApi();
    final client = _client(api, UpdaterStore()..apply(_available(7)));
    final install = client.install();
    final cancelled = client.cancelInstall();
    expect(client.request.value.phase, StudioUpdateRequestPhase.cancelling);
    final operation = _UpdateOperation();
    api.opened.complete(operation);
    await cancelled;
    expect((await install).readyVersion, isNull);
    expect(operation.cancelCalls, 1);
    expect(operation.disposeCalls, 1);
    expect(client.request.value.phase, StudioUpdateRequestPhase.cancelled);
    expect((await client.close()).complete, isTrue);
  });

  test(
    'cancel racing Ready cannot restart, even when the verified cache survives',
    () async {
      final api = _UpdateApi();
      final client = _client(api, UpdaterStore()..apply(_available(7)));
      final install = client.install();
      final operation = _UpdateOperation();
      api.opened.complete(operation);
      await operation.listened.future;
      api.store.apply(
        UpdaterStateSnapshot(
          activity: ReadyUpdaterActivity(
            revision: 8,
            readyAt: _now,
            update: _update,
          ),
        ),
      );
      await operation.handoffRequested.future;
      await client.cancelInstall();
      expect((await install).readyVersion, isNull);
      expect(client.state.activity, isA<ReadyUpdaterActivity>());
      expect(client.request.value.phase, StudioUpdateRequestPhase.cancelled);
      expect((await client.close()).complete, isTrue);
    },
  );

  test(
    'download failure ends preparation without an exit and releases resources',
    () async {
      final api = _UpdateApi();
      final client = _client(api, UpdaterStore()..apply(_available(7)));
      final install = client.install();
      final operation = _UpdateOperation(
        result: const FailedStudioUpdatePreparation(
          UpdaterErrorView(
            code: 'network',
            message: 'offline',
            retryable: true,
          ),
        ),
      );
      api.opened.complete(operation);
      await operation.listened.future;
      api.store.apply(
        UpdaterStateSnapshot(
          activity: InstallFailedUpdaterActivity(
            revision: 8,
            failedAt: _now,
            update: _update,
            error: const UpdaterErrorView(
              code: 'network',
              message: 'offline',
              retryable: true,
            ),
          ),
        ),
      );
      await operation.handoffRequested.future;
      operation.handoff.complete();
      expect((await install).readyVersion, isNull);
      expect(client.request.value.phase, StudioUpdateRequestPhase.failed);
      expect(client.request.value.error, 'offline');
      expect(client.state.activity, isA<InstallFailedUpdaterActivity>());
      expect((await client.close()).complete, isTrue);
    },
  );

  test('manual update joins an existing background download', () async {
    final api = _UpdateApi();
    final store = UpdaterStore()
      ..apply(
        UpdaterStateSnapshot(
          activity: DownloadingUpdaterActivity(
            revision: 7,
            updatedAt: _now,
            update: _update,
            downloaded: 1,
            total: 100,
          ),
        ),
      );
    final client = _client(api, store);
    final pending = client.install();
    expect(
      api.installCalls,
      1,
      reason: 'An ongoing background download must accept the restart intent',
    );
    final operation = _UpdateOperation();
    api.opened.complete(operation);
    await operation.listened.future;
    api.store.apply(
      UpdaterStateSnapshot(
        activity: ReadyUpdaterActivity(
          revision: 8,
          readyAt: _now,
          update: _update,
        ),
      ),
    );
    await operation.handoffRequested.future;
    operation.handoff.complete();
    expect((await pending).readyVersion, _update.version);
    expect((await client.close()).complete, isTrue);
  });

  test('close joins a coalesced check failure and joins its RPC', () async {
    final api = _UpdateApi()..checkReply = Completer();
    final client = _client(api, UpdaterStore());
    final check = client.check();
    expect(identical(client.check(), check), isTrue);
    expect(api.checkCalls, 1);
    final failure = expectLater(check, throwsStateError);
    var closeFinished = false;
    final closing = client.close().then((report) {
      closeFinished = true;
      return report;
    });
    expect(closeFinished, isFalse);
    api.checkReply!.completeError(StateError('check rejected'));
    await failure;
    expect(
      (await closing).complete,
      isTrue,
      reason:
          'a completed business failure leaves no native cleanup obligation',
    );
    expect(client.unresolvedResources, isEmpty);
    expect((await client.retryCleanup()).complete, isTrue);
    expect(api.checkCalls, 1, reason: 'cleanup must never replay the check');
  });

  test('a check past the close deadline retains its RPC until its real terminal reply', () async {
    final api = _UpdateApi()..checkReply = Completer();
    final client = _client(api, UpdaterStore());
    final check = client.check();
    final failure = expectLater(check, throwsStateError);
    final closing = client.close(deadline: DateTime.utc(2000));
    expect(
      identical(client.close(deadline: DateTime.utc(2099)), closing),
      isTrue,
    );
    final report = await closing;
    expect(report.complete, isFalse);
    expect(
      report.unresolved.any((entry) => entry.owner == 'update-rpc:check'),
      isTrue,
    );
    api.checkReply!.completeError(StateError('late check rejected'));
    await failure;
    expect((await client.retryCleanup()).complete, isTrue);
    expect(client.unresolvedResources, isEmpty);
    expect(api.checkCalls, 1);
  });

  test(
    'automatic startup belongs to the Client and waits for canonical readiness',
    () async {
      final api = _UpdateApi();
      final store = UpdaterStore();
      final client = _client(api, store);
      client.attach();
      expect(api.automaticStarts, 0);
      store.apply(_available(7));
      expect(api.automaticStarts, 1);
      final routeObserver = client.source.watch((_) {});
      routeObserver.cancel();
      store.apply(_available(8));
      client.attach();
      expect(api.automaticStarts, 1);
      expect((await client.close()).complete, isTrue);
      expect(api.automaticCancels, 1);
    },
  );

  test(
    'automatic cleanup failure retains its owner until a real cancel ACK',
    () async {
      final api = _UpdateApi()
        ..automaticCancelFailure = StateError('cancel failed');
      final store = UpdaterStore()..apply(_available(7));
      final client = _client(api, store);
      client.attach();
      expect((await client.close()).complete, isFalse);
      expect(api.automaticStarts, 1);
      expect(api.automaticCancels, 1);
      api.automaticCancelFailure = null;
      expect((await client.retryCleanup()).complete, isTrue);
      expect(
        api.automaticStarts,
        1,
        reason: 'retrying cleanup never repeats startup',
      );
      expect(api.automaticCancels, 2);
    },
  );

  test(
    'route observation ends without dropping the operation or its handoff ACK',
    () async {
      final api = _UpdateApi();
      final store = UpdaterStore()..apply(_available(7));
      final client = _client(api, store);
      final observer = client.source.watch((_) {});
      var complete = false;
      final result = client.install().then((value) {
        complete = true;
        return value;
      });
      expect(api.expectedRevision, 7);
      expect(api.version, '2.0.0');
      final operation = _UpdateOperation();
      api.opened.complete(operation);
      await operation.listened.future;
      observer.cancel();
      api.store.apply(
        UpdaterStateSnapshot(
          activity: ReadyUpdaterActivity(
            revision: 8,
            readyAt: _now,
            update: _update,
          ),
        ),
      );
      await operation.handoffRequested.future;
      expect(complete, isFalse);
      expect(operation.disposeCalls, 0);
      expect(store.state.value?.activity, isA<ReadyUpdaterActivity>());
      operation.handoff.complete();
      expect((await result).readyVersion, _update.version);
      expect(operation.disposeCalls, 1);
      expect((await client.close()).complete, isTrue);
    },
  );

  test('late install handle is cancelled by its original owner after close deadline', () async {
    final api = _UpdateApi();
    final store = UpdaterStore()..apply(_available(7));
    final client = _client(api, store);
    final install = client.install();
    final closing = client.close(deadline: DateTime.utc(2000));
    expect(
      identical(client.close(deadline: DateTime.utc(2099)), closing),
      isTrue,
    );
    expect((await closing).complete, isFalse);
    final operation = _UpdateOperation();
    api.opened.complete(operation);
    await operation.disposed.future;
    expect((await install).readyVersion, isNull);
    expect(operation.cancelCalls, 1);
    expect(operation.disposeCalls, 1);
  });

  test(
    'failed handoff keeps the strong handle until cleanup is confirmed',
    () async {
      final api = _UpdateApi();
      final store = UpdaterStore()..apply(_available(7));
      final client = _client(api, store);
      final install = client.install();
      final operation = _UpdateOperation(
        cancelFailure: StateError('native close failed'),
      );
      api.opened.complete(operation);
      await operation.listened.future;
      final failure = expectLater(install, throwsStateError);
      api.store.apply(
        UpdaterStateSnapshot(
          activity: ReadyUpdaterActivity(
            revision: 8,
            readyAt: _now,
            update: _update,
          ),
        ),
      );
      await operation.handoffRequested.future;
      operation.handoff.completeError(StateError('native handoff failed'));
      await failure;
      expect(operation.disposeCalls, 0);
      final report = await client.close();
      expect(report.complete, isFalse);
      expect(report.unresolved.single.owner, 'update:1');
      expect(operation.disposeCalls, 0);
    },
  );

  test(
    'unknown install reply is retained and never automatically replayed',
    () async {
      final api = _UpdateApi();
      final store = UpdaterStore()..apply(_available(7));
      final client = _client(api, store);
      final install = client.install();
      final failure = expectLater(install, throwsStateError);
      api.opened.completeError(StateError('reply lost'));
      await failure;
      await expectLater(client.install(), throwsStateError);
      expect(api.installCalls, 1);
      expect((await client.close()).complete, isFalse);
    },
  );
}
