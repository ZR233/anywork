import 'dart:async';
import 'dart:math';

import '../../../lifecycle.dart' show ClientCloseBudget, ClientResourceId;
import '../../contracts/stamps.dart';
import '../../lifecycle/close_report.dart';
import '../../models/failure_models.dart' show StudioFailureCode;
import '../../observation/latest_value.dart';
import '../domain/statistics_failure.dart';
import '../domain/statistics_models.dart';
import '../domain/statistics_repository.dart';
import 'statistics_materializer.dart';
import '../statistics_ports.dart';

/// The sole statistics reducer for one application graph.
final class StatisticsRepositoryImpl implements StatisticsRepository {
  StatisticsRepositoryImpl({
    required StatisticsFeedPort feed,
    required String owner,
  }) : _feed = feed,
       _owner = owner,
       _state = LatestValue(const StatisticsRepositoryState());

  final StatisticsFeedPort _feed;
  final String _owner;
  final LatestValue<StatisticsRepositoryState> _state;
  final Map<int, _StatisticsAttempt> _attempts = {};
  final Map<ClientResourceId, UnresolvedResource> _unresolved = {};
  final String _resourceScopeId = _newResourceScopeId();

  int _nextAttemptId = 0;
  int _generation = 0;
  int _visibleDemands = 0;
  bool _readRequested = false;
  bool _closed = false;
  _StatisticsAttempt? _current;
  Future<CloseReport>? _closing;

  @override
  StatisticsRepositoryState get state => _state.value;

  @override
  StatisticsObservation observe(
    void Function(StatisticsRepositoryState state) listener,
  ) {
    final watch = _state.watchLatest(listener);
    return _StatisticsObservation(watch.value, watch.observation);
  }

  @override
  StatisticsVisibilityLease acquireVisibleDemand() {
    if (_closed) {
      throw StatisticsFailure.local(
        category: StatisticsFailureCategory.closed,
        code: StudioFailureCode.runtimeStopped,
        message: 'Statistics repository is closed',
        retryable: false,
      );
    }
    _visibleDemands++;
    if (_visibleDemands == 1) {
      _readRequested = true;
      _ensureRead();
    }
    return _StatisticsVisibilityLease(this);
  }

  @override
  void refresh() {
    if (_closed || _visibleDemands == 0) return;
    final current = _current;
    // A click during a read or its cleanup belongs to that same read. A failed cleanup may be
    // retried explicitly, but a replacement cannot start until that exact owner has settled.
    if (current != null &&
        (!current.retireRequested || current.retirement != null)) {
      return;
    }
    _readRequested = true;
    _ensureRead();
  }

  @override
  Future<CloseReport> close({ClientCloseBudget? budget}) =>
      _closing ??= _close(budget);

  Future<CloseReport> _close(ClientCloseBudget? budget) async {
    _closed = true;
    _visibleDemands = 0;
    _readRequested = false;
    for (final attempt in _attempts.values) {
      attempt.cancelled = true;
    }
    _publishConnection(StatisticsConnectionPhase.closing);

    // Close every admitted attempt before awaiting any one of them.
    final attempts = _attempts.values
        .where((attempt) => !attempt.settled)
        .toList();
    final work = [for (final attempt in attempts) _requestRetirement(attempt)];
    await _joinBounded(work, budget);
    return CloseReport(unresolved: _unresolved.values);
  }

  @override
  Future<CloseReport> retryCleanup({ClientCloseBudget? budget}) async {
    final unresolved = _attempts.values
        .where((attempt) => !attempt.settled && attempt.retireRequested)
        .toList();
    final work = [
      for (final attempt in unresolved) _requestRetirement(attempt),
    ];
    await _joinBounded(work, budget);
    return CloseReport(unresolved: _unresolved.values);
  }

  void _releaseDemand() {
    if (_visibleDemands == 0) return;
    _visibleDemands--;
    if (_visibleDemands != 0) return;
    _readRequested = false;
    final current = _current;
    if (current != null && !current.settled) {
      current.cancelled = true;
      _publishConnection(StatisticsConnectionPhase.closing);
      _superviseRetirement(current);
    } else {
      _publishConnection(StatisticsConnectionPhase.idle);
    }
  }

