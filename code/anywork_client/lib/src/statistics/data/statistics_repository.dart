import 'dart:async';

import '../../../resources_ports.dart';
import '../domain/statistics_repository.dart';
import '../domain/statistics_state.dart';
import 'statistics_attempt.dart';
import 'statistics_port.dart';
import 'statistics_read_fields.dart';

/// The single canonical statistics mirror for one application instance.
///
/// The repository owns the visible demand and the concrete attempt; the attempt
/// owns both feeds and every read scope. Only this repository writes the
/// published state, and only from a compatible pair of complete materials.
StatisticsRepository createStatisticsRepository({
  required StatisticsPort port,
  required ResourceBudget budget,
}) => _StatisticsRepository(port, budget);

final class _StatisticsRepository implements StatisticsRepository {
  _StatisticsRepository(this.port, this.budget)
    : lifetime = ResourceLifetime(budget),
      source = ResourceSource(
        const StatisticsState(
          snapshot: null,
          sync: ResourceSyncState(
            phase: ResourceSyncPhase.idle,
            error: null,
            retryExhausted: false,
          ),
        ),
        budget,
        'statistics:observer',
      ) {
    lifetime.onSeal(source.seal);
  }

  final StatisticsPort port;
  final ResourceBudget budget;
  final ResourceLifetime lifetime;
  final ResourceSource<StatisticsState> source;

  StatisticsAttempt? _attempt;
  Future<void>? _starting;
  StudioFailure? _blocked;
  int _demand = 0;
  bool _sealed = false;
  bool _sourceClosed = false;

  @override
  ReadonlyLatestValue<StatisticsState> get state => source.readonly;

  @override
  StatisticsVisibilityLease acquireVisibleDemand() {
    _admit();
    final lease = _StatisticsLease(this);
    _demand++;
    if (_demand == 1) _ensureStarted();
    return lease;
  }

  @override
  Future<void> synchronize() async {
    _admit();
    if (_demand == 0) throw statisticsNoVisibleDemand();
    _ensureStarted();
    final starting = _starting;
    if (starting != null) await starting;
    // Reentrant hide/close/retry during the previous wait must not be granted
    // admission a second time.
    _admit();
    if (_demand == 0) throw statisticsNoVisibleDemand();
    final blocked = _blocked;
    if (blocked != null) throw blocked;
    final attempt = _attempt;
    if (attempt == null) throw statisticsNoVisibleDemand();
    if (attempt.retired) throw statisticsSuperseded;
    await attempt.paired;
  }

  @override
  Future<void> retrySync() async {
    _admit();
    if (_demand == 0) throw statisticsNoVisibleDemand();
    final current = _attempt;
    if (current != null && !current.retired && current.failure == null) {
      await current.paired;
      return;
    }
    _admit();
    if (current == null) {
      // No retained owner means the earlier failure never registered resources.
      // A retained block without an owner is not a licence to open another feed.
      final blocked = _blocked;
      if (blocked != null) throw blocked;
      return _startAndAwait();
    }
    // The explicit retry is a real retryCleanup of the original owner; only its
    // complete and clean report may release that owner.
    final report = await current.close(retry: true);
    if (!report.complete || !current.clean) {
      final failure = statisticsUnresolvedCleanup(
        'The statistics attempt has unresolved cleanup.',
      );
      _blocked = failure;
      _publishSync(ResourceSyncPhase.failed, failure);
      throw failure;
    }
    if (identical(_attempt, current)) _attempt = null;
    _blocked = null;
    return _startAndAwait();
  }

  Future<void> _startAndAwait() async {
    _admit();
    if (_demand == 0) throw statisticsNoVisibleDemand();
    final starting = _starting;
    if (starting != null) await starting;
    _admit();
    if (_demand == 0) throw statisticsNoVisibleDemand();
    final blocked = _blocked;
    if (blocked != null) throw blocked;
    final attempt = _attempt ?? _start();
    if (attempt == null) throw _blocked ?? statisticsSuperseded;
    await attempt.paired;
  }

  @override
  void seal() {
    if (_sealed) return;
    _sealed = true;
    lifetime.seal();
    _attempt?.requestRetire();
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      _close(deadline, true);

  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    seal();
    final attempt = _attempt;
    final reports = await Future.wait<CloseReport>([
      lifetime.close(deadline: deadline, retry: retry),
      if (attempt != null) attempt.close(deadline: deadline, retry: retry),
    ]);
    if (!_sourceClosed && reports.every((report) => report.complete)) {
      _sourceClosed = true;
      source.publish(
        StatisticsState(
          snapshot: source.value.snapshot,
          sync: const ResourceSyncState(
            phase: ResourceSyncPhase.closed,
            error: null,
            retryExhausted: false,
          ),
        ),
      );
      source.close();
    }
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }

  void _admit() {
    if (_sealed) throw resourceCancelled;
    lifetime.admit();
  }

  void _ensureStarted() {
    if (_sealed || _demand == 0) return;
    final current = _attempt;
    if (current != null) {
      if (!current.retired) return;
      _startAfter(current);
      return;
    }
    if (_blocked != null) return;
    _start();
  }

