import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/models_exact_read_fixture.dart';

final class _Fixture {
  _Fixture({StudioFailure? metadataFailure})
    : scope = ExactModelScope(metadataFailure: metadataFailure) {
    models = createModelsRepository(port: port, budget: budget).repository;
    addTearDown(() async {
      port.refusePendingOpensForTeardown();
      scope.releaseResponsesForTeardown();
      final report = await models.retryCleanup();
      expect(
        report.unresolved,
        isEmpty,
        reason: 'The original exact scope must really join; teardown cannot waive a cleanup failure',
      );
      expect(budget.usage, isEmpty);
    });
  }

  final port = ExactModelsPort();
  final budget = ResourceBudget();
  final ExactModelScope scope;
  late final ModelsRepository models;

  Future<DelegationModelDetail> read() async {
    final reading = models.loadDelegationModel(exactModelTarget);
    final opening = await port.firstOpen.future;
    expect(opening.target, exactModelTarget);
    opening.reply.complete(scope);
    await scope.headerEntered.future;
    scope.headerReply.complete(exactModelHeader);
    return reading;
  }
}

void main() {
  test('public exact model read releases its original permit after native Clean even when full metadata is no longer readable', () async {
    final fixture = _Fixture();
    final detail = await fixture.read();
    expect(
      (
        detail.target,
        detail.scope,
        detail.accountName,
        detail.descriptor.modelId,
        detail.descriptor.displayName,
      ),
      (
        exactModelTarget,
        exactModelIdentity,
        'Original exact account',
        'exact-model',
        'Typed exact model',
      ),
    );
    expect(
      (
        detail.available,
        detail.performance.sampleCount,
        detail.evaluations.window,
        detail.recentEvaluations.isEmpty,
      ),
      (true, 7, 10, true),
    );
    final closing = await fixture.scope.closed(
      0,
    ); // Actual original native close has entered.
    expect(closing.scope, same(fixture.scope));
    expect(closing.retry, isFalse);
    expect(
      fixture.budget.used(ResourceKind.readModel),
      1,
      reason: 'A typed result is not proof that its original native scope has joined',
    );
    final joining = fixture.models.close();
    expect(() => fixture.scope.identity, throwsA(same(exactScopeClosed)));
    expect(() => fixture.scope.target, throwsA(same(exactScopeClosed)));
    closing.completeClean();
    final report = await joining;
    expect(report.unresolved, isEmpty);
    expect(fixture.scope.disposed, isTrue);
    expect(fixture.scope.scopeId, exactModelIdentity.scopeId);
    expect(() => fixture.scope.identity, throwsA(same(exactScopeClosed)));
    expect(() => fixture.scope.target, throwsA(same(exactScopeClosed)));
    expect(fixture.budget.used(ResourceKind.readModel), 0);
    expect(fixture.budget.usage, isEmpty);
    expect(fixture.port.opens, hasLength(1));
    expect(fixture.scope.closes, hasLength(1));
    expect(
      detail.scope,
      exactModelIdentity,
      reason: 'A materialized value outlives metadata query admission',
    );
  });

  test('unconvertible full exact descriptor remains the query failure while its raw original identity still permits real cleanup', () async {
    final fixture = _Fixture(metadataFailure: exactMetadataFailure);
    final reading = fixture.models.loadDelegationModel(exactModelTarget);
    final failed = expectLater(reading, throwsA(same(exactMetadataFailure)));
    final opening = await fixture.port.firstOpen.future;
    expect(opening.target, exactModelTarget);
    opening.reply.complete(fixture.scope);
    await fixture.scope.identityEntered.future;
    await failed;
    expect(
      fixture.scope.headerEntered.isCompleted,
      isFalse,
      reason: 'The full scope descriptor failed before any detail query, not before native open',
    );
    final closing = await fixture.scope.closed(0);
    expect(closing.scope, same(fixture.scope));
    expect(fixture.budget.used(ResourceKind.readModel), 1);
    final joining = fixture.models.close();
    closing.completeClean();
    expect(
      (await joining).unresolved,
      isEmpty,
      reason: 'A full descriptor conversion error is not an independent raw-close identity failure',
    );
    expect(fixture.scope.disposed, isTrue);
    expect(fixture.scope.scopeId, exactModelIdentity.scopeId);
    expect(fixture.scope.metadataFailure, same(exactMetadataFailure));
    await expectLater(
      reading,
      throwsA(same(exactMetadataFailure)),
      reason:
          'Successful cleanup cannot rewrite the original public query failure',
    );
    expect(fixture.budget.usage, isEmpty);
    expect(fixture.port.opens, hasLength(1));
    expect(fixture.scope.closes, hasLength(1));
    expect(fixture.scope.closes.single.retry, isFalse);
  });

  test('a foreign exact close report retains the original permit until explicit retry on the same closed scope', () async {
    final fixture = _Fixture();
    final detail = await fixture.read();
    final original = await fixture.scope.closed(0);
    expect(original.scope, same(fixture.scope));
    original.reply.complete(
      FeedCloseReport(
        feedId: 'foreign-exact-scope',
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    final report = await fixture.models.close();
    expect(report.complete, isFalse);
    final unresolved = report.unresolved.single;
    expect(unresolved.owner, 'models:exact-model-reference-read');
    final issue = unresolved.issues.single;
    expect(
      (issue.diagnostic.code, issue.diagnostic.correlationId, issue.recovery),
      (
        StudioFailureCode.protocol.name,
        'resources',
        CleanupRecovery.retryClose,
      ),
    );
    expect(
      fixture.budget.usage.map(
        (usage) => (usage.kind, usage.owner, usage.phase),
      ),
      [
        (
          ResourceKind.readModel,
          'models:exact-model-reference-read',
          ResourcePhase.unresolved,
        ),
      ],
    );
    expect(
      fixture.scope.disposed,
      isTrue,
      reason: 'Native Clean alone is not an SDK authorization to discharge a mismatched scope report',
    );
    expect(() => fixture.scope.identity, throwsA(same(exactScopeClosed)));
    final joining = fixture.models.retryCleanup();
    final retry = await fixture.scope.closed(1);
    expect(retry.scope, same(fixture.scope));
    expect(retry.retry, isTrue);
    expect(fixture.budget.used(ResourceKind.readModel), 1);
    retry.completeClean();
    expect((await joining).unresolved, isEmpty);
    expect(fixture.budget.usage, isEmpty);
    expect(fixture.port.opens, hasLength(1));
    expect(fixture.scope.closes, hasLength(2));
    expect(detail.scope, exactModelIdentity);
  });
}