  void _ensureRead() {
    if (_closed || _visibleDemands == 0 || !_readRequested) return;
    final current = _current;
    if (current != null && !current.settled) {
      if (current.retireRequested) {
        _superviseRetirement(current);
        _publishConnection(StatisticsConnectionPhase.closing);
      }
      return;
    }
    _startAttempt();
  }

  void _startAttempt() {
    if (_closed || _visibleDemands == 0 || _current != null) return;
    _readRequested = false;
    final attemptId = ++_nextAttemptId;
    final generation = ++_generation;
    final attempt = _StatisticsAttempt(
      id: attemptId,
      generation: generation,
      resourceId: ClientResourceId(_resourceScopeId, attemptId),
    );
    _attempts[attemptId] = attempt;
    _current = attempt;
    attempt.opening = Future<void>.microtask(() async {
      if (_mustRetire(attempt)) return;
      await _openAttempt(attempt);
    });
    _publishConnection(
      _state.value.snapshot == null
          ? StatisticsConnectionPhase.connecting
          : StatisticsConnectionPhase.reconnecting,
    );
  }

  Future<void> _openAttempt(_StatisticsAttempt attempt) async {
    final StatisticsFeedConnection connection;
    try {
      connection = await _feed.open();
    } on Object catch (error) {
      final failure = StatisticsFailure.fromObject(
        error,
        category: StatisticsFailureCategory.connection,
      );
      attempt.failure = failure;
      // Even a failed open belongs to this generation until its registered opening future has
      // returned. Retirement joins it before a pending visible entry may open the next feed.
      if (!attempt.retireRequested) _superviseRetirement(attempt);
      return;
    }

    // Once open succeeds, keep the handle attached until retirement confirms close. A late
    // generation must retain the exact returned handle for cleanup.
    attempt.connection = connection;
    if (_mustRetire(attempt)) return;
    attempt.pump = _runPump(attempt);
    unawaited(attempt.pump!.then<void>((_) => _pumpFinished(attempt)));
  }

  Future<void> _runPump(_StatisticsAttempt attempt) async {
    final connection = attempt.connection!;
    try {
      await for (final event in connection.events()) {
        if (_mustRetire(attempt)) return;
        switch (event) {
          case StatisticsFeedBaseline(:final publication):
            if (publication.deliverySequence != 1) {
              throw _feedProtocolFailure(
                'baseline was duplicated or out of order',
              );
            }
            await _consumePublication(attempt, publication);
            // This GUI read owns only the baseline. Cancelling the stream iteration also drops
            // publications queued while the bounded materialization was in flight.
            return;
          case StatisticsFeedData(:final publication):
            throw _feedProtocolFailure(
              'data arrived before baseline (${publication.deliverySequence})',
            );
          case StatisticsFeedFailure(:final failure):
            throw failure;
          case StatisticsFeedClosed():
            throw StatisticsFailure.local(
              category: StatisticsFailureCategory.closed,
              code: StudioFailureCode.runtimeStopped,
              message: 'Statistics feed closed unexpectedly',
              retryable: true,
            );
        }
      }
    } on Object catch (error) {
      final failure = StatisticsFailure.fromObject(
        error,
        category: StatisticsFailureCategory.stream,
      );
      attempt.failure = failure;
      return;
    }
    if (!_mustRetire(attempt)) {
      final failure = StatisticsFailure.local(
        category: StatisticsFailureCategory.closed,
        code: StudioFailureCode.runtimeStopped,
        message: 'Statistics event stream ended without a terminal envelope',
        retryable: true,
      );
      attempt.failure = failure;
    }
  }

