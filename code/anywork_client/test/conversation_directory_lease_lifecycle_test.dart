import 'dart:async';

import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

ClientCloseBudget _budget() => ClientCloseBudget(const Duration(seconds: 5));
ClientCloseBudget _expired() => ClientCloseBudget(Duration.zero);

void main() {
  for (final boundedSessionJoin in [false, true]) {
    test(
      'root-first directory failure is only joined by ordinary close '
      '(bounded=$boundedSessionJoin), and one management pass clears it',
      () async {
        final fixture = _Fixture();
        final repository = fixture.client.conversations;
        repository.session('thread');
        final native = fixture.transport.handles.single;
        await native.waiting.future;
        final failure = StateError('original native directory close failed');

        fixture.root.requestClose();
        await native.closeStarted.future;
        native.closeReceipt.completeError(failure);
        final rootFailure = await fixture.root.close(budget: _budget());
        _expectFailure(rootFailure, native.resourceId, failure);

        // Both public joins invoke the real session close; neither is a
        // management retry. Exercise its bounded and unbounded lease joins.
        final budget = _budget();
        final repositoryFailure = await repository.close(
          budget: boundedSessionJoin ? budget : null,
        );
        _expectFailure(repositoryFailure, native.resourceId, failure);
        expect(
          repositoryFailure.unresolved.single.stages.any(
            (stage) =>
                stage.phase == ClientClosePhase.leaseRelease &&
                stage.scopePath.contains('conversation-session'),
          ),
          isTrue,
        );
        final clientFailure = await fixture.client.close(budget: budget);
        _expectFailure(clientFailure, native.resourceId, failure);
        expect(native.closeCalls, 1);
        expect(native.retryCalls, 0);

        // No await between these calls: repository and Client each enter the
        // actual session retry synchronously, joining the root's one pass.
        final retryBudget = _budget();
        final rootRetry = fixture.root.retryCleanup(budget: retryBudget);
        final repositoryRetry = repository.retryCleanup(budget: retryBudget);
        final clientRetry = fixture.client.retryCleanup(budget: retryBudget);
        await native.retryStarted.future;
        expect(native.closeCalls, 1);
        expect(native.retryCalls, 1);
        expect(native.acknowledged, isFalse);
        final pending = await fixture.root.close(budget: _expired());
        expect(pending.complete, isFalse);
        expect(pending.unresolved.single.resourceId, native.resourceId);

        native.retryReceipt.complete();
        for (final report in await Future.wait([
          rootRetry,
          repositoryRetry,
          clientRetry,
        ])) {
          expect(report.unresolved, isEmpty);
          expect(report.complete, isTrue);
        }
        expect(native.acknowledged, isTrue);
        expect(native.closeCalls, 1);
        expect(native.retryCalls, 1);
        expect((await fixture.root.close(budget: _budget())).complete, isTrue);
      },
    );
  }

  test('directory release synchronously reenters the same close Future and waits for native ACK', () async {
    final fixture = _Fixture();
    final repository = fixture.client.conversations;
    repository.session('thread');
    final native = fixture.transport.handles.single;
    await native.waiting.future;
    Future<CloseReport>? reentrantRepositoryClose;
    Future<CloseReport>? reentrantClientClose;
    var inCloseCall = false;
    var reenteredSynchronously = false;
    final budget = _budget();
    native.onRequestClose = () {
      reenteredSynchronously = inCloseCall;
      reentrantRepositoryClose = repository.close();
      reentrantClientClose = fixture.client.close(budget: budget);
    };

    inCloseCall = true;
    final closing = repository.close();
    inCloseCall = false;
    expect(reenteredSynchronously, isTrue);
    expect(reentrantRepositoryClose, same(closing));
    expect(repository.close(budget: budget), same(closing));
    expect(fixture.client.close(budget: budget), same(reentrantClientClose));
    await native.closeStarted.future;
    expect(native.acknowledged, isFalse);
    final pending = await fixture.root.close(budget: _expired());
    expect(pending.unresolved.single.resourceId, native.resourceId);
    expect(
      pending.unresolved.single.stages.any(
        (stage) =>
            stage.phase == ClientClosePhase.leaseRelease && stage.pending,
      ),
      isTrue,
    );

    native.closeReceipt.complete();
    expect((await closing).complete, isTrue);
    expect((await reentrantClientClose!).complete, isTrue);
    expect((await fixture.root.close(budget: budget)).complete, isTrue);
    expect(native.acknowledged, isTrue);
    expect(native.closeCalls, 1);
    expect(native.retryCalls, 0);
  });

  test('root close during lease acquisition captures late attachment and its native handle', () async {
    final fixture = _Fixture(autoAttach: false);
    final repository = fixture.client.conversations;
    Future<CloseReport>? nestedClosing;
    fixture.transport.onOpening = (native) {
      // The session lease is still being acquired and the native handle has
      // not attached to its registered owner. Closing must retain both entries.
      fixture.root.requestClose();
      native.onRequestClose = () => nestedClosing = repository.close();
    };
    final session = repository.session('late-thread');
    final native = fixture.transport.handles.single;
    expect(native.attached.isCompleted, isFalse);
    final pendingOpen = await fixture.root.close(budget: _expired());
    expect(pendingOpen.complete, isFalse);
    expect(pendingOpen.unresolved.single.resourceId, native.resourceId);
    expect(
      pendingOpen.unresolved.single.stages.any(
        (stage) => stage.phase == ClientClosePhase.opening && stage.pending,
      ),
      isTrue,
    );

    final closing = repository.close();
    expect(session.isClosed, isTrue);
    native.attached.complete();
    await native.closeStarted.future;
    expect(nestedClosing, same(closing));
    expect(native.acknowledged, isFalse);
    final pendingClose = await fixture.root.close(budget: _expired());
    expect(pendingClose.unresolved.single.resourceId, native.resourceId);

    native.closeReceipt.complete();
    expect((await closing).complete, isTrue);
    final budget = _budget();
    expect((await fixture.client.close(budget: budget)).complete, isTrue);
    expect((await fixture.root.close(budget: budget)).complete, isTrue);
    expect(native.closeCalls, 1);
    expect(native.retryCalls, 0);
    expect(native.acknowledged, isTrue);
    expect(fixture.transport.handles, hasLength(1));
  });

  test('a non-final session borrower has no retirement and leaves other consumers alive', () async {
    final fixture = _Fixture();
    final directory = fixture.client.threadDirectory;
    final remaining = directory.observeThread('shared');
    final probe = directory.observeThread('shared');
    fixture.client.conversations.session('shared');
    final unrelated = directory.observeThread('unrelated');
    final sharedNative = fixture.transport.handles.first;
    final otherNative = fixture.transport.handles.last;
    await Future.wait([
      sharedNative.waiting.future,
      otherNative.waiting.future,
    ]);
    expect(fixture.transport.handles, hasLength(2));

    await probe.release();
    expect(probe.retirementResourceIds, isEmpty);
    final budget = _budget();
    expect(
      (await fixture.client.conversations.close(budget: budget)).complete,
      isTrue,
    );
    expect(
      (await fixture.client.conversations.retryCleanup(budget: budget))
          .complete,
      isTrue,
    );
    for (final native in [sharedNative, otherNative]) {
      expect(native.requests, 0);
      expect(native.closeCalls, 0);
      expect(native.retryCalls, 0);
    }
    final received = remaining.state.waitFor(
      (state) => state.frame?.stamp.revision == 2,
    );
    sharedNative.emit(revision: 2);
    expect((await received).frame!.stamp.revision, 2);
    expect(unrelated.state.value.closed, isFalse);

    final releases = [remaining.release(), unrelated.release()];
    expect(remaining.retirementResourceIds, [sharedNative.resourceId]);
    expect(unrelated.retirementResourceIds, [otherNative.resourceId]);
    await Future.wait([
      sharedNative.closeStarted.future,
      otherNative.closeStarted.future,
    ]);
    sharedNative.closeReceipt.complete();
    otherNative.closeReceipt.complete();
    await Future.wait(releases);
    expect(sharedNative.closeCalls, 1);
    expect(otherNative.closeCalls, 1);
    expect((await fixture.client.close(budget: budget)).complete, isTrue);
    expect((await fixture.root.close(budget: budget)).complete, isTrue);
  });
}

