import 'package:anywork_client/anywork_client.dart';
import 'package:test/test.dart';

void main() {
  test('terminal operations across distinct targets obey retention budget', () {
    final board = MutationBoard(clientId: 'bounded', maxRetained: 3);
    for (var index = 0; index < 30; index++) {
      final operation = board.begin(target: 'thread:$index');
      operation.accept(
        CommitReceipt(
          operationId: operation.id,
          disposition: CommitDisposition.noChange,
          targets: const [],
          effect: EffectPoint.immediate,
        ),
      );
    }
    expect(board.operations, hasLength(3));
    expect(board.latest('thread:0'), isNull);
    expect(board.latest('thread:29'), isNotNull);
    expect(board.budget.used(ResourceKind.pendingOperation), 0);
  });

  test('paused observations retain one latest value and cancellation only detaches', () {
    final source = LatestValue(0);
    final seen = <int>[];
    final subscription = source.watchLatest(seen.add);
    expect(subscription.value, 0);
    subscription.observation.pause();
    for (var value = 1; value <= 1000; value++) {
      source.publish(value);
    }
    expect(seen, isEmpty);
    subscription.observation.resume();
    expect(seen, [1000]);
    subscription.observation.cancel();
    source.publish(1001);
    expect(seen, [1000]);
    expect(source.value, 1001);
    expect(source.observerCount, 0);
  });

  test(
    'watchLatest and waitFor observe updates adjacent to registration',
    () async {
      final source = LatestValue(2);
      final seen = <int>[];
      final registration = source.watchLatest(seen.add);
      final waiting = source.waitFor((value) => value >= 3);
      source.publish(3);

      expect(registration.value, 2);
      expect(await waiting, 3);
      expect(seen, [3]);
      expect(await source.waitFor((value) => value == 3), 3);
      registration.observation.cancel();
      expect(source.observerCount, 0);
    },
  );

  test(
    'receipt and owner frame can arrive in either order without losing Applied',
    () {
      for (final frameFirst in [true, false]) {
        final board = MutationBoard(clientId: 'app');
        final operation = board.begin(target: 'settings');
        const stamp = ResourceStamp(
          resourceKey: 'settings',
          ownerEpoch: 'epoch',
          revision: 12,
        );
        final receipt = CommitReceipt(
          operationId: operation.id,
          disposition: CommitDisposition.applied,
          targets: [stamp],
          effect: EffectPoint.nextTurn,
          durable: true,
        );
        if (frameFirst) board.observe(stamp);
        operation.accept(receipt);
        if (!frameFirst) {
          expect(operation.state.value.observed, isFalse);
          board.observe(stamp);
        }
        expect(operation.state.value.observed, isTrue);
        expect(
          operation.state.value.receipt?.disposition,
          CommitDisposition.applied,
        );
        expect(operation.state.value.effective, isFalse);
        expect(operation.state.value.durable, isTrue);
        expect(board.budget.used(ResourceKind.pendingOperation), 0);
      }
    },
  );

  test(
    'old outcomes do not clear a newer latest intent or unknown outcome',
    () {
      final board = MutationBoard(clientId: 'app');
      final old = board.begin(target: 'thread:model');
      final latest = board.begin(target: 'thread:model');
      latest.unknownOutcome(StateError('connection lost after write'));
      old.reject(StateError('old request rejected'));

      expect(board.latest('thread:model'), same(latest));
      expect(latest.state.value.phase, OperationPhase.unknownOutcome);
      expect(board.budget.used(ResourceKind.pendingOperation), 1);
      latest.accept(
        CommitReceipt(
          operationId: latest.id,
          disposition: CommitDisposition.noChange,
          targets: const [],
          effect: EffectPoint.immediate,
        ),
      );
      expect(latest.state.value.observed, isTrue);
      expect(latest.state.value.phase, OperationPhase.observed);
    },
  );

  test('new owner and view versions cannot satisfy old-domain receipts', () {
    final board = MutationBoard(clientId: 'app');
    final operation = board.begin(target: 'chat');
    const target = ViewStamp(
      threadId: 'thread',
      viewId: 'new',
      viewEpoch: 'new-epoch',
      version: 1,
    );
    operation.accept(
      CommitReceipt(
        operationId: operation.id,
        disposition: CommitDisposition.applied,
        targets: [target],
        effect: EffectPoint.immediate,
      ),
    );
    board.observe(
      const ViewStamp(
        threadId: 'thread',
        viewId: 'old',
        viewEpoch: 'old-epoch',
        version: 999,
      ),
    );
    expect(operation.state.value.observed, isFalse);
    board.observe(target);
    expect(operation.state.value.observed, isTrue);
  });

  test(
    'canonical patch rejects a stale owner without corrupting current value',
    () {
      final model = CanonicalReadModel<String>();
      const old = ResourceStamp(
        resourceKey: 'settings',
        ownerEpoch: 'a',
        revision: 50,
      );
      const fresh = ResourceStamp(
        resourceKey: 'settings',
        ownerEpoch: 'b',
        revision: 1,
      );
      model.replace(old, 'old');
      expect(model.replace(fresh, 'fresh'), isFalse);
      expect(model.replace(fresh, 'fresh', reset: true), isTrue);
      expect(
        model.patch(
          expected: old,
          next: const ResourceStamp(
            resourceKey: 'settings',
            ownerEpoch: 'a',
            revision: 51,
          ),
          reduce: (_) => 'corrupt',
        ),
        isFalse,
      );
      expect(model.state.value?.value, 'fresh');
    },
  );
}