  StatisticsAttempt? _start() {
    _admit();
    final existing = _attempt;
    if (existing != null) {
      // One demand owns at most one attempt: a concurrent re-visible start or
      // explicit retry reuses the live attempt, and a retained retired attempt
      // must be joined by retrySync before any replacement exists.
      return existing.retired ? null : existing;
    }
    late final StatisticsAttempt attempt;
    attempt = StatisticsAttempt(
      budget: budget,
      port: port,
      owner: 'statistics:${lifetime.nextAttempt()}',
      lastGood: () => source.value.snapshot,
      publish: _publishSnapshot,
      onFailure: (failure) => _attemptFailed(attempt, failure),
    );
    _attempt = attempt;
    _blocked = null;
    try {
      attempt.start();
    } catch (error) {
      final failure = statisticsFailure(error);
      // A reentrant hide during opening already retired this attempt; only a
      // real opening failure blocks the next visible attempt.
      if (!attempt.retired) {
        // The partially opened attempt keeps its cleanup responsibility: a
        // retry must join it before any replacement feed exists.
        _blocked = failure;
        if (_demand > 0) _publishSync(ResourceSyncPhase.failed, failure);
      }
      attempt.requestRetire();
      return null;
    }
    _publishSync(ResourceSyncPhase.connecting);
    return attempt;
  }

  /// A re-visible demand waits for the previous attempt's real retirement; an
  /// unresolved one is reported instead of being covered by a second feed.
  void _startAfter(StatisticsAttempt prior) {
    if (_starting != null) return;
    final done = Completer<void>();
    _starting = done.future;
    unawaited(
      prior.retirement
          .then<void>(
            (report) {
              if (!report.complete || !prior.clean) {
                // The original owner keeps its responsibility and its typed
                // block until an explicit retry of that same owner succeeds.
                final failure = statisticsUnresolvedCleanup(
                  'The previous statistics attempt has unresolved cleanup.',
                );
                _blocked = failure;
                if (!_sealed && _demand > 0)
                  _publishSync(ResourceSyncPhase.failed, failure);
                return;
              }
              if (identical(_attempt, prior)) _attempt = null;
              _blocked = null;
              if (_sealed || _demand == 0) return;
              _start();
            },
            onError: (Object error, StackTrace stack) {
              // A failed join does not change ownership: the original attempt
              // stays registered with its block.
              final failure = statisticsFailure(error);
              _blocked = failure;
              if (!_sealed && _demand > 0)
                _publishSync(ResourceSyncPhase.failed, failure);
            },
          )
          .whenComplete(() {
            if (!done.isCompleted) done.complete();
            if (identical(_starting, done.future)) _starting = null;
          }),
    );
  }

  void _publishSnapshot(StatisticsSnapshot snapshot) {
    if (_sealed) return;
    final current = source.value;
    final next = StatisticsState(
      snapshot: snapshot,
      sync: const ResourceSyncState(
        phase: ResourceSyncPhase.ready,
        error: null,
        retryExhausted: false,
      ),
    );
    // A reused material publishes only the transition to a current ready
    // value; it never republishes an unchanged snapshot as a new one.
    if (next != current) source.publish(next);
  }

  void _attemptFailed(StatisticsAttempt attempt, StudioFailure failure) {
    if (!identical(_attempt, attempt) || _sealed) return;
    _publishSync(ResourceSyncPhase.failed, failure);
  }

  void _publishSync(ResourceSyncPhase phase, [StudioFailure? error]) {
    if (_sealed || _sourceClosed) return;
    final current = source.value;
    final next = StatisticsState(
      snapshot: current.snapshot,
      sync: ResourceSyncState(
        phase: phase,
        error: error,
        retryExhausted: false,
      ),
    );
    if (next != current) source.publish(next);
  }

  void _releaseDemand() {
    if (_demand == 0) return;
    _demand--;
    if (_demand > 0) return;
    final attempt = _attempt;
    // Retire before publishing: a reentrant visible demand must observe the
    // retired attempt and wait for its real retirement, never reuse it.
    attempt?.requestRetire();
    _publishSync(ResourceSyncPhase.idle);
    if (attempt != null) unawaited(_superviseRetirement(attempt));
  }

  Future<void> _superviseRetirement(StatisticsAttempt attempt) async {
    try {
      final report = await attempt.retirement;
      if (report.complete) return;
      final failure = statisticsUnresolvedCleanup(
        'The previous statistics attempt has unresolved cleanup.',
      );
      _blocked = failure;
      if (!_sealed && _demand > 0)
        _publishSync(ResourceSyncPhase.failed, failure);
    } catch (error) {
      final failure = statisticsFailure(error);
      _blocked = failure;
      if (!_sealed && _demand > 0)
        _publishSync(ResourceSyncPhase.failed, failure);
    }
  }
}

final class _StatisticsLease implements StatisticsVisibilityLease {
  _StatisticsLease(this._repository);

  final _StatisticsRepository _repository;
  bool _released = false;

  @override
  void release() {
    if (_released) return;
    _released = true;
    _repository._releaseDemand();
  }
}
