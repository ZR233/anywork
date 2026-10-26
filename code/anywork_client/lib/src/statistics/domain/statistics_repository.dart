import '../../../resources.dart';
import 'statistics_state.dart';

/// The only public canonical statistics mirror for one application instance.
///
/// Observation is synchronous registration over [state]; a visible demand is a
/// separate lease and is the only reason to open the two statistics feeds.
abstract interface class StatisticsRepository {
  ReadonlyLatestValue<StatisticsState> get state;

  /// Registers one visible demand. The first demand opens both statistics
  /// feeds; a hidden build never creates a demand.
  StatisticsVisibilityLease acquireVisibleDemand();

  /// Awaits one complete publication of the current attempt, or its typed
  /// failure. It never creates a demand and never opens a hidden feed.
  Future<void> synchronize();

  /// Explicitly retries a failed attempt after its original resources are
  /// joined. Unresolved cleanup is reported instead of being hidden behind a
  /// second feed.
  Future<void> retrySync();

  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

/// One concrete visible demand, not a Freezed value or a listener count.
/// Releasing is idempotent; cancelling an observer never releases a demand.
abstract interface class StatisticsVisibilityLease {
  void release();
}
