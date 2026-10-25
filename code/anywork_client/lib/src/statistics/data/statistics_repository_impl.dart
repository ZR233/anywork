import 'dart:async';

import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart';
import '../../models/failure_models.dart' show StudioFailureCode;
import '../../observation/latest_value.dart';
import '../domain/statistics_failure.dart';
import '../domain/statistics_models.dart';
import '../domain/statistics_repository.dart';
import 'statistics_materializer.dart';
import '../statistics_ports.dart';

const _maximumReconnectAttempts = 5;
const _initialReconnectDelay = Duration(milliseconds: 250);
const _maximumReconnectDelay = Duration(seconds: 5);
const _stableConnectionWindow = Duration(seconds: 10);

/// The sole statistics reducer for one application graph.
final class StatisticsRepositoryImpl implements StatisticsRepository {
  StatisticsRepositoryImpl({
    required StatisticsFeedPort feed,
    required ResourceBudget budget,
    required String owner,
  }) : _feed = feed,
       _budget = budget,
       _owner = owner,
       _state = LatestValue(const StatisticsRepositoryState());

  final StatisticsFeedPort _feed;
  final ResourceBudget _budget;
  final String _owner;
  final LatestValue<StatisticsRepositoryState> _state;
  final Map<int, _StatisticsAttempt> _attempts = {};
  final Map<String, UnresolvedResource> _unresolved = {};