  Future<void> _consumePublication(
    _StatisticsAttempt attempt,
    StatisticsFeedIdentity publication,
  ) async {
    final connection = attempt.connection!;
    final scope = await connection.openScope(publication);
    attempt.scope = scope;
    if (_mustRetire(attempt)) return;
    // Every entry/refresh reads a complete fresh baseline, even when its revisions happen to
    // match the last read. Scope ownership stays on the attempt until close really succeeds.
    final materialized = await StatisticsMaterializer.read(
      scope: scope,
      publication: publication,
      previous: null,
      readSummaries: true,
      readHistory: true,
    );
    if (_mustRetire(attempt)) return;
    try {
      await connection.acknowledge(publication.deliverySequence);
    } on Object catch (error) {
      throw StatisticsFailure.fromObject(
        error,
        category: StatisticsFailureCategory.acknowledgement,
      );
    }
    if (_mustRetire(attempt)) return;
    attempt.snapshot = StatisticsSnapshot(
      ownerEpoch: publication.ownerEpoch,
      feedId: publication.feedId,
      publicationRevision: publication.publicationRevision,
      summariesRevision: publication.summariesRevision,
      historyRevision: publication.historyRevision,
      summaries: materialized.summaries,
      history: materialized.history,
      statisticsPending: publication.statisticsPending,
      statisticsGap: publication.statisticsGap,
      readFailed: publication.readFailed,
    );
  }

  StatisticsFailure _feedProtocolFailure(String diagnostic) =>
      StatisticsFailure.local(
        category: StatisticsFailureCategory.protocol,
        code: StudioFailureCode.protocol,
        message: 'Statistics source returned invalid feed metadata',
        retryable: false,
        details: {'diagnostic': diagnostic},
      );

  void _pumpFinished(_StatisticsAttempt attempt) {
    if (_mustRetire(attempt)) return;
    _superviseRetirement(attempt);
  }

  Future<void> _requestRetirement(_StatisticsAttempt attempt) {
    if (attempt.settled) return Future<void>.value();
    attempt.retireRequested = true;
    attempt.connection?.requestClose();
    final existing = attempt.retirement;
    if (existing != null) return existing;
    final task = Future<void>.microtask(() => _retireAttempt(attempt));
    attempt.retirement = task;
    return task;
  }

  void _superviseRetirement(_StatisticsAttempt attempt) {
    unawaited(
      _requestRetirement(attempt).catchError((Object _, StackTrace __) {
        // _retireAttempt has retained the original owner and published its cleanup failure.
      }),
    );
  }

  Future<void> _retireAttempt(_StatisticsAttempt attempt) async {
    try {
      final opening = attempt.opening;
      if (opening != null) await opening;
      if (attempt.settled) return;
      final connection = attempt.connection;
      if (connection != null) {
        connection.requestClose();
        final pump = attempt.pump;
        if (pump != null) await pump;
        final scope = attempt.scope;
        if (scope != null) {
          await scope.close();
          attempt.scope = null;
        }
        await connection.close();
      }
      _settleAttempt(attempt);
    } on Object catch (error) {
      final failure = StatisticsFailure.fromObject(
        error,
        category: StatisticsFailureCategory.cleanup,
      );
      attempt.failure = failure;
      _retainUnresolved(attempt, failure);
      attempt.retirement = null;
      if (!_closed && _visibleDemands > 0 && identical(_current, attempt)) {
        _publishConnection(StatisticsConnectionPhase.failed, failure: failure);
      }
      Error.throwWithStackTrace(failure, StackTrace.current);
    }
  }

  void _retainUnresolved(_StatisticsAttempt attempt, Object error) {
    final failure = StatisticsFailure.fromObject(
      error,
      category: StatisticsFailureCategory.cleanup,
    );
    _unresolved[attempt.resourceId] = UnresolvedResource(
      resourceId: attempt.resourceId,
      owner: _resourceOwner(attempt),
      attemptId: AttemptId(attempt.id),
      reason: failure,
    );
  }