void _expectFailure(
  CloseReport report,
  ClientResourceId identity,
  Object failure,
) {
  expect(report.complete, isFalse);
  expect(report.unresolved, hasLength(1));
  expect(report.unresolved.single.resourceId, identity);
  expect(
    report.unresolved.single.stages.any(
      (stage) => identical(stage.error, failure),
    ),
    isTrue,
  );
}

final class _Fixture {
  _Fixture({bool autoAttach = true}) {
    transport = _DirectoryTransport(
      root.child('native'),
      autoAttach: autoAttach,
    );
    client = AnyworkClient(
      transport: transport,
      clientId: 'directory-lease',
      scope: root.child('client'),
    );
    addTearDown(() async {
      // Settle only this fixture's explicitly scripted native receipts, even
      // when an assertion aborts a case with a pending late-open or close gate.
      for (final native in transport.handles) {
        if (!native.attached.isCompleted) native.attached.complete();
        if (!native.closeReceipt.isCompleted) native.closeReceipt.complete();
        if (!native.retryReceipt.isCompleted) native.retryReceipt.complete();
      }
      final budget = _budget();
      await client.close(budget: budget);
      await client.retryCleanup(budget: budget);
      await root.close(budget: budget);
      expect((await root.retryCleanup(budget: budget)).complete, isTrue);
    });
  }