  int _nextAttemptId = 0;
  int _generation = 0;
  int _visibleDemands = 0;
  int _reconnectAttempts = 0;
  bool _closed = false;
  _StatisticsAttempt? _current;
  Timer? _retryTimer;
  Timer? _stabilityTimer;
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
    if (_visibleDemands == 1) _ensureConnected();
    return _StatisticsVisibilityLease(this);
  }

  @override
  void retry() {
    if (_closed || _visibleDemands == 0) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _reconnectAttempts = 0;
    final current = _current;
    if (current == null) {
      _ensureConnected();
      return;
    }
    if (!current.settled) {
      _superviseRetirement(current, reconnectWhenSettled: true);
    }
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) =>
      _closing ??= _close(deadline);

  Future<CloseReport> _close(DateTime? deadline) async {
    _closed = true;
    _visibleDemands = 0;
    _retryTimer?.cancel();
    _stabilityTimer?.cancel();
    _publishConnection(StatisticsConnectionPhase.closing);

    // Close every admitted attempt before awaiting any one of them.
    final attempts = _attempts.values
        .where((attempt) => !attempt.settled)
        .toList();
    final work = [for (final attempt in attempts) _requestRetirement(attempt)];
    await _joinBounded(work, deadline);
    return CloseReport(unresolved: _unresolved.values);
  }

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) async {
    final unresolved = _attempts.values
        .where((attempt) => !attempt.settled && attempt.retireRequested)
        .toList();
    final work = [
      for (final attempt in unresolved) _requestRetirement(attempt),
    ];
    await _joinBounded(work, deadline);
    return CloseReport(unresolved: _unresolved.values);
  }

  void _releaseDemand() {
    if (_visibleDemands == 0) return;
    _visibleDemands--;
    if (_visibleDemands != 0) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _stabilityTimer?.cancel();
    final current = _current;
    if (current != null && !current.settled) {
      _publishConnection(StatisticsConnectionPhase.closing);
      _superviseRetirement(current);
    } else {
      _publishConnection(StatisticsConnectionPhase.idle);
    }
  }

  void _ensureConnected() {
    if (_closed || _visibleDemands == 0) return;
    final current = _current;
    if (current != null && !current.settled) {
      if (current.retireRequested) {
        _superviseRetirement(current, reconnectWhenSettled: true);
      }
      return;
    }
    if (_retryTimer != null) return;
    _startAttempt();
  }

  void _startAttempt() {
    if (_closed || _visibleDemands == 0 || _current != null) return;
    final attemptId = ++_nextAttemptId;
    final generation = ++_generation;
    final ResourcePermit permit;
    try {
      permit = _budget.acquire(
        ResourceKind.observer,
        owner: 'statistics:$_owner',
        phase: ResourcePhase.opening,
      );
    } on ResourceBudgetExceeded catch (error) {
      _publishConnection(
        StatisticsConnectionPhase.failed,
        failure: StatisticsFailure.fromObject(
          error,
          category: StatisticsFailureCategory.resourceBudget,
        ),
      );
      return;
    } on Object catch (error) {
      _publishConnection(
        StatisticsConnectionPhase.failed,
        failure: StatisticsFailure.fromObject(
          error,
          category: StatisticsFailureCategory.connection,
        ),
      );
      return;
    }

    final attempt = _StatisticsAttempt(
      id: attemptId,
      generation: generation,
      permit: permit,
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
      _releaseUnopenedAttempt(attempt, failure);
      return;
    }

    // Once open succeeds, keep the handle attached until retirement confirms close. A late
    // generation must not release the permit as if opening had failed.
    attempt.connection = connection;
    if (_mustRetire(attempt)) return;
    try {
      attempt.permit.mark(ResourcePhase.active);
      attempt.pump = _runPump(attempt);
      unawaited(attempt.pump!.then<void>((_) => _pumpFinished(attempt)));
    } on Object catch (error) {
      final failure = StatisticsFailure.fromObject(
        error,
        category: StatisticsFailureCategory.connection,
      );
      attempt.failure = failure;
      if (!_mustRetire(attempt)) {
        _publishConnection(_nextReconnectPhase(), failure: failure);
      }
      _superviseRetirement(
        attempt,
        reconnectWhenSettled: !_closed && _visibleDemands > 0,
      );
    }
  }

  Future<void> _runPump(_StatisticsAttempt attempt) async {
    final connection = attempt.connection!;
    var baselineReceived = false;
    var deliverySequence = 0;
    try {
      await for (final event in connection.events()) {
        if (_mustRetire(attempt)) return;
        switch (event) {
          case StatisticsFeedBaseline(:final publication):
            if (baselineReceived || publication.deliverySequence != 1) {
              throw _feedProtocolFailure(
                'baseline was duplicated or out of order',
              );
            }
            baselineReceived = true;
            deliverySequence = publication.deliverySequence;
            await _consumePublication(attempt, publication);
          case StatisticsFeedData(:final publication):
            if (!baselineReceived ||
                publication.deliverySequence != deliverySequence + 1) {
              throw _feedProtocolFailure(
                'statistics delivery sequence was not contiguous',
              );
            }
            deliverySequence = publication.deliverySequence;
            await _consumePublication(attempt, publication);
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
      if (!_mustRetire(attempt)) {
        _publishConnection(_nextReconnectPhase(), failure: failure);
      }
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
      _publishConnection(_nextReconnectPhase(), failure: failure);
    }
  }

  Future<void> _consumePublication(
    _StatisticsAttempt attempt,
    StatisticsFeedIdentity publication,
  ) async {
    final connection = attempt.connection!;
    final previous = _state.value.snapshot;
    final sameOwner = previous?.ownerEpoch == publication.ownerEpoch;
    if (sameOwner) {
      if (publication.publicationRevision < previous!.publicationRevision ||
          publication.summariesRevision < previous.summariesRevision ||
          publication.historyRevision < previous.historyRevision) {
        throw _feedProtocolFailure('publication revision moved backwards');
      }
      if ((publication.summariesRevision == previous.summariesRevision &&
              publication.summaryCount != previous.summaries.length) ||
          (publication.historyRevision == previous.historyRevision &&
              publication.historyCount != previous.history.length)) {
        throw _feedProtocolFailure('material count changed without a revision');
      }
    }

    final readSummaries =
        !sameOwner ||
        previous!.summariesRevision != publication.summariesRevision;
    final readHistory =
        !sameOwner || previous!.historyRevision != publication.historyRevision;
    StatisticsReadScope? scope;
    try {
      List<StatisticsSummary> summaries = previous?.summaries ?? const [];
      List<StatisticsSample> history = previous?.history ?? const [];
      if (readSummaries || readHistory) {
        scope = await connection.openScope(publication);
        final materialized = await StatisticsMaterializer.read(
          scope: scope,
          publication: publication,
          previous: previous,
          readSummaries: readSummaries,
          readHistory: readHistory,
        );
        summaries = materialized.summaries;
        history = materialized.history;
        if (_mustRetire(attempt)) return;
        await scope.close();
        scope = null;
      }

      if (_mustRetire(attempt)) return;
      // ACK only after all changed materials have been completely validated and materialized.
      try {
        await connection.acknowledge(publication.deliverySequence);
      } on Object catch (error) {
        throw StatisticsFailure.fromObject(
          error,
          category: StatisticsFailureCategory.acknowledgement,
        );
      }
      if (_mustRetire(attempt)) return;

      final snapshot = StatisticsSnapshot(
        ownerEpoch: publication.ownerEpoch,
        feedId: publication.feedId,
        publicationRevision: publication.publicationRevision,
        summariesRevision: publication.summariesRevision,
        historyRevision: publication.historyRevision,
        summaries: summaries,
        history: history,
        statisticsPending: publication.statisticsPending,
        statisticsGap: publication.statisticsGap,
        readFailed: publication.readFailed,
      );
      _state.publish(
        StatisticsRepositoryState(
          snapshot: snapshot,
          connection: const StatisticsConnectionState(
            phase: StatisticsConnectionPhase.ready,
          ),
        ),
      );
      _startStabilityTimer(attempt);
    } finally {
      final activeScope = scope;
      if (activeScope != null) {
        await activeScope.close();
      }
    }
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
    if (attempt.failure == null) {
      attempt.failure = StatisticsFailure.local(
        category: StatisticsFailureCategory.closed,
        code: StudioFailureCode.unavailable,
        message: 'Statistics feed ended unexpectedly',
        retryable: true,
      );
      _publishConnection(_nextReconnectPhase(), failure: attempt.failure);
    }
    _superviseRetirement(attempt, reconnectWhenSettled: true);
  }

  Future<void> _requestRetirement(
    _StatisticsAttempt attempt, {
    bool reconnectWhenSettled = false,
  }) {
    if (attempt.settled) return Future<void>.value();
    attempt.retireRequested = true;
    attempt.reconnectWhenSettled |= reconnectWhenSettled;
    attempt.connection?.requestClose();
    final existing = attempt.retirement;
    if (existing != null) return existing;
    final task = _retireAttempt(attempt);
    attempt.retirement = task;
    return task;
  }

  void _superviseRetirement(
    _StatisticsAttempt attempt, {
    bool reconnectWhenSettled = false,
  }) {
    unawaited(
      _requestRetirement(
        attempt,
        reconnectWhenSettled: reconnectWhenSettled,
      ).catchError((Object error, StackTrace _) {
        _retainUnresolved(attempt, error);
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
        await connection.close();
        final pump = attempt.pump;
        if (pump != null) await pump;
      }
      _settleAttempt(attempt);
    } on Object catch (error) {
      final failure = StatisticsFailure.fromObject(
        error,
        category: StatisticsFailureCategory.cleanup,
      );
      attempt.failure = failure;
      if (!attempt.permit.isReleased) {
        attempt.permit.mark(ResourcePhase.unresolved);
      }
      _retainUnresolved(attempt, failure);
      if (!_closed && _visibleDemands > 0 && identical(_current, attempt)) {
        _publishConnection(StatisticsConnectionPhase.failed, failure: failure);
      }
      attempt.retirement = null;
      Error.throwWithStackTrace(failure, StackTrace.current);
    }
  }

  void _retainUnresolved(_StatisticsAttempt attempt, Object error) {
    final failure = StatisticsFailure.fromObject(
      error,
      category: StatisticsFailureCategory.cleanup,
    );
    _unresolved[_resourceOwner(attempt)] = UnresolvedResource(
      owner: _resourceOwner(attempt),
      attemptId: AttemptId(attempt.id),
      reason: failure,
    );
  }

  void _releaseUnopenedAttempt(
    _StatisticsAttempt attempt,
    StatisticsFailure failure,
  ) {
    attempt.failure = failure;
    final reopenRequested =
        !attempt.retireRequested || attempt.reconnectWhenSettled;
    if (!_closed && _visibleDemands > 0 && reopenRequested) {
      attempt.reconnectWhenSettled = true;
      _publishConnection(_nextReconnectPhase(), failure: failure);
    }
    _settleAttempt(attempt);
  }

  void _settleAttempt(_StatisticsAttempt attempt) {
    if (attempt.settled) return;
    // This terminal path is reached only after native close/join, or after open failed before a
    // connection handle existed. In either case the original permit and unresolved record settle.
    attempt.permit.release();
    attempt.settled = true;
    _attempts.remove(attempt.id);
    _unresolved.remove(_resourceOwner(attempt));
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    if (identical(_current, attempt)) _current = null;
    if (attempt.reconnectWhenSettled && !_closed && _visibleDemands > 0) {
      _scheduleReconnect();
    } else if (!_closed && _visibleDemands == 0) {
      _publishConnection(StatisticsConnectionPhase.idle);
    }
  }

  bool _mustRetire(_StatisticsAttempt attempt) =>
      _closed ||
      _visibleDemands == 0 ||
      attempt.retireRequested ||
      attempt.generation != _generation ||
      !identical(_current, attempt);

  void _scheduleReconnect() {
    if (_closed || _visibleDemands == 0 || _retryTimer != null) return;
    if (_reconnectAttempts >= _maximumReconnectAttempts - 1) {
      _publishConnection(
        StatisticsConnectionPhase.failed,
        failure: _state.value.connection.failure,
      );
      return;
    }
    final attempt = _reconnectAttempts++;
    final delay = Duration(
      milliseconds: (_initialReconnectDelay.inMilliseconds * (1 << attempt))
          .clamp(0, _maximumReconnectDelay.inMilliseconds),
    );
    _publishConnection(
      _state.value.snapshot == null
          ? StatisticsConnectionPhase.connecting
          : StatisticsConnectionPhase.reconnecting,
      failure: _state.value.connection.failure,
    );
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _ensureConnected();
    });
  }

  StatisticsConnectionPhase _nextReconnectPhase() =>
      _reconnectAttempts >= _maximumReconnectAttempts - 1
      ? StatisticsConnectionPhase.failed
      : _state.value.snapshot == null
      ? StatisticsConnectionPhase.connecting
      : StatisticsConnectionPhase.reconnecting;

  void _startStabilityTimer(_StatisticsAttempt attempt) {
    if (_stabilityTimer != null) return;
    _stabilityTimer = Timer(_stableConnectionWindow, () {
      _stabilityTimer = null;
      if (!_mustRetire(attempt)) _reconnectAttempts = 0;
    });
  }

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

  Future<void> _joinBounded(List<Future<void>> work, DateTime? deadline) async {
    if (work.isEmpty) return;
    final joined = Future.wait<void>(work);
    try {
      final remaining = deadline?.difference(DateTime.now());
      if (remaining == null) {
        await joined;
      } else {
        await joined.timeout(remaining.isNegative ? Duration.zero : remaining);
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
        _unresolved[_resourceOwner(attempt)] = UnresolvedResource(
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
        _unresolved[_resourceOwner(attempt)] = UnresolvedResource(
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
    required this.permit,
  });

  final int id;
  final int generation;
  final ResourcePermit permit;
  StatisticsFeedConnection? connection;
  Future<void>? opening;
  Future<void>? pump;
  Future<void>? retirement;
  StatisticsFailure? failure;
  bool retireRequested = false;
  bool reconnectWhenSettled = false;
  bool settled = false;
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