  void _settleAttempt(_StatisticsAttempt attempt) {
    if (attempt.settled) return;
    // This terminal path is reached only after native close/join, or after open failed before a
    // connection handle existed. Only then can its unresolved record settle.
    attempt.settled = true;
    _attempts.remove(attempt.id);
    _unresolved.remove(attempt.resourceId);
    if (!identical(_current, attempt)) return;
    _current = null;
    if (_closed) return;
    if (_visibleDemands == 0) {
      _publishConnection(StatisticsConnectionPhase.idle);
    } else if (_readRequested) {
      _ensureRead();
    } else if (!attempt.cancelled) {
      final snapshot = attempt.snapshot;
      if (attempt.failure != null) {
        _publishConnection(
          StatisticsConnectionPhase.failed,
          failure: attempt.failure,
        );
      } else if (snapshot != null) {
        _state.publish(
          StatisticsRepositoryState(
            snapshot: snapshot,
            connection: const StatisticsConnectionState(
              phase: StatisticsConnectionPhase.ready,
            ),
          ),
        );
      }
    }
  }

  bool _mustRetire(_StatisticsAttempt attempt) =>
      _closed ||
      _visibleDemands == 0 ||
      attempt.cancelled ||
      attempt.retireRequested ||
      attempt.generation != _generation ||
      !identical(_current, attempt);

  void _publishConnection(
    StatisticsConnectionPhase phase, {
    StatisticsFailure? failure,
  }) {
    final current = _state.value;
    final next = StatisticsRepositoryState(
      snapshot: current.snapshot,
      connection: StatisticsConnectionState(phase: phase, failure: failure),
    );
    if (next != current) _state.publish(next);
  }

  String _resourceOwner(_StatisticsAttempt attempt) =>
      'statistics-feed:$_owner:${attempt.id}';

  Future<void> _joinBounded(
    List<Future<void>> work,
    ClientCloseBudget? budget,
  ) async {
    if (work.isEmpty) return;
    final joined = Future.wait<void>(work);
    try {
      if (budget == null) {
        await joined;
      } else {
        await joined.timeout(budget.remaining);
      }
    } on TimeoutException catch (error) {
      final failure = StatisticsFailure.fromObject(
        error,
        category: StatisticsFailureCategory.cleanup,
        retryable: true,
      );
      for (final attempt in _attempts.values.where(
        (attempt) => !attempt.settled,
      )) {
        _unresolved[attempt.resourceId] = UnresolvedResource(
          resourceId: attempt.resourceId,
          owner: _resourceOwner(attempt),
          attemptId: AttemptId(attempt.id),
          reason: failure,
        );
      }
    } on Object catch (error) {
      final failure = StatisticsFailure.fromObject(
        error,
        category: StatisticsFailureCategory.cleanup,
      );
      for (final attempt in _attempts.values.where(
        (attempt) => !attempt.settled,
      )) {
        _unresolved[attempt.resourceId] = UnresolvedResource(
          resourceId: attempt.resourceId,
          owner: _resourceOwner(attempt),
          attemptId: AttemptId(attempt.id),
          reason: failure,
        );
      }
    }
  }
}

final class _StatisticsAttempt {
  _StatisticsAttempt({
    required this.id,
    required this.generation,
    required this.resourceId,
  });

  final int id;
  final ClientResourceId resourceId;
  final int generation;
  StatisticsFeedConnection? connection;
  StatisticsReadScope? scope;
  StatisticsSnapshot? snapshot;
  Future<void>? opening;
  Future<void>? pump;
  Future<void>? retirement;
  StatisticsFailure? failure;
  bool retireRequested = false;
  bool cancelled = false;
  bool settled = false;
}

String _newResourceScopeId() {
  final random = Random.secure();
  final nonce = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'statistics-feed-$nonce';
}

final class _StatisticsObservation implements StatisticsObservation {
  _StatisticsObservation(this.initialState, this._observation);

  @override
  final StatisticsRepositoryState initialState;
  final Observation _observation;

  @override
  void cancel() => _observation.cancel();
}

final class _StatisticsVisibilityLease implements StatisticsVisibilityLease {
  _StatisticsVisibilityLease(this._repository);

  final StatisticsRepositoryImpl _repository;
  bool _released = false;

  @override
  bool get isReleased => _released;

  @override
  void release() {
    if (_released) return;
    _released = true;
    _repository._releaseDemand();
  }
}
