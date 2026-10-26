import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/session_costs_test_port.dart';

/// Hang guard only: every wait is released by a scripted native reply or an
/// observable repository publication.
const _guard = Duration(seconds: 5);
const _origin = ProductReadOrigin(
  ownerEpoch: 'session-costs-native',
  incarnation: 1,
);

Matcher _code(StudioFailureCode code) =>
    isA<StudioFailure>().having((failure) => failure.code, 'code', code);

SessionCostsHeader _header({
  required SessionCostsReadRef reference,
  required bool hasCost,
  required bool? hasUnpricedUsage,
}) => SessionCostsHeader(
  revision: 1,
  updatedAt: 1769904000,
  statisticsPending: false,
  statisticsGap: false,
  readFailed: false,
  hasCost: hasCost,
  hasUnpricedUsage: hasUnpricedUsage,
  reference: reference,
);

SessionCost _cost(SessionCost? value) {
  expect(value, isNotNull);
  return value!;
}

SessionCost? _readyCost(ReadValue<SessionCost?, SessionCostsReadRef>? value) {
  if (value is! ReadyReadValue<SessionCost?, SessionCostsReadRef>) return null;
  return value.current.value;
}

void main() {
  test('each root borrow keeps its own native scope and state', () async {
    const referenceA = SessionCostsReadRef(entry: 21, revision: 1);
    const referenceB = SessionCostsReadRef(entry: 22, revision: 1);
    final port = ScriptedSessionCostsPort(origin: _origin);
    port.reads[referenceA] = SessionCostsReadScript(
      cost: const SessionCostRead(
        rootThreadId: ReadText.inline(text: 'root-a'),
        purposeCosts: TypedListRef(listId: 11, total: 1),
        estimatedCosts: TypedListRef(listId: 12, total: 1),
        hasUnpricedUsage: true,
      ),
      purposes: const {
        11: [
          PurposeCostRead(
            purpose: ReadText.inline(text: 'chat'),
            estimatedCosts: TypedListRef(listId: 13, total: 1),
            hasUnpricedUsage: true,
          ),
        ],
      },
      amounts: const {
        12: [
          RuntimeCostRead(currency: ReadText.inline(text: 'USD'), amount: 1.5),
        ],
        13: [
          RuntimeCostRead(currency: ReadText.inline(text: 'USD'), amount: 0.5),
        ],
      },
    );
    port.reads[referenceB] = SessionCostsReadScript(
      cost: const SessionCostRead(
        rootThreadId: ReadText.inline(text: 'root-b'),
        purposeCosts: TypedListRef(listId: 21, total: 0),
        estimatedCosts: TypedListRef(listId: 22, total: 1),
        hasUnpricedUsage: false,
      ),
      amounts: const {
        22: [
          RuntimeCostRead(currency: ReadText.inline(text: 'EUR'), amount: 2.5),
        ],
      },
    );
    final budget = ResourceBudget();
    final repository = createSessionCostsRepository(port: port, budget: budget);
    addTearDown(() async {
      final report = await repository.close(
        deadline: DateTime.now().add(_guard),
      );
      expect(report.complete, isTrue);
      expect(budget.usage, isEmpty);
    });

    final a = repository.costs('root-a');
    final b = repository.costs('root-b');
    expect(a.rootThreadId, 'root-a');
    expect(b.rootThreadId, 'root-b');
    expect(a.state.value.cost, isNull);
    expect(b.state.value.projection.sync.phase, ResourceSyncPhase.idle);

    final loadingA = a.load();
    final feedA = await port.feedFor('root-a').timeout(_guard);
    await feedA.listened.future.timeout(_guard);
    feedA.emit(
      sessionCostsBaseline(
        feedId: 'session-costs-root-a',
        origin: _origin,
        header: _header(
          reference: referenceA,
          hasCost: true,
          hasUnpricedUsage: true,
        ),
      ),
    );
    await feedA.acknowledged(1).timeout(_guard);
    await loadingA.timeout(_guard);

    final costA = _cost(_readyCost(a.state.value.cost));
    expect(costA.rootThreadId, 'root-a');
    expect(costA.hasUnpricedUsage, isTrue);
    expect(costA.estimatedCosts.single.currency, 'USD');
    expect(costA.estimatedCosts.single.amount, 1.5);
    expect(costA.purposeCosts.single.purpose, 'chat');
    expect(costA.purposeCosts.single.estimatedCosts.single.amount, 0.5);
    // The other borrow keeps its own scope and is not touched by that read.
    expect(port.feedOpens, ['root-a']);
    expect(b.state.value.cost, isNull);
    expect(b.state.value.projection.sync.phase, ResourceSyncPhase.idle);

    final loadingB = b.load();
    final feedB = await port.feedFor('root-b').timeout(_guard);
    await feedB.listened.future.timeout(_guard);
    feedB.emit(
      sessionCostsBaseline(
        feedId: 'session-costs-root-b',
        origin: _origin,
        header: _header(
          reference: referenceB,
          hasCost: true,
          hasUnpricedUsage: false,
        ),
      ),
    );
    await feedB.acknowledged(1).timeout(_guard);
    await loadingB.timeout(_guard);

    final costB = _cost(_readyCost(b.state.value.cost));
    expect(costB.rootThreadId, 'root-b');
    expect(costB.estimatedCosts.single.currency, 'EUR');
    expect(costB.estimatedCosts.single.amount, 2.5);
    expect(costB.purposeCosts, isEmpty);
    // Each borrow opened its own root-scoped feed and read scope.
    expect(port.feedOpens, ['root-a', 'root-b']);
    expect(port.readOpens.map((open) => open.reference), [
      referenceA,
      referenceB,
    ]);
    expect(_readyCost(a.state.value.cost)!.rootThreadId, 'root-a');
  });

  test(
    'a scope answering another root is a protocol failure, not that root cost',
    () async {
      const reference = SessionCostsReadRef(entry: 31, revision: 1);
      final port = ScriptedSessionCostsPort(origin: _origin);
      port.reads[reference] = SessionCostsReadScript(
        cost: const SessionCostRead(
          rootThreadId: ReadText.inline(text: 'root-other'),
          purposeCosts: TypedListRef(listId: 11, total: 0),
          estimatedCosts: TypedListRef(listId: 12, total: 0),
          hasUnpricedUsage: true,
        ),
      );
      final budget = ResourceBudget();
      final repository = createSessionCostsRepository(
        port: port,
        budget: budget,
      );
      addTearDown(() async {
        final report = await repository.close(
          deadline: DateTime.now().add(_guard),
        );
        expect(report.complete, isTrue);
        expect(budget.usage, isEmpty);
      });

      final query = repository.costs('root-a');
      final loading = query.load();
      final feed = await port.feedFor('root-a').timeout(_guard);
      await feed.listened.future.timeout(_guard);
      feed.emit(
        sessionCostsBaseline(
          feedId: 'session-costs-root-a',
          origin: _origin,
          header: _header(
            reference: reference,
            hasCost: true,
            hasUnpricedUsage: true,
          ),
        ),
      );
      await feed.acknowledged(1).timeout(_guard);

      await expectLater(
        loading.timeout(_guard),
        throwsA(_code(StudioFailureCode.protocol)),
      );
      final failed = query.state.value.cost;
      expect(failed, isA<FailedReadValue<SessionCost?, SessionCostsReadRef>>());
      final typed =
          failed! as FailedReadValue<SessionCost?, SessionCostsReadRef>;
      expect(typed.error.code, StudioFailureCode.protocol);
      expect(
        typed.previous,
        isNull,
        reason: 'The other root cost is never installed as this root value',
      );
      expect(query.state.value.projection.sync.phase, ResourceSyncPhase.ready);
    },
  );
}
