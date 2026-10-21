import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026);
final _update = StudioUpdateInfoView(
  version: '2.0.0',
  publishedAt: _now,
  notesUrl: 'https://example.test/releases/2',
);

UpdaterStateSnapshot _available(int revision) => AvailableUpdaterStateSnapshot(
  revision: revision,
  checkedAt: _now,
  update: _update,
);

final class _UpdateApi implements StudioUpdateApi {
  Completer<StudioUpdateOperation> opened = Completer();
  UpdaterStateSnapshot snapshot = _available(7);
  int automaticStarts = 0;
  int automaticCancels = 0;
  int checkCalls = 0;
  Completer<UpdaterStateSnapshot>? checkReply;
  Object? automaticCancelFailure;
  int installCalls = 0;
  int? expectedRevision;
  String? version;

  @override
  Future<UpdaterStateSnapshot> read() async => snapshot;
  @override
  Future<UpdaterStateSnapshot> check() {
    checkCalls++;
    return checkReply?.future ?? Future.value(snapshot);
  }

  @override
  Future<void> startAutomaticUpdate() async {
    automaticStarts++;
  }

  @override
  Future<void> cancelAutomaticUpdate() async {
    automaticCancels++;
    if (automaticCancelFailure case final error?) throw error;
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
  _UpdateOperation({this.cancelFailure}) {
    frames = StreamController(onListen: () => listened.complete());
  }
  late final StreamController<UpdaterStateSnapshot> frames;
  final Completer<void> listened = Completer();
  final Completer<void> handoffRequested = Completer();
  final Completer<void> handoff = Completer();
  final Completer<void> disposed = Completer();
  final Object? cancelFailure;
  int disposeCalls = 0;
  int cancelCalls = 0;

  @override
  Stream<UpdaterStateSnapshot> get events => frames.stream;
  @override
  Future<void> cancel() async {
    cancelCalls++;
    if (cancelFailure case final error?) throw error;
    if (!frames.isClosed) {
      if (frames.hasListener) {
        await frames.close();
      } else {
        // No native progress observer was opened for a late install handle.
        unawaited(frames.close());
      }
    }
    if (!handoff.isCompleted) handoff.complete();
  }

  @override
  Future<void> finishPreparation() {
    if (!handoffRequested.isCompleted) handoffRequested.complete();
    return handoff.future;
  }

  @override
  void dispose() {
    disposeCalls++;
    if (!disposed.isCompleted) disposed.complete();
  }
}

StudioUpdateClient _client(
  _UpdateApi api,
  UpdaterStore store, {
  ResourceBudget? budget,
}) =>
    StudioUpdateClient(api: api, updater: store, enabled: true, budget: budget);

void main() {
  test('a confirmed pre-admission rejection can be retried without leaking an owner', () async {
    final api = _UpdateApi();
    final budget = ResourceBudget();
    final client = _client(
      api,
      UpdaterStore()..apply(_available(7)),
      budget: budget,
    );
    final rejected = client.install();
    final failure = expectLater(
      rejected,
      throwsA(isA<StudioUpdatePreparationRejected>()),
    );
    api.opened.completeError(
      const StudioUpdatePreparationRejected('Update state changed'),
    );
    await failure;
    expect(budget.usage, isEmpty);
    expect(client.unresolvedResources, isEmpty);
    api.opened = Completer();
    final retry = client.install();
    expect(api.installCalls, 2);
    final operation = _UpdateOperation();
    api.opened.complete(operation);
    await operation.listened.future;
    operation.frames.add(
      ReadyUpdaterStateSnapshot(revision: 8, readyAt: _now, update: _update),
    );
    await operation.frames.close();
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
      operation.frames.add(
        ReadyUpdaterStateSnapshot(revision: 8, readyAt: _now, update: _update),
      );
      await operation.frames.close();
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
      operation.frames.add(
        ReadyUpdaterStateSnapshot(revision: 8, readyAt: _now, update: _update),
      );
      await operation.frames.close();
      await operation.handoffRequested.future;
      await client.cancelInstall();
      expect((await install).readyVersion, isNull);
      expect(client.state, isA<ReadyUpdaterStateSnapshot>());
      expect(client.request.value.phase, StudioUpdateRequestPhase.cancelled);
      expect((await client.close()).complete, isTrue);
    },
  );

  test(
    'download failure ends preparation without an exit and releases resources',
    () async {
      final api = _UpdateApi();
      final budget = ResourceBudget();
      final client = _client(
        api,
        UpdaterStore()..apply(_available(7)),
        budget: budget,
      );
      final install = client.install();
      final operation = _UpdateOperation();
      api.opened.complete(operation);
      await operation.listened.future;
      operation.frames.add(
        InstallFailedUpdaterStateSnapshot(
          revision: 8,
          failedAt: _now,
          update: _update,
          error: const UpdaterErrorView(
            code: 'network',
            message: 'offline',
            retryable: true,
          ),
        ),
      );
      await operation.frames.close();
      await operation.handoffRequested.future;
      operation.handoff.complete();
      expect((await install).readyVersion, isNull);
      expect(client.request.value.phase, StudioUpdateRequestPhase.failed);
      expect(client.state, isA<InstallFailedUpdaterStateSnapshot>());
      expect(budget.usage, isEmpty);
      expect((await client.close()).complete, isTrue);
    },
  );

  test('manual update joins an existing background download', () async {
    final api = _UpdateApi();
    final store = UpdaterStore()
      ..apply(
        DownloadingUpdaterStateSnapshot(
          revision: 7,
          updatedAt: _now,
          update: _update,
          downloaded: 1,
          total: 100,
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
    operation.frames.add(
      ReadyUpdaterStateSnapshot(revision: 8, readyAt: _now, update: _update),
    );
    await operation.frames.close();
    await operation.handoffRequested.future;
    operation.handoff.complete();
    expect((await pending).readyVersion, _update.version);
    expect((await client.close()).complete, isTrue);
  });

  test(
    'close joins a coalesced check failure and releases its RPC budget',
    () async {
      final api = _UpdateApi()..checkReply = Completer();
      final budget = ResourceBudget();
      final client = _client(api, UpdaterStore(), budget: budget);
      final check = client.check();
      expect(identical(client.check(), check), isTrue);
      expect(api.checkCalls, 1);
      expect(budget.used(ResourceKind.pendingOperation), 1);
      final failure = expectLater(check, throwsStateError);
      var closeFinished = false;
      final closing = client.close().then((report) {
        closeFinished = true;
        return report;
      });
      expect(closeFinished, isFalse);
      expect(budget.used(ResourceKind.pendingOperation), 1);
      api.checkReply!.completeError(StateError('check rejected'));
      await failure;
      expect(
        (await closing).complete,
        isTrue,
        reason:
            'a completed business failure leaves no native cleanup obligation',
      );
      expect(budget.used(ResourceKind.pendingOperation), 0);
      expect(client.unresolvedResources, isEmpty);
      expect((await client.retryCleanup()).complete, isTrue);
      expect(api.checkCalls, 1, reason: 'cleanup must never replay the check');
    },
  );

  test('a check past the close deadline retains budget until its real terminal reply', () async {
    final api = _UpdateApi()..checkReply = Completer();
    final budget = ResourceBudget();
    final client = _client(api, UpdaterStore(), budget: budget);
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
    expect(budget.used(ResourceKind.pendingOperation), 1);
    expect(budget.usage.single.phase, ResourcePhase.unresolved);
    api.checkReply!.completeError(StateError('late check rejected'));
    await failure;
    expect((await client.retryCleanup()).complete, isTrue);
    expect(client.unresolvedResources, isEmpty);
    expect(budget.used(ResourceKind.pendingOperation), 0);
    expect(api.checkCalls, 1);
  });

  test(
    'a check cannot enter transport without a pending-operation permit',
    () async {
      final api = _UpdateApi();
      final budget = ResourceBudget(
        capacities: {ResourceKind.pendingOperation: 0},
      );
      final client = _client(api, UpdaterStore(), budget: budget);
      await expectLater(client.check(), throwsA(isA<ResourceBudgetExceeded>()));
      expect(api.checkCalls, 0);
      expect((await client.close()).complete, isTrue);
      expect(budget.usage, isEmpty);
    },
  );

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

  test('automatic cleanup failure retains its owner until a real cancel ACK', () async {
    final api = _UpdateApi()
      ..automaticCancelFailure = StateError('cancel failed');
    final store = UpdaterStore()..apply(_available(7));
    final budget = ResourceBudget();
    final client = _client(api, store, budget: budget);
    client.attach();
    expect((await client.close()).complete, isFalse);
    expect(api.automaticStarts, 1);
    expect(api.automaticCancels, 1);
    expect(
      budget.used(ResourceKind.pendingOperation),
      0,
      reason:
          'the cancel RPC ended, while its native producer still owns a permit',
    );
    expect(budget.used(ResourceKind.observer), 1);
    api.automaticCancelFailure = null;
    expect((await client.retryCleanup()).complete, isTrue);
    expect(
      api.automaticStarts,
      1,
      reason: 'retrying cleanup never repeats startup',
    );
    expect(api.automaticCancels, 2);
    expect(budget.usage, isEmpty);
  });

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
      operation.frames.add(
        ReadyUpdaterStateSnapshot(revision: 8, readyAt: _now, update: _update),
      );
      await operation.frames.close();
      await operation.handoffRequested.future;
      expect(complete, isFalse);
      expect(operation.disposeCalls, 0);
      expect(store.state.value, isA<ReadyUpdaterStateSnapshot>());
      operation.handoff.complete();
      expect((await result).readyVersion, _update.version);
      expect(operation.disposeCalls, 1);
      expect((await client.close()).complete, isTrue);
    },
  );

  test('late install handle is cancelled by its original owner after close deadline', () async {
    final api = _UpdateApi();
    final store = UpdaterStore()..apply(_available(7));
    final budget = ResourceBudget();
    final client = _client(api, store, budget: budget);
    final install = client.install();
    final closing = client.close(deadline: DateTime.utc(2000));
    expect(
      identical(client.close(deadline: DateTime.utc(2099)), closing),
      isTrue,
    );
    expect((await closing).complete, isFalse);
    expect(budget.used(ResourceKind.pendingOperation), 1);
    final operation = _UpdateOperation();
    api.opened.complete(operation);
    await operation.disposed.future;
    expect((await install).readyVersion, isNull);
    expect(operation.cancelCalls, 1);
    expect(operation.disposeCalls, 1);
    expect(budget.used(ResourceKind.pendingOperation), 0);
  });

  test('failed handoff keeps the strong handle and budget until cleanup is confirmed', () async {
    final api = _UpdateApi();
    final store = UpdaterStore()..apply(_available(7));
    final budget = ResourceBudget();
    final client = _client(api, store, budget: budget);
    final install = client.install();
    final operation = _UpdateOperation(
      cancelFailure: StateError('native close failed'),
    );
    api.opened.complete(operation);
    await operation.listened.future;
    final failure = expectLater(install, throwsStateError);
    operation.frames.add(
      ReadyUpdaterStateSnapshot(revision: 8, readyAt: _now, update: _update),
    );
    await operation.frames.close();
    await operation.handoffRequested.future;
    operation.handoff.completeError(StateError('native handoff failed'));
    await failure;
    expect(operation.disposeCalls, 0);
    expect(budget.used(ResourceKind.pendingOperation), 1);
    final report = await client.close();
    expect(report.complete, isFalse);
    expect(report.unresolved.single.owner, 'update:1');
    expect(operation.disposeCalls, 0);
  });

  test(
    'unknown install reply is retained and never automatically replayed',
    () async {
      final api = _UpdateApi();
      final store = UpdaterStore()..apply(_available(7));
      final budget = ResourceBudget();
      final client = _client(api, store, budget: budget);
      final install = client.install();
      final failure = expectLater(install, throwsStateError);
      api.opened.completeError(StateError('reply lost'));
      await failure;
      await expectLater(client.install(), throwsStateError);
      expect(api.installCalls, 1);
      expect(budget.used(ResourceKind.pendingOperation), 1);
      expect((await client.close()).complete, isFalse);
    },
  );
}
