import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

const _unknown = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'Connection lost after dispatch',
  retryable: true,
  correlationId: 'unknown-write',
);
const _rejected = StudioFailure(
  code: StudioFailureCode.conflict,
  message: 'The older request was rejected',
  retryable: false,
  correlationId: 'old-write',
);

void main() {
  test('terminal operations across distinct targets obey retention budget', () async {
    final budget = ResourceBudget();
    final registry = OperationRegistry(clientId: 'bounded', budget: budget, maxRetained: 3);
    final results = <Future<CommandResult<Unit>>>[];
    for (var index = 0; index < 30; index++) {
      final operation = registry.begin<Unit>(target: 'thread:$index');
      final ticket = operation.ticket;
      results.add(ticket.result);
      operation.accepted(const Unit(), CommitReceipt(
        operationId: ticket.id,
        disposition: CommitDisposition.noChange,
        targets: const [],
        effect: EffectPoint.immediate,
      ));
    }
    expect(await Future.wait(results), everyElement(isA<CommittedCommandResult<Unit>>()));
    expect(registry.observations.records.value, hasLength(3));
    expect(registry.observations.latest('thread:0'), isNull);
    expect(registry.observations.latest('thread:29'), isNotNull);
    expect(budget.used(ResourceKind.pendingOperation), 0);
  });

  test('paused observations retain one latest value and cancellation only detaches', () {
    final publisher = LatestValue(0);
    final source = publisher.readonly;
    final seen = <int>[];
    final subscription = source.watchLatest(seen.add);
    expect(subscription.value, 0);
    subscription.observation.pause();
    for (var value = 1; value <= 1000; value++) {
      publisher.publish(value);
    }
    expect(seen, isEmpty);
    subscription.observation.resume();
    expect(seen, [1000]);
    subscription.observation.cancel();
    publisher.publish(1001);
    expect(seen, [1000]);
    expect(source.value, 1001);
    expect(source.observerCount, 0);
    publisher.close();
  });

  test('watchLatest and waitFor observe updates adjacent to registration and reject stale reentrant predicates', () async {
    final publisher = LatestValue(2);
    final source = publisher.readonly;
    final seen = <int>[];
    final registration = source.watchLatest(seen.add);
    final waiting = source.waitFor((value) => value >= 3);
    publisher.publish(3);
    expect(registration.value, 2);
    expect(await waiting, 3);
    expect(seen, [3]);
    expect(await source.waitFor((value) => value == 3), 3);
    registration.observation.cancel();

    final reentrant = source.waitFor((value) {
      if (value == 3) {
        publisher.publish(4);
        return true; // This truth belongs to an obsolete publication.
      }
      return value == 5;
    });
    publisher.publish(5);
    expect(await reentrant, 5, reason: 'A predicate cannot settle a stale snapshot after reentry');
    expect(source.observerCount, 0);
    publisher.close();
  });

  test('receipt and owner frame can arrive in either order without losing Applied or trusting mutable target aliases', () async {
    for (final frameFirst in [true, false]) {
      final budget = ResourceBudget();
      final registry = OperationRegistry(clientId: 'app', budget: budget);
      final operation = registry.begin<Unit>(target: 'settings');
      final ticket = operation.ticket;
      const stamp = ResourceStamp(resourceKey: 'settings', ownerEpoch: 'epoch', revision: 12);
      final originalTargets = <ObservationStamp>[stamp];
      final receipt = CommitReceipt(
        operationId: ticket.id,
        disposition: CommitDisposition.applied,
        targets: originalTargets,
        effect: EffectPoint.nextTurn,
        durable: true,
      );
      originalTargets.clear();
      if (frameFirst) registry.observe(stamp);
      operation.accepted(const Unit(), receipt);
      if (!frameFirst) {
        expect(ticket.state.value.observed, isFalse,
            reason: 'Clearing the caller list cannot erase an observation obligation');
        expect(budget.used(ResourceKind.pendingOperation), 1);
        registry.observe(stamp);
      }
      expect(await ticket.result, CommandResult<Unit>.committed(value: const Unit(), receipt: receipt));
      expect(ticket.state.value.observed, isTrue);
      expect(ticket.state.value.receipt?.disposition, CommitDisposition.applied);
      expect(ticket.state.value.effective, isFalse);
      expect(ticket.state.value.durable, isTrue);
      expect(budget.used(ResourceKind.pendingOperation), 0);
    }
  });

  test('old outcomes do not clear a newer latest intent or rewrite an already delivered unknown result', () async {
    final budget = ResourceBudget();
    final registry = OperationRegistry(clientId: 'app', budget: budget);
    final old = registry.begin<Unit>(target: 'thread:model');
    final latest = registry.begin<Unit>(target: 'thread:model');
    final ticket = latest.ticket;
    latest.unknownOutcome(_unknown);
    old.rejected(_rejected);
    expect(registry.observations.latest('thread:model'), same(ticket));
    expect(ticket.state.value.failurePhase, OperationFailurePhase.unknownOutcome);
    expect(await ticket.result, const CommandResult<Unit>.unknownOutcome(error: _unknown));
    expect(budget.used(ResourceKind.pendingOperation), 1);
    latest.accepted(const Unit(), CommitReceipt(
      operationId: ticket.id,
      disposition: CommitDisposition.noChange,
      targets: const [],
      effect: EffectPoint.immediate,
    ));
    expect(ticket.state.value.observed, isTrue);
    expect(ticket.state.value.failurePhase, isNull);
    expect(await ticket.result, const CommandResult<Unit>.unknownOutcome(error: _unknown),
        reason: 'Later true evidence updates the same record, not the delivered result');
    expect(budget.used(ResourceKind.pendingOperation), 0);
  });

  test('different owner, view and stamp kind cannot satisfy another identity even when string keys collide', () async {
    final registry = OperationRegistry(clientId: 'app', budget: ResourceBudget());
    final operation = registry.begin<Unit>(target: 'chat');
    final ticket = operation.ticket;
    const target = ViewStamp(threadId: 'thread:a', viewId: 'view', viewEpoch: 'new-epoch', version: 1);
    operation.accepted(const Unit(), CommitReceipt(
      operationId: ticket.id,
      disposition: CommitDisposition.applied,
      targets: [target],
      effect: EffectPoint.immediate,
    ));
    for (final unrelated in <ObservationStamp>[
      const ViewStamp(threadId: 'thread:a', viewId: 'view', viewEpoch: 'old-epoch', version: 999),
      const ViewStamp(threadId: 'thread', viewId: 'a:view', viewEpoch: 'new-epoch', version: 999),
      ResourceStamp(resourceKey: target.resourceKey, ownerEpoch: target.viewEpoch, revision: 999),
    ]) {
      registry.observe(unrelated);
      expect(ticket.state.value.observed, isFalse,
          reason: 'Only the complete typed owner/view identity can discharge a receipt');
    }
    registry.observe(target);
    expect(await ticket.result, isA<CommittedCommandResult<Unit>>());
    expect(ticket.state.value.observed, isTrue);

    // Colliding but unrelated observations must not evict evidence already
    // registered for this exact typed identity before the next receipt arrives.
    registry.observe(const ViewStamp(
      threadId: 'thread', viewId: 'a:view', viewEpoch: 'new-epoch', version: 1000,
    ));
    registry.observe(ResourceStamp(
      resourceKey: target.resourceKey, ownerEpoch: target.viewEpoch, revision: 1000,
    ));
    final later = registry.begin<Unit>(target: 'chat:later-operation');
    later.accepted(const Unit(), CommitReceipt(
      operationId: later.ticket.id,
      disposition: CommitDisposition.applied,
      targets: [target],
      effect: EffectPoint.immediate,
    ));
    expect(later.ticket.state.value.observed, isTrue,
        reason: 'An unrelated stamp with the same rendered key cannot erase pre-observed evidence');
    expect(await later.ticket.result, isA<CommittedCommandResult<Unit>>());
  });

  // The removed writable canonical-helper regression is now exercised through
  // actual native baselines and an old-owner delta in model_catalog_lifecycle_test.
}
