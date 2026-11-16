import 'dart:async';

import 'package:anywork_client/lifecycle.dart';
import 'package:test/test.dart';

ClientCloseBudget _budget() => ClientCloseBudget(const Duration(seconds: 1));
ClientCloseBudget _expired() => ClientCloseBudget(Duration.zero);

// Move to the next event turn so all already scheduled microtasks can finish.
// Resource ordering itself is controlled by the explicit gates below.
Future<void> _drain() => Future<void>(() {});

final class _Raw implements ClientResource {
  _Raw(this.resourceId);

  @override
  final ClientResourceId resourceId;
  final requested = Completer<void>();
  final closeStarted = Completer<void>();
  final retryStarted = Completer<void>();
  Completer<void>? closeGate;
  Completer<void>? retryGate;
  Object? closeError;
  Object? retryError;
  void Function()? onRequest;
  void Function()? onClose;
  void Function()? onRetry;
  int requests = 0;
  int closes = 0;
  int retries = 0;

  @override
  void requestClose() {
    requests++;
    onRequest?.call();
    if (!requested.isCompleted) requested.complete();
  }

  @override
  Future<void> close() {
    closes++;
    if (!closeStarted.isCompleted) closeStarted.complete();
    onClose?.call();
    if (closeError case final error?) return Future<void>.error(error);
    return closeGate?.future ?? Future<void>.value();
  }

  @override
  Future<void> retryClose() {
    retries++;
    if (!retryStarted.isCompleted) retryStarted.complete();
    onRetry?.call();
    if (retryError case final error?) return Future<void>.error(error);
    return retryGate?.future ?? Future<void>.value();
  }
}

final class _Port implements ClientResource {
  _Port(this.actualOwner);

  final ClientAcquisition<_Raw> actualOwner;
  @override
  ClientResourceId get resourceId => actualOwner.resourceId;
  @override
  void requestClose() => actualOwner.requestClose();
  @override
  Future<void> close() => actualOwner.close();
  @override
  Future<void> retryClose() => actualOwner.retryClose();
}

typedef _Shared = ({
  _Raw raw,
  ClientAcquisition<_Raw> actualOwner,
  ClientAcquisition<_Port> proxy,
});

Future<_Shared> _shared(
  ClientScope sdk,
  ClientScope transport, {
  Future<void> Function(_Port, ClientOperation)? consume,
}) async {
  late _Raw raw;
  late ClientAcquisition<_Raw> actualOwner;
  final proxy = sdk.open<_Port>(
    'sdk-port',
    (operation) {
      actualOwner = transport.open<_Raw>(
        'native-owner',
        (operation) async => raw = _Raw(operation.resourceId),
        identity: operation.resourceId,
      );
      return actualOwner.ready.then((_) => _Port(actualOwner));
    },
    ownership: ClientOwnership.proxy,
    consume: consume,
  );
  await proxy.ready;
  return (raw: raw, actualOwner: actualOwner, proxy: proxy);
}

final class _Lease implements ClientLease {
  _Lease(this.identities, this.onRelease);

  final List<ClientResourceId> identities;
  final Future<void> Function(int call) onRelease;
  List<ClientResourceId> _retirement = const [];
  int calls = 0;
  int withdrawals = 0;

  @override
  List<ClientResourceId> get retirementResourceIds => _retirement;

  @override
  Future<void> release() {
    calls++;
    if (calls == 1) {
      withdrawals++;
      _retirement = List.of(identities);
    }
    return onRelease(calls);
  }
}

final class _Observation implements Observation {
  void Function()? onCancel;
  int cancellations = 0;
  @override
  bool isCancelled = false;
  @override
  bool isPaused = false;

  @override
  void cancel() {
    cancellations++;
    onCancel?.call();
    isCancelled = true;
  }

  @override
  void pause() => isPaused = true;
  @override
  void resume() => isPaused = false;
}

