import 'dart:async';

import 'package:anywork_client/statistics.dart';
import 'package:anywork_client/statistics_ports.dart';
import 'package:anywork_client/studio_client.dart'
    show ResourceBudget, ResourceKind, ResourcePhase;
import 'package:test/test.dart';

import 'support/statistics_test_feed.dart';

void main() {
  group('StatisticsRepository public behavior', () {
    test(
      'materializes every bounded page and reuses unchanged material',
      () async {
        final summaries = List.generate(
          129,
          (index) =>
              _summaryItem('model-$index', effortCount: index == 0 ? 129 : 0),
        );
        final efforts = <int, Iterable<StatisticsEffortSummary>>{
          0: List.generate(129, (index) => _effort('effort-$index')),
        };
        final history = List.generate(3000, (index) => _sample(index));
        final initial = _publication(
          summaries: summaries,
          history: history,
          efforts: efforts,
        );
        final statusOnly = _publication(
          sequence: 2,
          publicationRevision: 2,
          summariesRevision: initial.identity.summariesRevision,
          historyRevision: initial.identity.historyRevision,
          summaries: summaries,
          history: history,
          efforts: efforts,
          statisticsPending: true,
        );
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: initial),
        ]);
        final budget = ResourceBudget();
        final repository = _repository(port, budget, 'materialize');
        final demand = repository.acquireVisibleDemand();
        final connection = await port.waitForConnection(1);

        final baseline = await _waitForState(
          repository,
          (state) =>
              state.connection.phase == StatisticsConnectionPhase.ready &&
              state.snapshot?.publicationRevision == 1,
        );
        expect(baseline.snapshot!.summaries, hasLength(129));
        expect(baseline.snapshot!.history, hasLength(3000));
        expect(
          baseline.snapshot!.summaries.first.effortBreakdowns,
          hasLength(129),
        );
        expect(connection.summaryOffsets, [0, 128]);
        expect(connection.historyOffsets, [
          for (var offset = 0; offset < 3000; offset += 128) offset,
        ]);
        expect(
          connection.effortReads
              .where((read) => read.$1 == 0)
              .map((read) => read.$2),
          [0, 128],
        );
        expect(connection.acknowledgedSequences, [1]);
        final materialReads = (
          connection.scopeOpenCalls,
          connection.summaryOffsets.length,
          connection.historyOffsets.length,
          connection.effortReads.length,
        );

        connection.emit(statusOnly);
        final statusUpdate = await _waitForState(
          repository,
          (state) =>
              state.connection.phase == StatisticsConnectionPhase.ready &&
              state.snapshot?.publicationRevision == 2,
        );
        expect(statusUpdate.snapshot!.statisticsPending, isTrue);
        expect(
          statusUpdate.snapshot!.summaries,
          same(baseline.snapshot!.summaries),
        );
        expect(
          statusUpdate.snapshot!.history,
          same(baseline.snapshot!.history),
        );
        expect(
          () => statusUpdate.snapshot!.history.clear(),
          throwsUnsupportedError,
        );
        expect(
          () => statusUpdate.snapshot!.summaries.clear(),
          throwsUnsupportedError,
        );
        final republished = baseline.snapshot!.withPublication(
          statusOnly.identity,
        );
        expect(republished.history, same(baseline.snapshot!.history));
        expect(republished.summaries, same(baseline.snapshot!.summaries));
        expect((
          connection.scopeOpenCalls,
          connection.summaryOffsets.length,
          connection.historyOffsets.length,
          connection.effortReads.length,
        ), materialReads);
        expect(connection.acknowledgedSequences, [1, 2]);

        final changedHistory = [_sample(500)];
        connection.emit(
          _publication(
            sequence: 3,
            publicationRevision: 3,
            historyRevision: 2,
            summaries: summaries,
            history: changedHistory,
            efforts: efforts,
          ),
        );
        final changed = await _waitForState(
          repository,
          (state) => state.snapshot?.publicationRevision == 3,
        );
        expect(changed.snapshot!.summaries, same(baseline.snapshot!.summaries));
        expect(
          changed.snapshot!.history,
          isNot(same(baseline.snapshot!.history)),
        );
        expect(changed.snapshot!.history.single.callId, 'call-500');
        expect(baseline.snapshot!.history, hasLength(3000));
        expect(connection.acknowledgedSequences, [1, 2, 3]);

        demand.release();
        expect(
          (await repository.close(deadline: _deadline())).complete,
          isTrue,
        );
      },
    );

    test('a partial page failure keeps the last complete snapshot', () async {
      final initial = _publication(
        summaries: [_summaryItem('last-good')],
        history: [_sample(0, modelId: 'last-good')],
      );
      final failed = _publication(
        sequence: 2,
        publicationRevision: 2,
        summariesRevision: 2,
        historyRevision: 2,
        summaries: [_summaryItem('partial-new')],
        history: [_sample(1, modelId: 'partial-new')],
        failHistoryOffset: 0,
      );
      final port = ControlledStatisticsFeedPort([
        StatisticsConnectionPlan(initial: initial),
      ]);
      final repository = _repository(port, ResourceBudget(), 'last-good');
      final demand = repository.acquireVisibleDemand();
      final connection = await port.waitForConnection(1);
      final ready = await _waitForState(
        repository,
        (state) => state.connection.phase == StatisticsConnectionPhase.ready,
      );

      connection.emit(failed);
      final failedState = await _waitForState(
        repository,
        (state) =>
            state.connection.phase == StatisticsConnectionPhase.reconnecting &&
            state.snapshot?.publicationRevision == 1,
      );
      expect(failedState.snapshot, ready.snapshot);
      expect(failedState.snapshot!.summaries.single.modelId, 'last-good');
      expect(connection.acknowledgedSequences, [1]);

      demand.release();
      expect((await repository.close(deadline: _deadline())).complete, isTrue);
    });

    test(
      'hidden and reopened views discard a late old-generation page',
      () async {
        final pageGate = StatisticsTestGate();
        final initial = _publication(
          ownerEpoch: 'owner-old',
          feedId: 'feed-old',
          summaries: [_summaryItem('old-owner')],
          history: [_sample(0, modelId: 'old-owner')],
        );
        final lateOldPublication = _publication(
          ownerEpoch: 'owner-old',
          feedId: 'feed-old',
          sequence: 2,
          publicationRevision: 2,
          summariesRevision: 2,
          historyRevision: 2,
          summaries: [_summaryItem('late-old')],
          history: [_sample(1, modelId: 'late-old')],
          historyGate: pageGate,
        );
        final openGate = StatisticsTestGate();
        final reopened = _publication(
          ownerEpoch: 'owner-new',
          feedId: 'feed-new',
          summaries: [_summaryItem('new-owner')],
          history: [_sample(2, modelId: 'new-owner')],
        );
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: initial),
          StatisticsConnectionPlan(initial: reopened, openGate: openGate),
        ]);
        final repository = _repository(port, ResourceBudget(), 'reopen');
        final firstDemand = repository.acquireVisibleDemand();
        final oldConnection = await port.waitForConnection(1);
        final oldReady = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        );

        oldConnection.emit(lateOldPublication);
        await pageGate.entered.future.timeout(const Duration(seconds: 5));
        firstDemand.release();
        final secondDemand = repository.acquireVisibleDemand();
        pageGate.release.complete();

        final reconnecting = await _waitForState(
          repository,
          (state) =>
              state.connection.phase ==
                  StatisticsConnectionPhase.reconnecting &&
              state.snapshot?.ownerEpoch == 'owner-old',
        );
        expect(reconnecting.snapshot, oldReady.snapshot);
        expect(reconnecting.snapshot!.summaries.single.modelId, 'old-owner');
        await port.waitForOpenCall(2).timeout(const Duration(seconds: 5));
        await openGate.entered.future.timeout(const Duration(seconds: 5));
        expect(
          repository.state.connection.phase,
          StatisticsConnectionPhase.reconnecting,
        );
        expect(
          repository.state.snapshot!.summaries.single.modelId,
          'old-owner',
        );

        openGate.release.complete();
        final newConnection = await port
            .waitForConnection(2)
            .timeout(const Duration(seconds: 5));
        final newReady = await _waitForState(
          repository,
          (state) =>
              state.connection.phase == StatisticsConnectionPhase.ready &&
              state.snapshot?.ownerEpoch == 'owner-new',
        );
        expect(newReady.snapshot!.summaries.single.modelId, 'new-owner');
        expect(oldConnection.acknowledgedSequences, [1]);
        expect(oldConnection.scopeOpenCalls, 2);
        expect(newConnection.scopeOpenCalls, 1);

        secondDemand.release();
        expect(
          (await repository.close(deadline: _deadline())).complete,
          isTrue,
        );
      },
    );

    test(
      'close waits for an admitted feed open before releasing its permit',
      () async {
        final openGate = StatisticsTestGate();
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: _publication(), openGate: openGate),
        ]);
        final budget = ResourceBudget();
        final repository = _repository(port, budget, 'close-opening');
        final demand = repository.acquireVisibleDemand();
        expect(budget.used(ResourceKind.observer), 1);
        await port.waitForOpenCall(1).timeout(const Duration(seconds: 5));

        final closing = repository.close(deadline: _deadline());
        expect(
          repository.state.connection.phase,
          StatisticsConnectionPhase.closing,
        );
        expect(budget.used(ResourceKind.observer), 1);
        openGate.release.complete();
        final report = await closing;
        demand.release();

        expect(report.complete, isTrue);
        expect(budget.used(ResourceKind.observer), 0);
        expect(repository.state.snapshot, isNull);
        expect(port.connections.single.isClosed, isTrue);
      },
    );

    test(
      'connecting observation may close without losing registered startup work',
      () async {
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: _publication()),
        ]);
        final budget = ResourceBudget();
        final repository = _repository(
          port,
          budget,
          'connecting-close-reentry',
        );
        Future<CloseReport>? closing;
        var closeFinished = false;
        var finishedAtReentry = true;
        var permitsAtReentry = 0;
        final observation = repository.observe((state) {
          if (state.connection.phase != StatisticsConnectionPhase.connecting ||
              closing != null) {
            return;
          }
          closing = repository.close(deadline: _deadline());
          unawaited(
            closing!.then<void>(
              (_) {
                closeFinished = true;
              },
              onError: (Object _, StackTrace __) {
                closeFinished = true;
              },
            ),
          );
          finishedAtReentry = closeFinished;
          permitsAtReentry = budget.used(ResourceKind.observer);
        });

        final demand = repository.acquireVisibleDemand();
        final report = await closing!.timeout(const Duration(seconds: 5));
        demand.release();
        observation.cancel();

        expect(finishedAtReentry, isFalse);
        expect(permitsAtReentry, 1);
        expect(report.complete, isTrue);
        expect(port.openCalls, 0);
        expect(port.connections, isEmpty);
        expect(budget.used(ResourceKind.observer), 0);
      },
    );

    test(
      'connecting observation may retry without leaving the repository closing',
      () async {
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: _publication()),
        ]);
        final budget = ResourceBudget();
        final repository = _repository(
          port,
          budget,
          'connecting-retry-reentry',
        );
        var retried = false;
        final observation = repository.observe((state) {
          if (state.connection.phase == StatisticsConnectionPhase.connecting &&
              !retried) {
            retried = true;
            repository.retry();
          }
        });
        final demand = repository.acquireVisibleDemand();

        final call = port.waitForOpenCall(1);
        await call.timeout(const Duration(seconds: 5));
        final connection = await port
            .waitForConnection(1)
            .timeout(const Duration(seconds: 5));
        final ready = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        );

        expect(retried, isTrue);
        expect(ready.snapshot, isNotNull);
        expect(port.openCalls, 1);
        expect(budget.used(ResourceKind.observer), 1);
        expect(
          repository.state.connection.phase,
          StatisticsConnectionPhase.ready,
        );

        demand.release();
        expect(
          (await repository.close(deadline: _deadline())).complete,
          isTrue,
        );
        observation.cancel();
        expect(connection.isClosed, isTrue);
        expect(budget.used(ResourceKind.observer), 0);
      },
    );

    test(
      'synchronous open callback close retains and closes the returned handle',
      () async {
        late StatisticsRepository repository;
        Future<CloseReport>? closing;
        final budget = ResourceBudget();
        final openEntered = Completer<void>();
        final closeRegistered = Completer<void>();
        var permitsAtOpenReentry = 0;
        var closeFinished = false;
        var closeFinishedAtOpenReentry = true;
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(
            initial: _publication(),
            onOpen: () {
              if (!openEntered.isCompleted) openEntered.complete();
              closing = repository.close(deadline: _deadline());
              unawaited(
                closing!.then<void>(
                  (_) {
                    closeFinished = true;
                  },
                  onError: (Object _, StackTrace __) {
                    closeFinished = true;
                  },
                ),
              );
              if (!closeRegistered.isCompleted) closeRegistered.complete();
              closeFinishedAtOpenReentry = closeFinished;
              permitsAtOpenReentry = budget.used(ResourceKind.observer);
            },
          ),
        ]);
        repository = _repository(port, budget, 'open-callback-close-reentry');
        final demand = repository.acquireVisibleDemand();

        await openEntered.future.timeout(const Duration(seconds: 5));
        await closeRegistered.future.timeout(const Duration(seconds: 5));
        final report = await closing!.timeout(const Duration(seconds: 5));
        final connection = port.connections.single;
        demand.release();

        expect(closeFinishedAtOpenReentry, isFalse);
        expect(permitsAtOpenReentry, 1);
        expect(report.complete, isTrue);
        expect(port.openCalls, 1);
        expect(connection.closeCalls, 1);
        expect(connection.isClosed, isTrue);
        expect(budget.used(ResourceKind.observer), 0);
      },
    );

    test(
      'open failure after hide and immediate reopen honors the latest demand',
      () async {
        final openGate = StatisticsTestGate();
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(
            initial: _publication(ownerEpoch: 'owner-open-fails'),
            openGate: openGate,
            failOpen: true,
          ),
          StatisticsConnectionPlan(
            initial: _publication(
              ownerEpoch: 'owner-after-reopen',
              feedId: 'feed-after-reopen',
            ),
          ),
        ]);
        final budget = ResourceBudget(capacities: {ResourceKind.observer: 1});
        final repository = _repository(port, budget, 'open-failure-reopen');
        final firstDemand = repository.acquireVisibleDemand();
        await port.waitForOpenCall(1);
        await openGate.entered.future.timeout(const Duration(seconds: 5));

        firstDemand.release();
        final reopenedDemand = repository.acquireVisibleDemand();
        openGate.release.complete();

        await port.waitForOpenCall(2).timeout(const Duration(seconds: 5));
        final reopenedConnection = await port
            .waitForConnection(1)
            .timeout(const Duration(seconds: 5));
        final reopened = await _waitForState(
          repository,
          (state) =>
              state.connection.phase == StatisticsConnectionPhase.ready &&
              state.snapshot?.ownerEpoch == 'owner-after-reopen',
        );

        expect(reopened.snapshot!.feedId, 'feed-after-reopen');
        expect(port.openCalls, 2);
        expect(port.connections, hasLength(1));
        expect(budget.used(ResourceKind.observer), 1);
        expect(
          repository.state.connection.phase,
          isNot(StatisticsConnectionPhase.closing),
        );

        reopenedDemand.release();
        expect(
          (await repository.close(deadline: _deadline())).complete,
          isTrue,
        );
        expect(identical(port.connections.single, reopenedConnection), isTrue);
        expect(budget.used(ResourceKind.observer), 0);
      },
    );

    test('late open failure clears timeout unresolved state and releases its permit', () async {
      final openGate = StatisticsTestGate();
      final port = ControlledStatisticsFeedPort([
        StatisticsConnectionPlan(
          initial: _publication(),
          openGate: openGate,
          failOpen: true,
        ),
      ]);
      final budget = ResourceBudget(capacities: {ResourceKind.observer: 1});
      final repository = _repository(port, budget, 'late-open-failure');
      final demand = repository.acquireVisibleDemand();
      await port.waitForOpenCall(1);
      await openGate.entered.future.timeout(const Duration(seconds: 5));

      final timedOut = await repository.close(deadline: DateTime.now());
      expect(timedOut.complete, isFalse);
      expect(timedOut.unresolved, hasLength(1));
      expect(budget.used(ResourceKind.observer), 1);
      expect(port.openCalls, 1);

      openGate.release.complete();
      final cleaned = await repository.retryCleanup(deadline: _deadline());
      demand.release();

      expect(cleaned.complete, isTrue);
      expect(cleaned.unresolved, isEmpty);
      expect(
        repository.state.connection.phase,
        StatisticsConnectionPhase.closing,
      );
      expect(port.openCalls, 1);
      expect(port.connections, isEmpty);
      expect(budget.used(ResourceKind.observer), 0);
    });

    test(
      'an unexpectedly closed feed exhausts five total connection attempts',
      () async {
        final port = ControlledStatisticsFeedPort([
          for (var attempt = 1; attempt <= 5; attempt++)
            StatisticsConnectionPlan(
              initial: _publication(
                ownerEpoch: 'owner-$attempt',
                feedId: 'feed-$attempt',
              ),
              closeAfterBaseline: true,
            ),
        ]);
        final budget = ResourceBudget();
        final repository = _repository(port, budget, 'finite-retry');
        final demand = repository.acquireVisibleDemand();

        final failed = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.failed,
        );
        expect(failed.snapshot, isNotNull);
        expect(failed.connection.failure, isNotNull);
        expect(port.openCalls, 5);
        expect(port.connections, hasLength(5));
        expect(
          port.connections.map(
            (connection) => connection.acknowledgedSequences,
          ),
          everyElement([1]),
        );

        // The retry policy's last possible backoff is shorter than this bound. Waiting on the
        // open event (rather than sleeping) distinguishes a terminal fifth attempt from a queued
        // sixth connection while still allowing the real timer to fire.
        await expectLater(
          port.waitForOpenCall(6).timeout(const Duration(seconds: 5)),
          throwsA(isA<TimeoutException>()),
        );
        expect(port.openCalls, 5);

        demand.release();
        expect(
          (await repository.close(deadline: _deadline())).complete,
          isTrue,
        );
        expect(budget.used(ResourceKind.observer), 0);
      },
    );

    test(
      'close joins an in-flight ACK and does not publish its late result',
      () async {
        final ackGate = StatisticsTestGate();
        final publication = _publication(acknowledgementGate: ackGate);
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: publication),
        ]);
        final budget = ResourceBudget();
        final repository = _repository(port, budget, 'close-ack');
        final demand = repository.acquireVisibleDemand();
        final connection = await port.waitForConnection(1);
        await ackGate.entered.future.timeout(const Duration(seconds: 5));

        final closing = repository.close(deadline: _deadline());
        expect(budget.used(ResourceKind.observer), 1);
        ackGate.release.complete();
        final report = await closing;
        demand.release();

        expect(report.complete, isTrue);
        expect(connection.acknowledgedSequences, [1]);
        expect(repository.state.snapshot, isNull);
        expect(budget.used(ResourceKind.observer), 0);
      },
    );

    test(
      'close joins an in-flight page before releasing its observer permit',
      () async {
        final pageGate = StatisticsTestGate();
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(
            initial: _publication(historyGate: pageGate),
          ),
        ]);
        final budget = ResourceBudget();
        final repository = _repository(port, budget, 'close-page');
        final demand = repository.acquireVisibleDemand();
        await port.waitForConnection(1);
        await pageGate.entered.future.timeout(const Duration(seconds: 5));

        final closing = repository.close(deadline: _deadline());
        expect(budget.used(ResourceKind.observer), 1);
        expect(
          repository.state.connection.phase,
          StatisticsConnectionPhase.closing,
        );
        pageGate.release.complete();
        final report = await closing;
        demand.release();

        expect(report.complete, isTrue);
        expect(budget.used(ResourceKind.observer), 0);
        expect(repository.state.snapshot, isNull);
      },
    );

    test('visibility leases are shared per instance but repositories stay isolated', () async {
      final portA = ControlledStatisticsFeedPort([
        StatisticsConnectionPlan(
          initial: _publication(feedId: 'feed-a', ownerEpoch: 'owner-a'),
        ),
      ]);
      final portB = ControlledStatisticsFeedPort([
        StatisticsConnectionPlan(
          initial: _publication(feedId: 'feed-b', ownerEpoch: 'owner-b'),
        ),
      ]);
      final budgetA = ResourceBudget();
      final budgetB = ResourceBudget();
      final first = _repository(portA, budgetA, 'graph-a');
      final second = _repository(portB, budgetB, 'graph-b');
      final firstDemand = first.acquireVisibleDemand();
      final secondDemand = first.acquireVisibleDemand();
      final otherGraphDemand = second.acquireVisibleDemand();
      final connectionA = await portA.waitForConnection(1);
      final connectionB = await portB.waitForConnection(1);
      final initialObservation = first.observe((_) {});
      expect(initialObservation.initialState.snapshot, isNull);
      initialObservation.cancel();
      await Future.wait([
        _waitForState(
          first,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        ),
        _waitForState(
          second,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        ),
      ]);
      expect(first.state.snapshot!.feedId, 'feed-a');
      expect(second.state.snapshot!.feedId, 'feed-b');

      firstDemand.release();
      expect(connectionA.closeRequested, isFalse);
      expect(budgetA.used(ResourceKind.observer), 1);
      secondDemand.release();
      await _waitForState(
        first,
        (state) => state.connection.phase == StatisticsConnectionPhase.idle,
      );
      expect(connectionA.isClosed, isTrue);
      expect(budgetA.used(ResourceKind.observer), 0);
      expect(second.state.connection.phase, StatisticsConnectionPhase.ready);
      expect(connectionB.closeRequested, isFalse);
      expect(budgetB.used(ResourceKind.observer), 1);

      otherGraphDemand.release();
      expect((await first.close(deadline: _deadline())).complete, isTrue);
      expect((await second.close(deadline: _deadline())).complete, isTrue);
      expect(budgetB.used(ResourceKind.observer), 0);
    });

    test(
      'unconfirmed close retains the same owner for explicit cleanup retry',
      () async {
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: _publication(), closeFailures: 1),
        ]);
        final budget = ResourceBudget();
        final repository = _repository(port, budget, 'retry-close');
        final demand = repository.acquireVisibleDemand();
        final connection = await port.waitForConnection(1);
        await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        );

        final unresolved = await repository.close(deadline: _deadline());
        expect(unresolved.complete, isFalse);
        expect(unresolved.unresolved, hasLength(1));
        final cleanupFailure = unresolved.unresolved.single.reason;
        expect(cleanupFailure, isA<StatisticsFailure>());
        final typedCleanupFailure = cleanupFailure as StatisticsFailure;
        expect(typedCleanupFailure.category, StatisticsFailureCategory.cleanup);
        expect(typedCleanupFailure.cause, isA<StateError>());
        expect(budget.used(ResourceKind.observer), 1);
        expect(budget.usage.single.phase, ResourcePhase.unresolved);
        expect(connection.closeCalls, 1);

        final retried = await repository.retryCleanup(deadline: _deadline());
        demand.release();
        expect(retried.complete, isTrue);
        expect(port.openCalls, 1);
        expect(identical(port.connections.single, connection), isTrue);
        expect(connection.closeCalls, 2);
        expect(budget.used(ResourceKind.observer), 0);
      },
    );

    test('retry supervises repeated native close failures and cleanup keeps the same feed', () async {
      final port = ControlledStatisticsFeedPort([
        StatisticsConnectionPlan(initial: _publication(), closeFailures: 3),
      ]);
      final budget = ResourceBudget();
      final repository = _repository(port, budget, 'retry-supervision');
      final demand = repository.acquireVisibleDemand();
      final connection = await port.waitForConnection(1);
      await _waitForState(
        repository,
        (state) => state.connection.phase == StatisticsConnectionPhase.ready,
      );

      // The Settings retry affordance calls this public repository operation. Both failed
      // retirement futures must be supervised and retained instead of escaping the UI callback.
      repository.retry();
      final firstFailure = await _waitForState(
        repository,
        (state) =>
            state.connection.phase == StatisticsConnectionPhase.failed &&
            state.connection.failure?.category ==
                StatisticsFailureCategory.cleanup,
      );
      expect(connection.closeCalls, 1);
      expect(port.openCalls, 1);
      expect(budget.used(ResourceKind.observer), 1);

      repository.retry();
      final secondFailure = await _waitForState(
        repository,
        (state) =>
            state.connection.phase == StatisticsConnectionPhase.failed &&
            state.connection.failure?.category ==
                StatisticsFailureCategory.cleanup &&
            state.connection.failure?.correlationId !=
                firstFailure.connection.failure?.correlationId,
      );
      expect(secondFailure.connection.failure, isNotNull);
      expect(connection.closeCalls, 2);
      expect(port.openCalls, 1);
      expect(budget.used(ResourceKind.observer), 1);

      final closing = await repository.close(deadline: _deadline());
      expect(closing.complete, isFalse);
      demand.release();
      final retried = await repository.retryCleanup(deadline: _deadline());

      expect(retried.complete, isTrue);
      expect(port.openCalls, 1);
      expect(identical(port.connections.single, connection), isTrue);
      expect(connection.closeCalls, 4);
      expect(budget.used(ResourceKind.observer), 0);
    });

    test('hide and reopen supervises repeated close failure without replacing the owner', () async {
      final port = ControlledStatisticsFeedPort([
        StatisticsConnectionPlan(initial: _publication(), closeFailures: 8),
      ]);
      final budget = ResourceBudget();
      final repository = _repository(port, budget, 'hide-reopen-supervision');
      final firstDemand = repository.acquireVisibleDemand();
      final connection = await port.waitForConnection(1);
      await _waitForState(
        repository,
        (state) => state.connection.phase == StatisticsConnectionPhase.ready,
      );

      firstDemand.release();
      final hiddenCleanup = await repository.retryCleanup(
        deadline: _deadline(),
      );
      expect(hiddenCleanup.complete, isFalse);
      expect(budget.used(ResourceKind.observer), 1);

      final reopenedDemand = repository.acquireVisibleDemand();
      final reopenedFailure = await _waitForState(
        repository,
        (state) =>
            state.connection.phase == StatisticsConnectionPhase.failed &&
            state.connection.failure?.category ==
                StatisticsFailureCategory.cleanup,
      );
      expect(reopenedFailure.snapshot, isNotNull);
      expect(connection.closeCalls, greaterThanOrEqualTo(2));
      expect(port.openCalls, 1);
      expect(budget.used(ResourceKind.observer), 1);

      final closing = await repository.close(deadline: _deadline());
      expect(closing.complete, isFalse);
      reopenedDemand.release();
      final closeCallsBeforeCleanup = connection.closeCalls;
      connection.allowCloseToSucceed();
      final retried = await repository.retryCleanup(deadline: _deadline());

      expect(retried.complete, isTrue);
      expect(port.openCalls, 1);
      expect(identical(port.connections.single, connection), isTrue);
      expect(connection.closeCalls, closeCallsBeforeCleanup + 1);
      expect(budget.used(ResourceKind.observer), 0);
    });
  });
}

