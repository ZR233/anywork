import '../../lifecycle/resource_budget.dart' show CloseReport;
import 'statistics_failure.dart';
import 'statistics_models.dart';

enum StatisticsConnectionPhase {
  idle,
  connecting,
  ready,
  reconnecting,
  failed,
  closing,
}

final class StatisticsConnectionState {
  const StatisticsConnectionState({
    this.phase = StatisticsConnectionPhase.idle,
    this.failure,
  });

  final StatisticsConnectionPhase phase;
  final StatisticsFailure? failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatisticsConnectionState &&
          phase == other.phase &&
          failure == other.failure;

  @override
  int get hashCode => Object.hash(phase, failure);
}

/// Last complete materialized snapshot and the current feed connection state.
///
/// During refresh or a failed read, `snapshot` remains the previous complete value while the
/// connection phase explains why it is not a ready value from the current feed.
final class StatisticsRepositoryState {
  const StatisticsRepositoryState({
    this.snapshot,
    this.connection = const StatisticsConnectionState(),
  });

  final StatisticsSnapshot? snapshot;
  final StatisticsConnectionState connection;

  bool get hasSnapshot => snapshot != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatisticsRepositoryState &&
          snapshot == other.snapshot &&
          connection == other.connection;

  @override
  int get hashCode => Object.hash(snapshot, connection);
}

/// Synchronous observation registration. Cancelling it never closes a statistics feed.
abstract interface class StatisticsObservation {
  StatisticsRepositoryState get initialState;
  void cancel();
}

/// Independent visible-demand lease. Its lifetime is not tied to listener count.
abstract interface class StatisticsVisibilityLease {
  bool get isReleased;
  void release();
}

/// The only public canonical statistics reducer for one AppGraph instance.
abstract interface class StatisticsRepository {
  StatisticsRepositoryState get state;

  StatisticsObservation observe(
    void Function(StatisticsRepositoryState state) listener,
  );

  StatisticsVisibilityLease acquireVisibleDemand();

  /// Bounded cleanup joins existing resources; failure retains their owners for retry.
  Future<CloseReport> close({DateTime? deadline});

  /// Retries cleanup of the same unresolved feed/scope; never opens a replacement to mask it.
  Future<CloseReport> retryCleanup({DateTime? deadline});

  /// Explicitly restarts a bounded, failed connection attempt while demand remains visible.
  void retry();
}
