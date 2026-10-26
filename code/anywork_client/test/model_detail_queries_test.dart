import 'dart:async';

import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/models_exact_read_fixture.dart';

/// Exact account/model detail reads. The client keeps no detail cache: only
/// still-pending identical queries coalesce, every explicit query captures its
/// own native reference window, and the returned value keeps its original
/// value identity after the handle is gone.
final class _DetailsFixture {
  _DetailsFixture() {
    models = createModelsRepository(port: port, budget: budget).repository;
  }

  final port = ExactModelsPort();
  final budget = ResourceBudget();
  late final ModelsRepository models;
  final scopes = <ExactModelScope>[];

  int _nextOpen = 0;

  Future<ExactModelScope> opened() async {
    final opening = await port.openAt(_nextOpen++);
    expect(opening.target, exactModelTarget);
    final scope = ExactModelScope();
    scopes.add(scope);
    opening.reply.complete(scope);
    return scope;
  }

  Future<void> tearDown() async {
    port.refusePendingOpensForTeardown();
    for (final scope in scopes) {
      scope.releaseResponsesForTeardown();
    }
    final report = await models.retryCleanup();
    expect(report.unresolved, isEmpty);
    expect(budget.usage, isEmpty);
  }
}

void main() {
  test('pending exact queries dedupe while each explicit query opens a fresh window', () async {
    final fixture = _DetailsFixture();
    addTearDown(fixture.tearDown);

    final first = fixture.models.loadDelegationModel(exactModelTarget);
    expect(
      identical(fixture.models.loadDelegationModel(exactModelTarget), first),
      isTrue,
      reason: 'Only a still-pending identical query may be joined',
    );
    final scope = await fixture.opened();
    await scope.identityEntered.future;
    scope.headerReply.complete(exactModelHeader);
    final detail = await first;
    expect(detail.target, exactModelTarget);
    expect(detail.accountName, 'Original exact account');
    expect(detail.descriptor.modelId, exactModelTarget.model.modelId);
    expect(detail.performance.sampleCount, 7);
    expect(detail.performance.averageTtftMillis, 250);
    // 55 call samples cannot become task evaluations.
    expect(detail.recentEvaluations, isEmpty);
    expect(detail.evaluations.window, 10);
    expect(fixture.port.opens, hasLength(1));

    // The native handle is still the client's until it really joins.
    final closing = await scope.closed(0);
    expect(fixture.budget.used(ResourceKind.readModel), 1);
    closing.completeClean();

    // A settled query is not a cache: the next query captures a new window.
    final second = fixture.models.loadDelegationModel(exactModelTarget);
    expect(identical(second, first), isFalse);
    final replacement = await fixture.opened();
    await replacement.identityEntered.future;
    replacement.headerReply.complete(exactModelHeader);
    final again = await second;
    expect(again.target, exactModelTarget);
    expect(fixture.port.opens, hasLength(2));
    final replacementClose = await replacement.closed(0);
    replacementClose.completeClean();
    // The real permits are released by the owner's own join, which teardown
    // asserts after retryCleanup.
    await Future<void>.delayed(Duration.zero);
    expect(fixture.budget.usage, isEmpty);
  });

  test('a native detail for another model is refused and materializes nothing', () async {
    final fixture = _DetailsFixture();
    addTearDown(fixture.tearDown);

    final reading = fixture.models.loadDelegationModel(exactModelTarget);
    final scope = await fixture.opened();
    await scope.identityEntered.future;
    final refused = expectLater(
      reading,
      throwsA(
        isA<StudioFailure>().having(
          (StudioFailure failure) => failure.code,
          'code',
          StudioFailureCode.protocol,
        ),
      ),
    );
    scope.headerReply.complete(
      exactModelHeader.copyWith(
        descriptor: exactModelHeader.descriptor.copyWith(
          modelId: ReadText.inline(text: 'another-model'),
        ),
      ),
    );
    await refused;
    final closing = await scope.closed(0);
    closing.completeClean();
    // A wrong-account/model return never materializes a value: the client keeps
    // no detail cache, so the refused query leaves nothing to substitute.
    expect(fixture.port.opens, hasLength(1));
  });

  test(
    'close joins an in-flight detail query and refuses later ones',
    () async {
      final fixture = _DetailsFixture();
      addTearDown(fixture.tearDown);

      final reading = fixture.models.loadDelegationModel(exactModelTarget);
      final scope = await fixture.opened();
      await scope.identityEntered.future;
      final closed = fixture.models.close();
      var joined = false;
      unawaited(closed.then((_) => joined = true));
      await Future<void>.delayed(Duration.zero);
      // Dismissing a query never drops ownership of its real native read.
      expect(joined, isFalse);
      expect(fixture.budget.used(ResourceKind.readModel), 1);

      final failure = expectLater(reading, throwsA(isA<StudioFailure>()));
      scope.headerReply.complete(exactModelHeader);
      await failure;
      final closing = await scope.closed(0);
      closing.completeClean();
      final report = await closed;
      expect(report.unresolved, isEmpty);
      expect(joined, isTrue);
      expect(
        () => fixture.models.loadDelegationModel(exactModelTarget),
        throwsA(
          isA<StudioFailure>().having(
            (StudioFailure error) => error.code,
            'code',
            StudioFailureCode.cancelled,
          ),
        ),
      );
    },
  );
}