void main() {
  group('identity and budget', () {
    test('identity equality includes both fields', () {
      const first = ClientResourceId('scope', 1);
      expect(first, const ClientResourceId('scope', 1));
      expect(first.hashCode, const ClientResourceId('scope', 1).hashCode);
      expect(first, isNot(const ClientResourceId('other', 1)));
      expect(first, isNot(const ClientResourceId('scope', 2)));
      final ids = {first};
      ids.add(const ClientResourceId('scope', 1));
      expect(ids, hasLength(1));
    });

    test('budget rejects negative and never resets or adds time', () {
      expect(
        () => ClientCloseBudget(const Duration(microseconds: -1)),
        throwsArgumentError,
      );
      final budget = ClientCloseBudget(const Duration(seconds: 1));
      final first = budget.remaining;
      expect(budget.remaining, lessThanOrEqualTo(first));
      final expired = _expired();
      expect(expired.expired, isTrue);
      expect(expired.remaining, Duration.zero);
      expect(expired.remaining, Duration.zero);
    });

    test(
      'duplicate actual owner is rejected before invoking its factory',
      () async {
        final scope = ClientScope(owner: 'root');
        final first = scope.open(
          'first',
          (operation) async => _Raw(operation.resourceId),
        );
        await first.ready;
        var invoked = false;
        expect(
          () => scope.child('other').open<_Raw>(
            'second',
            (operation) async {
              invoked = true;
              return _Raw(operation.resourceId);
            },
            identity: ClientResourceId(
              first.resourceId.scopeId,
              first.resourceId.sequence,
            ),
          ),
          throwsStateError,
        );
        expect(invoked, isFalse);
        await first.close();
        expect(
          () => scope.open(
            'reused',
            (operation) async => _Raw(operation.resourceId),
            identity: first.resourceId,
          ),
          throwsStateError,
        );
        expect((await scope.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'independent roots reject foreign identities without sharing resources',
      () async {
        final left = ClientScope(owner: 'same-owner');
        final right = ClientScope(owner: 'same-owner');
        final l = left.open('raw', (op) async => _Raw(op.resourceId));
        final r = right.open('raw', (op) async => _Raw(op.resourceId));
        final lr = await l.ready;
        final rr = await r.ready;
        expect(l.resourceId, isNot(r.resourceId));
        expect(l.resourceId.scopeId, isNot(contains('same-owner')));
        var foreignFactories = 0;
        for (final ownership in ClientOwnership.values) {
          expect(
            () => right.open<_Raw>(
              'foreign',
              (op) async {
                foreignFactories++;
                return _Raw(op.resourceId);
              },
              identity: l.resourceId,
              ownership: ownership,
            ),
            throwsStateError,
          );
        }
        expect(foreignFactories, 0);
        await left.close(budget: _budget());
        expect(lr.closes, 1);
        expect(rr.requests, 0);
        expect((await right.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'only allocation reserves an identity, not a guessed sequence',
      () async {
        final scope = ClientScope(owner: 'root');
        final first = scope.open('first', (op) async => _Raw(op.resourceId));
        await first.ready;
        final guessed = ClientResourceId(
          first.resourceId.scopeId,
          first.resourceId.sequence + 1,
        );
        var invoked = false;
        for (final ownership in ClientOwnership.values) {
          expect(
            () => scope.open<_Raw>(
              'unallocated',
              (op) async {
                invoked = true;
                return _Raw(op.resourceId);
              },
              identity: guessed,
              ownership: ownership,
            ),
            throwsStateError,
          );
        }
        expect(invoked, isFalse);
        final next = scope.open('next', (op) async => _Raw(op.resourceId));
        await next.ready;
        expect(next.resourceId, guessed);
        expect((await scope.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'an opening or closing owner rejects synchronous reentrant ownership',
      () async {
        final scope = ClientScope(owner: 'root');
        var duplicates = 0;
        void rejectDuplicate(ClientResourceId identity) {
          expect(
            () => scope.open<_Raw>('duplicate', (op) async {
              duplicates++;
              return _Raw(op.resourceId);
            }, identity: identity),
            throwsStateError,
          );
        }

        final acquisition = scope.open<_Raw>('original', (op) {
          rejectDuplicate(op.resourceId);
          return Future.value(_Raw(op.resourceId));
        });
        final raw = await acquisition.ready;
        raw.onClose = () => rejectDuplicate(acquisition.resourceId);
        await acquisition.close();
        expect(duplicates, 0);
        expect(raw.closes, 1);
        final fresh = scope.open('fresh', (op) async => _Raw(op.resourceId));
        await fresh.ready;
        expect(fresh.resourceId, isNot(acquisition.resourceId));
        expect((await scope.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'failed creation removes both an unclaimed proxy ID and a fresh owned ID',
      () async {
        final scope = ClientScope(owner: 'root');
        for (final ownership in ClientOwnership.values) {
          final failure = StateError('failed without producing a resource');
          final failed = scope.open<_Raw>(
            'failed',
            (_) => throw failure,
            ownership: ownership,
          );
          await expectLater(failed.ready, throwsA(same(failure)));
          await failed.close();
          expect(failed.isClosed, isTrue);
          for (final replacement in ClientOwnership.values) {
            expect(
              () => scope.open<_Raw>(
                'retired',
                (_) => throw StateError('must not run'),
                identity: failed.resourceId,
                ownership: replacement,
              ),
              throwsStateError,
            );
          }
          final fresh = scope.open('fresh', (op) async => _Raw(op.resourceId));
          await fresh.ready;
          await fresh.close();
        }
        expect((await scope.close(budget: _budget())).complete, isTrue);
      },
    );
  });

  group('opening and consumption', () {
    test(
      'late handle is retained and closed, never passed to consumer',
      () async {
        final scope = ClientScope(owner: 'root');
        final created = Completer<_Raw>();
        late ClientOperation operation;
        var consumed = false;
        final acquisition = scope.open<_Raw>('opening', (op) {
          operation = op;
          return created.future;
        }, consume: (_, _) async => consumed = true);
        expect(acquisition.isClosed, isFalse);
        final ready = acquisition.ready;
        final timedOut = await scope.close(budget: _expired());
        expect(operation.closeRequested, isTrue);
        expect(timedOut.unresolved.single.resourceId, acquisition.resourceId);
        expect(
          timedOut.unresolved.single.stages.map((s) => s.phase),
          contains(ClientClosePhase.opening),
        );
        await expectLater(ready, throwsA(isA<ClientResourceClosed>()));
        final raw = _Raw(operation.resourceId)..closeGate = Completer<void>();
        created.complete(raw);
        await raw.closeStarted.future;
        expect(acquisition.isClosed, isFalse);
        expect(raw.requests, 1);
        expect(consumed, isFalse);
        expect((await scope.close(budget: _expired())).complete, isFalse);
        raw.closeGate!.complete();
        expect((await scope.close(budget: _budget())).complete, isTrue);
        expect(acquisition.isClosed, isTrue);
        expect(raw.closes, 1);
      },
    );

    test(
      'factory can synchronously close its own already registered scope',
      () async {
        final scope = ClientScope(owner: 'root');
        late _Raw raw;
        final acquisition = scope.open<_Raw>('reentrant', (op) {
          scope.requestClose();
          expect(op.closeRequested, isTrue);
          raw = _Raw(op.resourceId);
          return Future.value(raw);
        });
        await expectLater(
          acquisition.ready,
          throwsA(isA<ClientResourceClosed>()),
        );
        expect((await scope.close(budget: _budget())).complete, isTrue);
        expect(raw.requests, 1);
        expect(raw.closes, 1);
      },
    );

    test(
      'factory failure and throwing failure callback leave no false owner',
      () async {
        final scope = ClientScope(owner: 'root');
        final error = StateError('factory failed before creating a handle');
        final callbackError = StateError('domain callback failed');
        ClientOperation? operation;
        final failures = <Object>[];
        final acquisition = scope.open<_Raw>(
          'failure',
          (op) {
            operation = op;
            throw error;
          },
          onFailure: (failure, stack) {
            failures.add(failure);
            expect(operation!.closeRequested, isTrue);
            scope.requestClose();
            throw callbackError;
          },
        );
        // Deliberately do not subscribe to ready until cleanup has already run.
        await _drain();
        expect(failures, [same(error)]);
        await expectLater(acquisition.ready, throwsA(same(error)));
        expect((await scope.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'stop wakes pending consumer, which joins before actual close',
      () async {
        final scope = ClientScope(owner: 'root');
        final consumerStarted = Completer<void>();
        final consumerExited = Completer<void>();
        final finishConsumer = Completer<void>();
        late ClientOperation operation;
        final acquisition = scope.open<_Raw>(
          'consumer',
          (op) async => _Raw(op.resourceId),
          consume: (raw, op) async {
            operation = op;
            consumerStarted.complete();
            await raw.requested.future;
            expect(op.closeRequested, isTrue);
            await finishConsumer.future;
            consumerExited.complete();
          },
        );
        final raw = await acquisition.ready;
        await consumerStarted.future;
        raw.onClose = () => expect(consumerExited.isCompleted, isTrue);
        final closing = acquisition.close();
        expect(operation.closeRequested, isTrue);
        expect(raw.requests, 1);
        final pending = await scope.close(budget: _expired());
        expect(pending.complete, isFalse);
        expect(raw.closes, 0);
        expect(
          pending.unresolved.single.stages
              .where((s) => s.pending)
              .map((s) => s.phase),
          contains(ClientClosePhase.consumer),
        );
        finishConsumer.complete();
        await closing;
        expect(raw.closes, 1);
        expect((await scope.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'synchronous consumer failure triggers cleanup and reports true error',
      () async {
        final scope = ClientScope(owner: 'root');
        final error = StateError('consumer conversion failed');
        final failures = <Object>[];
        final acquisition = scope.open<_Raw>(
          'consumer',
          (op) async => _Raw(op.resourceId),
          consume: (_, _) => throw error,
          onFailure: (failure, _) => failures.add(failure),
        );
        final raw = await acquisition.ready;
        await _drain();
        expect(failures, [same(error)]);
        expect(raw.requests, 1);
        expect(raw.closes, 1);
        expect((await scope.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'a mismatched handle identity is still taken into cleanup ownership',
      () async {
        final scope = ClientScope(owner: 'root');
        final raw = _Raw(const ClientResourceId('wrong', 9));
        final failures = <Object>[];
        final acquisition = scope.open<_Raw>(
          'invalid',
          (_) async => raw,
          onFailure: (e, _) => failures.add(e),
        );
        await expectLater(acquisition.ready, throwsStateError);
        expect((await scope.close(budget: _budget())).complete, isTrue);
        expect(failures, hasLength(1));
        expect(raw.closes, 1);
      },
    );
  });

  group('stop, failure retention and retry', () {
    test(
      'retry state is installed before a stop callback reenters close',
      () async {
        final scope = ClientScope(owner: 'root');
        final acquisition = scope.open(
          'raw',
          (op) async => _Raw(op.resourceId),
        );
        final raw = await acquisition.ready;
        final closeError = StateError('native close failed');
        raw.onRequest = () => throw StateError('stop failed');
        raw.closeError = closeError;
        await expectLater(acquisition.close(), throwsA(same(closeError)));
        expect(
          (await scope.close(budget: _budget())).unresolved.single.reason,
          same(closeError),
        );
        Future<void>? reentered;
        raw.onRequest = () => reentered = acquisition.close();
        raw.retryGate = Completer<void>();
        final retrying = acquisition.retryClose();
        expect(reentered, same(retrying));
        await raw.retryStarted.future;
        raw.retryGate!.complete();
        await retrying;
        expect(raw.retries, 1);
        expect((await scope.close(budget: _budget())).complete, isTrue);
      },
    );

    test('failed stop notification is retained and explicitly retried to wake consumer', () async {
      final scope = ClientScope(owner: 'root');
      final entered = Completer<void>();
      final acquisition = scope.open<_Raw>(
        'consumer',
        (op) async => _Raw(op.resourceId),
        consume: (raw, op) async {
          entered.complete();
          await raw.requested.future;
          expect(op.closeRequested, isTrue);
        },
      );
      final raw = await acquisition.ready;
      await entered.future;
      final error = StateError('stop failed before wakeup');
      raw.onRequest = () => throw error;
      final report = await scope.close(budget: _expired());
      expect(
        report.unresolved.single.stages.any(
          (s) =>
              s.phase == ClientClosePhase.closeRequest &&
              identical(s.error, error),
        ),
        isTrue,
      );
      expect(raw.requests, 1);
      expect(raw.closes, 0);
      await scope.close(budget: _expired());
      expect(raw.requests, 1);
      raw.onRequest = null;
      expect((await scope.retryCleanup(budget: _budget())).complete, isTrue);
      expect(raw.requests, 2);
      expect(raw.closes, 1);
      expect(raw.retries, 0);
    });

    test('unawaited asynchronous failures are held and their true errors remain observable', () async {
      final scope = ClientScope(owner: 'root');
      final creating = Completer<_Raw>();
      final opening = scope.open<_Raw>('factory', (_) => creating.future);
      final factoryError = StateError('async creation failed');
      creating.completeError(factoryError);
      await _drain();
      await expectLater(opening.ready, throwsA(same(factoryError)));
      final consuming = Completer<void>();
      final acquisition = scope.open<_Raw>(
        'consumer',
        (op) async => _Raw(op.resourceId),
        consume: (_, _) => consuming.future,
      );
      final raw = await acquisition.ready;
      final consumerError = StateError('async consumer failed');
      final closeError = StateError('async cleanup failed');
      raw.closeError = closeError;
      consuming.completeError(consumerError);
      await _drain();
      final report = await scope.close(budget: _budget());
      expect(report.unresolved, hasLength(1));
      expect(report.unresolved.single.reason, same(closeError));
      await expectLater(acquisition.close(), throwsA(same(closeError)));
      expect((await scope.retryCleanup(budget: _budget())).complete, isTrue);
    });

    test(
      'all scopes are sealed and siblings notified before joining anything',
      () async {
        final root = ClientScope(owner: 'root');
        final firstScope = root.child('first');
        final secondScope = root.child('second');
        final log = <String>[];
        final first = firstScope.open(
          'first',
          (op) async => _Raw(op.resourceId),
        );
        final second = secondScope.open(
          'second',
          (op) async => _Raw(op.resourceId),
        );
        final a = await first.ready;
        final b = await second.ready;
        a.onRequest = () {
          log.add('stop-first');
          expect(
            () => secondScope.child('forbidden'),
            throwsA(isA<ClientResourceClosed>()),
          );
          root.requestClose();
          throw StateError('stop hook failed');
        };
        b.onRequest = () => log.add('stop-second');
        a.onClose = () {
          expect(log, ['stop-first', 'stop-second']);
          log.add('close-first');
        };
        b.onClose = () => expect(log, contains('stop-first'));
        final closing = root.close(budget: _budget());
        expect(a.requests, 1);
        expect(b.requests, 1);
        expect((await closing).complete, isTrue);
      },
    );

    test(
      'ordinary close caches error; explicit retries reuse the original handle',
      () async {
        final scope = ClientScope(owner: 'root');
        final acquisition = scope.open(
          'raw',
          (op) async => _Raw(op.resourceId),
        );
        final raw = await acquisition.ready;
        final original = StateError('native close failed');
        raw.closeError = original;
        final closing = acquisition.close();
        expect(identical(closing, acquisition.close()), isTrue);
        await expectLater(closing, throwsA(same(original)));
        expect(acquisition.isClosed, isFalse);
        await expectLater(acquisition.close(), throwsA(same(original)));
        final report = await scope.close(budget: _budget());
        expect(report.unresolved.single.reason, same(original));
        expect(report.unresolved.single.resourceId, acquisition.resourceId);
        expect(raw.closes, 1);
        raw.retryGate = Completer<void>();
        final retrying = acquisition.retryClose();
        expect(identical(retrying, acquisition.retryClose()), isTrue);
        expect(identical(retrying, acquisition.close()), isTrue);
        await raw.retryStarted.future;
        expect(acquisition.isClosed, isFalse);
        expect(raw.retries, 1);
        expect((await scope.close(budget: _expired())).complete, isFalse);
        raw.retryGate!.complete();
        await retrying;
        expect(acquisition.isClosed, isTrue);
        await acquisition.close();
        await acquisition.retryClose();
        expect(raw.closes, 1);
        expect(raw.retries, 1);
        expect((await scope.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'deadline ends only waiting; a late ACK still settles the same entry',
      () async {
        final scope = ClientScope(owner: 'root');
        final acquisition = scope.open(
          'raw',
          (op) async => _Raw(op.resourceId),
        );
        final raw = await acquisition.ready;
        raw.closeGate = Completer<void>();
        final expired = _expired();
        final pending = await scope.close(budget: expired);
        expect(raw.requests, 1);
        expect(pending.unresolved.single.resourceId, acquisition.resourceId);
        await raw.closeStarted.future;
        final second = await scope.close(
          budget: ClientCloseBudget(const Duration(milliseconds: 2)),
        );
        expect(second.complete, isFalse);
        expect(raw.closes, 1);
        raw.closeGate!.complete();
        await acquisition.close();
        expect((await scope.close(budget: expired)).complete, isTrue);
        expect(raw.closes, 1);
        expect(raw.retries, 0);
      },
    );

    test(
      'retryCleanup does not close active unrelated entries or seal admission',
      () async {
        final scope = ClientScope(owner: 'root');
        final retiring = scope.open('old', (op) async => _Raw(op.resourceId));
        final old = await retiring.ready;
        old.closeError = StateError('old close failed');
        await expectLater(retiring.close(), throwsStateError);
        final active = scope.open('new', (op) async => _Raw(op.resourceId));
        final current = await active.ready;
        expect((await scope.retryCleanup(budget: _budget())).complete, isTrue);
        expect(old.retries, 1);
        expect(current.requests, 0);
        final added = scope.open('later', (op) async => _Raw(op.resourceId));
        await added.ready;
        expect((await scope.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'an old identity cannot remove a new same-labelled resource',
      () async {
        final scope = ClientScope(owner: 'root');
        final old = scope.open('A', (op) async => _Raw(op.resourceId));
        final oldRaw = await old.ready;
        oldRaw.closeGate = Completer<void>();
        final oldClose = old.close();
        final current = scope.open('A', (op) async => _Raw(op.resourceId));
        final currentRaw = await current.ready;
        expect(current.resourceId, isNot(old.resourceId));
        oldRaw.closeGate!.complete();
        await oldClose;
        expect(currentRaw.requests, 0);
        expect((await scope.close(budget: _budget())).complete, isTrue);
        expect(currentRaw.closes, 1);
      },
    );
  });

  group('owner, proxy and root cleanup pass', () {
    test(
      'ACK exists only until the last proxy releases its reference',
      () async {
        final root = ClientScope(owner: 'root');
        final sdk = root.child('sdk');
        final transport = root.child('transport');
        final shared = await _shared(sdk, transport);
        await shared.actualOwner.close();
        var replacementOwners = 0;
        expect(
          () => transport.open<_Raw>('duplicate-after-ACK', (op) async {
            replacementOwners++;
            return _Raw(op.resourceId);
          }, identity: shared.proxy.resourceId),
          throwsStateError,
        );
        // A live proxy keeps the ACK available to other aliases, not to a new
        // actual owner. No extra native close is needed for either alias.
        final alias = sdk.open<_Port>(
          'alias',
          (_) async => _Port(shared.actualOwner),
          identity: shared.proxy.resourceId,
          ownership: ClientOwnership.proxy,
        );
        await alias.ready;
        await alias.close();
        await shared.proxy.close();
        for (final ownership in ClientOwnership.values) {
          expect(
            () => sdk.open<_Port>(
              'retired',
              (_) async => _Port(shared.actualOwner),
              identity: shared.proxy.resourceId,
              ownership: ownership,
            ),
            throwsStateError,
          );
        }
        expect(replacementOwners, 0);
        expect(shared.raw.closes, 1);
        expect(shared.raw.retries, 0);
        expect((await root.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'failure callback may register a late owner before the proxy unregisters',
      () async {
        final root = ClientScope(owner: 'root');
        final sdk = root.child('sdk');
        final transport = root.child('transport');
        final failure = StateError('proxy creation failed');
        late ClientOperation operation;
        late ClientAcquisition<_Raw> actual;
        late _Raw raw;
        final proxy = sdk.open<_Port>(
          'proxy',
          (op) {
            operation = op;
            throw failure;
          },
          ownership: ClientOwnership.proxy,
          onFailure: (error, stack) {
            expect(error, same(failure));
            actual = transport.open<_Raw>('late-owner', (op) {
              expect(op.closeRequested, isTrue);
              raw = _Raw(op.resourceId);
              return Future.value(raw);
            }, identity: operation.resourceId);
            sdk.requestClose();
          },
        );
        await expectLater(proxy.ready, throwsA(same(failure)));
        await actual.close();
        expect((await sdk.close(budget: _budget())).complete, isTrue);
        expect(raw.requests, 1);
        expect(raw.closes, 1);
        expect(
          () => transport.open<_Raw>(
            'retired',
            (op) async => _Raw(op.resourceId),
            identity: operation.resourceId,
          ),
          throwsStateError,
        );
        expect((await root.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'failed proxy factory still joins a partially-created actual owner',
      () async {
        final root = ClientScope(owner: 'root');
        final sdk = root.child('sdk');
        final transport = root.child('transport');
        final factoryError = StateError('port attachment failed');
        final closeError = StateError('partial native cleanup failed');
        late _Raw raw;
        final acquisition = sdk.open<_Port>('sdk-port', (operation) async {
          final actual = transport.open<_Raw>(
            'native-owner',
            (op) async => raw = _Raw(op.resourceId),
            identity: operation.resourceId,
          );
          await actual.ready;
          raw.closeError = closeError;
          actual.requestClose();
          throw factoryError;
        }, ownership: ClientOwnership.proxy);
        await expectLater(acquisition.ready, throwsA(same(factoryError)));
        final failed = await sdk.close(budget: _budget());
        expect(failed.unresolved.single.resourceId, acquisition.resourceId);
        expect(failed.unresolved.single.owner, 'native-owner');
        expect(failed.unresolved.single.reason, same(closeError));
        expect(raw.closes, 1);
        await expectLater(acquisition.close(), throwsA(same(closeError)));
        expect((await sdk.retryCleanup(budget: _budget())).complete, isTrue);
        expect(raw.retries, 1);
        expect((await root.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'an owner registered after proxy stop inherits that stop before factory',
      () async {
        final root = ClientScope(owner: 'root');
        final sdk = root.child('sdk');
        final transport = root.child('transport');
        final continueFactory = Completer<void>();
        final nativeStarted = Completer<void>();
        late _Raw raw;
        var consumed = false;
        final acquisition = sdk.open<_Port>(
          'sdk-port',
          (operation) async {
            await continueFactory.future;
            final actual = transport.open<_Raw>('native-owner', (op) async {
              expect(op.closeRequested, isTrue);
              raw = _Raw(op.resourceId);
              nativeStarted.complete();
              return raw;
            }, identity: operation.resourceId);
            await actual.ready;
            return _Port(actual);
          },
          ownership: ClientOwnership.proxy,
          consume: (_, _) async => consumed = true,
        );
        sdk.requestClose();
        await expectLater(
          acquisition.ready,
          throwsA(isA<ClientResourceClosed>()),
        );
        continueFactory.complete();
        await nativeStarted.future;
        expect((await sdk.close(budget: _budget())).complete, isTrue);
        expect(consumed, isFalse);
        expect(raw.requests, 1);
        expect(raw.closes, 1);
        final unrelated = transport.open(
          'unrelated',
          (op) async => _Raw(op.resourceId),
        );
        await unrelated.ready;
        expect((await root.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'same-labelled aliases retain distinct scope paths after owner ACK',
      () async {
        final root = ClientScope(owner: 'root');
        final firstScope = root.child('first-sdk');
        final secondScope = root.child('second-sdk');
        final exit = Completer<void>();
        final shared = await _shared(
          firstScope,
          root.child('transport'),
          consume: (_, _) => exit.future,
        );
        final second = secondScope.open<_Port>(
          'sdk-port',
          (_) async => _Port(shared.actualOwner),
          identity: shared.proxy.resourceId,
          ownership: ClientOwnership.proxy,
          consume: (_, _) => exit.future,
        );
        await second.ready;
        root.requestClose();
        await shared.actualOwner.close();
        final pending = await root.close(budget: _expired());
        final consumers = pending.unresolved.single.stages
            .where((s) => s.phase == ClientClosePhase.consumer)
            .toList();
        expect(consumers, hasLength(2));
        expect(
          consumers.map((s) => s.scopePath),
          containsAll([
            ['root', 'first-sdk'],
            ['root', 'second-sdk'],
          ]),
        );
        exit.complete();
        expect((await root.close(budget: _budget())).complete, isTrue);
        expect(shared.raw.closes, 1);
      },
    );

    test('proxy is registered first; both aliases join one actual close and retry', () async {
      final root = ClientScope(owner: 'root');
      final sdk = root.child('sdk');
      final transport = root.child('transport');
      final shared = await _shared(sdk, transport);
      final failure = StateError('native ACK failed');
      shared.raw.closeError = failure;
      final failed = await root.close(budget: _budget());
      expect(failed.unresolved, hasLength(1));
      final resource = failed.unresolved.single;
      expect(resource.resourceId, shared.proxy.resourceId);
      expect(resource.owner, 'native-owner');
      expect(resource.reason, same(failure));
      expect(
        resource.stages.map((s) => s.owner),
        containsAll(['sdk-port', 'native-owner']),
      );
      expect(shared.raw.closes, 1);
      shared.raw.retryError = failure;
      final retriedFailure = await root.retryCleanup(budget: _budget());
      expect(retriedFailure.unresolved, hasLength(1));
      expect(retriedFailure.unresolved.single.reason, same(failure));
      expect(shared.raw.retries, 1);
      shared.raw.retryError = null;
      final completed = await root.retryCleanup(budget: _budget());
      expect(
        completed.complete,
        isTrue,
        reason:
            'retries=${shared.raw.retries}; ${completed.unresolved.map((r) => r.stages.map((s) => '${s.owner}/${s.phase.name}: pending=${s.pending}, error=${s.error}'))}',
      );
      expect(shared.raw.retries, 2);
      expect(shared.raw.closes, 1);
    });

    test('concurrent child retries share the same native attempt', () async {
      final root = ClientScope(owner: 'root');
      final sdk = root.child('sdk');
      final transport = root.child('transport');
      final shared = await _shared(sdk, transport);
      shared.raw.closeError = StateError('first failure');
      await root.close(budget: _budget());
      shared.raw.retryGate = Completer<void>();
      final upper = sdk.retryCleanup(budget: _budget());
      final lower = transport.retryCleanup(budget: _budget());
      await shared.raw.retryStarted.future;
      expect(shared.raw.retries, 1);
      shared.raw.retryGate!.complete();
      expect((await upper).complete, isTrue);
      expect((await lower).complete, isTrue);
      expect(shared.raw.retries, 1);
      expect((await root.close(budget: _budget())).complete, isTrue);
    });

    test('owner ACK cannot erase a still-running proxy consumer', () async {
      final root = ClientScope(owner: 'root');
      final exit = Completer<void>();
      final started = Completer<void>();
      final shared = await _shared(
        root.child('sdk'),
        root.child('transport'),
        consume: (port, operation) async {
          started.complete();
          await exit.future;
        },
      );
      await started.future;
      root.requestClose();
      await shared.actualOwner.close();
      final pending = await root.close(budget: _expired());
      expect(pending.complete, isFalse);
      final stages = pending.unresolved.single.stages;
      expect(
        stages.any((s) => s.phase == ClientClosePhase.consumer && s.pending),
        isTrue,
      );
      expect(
        stages.any((s) => s.ownership == ClientOwnership.owned && s.complete),
        isTrue,
      );
      expect(shared.raw.closes, 1);
      exit.complete();
      expect((await root.close(budget: _budget())).complete, isTrue);
      expect(shared.raw.closes, 1);
      expect(shared.raw.retries, 0);
    });

    test('retry deadline does not abandon a pending actual attempt', () async {
      final root = ClientScope(owner: 'root');
      final shared = await _shared(root.child('sdk'), root.child('transport'));
      shared.raw.closeError = StateError('first failure');
      await root.close(budget: _budget());
      shared.raw.retryGate = Completer<void>();
      expect((await root.retryCleanup(budget: _expired())).complete, isFalse);
      await shared.raw.retryStarted.future;
      expect((await root.retryCleanup(budget: _expired())).complete, isFalse);
      expect(shared.raw.retries, 1);
      shared.raw.retryGate!.complete();
      expect((await root.close(budget: _budget())).complete, isTrue);
      expect(shared.raw.retries, 1);
    });
  });

  group('lease adapter', () {
    test(
      'ACK exists only until the last lease releases its reference',
      () async {
        final root = ClientScope(owner: 'root');
        final ui = root.child('ui');
        final actual = root.open('native', (op) async => _Raw(op.resourceId));
        final raw = await actual.ready;
        final released = Completer<void>();
        final lease = _Lease([actual.resourceId], (_) {
          actual.requestClose();
          return released.future;
        });
        ui.acquireLease('lease', () => lease);
        ui.requestClose();
        await actual.close();
        expect(
          () => root.open<_Raw>(
            'duplicate-after-ACK',
            (op) async => _Raw(op.resourceId),
            identity: actual.resourceId,
          ),
          throwsStateError,
        );
        final alias = root.open<_Port>(
          'ACK-reference',
          (_) async => _Port(actual),
          identity: actual.resourceId,
          ownership: ClientOwnership.proxy,
        );
        await alias.ready;
        await alias.close();
        expect((await ui.close(budget: _expired())).complete, isFalse);
        released.complete();
        expect((await ui.close(budget: _budget())).complete, isTrue);
        for (final ownership in ClientOwnership.values) {
          expect(
            () => root.open<_Port>(
              'retired',
              (_) async => _Port(actual),
              identity: actual.resourceId,
              ownership: ownership,
            ),
            throwsStateError,
          );
        }
        expect(raw.closes, 1);
        expect(raw.retries, 0);
        expect((await root.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'a lease alone keeps an unclaimed ID available to its late owner',
      () async {
        final root = ClientScope(owner: 'root');
        final sdk = root.child('sdk');
        final ui = root.child('ui');
        final transport = root.child('transport');
        final opening = Completer<_Port>();
        final released = Completer<void>();
        final proxy = sdk.open<_Port>(
          'proxy',
          (_) => opening.future,
          ownership: ClientOwnership.proxy,
        );
        final lease = _Lease([proxy.resourceId], (_) => released.future);
        ui.acquireLease('lease', () => lease);
        ui.requestClose();
        final failure = StateError('no proxy was produced');
        opening.completeError(failure);
        await expectLater(proxy.ready, throwsA(same(failure)));
        await proxy.close();
        late _Raw raw;
        final actual = transport.open<_Raw>('late-owner', (op) {
          expect(op.closeRequested, isTrue);
          raw = _Raw(op.resourceId);
          return Future.value(raw);
        }, identity: proxy.resourceId);
        await expectLater(actual.ready, throwsA(isA<ClientResourceClosed>()));
        await actual.close();
        expect(raw.closes, 1);
        expect((await ui.close(budget: _expired())).complete, isFalse);
        released.complete();
        expect((await ui.close(budget: _budget())).complete, isTrue);
        for (final ownership in ClientOwnership.values) {
          expect(
            () => transport.open<_Raw>(
              'retired',
              (_) => throw StateError('must not run'),
              identity: proxy.resourceId,
              ownership: ownership,
            ),
            throwsStateError,
          );
        }
        expect((await root.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'lease metadata cannot resurrect a retired or foreign identity',
      () async {
        final root = ClientScope(owner: 'root');
        final foreignRoot = ClientScope(owner: 'foreign-root');
        final retired = root.open('retired', (op) async => _Raw(op.resourceId));
        await retired.ready;
        await retired.close();
        final foreign = foreignRoot.open(
          'foreign',
          (op) async => _Raw(op.resourceId),
        );
        final foreignRaw = await foreign.ready;
        for (final id in [retired.resourceId, foreign.resourceId]) {
          final ui = root.child('ui');
          ui.acquireLease(
            'invalid',
            () => _Lease([id], (_) => Future<void>.value()),
          );
          final report = await ui.close(budget: _budget());
          expect(report.unresolved.single.resourceId, id);
          expect(report.unresolved.single.reason, isA<StateError>());
          for (final ownership in ClientOwnership.values) {
            expect(
              () => root.open<_Raw>(
                'invalid',
                (_) => throw StateError('must not run'),
                identity: id,
                ownership: ownership,
              ),
              throwsStateError,
            );
          }
        }
        expect(foreignRaw.requests, 0);
        expect((await foreignRoot.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'placeholder captures disposal reentered by synchronous acquire',
      () async {
        final scope = ClientScope(owner: 'ui');
        final gate = Completer<void>();
        final lease = _Lease([], (_) {
          scope.requestClose();
          return gate.future;
        });
        final acquired = scope.acquireLease('lease', () {
          scope.requestClose();
          return lease;
        });
        expect(acquired, same(lease));
        expect(lease.withdrawals, 1);
        expect(lease.calls, 1);
        expect((await scope.close(budget: _expired())).complete, isFalse);
        gate.complete();
        expect((await scope.close(budget: _budget())).complete, isTrue);
        expect(lease.calls, 1);
      },
    );

    test('throwing synchronous acquire closes the empty placeholder', () async {
      final scope = ClientScope(owner: 'ui');
      final failure = StateError('acquire failed');
      expect(
        () => scope.acquireLease<_Lease>('lease', () {
          scope.requestClose();
          throw failure;
        }),
        throwsA(same(failure)),
      );
      expect((await scope.close(budget: _budget())).complete, isTrue);
    });

    test(
      'retirement identities are captured before waiting, even on sync throw',
      () async {
        final root = ClientScope(owner: 'root');
        final ui = root.child('ui');
        final actual = root
            .child('actual')
            .open('native', (op) async => _Raw(op.resourceId));
        final raw = await actual.ready;
        final failure = StateError('release synchronous failure');
        final lease = _Lease([actual.resourceId], (call) {
          actual.requestClose();
          if (call == 1) throw failure;
          return actual.retryClose();
        });
        ui.acquireLease('lease', () => lease);
        final failed = await ui.close(budget: _budget());
        expect(failed.unresolved.single.resourceId, actual.resourceId);
        expect(
          failed.unresolved.single.stages.any(
            (s) => identical(s.error, failure),
          ),
          isTrue,
        );
        expect(lease.withdrawals, 1);
        expect((await ui.close(budget: _budget())).complete, isFalse);
        expect(lease.calls, 1);
        expect((await ui.retryCleanup(budget: _budget())).complete, isTrue);
        expect(lease.calls, 2);
        expect(lease.withdrawals, 1);
        expect(raw.closes, 1);
        expect(raw.retries, 0);
        await root.close(budget: _budget());
      },
    );

    test(
      'lease timeout reports captured old source, not its synthetic adapter ID',
      () async {
        final root = ClientScope(owner: 'root');
        final ui = root.child('ui');
        final actual = root
            .child('actual')
            .open('native', (op) async => _Raw(op.resourceId));
        final raw = await actual.ready;
        raw.closeGate = Completer<void>();
        final lease = _Lease([actual.resourceId], (_) => actual.close());
        ui.acquireLease('lease', () => lease);
        final report = await ui.close(budget: _expired());
        expect(lease.withdrawals, 1);
        expect(report.unresolved.single.resourceId, actual.resourceId);
        expect(
          report.unresolved.single.stages.any(
            (s) => s.phase == ClientClosePhase.leaseRelease && s.pending,
          ),
          isTrue,
        );
        raw.closeGate!.complete();
        expect((await ui.close(budget: _budget())).complete, isTrue);
        expect(lease.calls, 1);
        await root.close(budget: _budget());
      },
    );

    test('multiple failed leases join one owner retry per cleanup pass', () async {
      final root = ClientScope(owner: 'root');
      final ui = root.child('ui');
      final actual = root
          .child('actual')
          .open('native', (op) async => _Raw(op.resourceId));
      final raw = await actual.ready;
      final failure = StateError('native ACK failed');
      raw.closeError = failure;
      final leases = List.generate(
        2,
        (_) => _Lease([
          actual.resourceId,
        ], (call) => call == 1 ? actual.close() : actual.retryClose()),
      );
      for (final lease in leases) {
        ui.acquireLease('lease', () => lease);
      }
      expect((await root.close(budget: _budget())).unresolved, hasLength(1));
      raw.retryError = failure;
      expect(
        (await root.retryCleanup(budget: _budget())).unresolved,
        hasLength(1),
      );
      expect(raw.retries, 1);
      expect(leases.map((l) => l.calls), [2, 2]);
      raw.retryError = null;
      final completed = await root.retryCleanup(budget: _budget());
      expect(
        completed.complete,
        isTrue,
        reason:
            'retries=${raw.retries}; ${completed.unresolved.map((r) => r.stages.map((s) => '${s.owner}/${s.phase.name}: pending=${s.pending}, error=${s.error}'))}',
      );
      expect(raw.retries, 2);
      expect(leases.map((l) => l.calls), [3, 3]);
      expect(leases.map((l) => l.withdrawals), [1, 1]);
    });

    test(
      'bundle captures all retired identities and retries both original owners',
      () async {
        final root = ClientScope(owner: 'root');
        final ui = root.child('ui');
        final sources = root.child('sources');
        final old = List.generate(
          2,
          (_) => sources.open('source', (op) async => _Raw(op.resourceId)),
        );
        final handles = await Future.wait(old.map((a) => a.ready));
        for (final raw in handles) {
          raw.closeError = StateError('old source failed');
        }
        final lease = _Lease(
          [...old.map((a) => a.resourceId), old.first.resourceId],
          (call) async {
            await Future.wait(
              old.map((a) => call == 1 ? a.close() : a.retryClose()),
            );
          },
        );
        ui.acquireLease('bundle', () => lease);
        expect((await ui.close(budget: _budget())).unresolved, hasLength(2));
        final replacement = sources.open(
          'source',
          (op) async => _Raw(op.resourceId),
        );
        final current = await replacement.ready;
        expect((await ui.retryCleanup(budget: _budget())).complete, isTrue);
        expect(handles.map((h) => h.retries), [1, 1]);
        expect(current.requests, 0);
        expect(lease.withdrawals, 1);
        expect((await root.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'non-final demand has no source retirement and never closes siblings',
      () async {
        final root = ClientScope(owner: 'root');
        final ui = root.child('ui');
        final source = root
            .child('source')
            .open('native', (op) async => _Raw(op.resourceId));
        final raw = await source.ready;
        final lease = _Lease([], (_) => Future<void>.value());
        ui.acquireLease('one-of-many', () => lease);
        expect((await ui.close(budget: _budget())).complete, isTrue);
        expect(lease.withdrawals, 1);
        expect(raw.requests, 0);
        expect(raw.closes, 0);
        expect((await root.close(budget: _budget())).complete, isTrue);
      },
    );
  });

  group('observations and reporting', () {
    test(
      'a reentrant zero-budget report cannot acknowledge an in-flight cancel',
      () async {
        final scope = ClientScope(owner: 'root');
        final observation = _Observation();
        final failure = StateError('cancel failed after reentry');
        Future<CloseReport>? nested;
        observation.onCancel = () {
          nested = scope.close(budget: _expired());
          throw failure;
        };
        scope.observe(observation);
        scope.requestClose();
        final pending = await nested!;
        expect(pending.complete, isFalse);
        expect(pending.unresolved.single.stages.single.pending, isTrue);
        final failed = await scope.close(budget: _budget());
        expect(failed.unresolved.single.reason, same(failure));
        expect(observation.cancellations, 1);
        observation.onCancel = null;
        expect((await scope.retryCleanup(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'throwing and reentrant cancellation does not stop other notifications',
      () async {
        final scope = ClientScope(owner: 'root');
        final bad = _Observation();
        final good = _Observation();
        final failure = StateError('cancel failed');
        bad.onCancel = () {
          scope.requestClose();
          throw failure;
        };
        scope.observe(bad);
        final wrapped = scope.observe(good);
        wrapped.pause();
        expect(good.isPaused, isTrue);
        wrapped.resume();
        expect(good.isPaused, isFalse);
        final resource = scope.open('raw', (op) async => _Raw(op.resourceId));
        final raw = await resource.ready;
        final report = await scope.close(budget: _budget());
        expect(report.unresolved.single.reason, same(failure));
        expect(
          report.unresolved.single.stages.single.phase,
          ClientClosePhase.observation,
        );
        expect(good.cancellations, 1);
        expect(raw.requests, 1);
        bad.onCancel = null;
        expect((await scope.retryCleanup(budget: _budget())).complete, isTrue);
        expect(wrapped.isCancelled, isTrue);
        expect(good.cancellations, 1);
      },
    );

    test(
      'closing gates all new acquisitions and observations synchronously',
      () async {
        final scope = ClientScope(owner: 'root');
        scope.requestClose();
        expect(
          () => scope.open('raw', (op) async => _Raw(op.resourceId)),
          throwsA(isA<ClientResourceClosed>()),
        );
        expect(
          () => scope.acquireLease('lease', () => _Lease([], (_) async {})),
          throwsA(isA<ClientResourceClosed>()),
        );
        expect(
          () => scope.observe(_Observation()),
          throwsA(isA<ClientResourceClosed>()),
        );
        expect(
          () => scope.child('child'),
          throwsA(isA<ClientResourceClosed>()),
        );
        expect((await scope.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'reports merge by explicit identity and retain every unfinished phase',
      () {
        const identity = ClientResourceId('scope', 1);
        final failure = StateError('actual owner failed');
        final report = CloseReport(
          unresolved: [
            UnresolvedResource(
              resourceId: identity,
              owner: 'proxy',
              attemptId: const AttemptId(1),
              reason: StateError('consumer pending'),
              ownership: ClientOwnership.proxy,
              stages: [
                const ClientResourceStage(
                  owner: 'proxy',
                  phase: ClientClosePhase.consumer,
                  ownership: ClientOwnership.proxy,
                  pending: true,
                ),
              ],
            ),
            UnresolvedResource(
              resourceId: identity,
              owner: 'raw',
              attemptId: const AttemptId(1),
              reason: failure,
              ownership: ClientOwnership.owned,
              stages: [
                ClientResourceStage(
                  owner: 'raw',
                  phase: ClientClosePhase.close,
                  ownership: ClientOwnership.owned,
                  error: failure,
                ),
              ],
            ),
          ],
        );
        expect(report.unresolved, hasLength(1));
        expect(report.unresolved.single.owner, 'raw');
        expect(report.unresolved.single.reason, same(failure));
        expect(report.unresolved.single.stages, hasLength(2));
        final mergedAgain = CloseReport(
          unresolved: [...report.unresolved, ...report.unresolved],
        );
        expect(mergedAgain.unresolved.single.stages, hasLength(2));
        expect(() => mergedAgain.unresolved.clear(), throwsUnsupportedError);
        expect(
          () => mergedAgain.unresolved.single.stages.clear(),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'different identities never merge despite the same owner and attempt',
      () {
        const first = ClientResourceId('scope', 1);
        const second = ClientResourceId('scope', 2);
        final error = StateError('shared failure');
        final report = CloseReport(
          unresolved: [
            UnresolvedResource(
              resourceId: first,
              owner: 'same',
              attemptId: const AttemptId(1),
              reason: error,
            ),
            UnresolvedResource(
              resourceId: second,
              owner: 'same',
              attemptId: const AttemptId(1),
              reason: error,
            ),
          ],
        );
        expect(report.unresolved, hasLength(2));
        expect(report.unresolved.map((resource) => resource.resourceId), [
          first,
          second,
        ]);
        expect(report.unresolved.map((resource) => resource.owner), [
          'same',
          'same',
        ]);
        expect(report.unresolved.map((resource) => resource.attemptId), [
          const AttemptId(1),
          const AttemptId(1),
        ]);
        expect(
          report.unresolved.map((resource) => resource.reason),
          everyElement(same(error)),
        );
        final mergedAgain = CloseReport(
          unresolved: [...report.unresolved, ...report.unresolved],
        );
        expect(mergedAgain.unresolved.map((resource) => resource.resourceId), [
          first,
          second,
        ]);
      },
    );
  });
}