  final root = ClientScope(owner: 'directory-lease-test');
  late final _DirectoryTransport transport;
  late final AnyworkClient client;
}

final class _DirectoryTransport implements StudioTransport {
  _DirectoryTransport(this.scope, {required this.autoAttach});
  final ClientScope scope;
  final bool autoAttach;
  final List<_NativeMetadata> handles = [];
  void Function(_NativeMetadata native)? onOpening;

  @override
  Future<ThreadObservationHandle> openThreadObservation(
    String threadId, {
    required ClientResourceId resourceId,
  }) async {
    final owner = scope.open<_NativeMetadata>('native-directory:$threadId', (
      operation,
    ) {
      final native = _NativeMetadata(operation.resourceId, threadId);
      handles.add(native);
      if (autoAttach) native.attached.complete();
      onOpening?.call(native);
      return native.attached.future.then((_) => native);
    }, identity: resourceId);
    return _MetadataProxy(owner, await owner.ready);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unscripted ${invocation.memberName}');
}

final class _MetadataProxy implements ThreadObservationHandle {
  _MetadataProxy(this.owner, this.native);
  final ClientAcquisition<_NativeMetadata> owner;
  final _NativeMetadata native;

  @override
  ClientResourceId get resourceId => owner.resourceId;
  @override
  Future<ThreadMetadataFrame?> next() => native.next();
  @override
  void requestClose() => owner.requestClose();
  @override
  Future<void> close() => owner.close();
  @override
  Future<void> retryClose() => owner.retryClose();
}

final class _NativeMetadata implements ThreadObservationHandle {
  _NativeMetadata(this.resourceId, this.threadId) {
    emit(revision: 1);
  }
  @override
  final ClientResourceId resourceId;
  final String threadId;
  final attached = Completer<void>();
  final waiting = Completer<void>();
  final closeStarted = Completer<void>();
  final retryStarted = Completer<void>();
  final closeReceipt = Completer<void>();
  final retryReceipt = Completer<void>();
  Completer<ThreadMetadataFrame?>? _next;
  ThreadMetadataFrame? _latest;
  void Function()? onRequestClose;
  bool _closing = false;
  bool acknowledged = false;
  int requests = 0;
  int closeCalls = 0;
  int retryCalls = 0;

  void emit({required int revision}) {
    if (_closing) throw StateError('Directory source is closing');
    final frame = ThreadMetadataFrame(
      threadId: threadId,
      stamp: ResourceStamp(
        resourceKey: 'thread-directory',
        ownerEpoch: 'directory-lease-test',
        revision: revision,
      ),
      row: null,
    );
    final pending = _next;
    if (pending == null) {
      _latest = frame;
    } else {
      _next = null;
      pending.complete(frame);
    }
  }

  @override
  Future<ThreadMetadataFrame?> next() {
    if (_closing) return Future.value(null);
    if (_next != null) throw StateError('Concurrent native metadata pulls');
    if (_latest case final frame?) {
      _latest = null;
      return Future.value(frame);
    }
    _next = Completer<ThreadMetadataFrame?>();
    if (!waiting.isCompleted) waiting.complete();
    return _next!.future;
  }

  @override
  void requestClose() {
    requests++;
    if (_closing) return;
    _closing = true;
    _latest = null;
    _next?.complete(null);
    _next = null;
    onRequestClose?.call();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    if (!closeStarted.isCompleted) closeStarted.complete();
    await closeReceipt.future;
    acknowledged = true;
  }

  @override
  Future<void> retryClose() async {
    retryCalls++;
    requestClose();
    if (!retryStarted.isCompleted) retryStarted.complete();
    await retryReceipt.future;
    acknowledged = true;
  }
}