StatisticsRepository _repository(
  StatisticsFeedPort feed,
  ResourceBudget budget,
  String owner,
) => createStatisticsRepository(feed: feed, budget: budget, owner: owner);

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));

Future<StatisticsRepositoryState> _waitForState(
  StatisticsRepository repository,
  bool Function(StatisticsRepositoryState) predicate,
) async {
  final completer = Completer<StatisticsRepositoryState>();
  final observation = repository.observe((state) {
    if (!completer.isCompleted && predicate(state)) completer.complete(state);
  });
  if (predicate(observation.initialState)) {
    observation.cancel();
    return observation.initialState;
  }
  try {
    return await completer.future.timeout(const Duration(seconds: 5));
  } finally {
    observation.cancel();
  }
}

StatisticsPublicationFixture _publication({
  String ownerEpoch = 'owner-1',
  String feedId = 'feed-1',
  int sequence = 1,
  int publicationRevision = 1,
  int summariesRevision = 1,
  int historyRevision = 1,
  Iterable<StatisticsSummaryPageItem>? summaries,
  Iterable<StatisticsSample>? history,
  Map<int, Iterable<StatisticsEffortSummary>> efforts = const {},
  bool statisticsPending = false,
  bool statisticsGap = false,
  bool readFailed = false,
  StatisticsTestGate? summaryGate,
  StatisticsTestGate? historyGate,
  StatisticsTestGate? effortGate,
  StatisticsTestGate? acknowledgementGate,
  int? failHistoryOffset,
}) {
  final summaryItems = summaries?.toList() ?? [_summaryItem('model-1')];
  final historyItems = history?.toList() ?? [_sample(0)];
  return StatisticsPublicationFixture(
    identity: StatisticsFeedIdentity(
      ownerEpoch: ownerEpoch,
      feedId: feedId,
      deliverySequence: sequence,
      publicationRevision: publicationRevision,
      summariesRevision: summariesRevision,
      historyRevision: historyRevision,
      summaryCount: summaryItems.length,
      historyCount: historyItems.length,
      statisticsPending: statisticsPending,
      statisticsGap: statisticsGap,
      readFailed: readFailed,
    ),
    summaries: summaryItems,
    history: historyItems,
    efforts: efforts,
    summaryGate: summaryGate,
    historyGate: historyGate,
    effortGate: effortGate,
    acknowledgementGate: acknowledgementGate,
    failHistoryOffset: failHistoryOffset,
  );
}

