import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/conversation_fixture.dart';
import 'support/timeline_transport.dart';

({ConversationFixture fixture, ResourcePermit pressure}) _blocked() {
  final budget = ResourceBudget(capacities: {
    ...ResourceBudget().capacities,
    ResourceKind.readModel: 2,
  });
  final fixture = ConversationFixture(budget: budget);
  final pressure = budget.acquire(ResourceKind.readModel, owner: 'test-activation-pressure');
  addTearDown(() async {
    pressure.release();
    final report = await fixture.repository.close(
      deadline: DateTime.now().add(const Duration(seconds: 3)));
    expect(report.unresolved, isEmpty);
    expect(budget.usage, isEmpty);
  });
  return (fixture: fixture, pressure: pressure);
}

Future<ConversationSession> _completeSelected(ConversationFixture fixture, String threadId) async {
  final session = fixture.repository.active.value!;
  expect(session.threadId, threadId);
  session.timeline.attachConsumer((_) {});
  final request = await fixture.timeline.opened(0);
  expect(request.threadId, threadId);
  final connection = TimelineConnectionProbe(TestTimelineConnection(
    initial: baseline(1, subscriptionId: 'activated-$threadId',
      items: [timelineItem(1, threadId: threadId)])));
  request.result.complete(connection);
  await session.timeline.ready;
  await connection.acknowledged(1);
  return session;
}

Matcher _failure(StudioFailureCode code) => isA<StudioFailure>().having(
  (failure) => failure.code, 'code', code,
);

void main() {
  test('Session budget rejection is visible for the original demand and explicit retry does not select again', () async {
    final blocked = _blocked();
    final fixture = blocked.fixture;
    fixture.demand.select(threadId: 'A', needsOpen: false, selectionGeneration: 4);
    final failed = fixture.repository.activationFailure.value!;
    expect(failed.threadId, 'A');
    expect(failed.selectionGeneration, 4);
    expect(failed.error, _failure(StudioFailureCode.overloaded));
    expect(failed.error.details, isA<ResourceLimitFailureDetails>());
    expect((failed.error.details as ResourceLimitFailureDetails).resource, 'readModel');
    expect(fixture.repository.active.value, isNull);
    expect(fixture.repository.existingSession('A'), isNull);
    expect(fixture.context.metadataRequests, isEmpty);
    expect(fixture.timeline.requests, isEmpty);
    expect(fixture.budget.used(ResourceKind.readModel), 2,
      reason: 'Rejected construction cannot strand another Session permit');
    blocked.pressure.release();
    fixture.repository.retryActivation(threadId: 'A', selectionGeneration: 4);
    expect(fixture.repository.activationFailure.value, isNull);
    final session = await _completeSelected(fixture, 'A');
    fixture.repository.retryActivation(threadId: 'A', selectionGeneration: 4);
    fixture.demand.select(threadId: 'A', needsOpen: false, selectionGeneration: 4);
    expect(fixture.repository.active.value, same(session));
    expect(fixture.repository.existingSession('A'), same(session));
    expect(fixture.context.metadataRequests, ['A']);
    expect(fixture.timeline.requests, hasLength(1));
    expect(fixture.operations.observations.records.value, isEmpty,
      reason: 'Retrying activation does not replay a business command');
  });

  test('a synchronous replacement during failure publication owns the visible failure slot', () {
    final blocked = _blocked();
    final fixture = blocked.fixture;
    final seen = <String>[];
    final observation = fixture.repository.activationFailure.watch((failure) {
      if (failure == null) return;
      seen.add(failure.threadId);
      if (failure.threadId == 'A') {
        fixture.demand.select(threadId: 'B', needsOpen: false, selectionGeneration: 2);
      }
    });
    addTearDown(observation.cancel);
    fixture.demand.select(threadId: 'A', needsOpen: false, selectionGeneration: 1);
    expect(seen, ['A', 'B']);
    expect(fixture.repository.activationFailure.value!.threadId, 'B');
    expect(fixture.repository.activationFailure.value!.selectionGeneration, 2);
    expect(() => fixture.repository.retryActivation(threadId: 'A', selectionGeneration: 1),
      throwsA(_failure(StudioFailureCode.superseded)));
    expect(fixture.repository.active.value, isNull);
    expect(fixture.context.metadataRequests, isEmpty);
    expect(fixture.timeline.requests, isEmpty);
    expect(fixture.budget.used(ResourceKind.readModel), 2);
  });

  test('retry clearing cannot activate its old target after a reentrant selection replacement', () async {
    final blocked = _blocked();
    final fixture = blocked.fixture;
    fixture.demand.select(threadId: 'A', needsOpen: false, selectionGeneration: 1);
    expect(fixture.repository.activationFailure.value!.threadId, 'A');
    final observation = fixture.repository.activationFailure.watch((failure) {
      if (failure == null) {
        fixture.demand.select(threadId: 'B', needsOpen: false, selectionGeneration: 2);
      }
    });
    addTearDown(observation.cancel);
    blocked.pressure.release();
    fixture.repository.retryActivation(threadId: 'A', selectionGeneration: 1);
    final current = await _completeSelected(fixture, 'B');
    expect(fixture.repository.active.value, same(current));
    expect(fixture.repository.existingSession('A'), isNull);
    expect(fixture.repository.activationFailure.value, isNull);
    expect(fixture.context.metadataRequests, ['B']);
    expect(fixture.timeline.requests, hasLength(1));
    expect(() => fixture.repository.retryActivation(threadId: 'A', selectionGeneration: 1),
      throwsA(_failure(StudioFailureCode.superseded)));
  });

  test('needsOpen and seal invalidate activation failure without opening or replaying the Thread', () {
    final blocked = _blocked();
    final fixture = blocked.fixture;
    fixture.demand.select(threadId: 'A', needsOpen: false, selectionGeneration: 1);
    expect(fixture.repository.activationFailure.value, isNotNull);
    fixture.demand.select(threadId: 'A', needsOpen: true, selectionGeneration: 1);
    expect(fixture.repository.activationFailure.value, isNull);
    expect(() => fixture.repository.retryActivation(threadId: 'A', selectionGeneration: 1),
      throwsA(_failure(StudioFailureCode.superseded)));
    fixture.demand.select(threadId: 'A', needsOpen: false, selectionGeneration: 2);
    expect(fixture.repository.activationFailure.value!.selectionGeneration, 2);
    fixture.repository.seal();
    expect(fixture.repository.activationFailure.value, isNull);
    expect(() => fixture.repository.retryActivation(threadId: 'A', selectionGeneration: 2),
      throwsA(_failure(StudioFailureCode.cancelled)));
    expect(fixture.repository.active.value, isNull);
    expect(fixture.context.metadataRequests, isEmpty);
    expect(fixture.timeline.requests, isEmpty);
  });

  test('direct borrow and invalid-generation errors never become selected activation failures', () {
    final blocked = _blocked();
    final fixture = blocked.fixture;
    expect(() => fixture.repository.session('unselected'),
      throwsA(_failure(StudioFailureCode.overloaded)));
    expect(() => fixture.demand.select(threadId: 'A', needsOpen: false, selectionGeneration: -1),
      throwsA(_failure(StudioFailureCode.invalidArgument)));
    expect(fixture.repository.activationFailure.value, isNull);
    expect(fixture.repository.active.value, isNull);
    expect(fixture.repository.existingSession('unselected'), isNull);
    expect(fixture.budget.used(ResourceKind.readModel), 2);
    expect(fixture.context.metadataRequests, isEmpty);
    expect(fixture.timeline.requests, isEmpty);
  });
}
