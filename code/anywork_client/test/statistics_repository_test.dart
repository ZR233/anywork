import 'dart:async';

import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/statistics.dart';
import 'package:anywork_client/statistics_ports.dart';
import 'package:test/test.dart';

import 'support/statistics_test_feed.dart';

void main() {
  test('request tier participates in immutable statistics content identity', () {
    const tiers = [
      null,
      'standard',
      'notApplicable',
      'tier:priority',
      'tier:ultrafast',
    ];
    final efforts = [
      for (final tier in tiers) _effort('high', requestedServiceTier: tier),
    ];
    final samples = [
      for (final tier in tiers) _sample(0, requestedServiceTier: tier),
    ];
    expect(efforts.toSet(), hasLength(tiers.length));
    expect(samples.toSet(), hasLength(tiers.length));
    for (var index = 0; index < tiers.length; index++) {
      final effort = _effort('high', requestedServiceTier: tiers[index]);
      final sample = _sample(0, requestedServiceTier: tiers[index]);
      expect(efforts[index], effort);
      expect(efforts[index].hashCode, effort.hashCode);
      expect(samples[index], sample);
      expect(samples[index].hashCode, sample.hashCode);
      for (var other = 0; other < index; other++) {
        expect(efforts[index], isNot(efforts[other]));
        expect(samples[index], isNot(samples[other]));
      }
      // Independent effort filtering must not turn into a combined-tier filter.
      expect(samples[index].effortKey, samples.first.effortKey);
      expect(
        samples[index].serviceTierKey,
        '[${tiers[index] == null ? 'null' : '"${tiers[index]}"'}]',
      );
    }
  });

  group('StatisticsRepository public behavior', () {
    test(
      'refresh always materializes a fresh baseline and coalesces busy clicks',
      () async {
        final pageGate = StatisticsTestGate();
        final ackGate = StatisticsTestGate();
        final closeGate = StatisticsTestGate();
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: _publication()),
          StatisticsConnectionPlan(
            initial: _publication(
              historyGate: pageGate,
              acknowledgementGate: ackGate,
            ),
            closeGate: closeGate,
          ),
        ]);
        final repository = _repository(port, 'refresh-same-revisions');
        repository.refresh();
        expect(port.openCalls, 0);
        final demand = repository.acquireVisibleDemand();
        final first = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        );
        repository.refresh();
        final connection = await port.waitForConnection(2);
        await pageGate.entered.future;
        expect(repository.state.snapshot, same(first.snapshot));
        expect(
          repository.state.connection.phase,
          StatisticsConnectionPhase.reconnecting,
        );
        repository.refresh();
        repository.refresh();
        pageGate.release.complete();
        await ackGate.entered.future;
        repository.refresh();
        expect(repository.state.snapshot, same(first.snapshot));
        ackGate.release.complete();
        await closeGate.entered.future;
        repository.refresh();
        expect(repository.state.snapshot, same(first.snapshot));
        expect(port.openCalls, 2);
        closeGate.release.complete();
        final refreshed = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        );
        expect(refreshed.snapshot, first.snapshot);
        expect(refreshed.snapshot, isNot(same(first.snapshot)));
        expect(connection.summaryOffsets, [0]);
        expect(connection.historyOffsets, [0]);
        expect(connection.acknowledgedSequences, [1]);
        expect(connection.isClosed, isTrue);
        expect(port.openCalls, 2);
        demand.release();
        repository.refresh();
        expect(
          repository.state.connection.phase,
          StatisticsConnectionPhase.idle,
        );
        expect(port.openCalls, 2);
        expect((await repository.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'a new visible entry reads again after the previous baseline settled',
      () async {
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: _publication(ownerEpoch: 'first')),
          StatisticsConnectionPlan(initial: _publication(ownerEpoch: 'second')),
        ]);
        final repository = _repository(port, 'entry');
        final first = repository.acquireVisibleDemand();
        await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        );
        first.release();
        first.release();
        expect(first.isReleased, isTrue);
        final second = repository.acquireVisibleDemand();
        final ready = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        );
        expect(ready.snapshot!.ownerEpoch, 'second');
        expect(port.openCalls, 2);
        second.release();
        expect((await repository.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'a late successful open is joined before reopening the hidden generation',
      () async {
        final openGate = StatisticsTestGate();
        final closeGate = StatisticsTestGate();
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(
            initial: _publication(ownerEpoch: 'late'),
            openGate: openGate,
            closeGate: closeGate,
          ),
          StatisticsConnectionPlan(
            initial: _publication(ownerEpoch: 'current'),
          ),
        ]);
        final repository = _repository(port, 'late-open');
        final first = repository.acquireVisibleDemand();
        await openGate.entered.future;
        first.release();
        final second = repository.acquireVisibleDemand();
        openGate.release.complete();
        await closeGate.entered.future;
        expect(repository.state.snapshot, isNull);
        expect(port.openCalls, 1);
        expect(port.connections.single.scopeOpenCalls, 0);
        closeGate.release.complete();
        final ready = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        );
        expect(ready.snapshot!.ownerEpoch, 'current');
        expect(port.connections.first.isClosed, isTrue);
        expect(port.connections.first.acknowledgedSequences, isEmpty);
        second.release();
        expect((await repository.close(budget: _budget())).complete, isTrue);
      },
    );

    for (final scenario in [
      (
        name: 'noninitial baseline sequence',
        plan: StatisticsConnectionPlan(initial: _publication(sequence: 2)),
        category: StatisticsFailureCategory.protocol,
      ),
      (
        name: 'data before baseline',
        plan: StatisticsConnectionPlan(
          initial: _publication(),
          initialEvent: StatisticsFeedData(_publication().identity),
        ),
        category: StatisticsFailureCategory.protocol,
      ),
      (
        name: 'close before baseline',
        plan: StatisticsConnectionPlan(
          initial: _publication(),
          initialEvent: const StatisticsFeedClosed(),
        ),
        category: StatisticsFailureCategory.closed,
      ),
      (
        name: 'stream end before baseline',
        plan: StatisticsConnectionPlan(
          initial: _publication(),
          endWithoutBaseline: true,
        ),
        category: StatisticsFailureCategory.closed,
      ),
      (
        name: 'page from a different feed',
        plan: StatisticsConnectionPlan(
          initial: _publication(pageFeedId: 'wrong-feed'),
        ),
        category: StatisticsFailureCategory.protocol,
      ),
      (
        name: 'ACK failure',
        plan: StatisticsConnectionPlan(
          initial: _publication(failAcknowledgement: true),
        ),
        category: StatisticsFailureCategory.acknowledgement,
      ),
    ]) {
      test(
        '${scenario.name} fails without publishing a partial snapshot',
        () async {
          final port = ControlledStatisticsFeedPort([scenario.plan]);
          final repository = _repository(port, scenario.name);
          final demand = repository.acquireVisibleDemand();
          final failed = await _waitForState(
            repository,
            (state) =>
                state.connection.phase == StatisticsConnectionPhase.failed,
          );
          expect(failed.snapshot, isNull);
          expect(failed.connection.failure!.category, scenario.category);
          expect(port.openCalls, 1);
          expect(port.connections.single.acknowledgedSequences, isEmpty);
          expect(port.connections.single.isClosed, isTrue);
          demand.release();
          expect((await repository.close(budget: _budget())).complete, isTrue);
        },
      );
    }

    test('scope close failure retains its exact owner through timeout and cleanup retry', () async {
      final scopeCloseGate = StatisticsTestGate();
      final port = ControlledStatisticsFeedPort([
        StatisticsConnectionPlan(
          initial: _publication(),
          scopeCloseFailures: 1,
          scopeCloseGate: scopeCloseGate,
        ),
      ]);
      final repository = _repository(port, 'scope-owner');
      final demand = repository.acquireVisibleDemand();
      final connection = await port.waitForConnection(1);
      await scopeCloseGate.entered.future;
      expect(repository.state.snapshot, isNull);
      expect(connection.acknowledgedSequences, [1]);
      expect(connection.closeCalls, 0);
      final timedOut = await repository.close(
        budget: ClientCloseBudget(Duration.zero),
      );
      expect(timedOut.complete, isFalse);
      expect(timedOut.unresolved, hasLength(1));
      final failedCleanup = repository.retryCleanup(budget: _budget());
      scopeCloseGate.release.complete();
      final failed = await failedCleanup;
      expect(failed.complete, isFalse);
      expect(
        failed.unresolved.single.resourceId,
        timedOut.unresolved.single.resourceId,
      );
      expect(connection.scopeCloseCalls, 1);
      expect(connection.closeCalls, 0);
      final cleaned = await repository.retryCleanup(budget: _budget());
      expect(cleaned.complete, isTrue);
      expect(connection.scopeCloseCalls, 2);
      expect(connection.closeCalls, 1);
      expect(connection.isClosed, isTrue);
      expect(port.openCalls, 1);
      expect(repository.state.snapshot, isNull);
      demand.release();
    });

    test('one visible read closes its feed before becoming ready', () async {
      final pageGate = StatisticsTestGate();
      final port = ControlledStatisticsFeedPort([
        StatisticsConnectionPlan(initial: _publication(historyGate: pageGate)),
      ]);
      final repository = _repository(port, 'one-read');
      final demand = repository.acquireVisibleDemand();
      final connection = await port.waitForConnection(1);
      await pageGate.entered.future;
      connection.emit(_publication(sequence: 2, publicationRevision: 2));
      pageGate.release.complete();
      await _waitForState(
        repository,
        (state) => state.connection.phase == StatisticsConnectionPhase.ready,
      );
      try {
        expect(connection.isClosed, isTrue);
        expect(repository.state.snapshot!.publicationRevision, 1);
        expect(connection.acknowledgedSequences, [1]);
        expect(connection.scopeOpenCalls, 1);
      } finally {
        demand.release();
        expect((await repository.close(budget: _budget())).complete, isTrue);
      }
    });

    test(
      'ready observation may refresh then close in the same callback',
      () async {
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: _publication()),
        ]);
        final repository = _repository(port, 'ready-refresh-close');
        final closing = Completer<CloseReport>();
        final observation = repository.observe((state) {
          if (state.connection.phase != StatisticsConnectionPhase.ready ||
              closing.isCompleted)
            return;
          expect(port.connections.single.isClosed, isTrue);
          repository.refresh();
          closing.complete(repository.close(budget: _budget()));
        });
        final demand = repository.acquireVisibleDemand();
        final report = await closing.future.timeout(const Duration(seconds: 5));
        expect(report.complete, isTrue);
        expect(port.openCalls, 1);
        expect(
          repository.state.connection.phase,
          StatisticsConnectionPhase.closing,
        );
        observation.cancel();
        demand.release();
      },
    );

    test(
      'materializes the complete bounded window once, including nested pages',
      () async {
        final summaries = List.generate(
          129,
          (index) =>
              _summaryItem('model-$index', effortCount: index == 0 ? 129 : 0),
        );
        final efforts = <int, Iterable<StatisticsEffortSummary>>{
          0: [
            for (var index = 0; index < 126; index++)
              _effort('high', requestedServiceTier: 'tier:custom-$index'),
            _effort('high', requestedServiceTier: 'standard'),
            _effort('high', requestedServiceTier: 'tier:priority'),
            _effort('high', requestedServiceTier: 'tier:ultrafast'),
          ],
        };
        final history = List.generate(
          3000,
          (index) => _sample(
            index,
            requestedServiceTier: switch (index % 3) {
              0 => 'standard',
              1 => 'tier:priority',
              _ => 'tier:ultrafast',
            },
          ),
        );
        final initial = _publication(
          summaries: summaries,
          history: history,
          efforts: efforts,
        );
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: initial),
        ]);
        final repository = _repository(port, 'materialize');
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
        expect(baseline.snapshot!.summaries.first.effortBreakdowns, efforts[0]);
        expect(baseline.snapshot!.history, history);
        expect(
          baseline.snapshot!.summaries.first.effortBreakdowns
              .skip(126)
              .map((item) => (item.effort, item.requestedServiceTier)),
          [
            ('high', 'standard'),
            ('high', 'tier:priority'),
            ('high', 'tier:ultrafast'),
          ],
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
        expect(connection.isClosed, isTrue);
        expect(
          () => baseline.snapshot!.history.clear(),
          throwsUnsupportedError,
        );
        expect(
          () => baseline.snapshot!.summaries.clear(),
          throwsUnsupportedError,
        );

        demand.release();
        expect((await repository.close(budget: _budget())).complete, isTrue);
      },
    );

    test(
      'a partial refresh failure keeps last-good until an explicit fresh read',
      () async {
        final initial = _publication(
          summaries: [_summaryItem('last-good')],
          history: [_sample(0, modelId: 'last-good')],
        );
        final failed = _publication(
          ownerEpoch: 'failed-owner',
          feedId: 'failed-feed',
          summaries: [_summaryItem('partial-new')],
          history: [_sample(1, modelId: 'partial-new')],
          failHistoryOffset: 0,
        );
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: initial),
          StatisticsConnectionPlan(initial: failed),
          StatisticsConnectionPlan(
            initial: _publication(ownerEpoch: 'recovered'),
          ),
        ]);
        final repository = _repository(port, 'last-good');
        final demand = repository.acquireVisibleDemand();
        final ready = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        );
        repository.refresh();
        expect(repository.state.snapshot, same(ready.snapshot));
        expect(
          repository.state.connection.phase,
          StatisticsConnectionPhase.reconnecting,
        );
        final connection = await port.waitForConnection(2);
        final failedState = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.failed,
        );
        expect(failedState.snapshot, same(ready.snapshot));
        expect(failedState.snapshot!.ownerEpoch, 'owner-1');
        expect(failedState.snapshot!.summaries.single.modelId, 'last-good');
        expect(connection.acknowledgedSequences, isEmpty);
        expect(connection.isClosed, isTrue);
        await expectLater(
          port.waitForOpenCall(3).timeout(const Duration(milliseconds: 500)),
          throwsA(isA<TimeoutException>()),
        );
        repository.refresh();
        final recovered = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        );
        expect(recovered.snapshot!.ownerEpoch, 'recovered');
        expect(port.openCalls, 3);
        demand.release();
        expect((await repository.close(budget: _budget())).complete, isTrue);
      },
    );

    test('hidden and reopened views join a late old-generation page before a fresh baseline', () async {
      final pageGate = StatisticsTestGate();
      final openGate = StatisticsTestGate();
      final port = ControlledStatisticsFeedPort([
        StatisticsConnectionPlan(
          initial: _publication(ownerEpoch: 'last-good'),
        ),
        StatisticsConnectionPlan(
          initial: _publication(
            ownerEpoch: 'old-in-flight',
            historyGate: pageGate,
          ),
        ),
        StatisticsConnectionPlan(
          initial: _publication(ownerEpoch: 'new-owner', feedId: 'new-feed'),
          openGate: openGate,
        ),
      ]);
      final repository = _repository(port, 'reopen');
      final firstDemand = repository.acquireVisibleDemand();
      final lastGood = await _waitForState(
        repository,
        (state) => state.connection.phase == StatisticsConnectionPhase.ready,
      );
      repository.refresh();
      final oldConnection = await port.waitForConnection(2);
      await pageGate.entered.future;
      firstDemand.release();
      final secondDemand = repository.acquireVisibleDemand();
      expect(port.openCalls, 2);
      expect(repository.state.snapshot, same(lastGood.snapshot));
      expect(
        repository.state.connection.phase,
        StatisticsConnectionPhase.closing,
      );
      pageGate.release.complete();
      await openGate.entered.future.timeout(const Duration(seconds: 5));
      expect(oldConnection.isClosed, isTrue);
      expect(oldConnection.acknowledgedSequences, isEmpty);
      expect(repository.state.snapshot, same(lastGood.snapshot));
      expect(
        repository.state.connection.phase,
        StatisticsConnectionPhase.reconnecting,
      );
      openGate.release.complete();
      final newReady = await _waitForState(
        repository,
        (state) =>
            state.connection.phase == StatisticsConnectionPhase.ready &&
            state.snapshot?.ownerEpoch == 'new-owner',
      );
      expect(newReady.snapshot!.feedId, 'new-feed');
      expect(port.connections.last.isClosed, isTrue);
      secondDemand.release();
      expect((await repository.close(budget: _budget())).complete, isTrue);
    });

    test(
      'close waits for an admitted feed open before releasing ownership',
      () async {
        final openGate = StatisticsTestGate();
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: _publication(), openGate: openGate),
        ]);
        final repository = _repository(port, 'close-opening');
        final demand = repository.acquireVisibleDemand();
        await port.waitForOpenCall(1).timeout(const Duration(seconds: 5));

        final closing = repository.close(budget: _budget());
        expect(
          repository.state.connection.phase,
          StatisticsConnectionPhase.closing,
        );
        openGate.release.complete();
        final report = await closing;
        demand.release();

        expect(report.complete, isTrue);
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
        final repository = _repository(port, 'connecting-close-reentry');
        Future<CloseReport>? closing;
        var closeFinished = false;
        var finishedAtReentry = true;
        final observation = repository.observe((state) {
          if (state.connection.phase != StatisticsConnectionPhase.connecting ||
              closing != null) {
            return;
          }
          closing = repository.close(budget: _budget());
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
        });

        final demand = repository.acquireVisibleDemand();
        final report = await closing!.timeout(const Duration(seconds: 5));
        demand.release();
        observation.cancel();

        expect(finishedAtReentry, isFalse);
        expect(report.complete, isTrue);
        expect(port.openCalls, 0);
        expect(port.connections, isEmpty);
      },
    );

    test(
      'connecting observation may refresh without opening a second feed',
      () async {
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: _publication()),
        ]);
        final repository = _repository(port, 'connecting-retry-reentry');
        var retried = false;
        final observation = repository.observe((state) {
          if (state.connection.phase == StatisticsConnectionPhase.connecting &&
              !retried) {
            retried = true;
            repository.refresh();
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
        expect(
          repository.state.connection.phase,
          StatisticsConnectionPhase.ready,
        );

        demand.release();
        expect((await repository.close(budget: _budget())).complete, isTrue);
        observation.cancel();
        expect(connection.isClosed, isTrue);
      },
    );

    test(
      'synchronous open callback close retains and closes the returned handle',
      () async {
        late StatisticsRepository repository;
        Future<CloseReport>? closing;
        final openEntered = Completer<void>();
        final closeRegistered = Completer<void>();
        var closeFinished = false;
        var closeFinishedAtOpenReentry = true;
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(
            initial: _publication(),
            onOpen: () {
              if (!openEntered.isCompleted) openEntered.complete();
              closing = repository.close(budget: _budget());
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
            },
          ),
        ]);
        repository = _repository(port, 'open-callback-close-reentry');
        final demand = repository.acquireVisibleDemand();

        await openEntered.future.timeout(const Duration(seconds: 5));
        await closeRegistered.future.timeout(const Duration(seconds: 5));
        final report = await closing!.timeout(const Duration(seconds: 5));
        final connection = port.connections.single;
        demand.release();

        expect(closeFinishedAtOpenReentry, isFalse);
        expect(report.complete, isTrue);
        expect(port.openCalls, 1);
        expect(connection.closeCalls, 1);
        expect(connection.isClosed, isTrue);
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
        final repository = _repository(port, 'open-failure-reopen');
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
        expect(
          repository.state.connection.phase,
          isNot(StatisticsConnectionPhase.closing),
        );

        reopenedDemand.release();
        expect((await repository.close(budget: _budget())).complete, isTrue);
        expect(identical(port.connections.single, reopenedConnection), isTrue);
      },
    );

    test('late open failure clears timeout unresolved state and releases its owner', () async {
      final openGate = StatisticsTestGate();
      final port = ControlledStatisticsFeedPort([
        StatisticsConnectionPlan(
          initial: _publication(),
          openGate: openGate,
          failOpen: true,
        ),
      ]);
      final repository = _repository(port, 'late-open-failure');
      final demand = repository.acquireVisibleDemand();
      await port.waitForOpenCall(1);
      await openGate.entered.future.timeout(const Duration(seconds: 5));

      final timedOut = await repository.close(
        budget: ClientCloseBudget(Duration.zero),
      );
      expect(timedOut.complete, isFalse);
      expect(timedOut.unresolved, hasLength(1));
      expect(port.openCalls, 1);

      openGate.release.complete();
      final cleaned = await repository.retryCleanup(budget: _budget());
      demand.release();

      expect(cleaned.complete, isTrue);
      expect(cleaned.unresolved, isEmpty);
      expect(
        repository.state.connection.phase,
        StatisticsConnectionPhase.closing,
      );
      expect(port.openCalls, 1);
      expect(port.connections, isEmpty);
    });

    test(
      'open failure waits for user refresh without automatic reconnection',
      () async {
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: _publication(), failOpen: true),
          StatisticsConnectionPlan(
            initial: _publication(ownerEpoch: 'recovered'),
          ),
        ]);
        final repository = _repository(port, 'no-auto-retry');
        final demand = repository.acquireVisibleDemand();
        final failed = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.failed,
        );
        expect(failed.snapshot, isNull);
        expect(
          failed.connection.failure!.category,
          StatisticsFailureCategory.connection,
        );
        await expectLater(
          port.waitForOpenCall(2).timeout(const Duration(milliseconds: 500)),
          throwsA(isA<TimeoutException>()),
        );
        repository.refresh();
        final ready = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        );
        expect(ready.snapshot!.ownerEpoch, 'recovered');
        expect(port.openCalls, 2);
        demand.release();
        expect((await repository.close(budget: _budget())).complete, isTrue);
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
        final repository = _repository(port, 'close-ack');
        final demand = repository.acquireVisibleDemand();
        final connection = await port.waitForConnection(1);
        await ackGate.entered.future.timeout(const Duration(seconds: 5));

        final closing = repository.close(budget: _budget());
        ackGate.release.complete();
        final report = await closing;
        demand.release();

        expect(report.complete, isTrue);
        expect(connection.acknowledgedSequences, [1]);
        expect(repository.state.snapshot, isNull);
      },
    );

    test('close joins an in-flight page before releasing ownership', () async {
      final pageGate = StatisticsTestGate();
      final port = ControlledStatisticsFeedPort([
        StatisticsConnectionPlan(initial: _publication(historyGate: pageGate)),
      ]);
      final repository = _repository(port, 'close-page');
      final demand = repository.acquireVisibleDemand();
      await port.waitForConnection(1);
      await pageGate.entered.future.timeout(const Duration(seconds: 5));

      final closing = repository.close(budget: _budget());
      expect(
        repository.state.connection.phase,
        StatisticsConnectionPhase.closing,
      );
      pageGate.release.complete();
      final report = await closing;
      demand.release();

      expect(report.complete, isTrue);
      expect(repository.state.snapshot, isNull);
    });

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
      final first = _repository(portA, 'graph-a');
      final second = _repository(portB, 'graph-b');
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
      expect(connectionA.isClosed, isTrue);
      secondDemand.release();
      await _waitForState(
        first,
        (state) => state.connection.phase == StatisticsConnectionPhase.idle,
      );
      expect(connectionA.isClosed, isTrue);
      expect(second.state.connection.phase, StatisticsConnectionPhase.ready);
      expect(connectionB.isClosed, isTrue);

      otherGraphDemand.release();
      expect((await first.close(budget: _budget())).complete, isTrue);
      expect((await second.close(budget: _budget())).complete, isTrue);
    });

    test(
      'unconfirmed close retains the same owner for explicit cleanup retry',
      () async {
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: _publication(), closeFailures: 2),
        ]);
        final repository = _repository(port, 'retry-close');
        final demand = repository.acquireVisibleDemand();
        final connection = await port.waitForConnection(1);
        await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.failed,
        );

        final unresolved = await repository.close(budget: _budget());
        expect(unresolved.complete, isFalse);
        expect(unresolved.unresolved, hasLength(1));
        final cleanupFailure = unresolved.unresolved.single.reason;
        expect(cleanupFailure, isA<StatisticsFailure>());
        final typedCleanupFailure = cleanupFailure as StatisticsFailure;
        expect(typedCleanupFailure.category, StatisticsFailureCategory.cleanup);
        expect(typedCleanupFailure.cause, isA<StateError>());
        expect(connection.closeCalls, 2);

        final retried = await repository.retryCleanup(budget: _budget());
        demand.release();
        expect(retried.complete, isTrue);
        expect(port.openCalls, 1);
        expect(identical(port.connections.single, connection), isTrue);
        expect(connection.closeCalls, 3);
      },
    );

    test(
      'refresh retries the same failed close before opening a replacement',
      () async {
        final closeGate = StatisticsTestGate();
        final port = ControlledStatisticsFeedPort([
          StatisticsConnectionPlan(initial: _publication()),
          StatisticsConnectionPlan(
            initial: _publication(ownerEpoch: 'discarded'),
            closeFailures: 2,
            closeGate: closeGate,
          ),
          StatisticsConnectionPlan(initial: _publication(ownerEpoch: 'fresh')),
        ]);
        final repository = _repository(port, 'refresh-cleanup');
        final demand = repository.acquireVisibleDemand();
        final lastGood = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        );
        repository.refresh();
        final connection = await port.waitForConnection(2);
        await closeGate.entered.future;
        expect(repository.state.snapshot, same(lastGood.snapshot));
        expect(
          repository.state.connection.phase,
          StatisticsConnectionPhase.reconnecting,
        );
        repository.refresh();
        repository.refresh();
        expect(port.openCalls, 2);
        closeGate.release.complete();
        final firstFailure = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.failed,
        );
        expect(firstFailure.snapshot, same(lastGood.snapshot));
        expect(connection.closeCalls, 1);
        repository.refresh();
        final secondFailure = await _waitForState(
          repository,
          (state) =>
              state.connection.phase == StatisticsConnectionPhase.failed &&
              state.connection.failure != firstFailure.connection.failure,
        );
        expect(secondFailure.snapshot, same(lastGood.snapshot));
        expect(connection.closeCalls, 2);
        expect(port.openCalls, 2);
        repository.refresh();
        final ready = await _waitForState(
          repository,
          (state) => state.connection.phase == StatisticsConnectionPhase.ready,
        );
        expect(ready.snapshot!.ownerEpoch, 'fresh');
        expect(connection.closeCalls, 3);
        expect(connection.isClosed, isTrue);
        expect(port.openCalls, 3);
        demand.release();
        expect((await repository.close(budget: _budget())).complete, isTrue);
      },
    );

    test('hide and reopen supervises repeated close failure without replacing the owner', () async {
      final port = ControlledStatisticsFeedPort([
        StatisticsConnectionPlan(initial: _publication(), closeFailures: 8),
      ]);
      final repository = _repository(port, 'hide-reopen-supervision');
      final firstDemand = repository.acquireVisibleDemand();
      final connection = await port.waitForConnection(1);
      await _waitForState(
        repository,
        (state) => state.connection.phase == StatisticsConnectionPhase.failed,
      );

      firstDemand.release();
      final hiddenCleanup = await repository.retryCleanup(budget: _budget());
      expect(hiddenCleanup.complete, isFalse);

      final reopenedDemand = repository.acquireVisibleDemand();
      final reopenedFailure = await _waitForState(
        repository,
        (state) =>
            state.connection.phase == StatisticsConnectionPhase.failed &&
            state.connection.failure?.category ==
                StatisticsFailureCategory.cleanup,
      );
      expect(reopenedFailure.snapshot, isNull);
      expect(connection.closeCalls, greaterThanOrEqualTo(2));
      expect(port.openCalls, 1);

      final closing = await repository.close(budget: _budget());
      expect(closing.complete, isFalse);
      reopenedDemand.release();
      final closeCallsBeforeCleanup = connection.closeCalls;
      connection.allowCloseToSucceed();
      final retried = await repository.retryCleanup(budget: _budget());

      expect(retried.complete, isTrue);
      expect(port.openCalls, 1);
      expect(identical(port.connections.single, connection), isTrue);
      expect(connection.closeCalls, closeCallsBeforeCleanup + 1);
    });
  });
}

StatisticsRepository _repository(StatisticsFeedPort feed, String owner) =>
    createStatisticsRepository(feed: feed, owner: owner);

ClientCloseBudget _budget() => ClientCloseBudget(const Duration(seconds: 5));

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
  String? pageFeedId,
  bool failAcknowledgement = false,
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
    pageFeedId: pageFeedId,
    failAcknowledgement: failAcknowledgement,
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

StatisticsEffortSummary _effort(
  String effort, {
  String? requestedServiceTier,
}) => StatisticsEffortSummary(
  effort: effort,
  requestedServiceTier: requestedServiceTier,
  sampleCount: 1,
  completionTokens: 1,
  totalTtftMillis: 1,
  ttftSampleCount: 1,
  totalResponseMillis: 2,
  tokensPerSecond: 500,
  averageTtftMillis: 1,
  averageResponseMillis: 2,
);

StatisticsSample _sample(
  int index, {
  String? modelId,
  String? requestedServiceTier,
}) => StatisticsSample(
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
  requestedServiceTier: requestedServiceTier,
  completionTokens: 20,
  ttftMillis: 40,
  decodeMillis: 160,
  totalResponseMillis: 200,
  tokensPerSecond: 100,
);