StatisticsSummaryPageItem _summaryItem(String modelId, {int effortCount = 0}) =>
    StatisticsSummaryPageItem(
      accountId: 'account-$modelId',
      accountDisplayName: 'Account $modelId',
      modelId: modelId,
      sampleCount: 1,
      completionTokens: 20,
      totalTtftMillis: 40,
      ttftSampleCount: 1,
      totalResponseMillis: 200,
      tokensPerSecond: 100,
      averageTtftMillis: 40,
      averageResponseMillis: 200,
      effortCount: effortCount,
    );

StatisticsEffortSummary _effort(String effort) => StatisticsEffortSummary(
  effort: effort,
  sampleCount: 1,
  completionTokens: 1,
  totalTtftMillis: 1,
  ttftSampleCount: 1,
  totalResponseMillis: 2,
  tokensPerSecond: 500,
  averageTtftMillis: 1,
  averageResponseMillis: 2,
);

StatisticsSample _sample(int index, {String? modelId}) => StatisticsSample(
  threadId: 'thread-statistics',
  callId: 'call-$index',
  purpose: 'primary',
  firstOutputSource: FirstOutputSource.incremental,
  usageStatus: UsageReportStatus.reported,
  ttftAvailability: MetricAvailability.available,
  throughputAvailability: MetricAvailability.available,
  completedAt: DateTime.utc(2026, 3, 1).add(Duration(seconds: index)),
  accountId: 'account-$index',
  accountDisplayName: 'Account $index',
  modelId: modelId ?? 'model-$index',
  sentModel: modelId ?? 'model-$index',
  reportedModel: modelId ?? 'model-$index',
  modelMatchState: StatisticsModelMatchState.matched,
  effort: 'high',
  completionTokens: 20,
  ttftMillis: 40,
  decodeMillis: 160,
  totalResponseMillis: 200,
  tokensPerSecond: 100,
);
