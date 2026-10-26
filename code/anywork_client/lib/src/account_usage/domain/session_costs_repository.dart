import '../../../resources.dart';
import 'session_costs_state.dart';

/// The root-session cost capability of the account-usage domain. It keeps its
/// own responsibility, entry point and close rights; it is not a statistics
/// read and does not see the global history.
abstract interface class SessionCostsRepository {
  /// One root-scoped borrow. Every borrow registers its own native observation
  /// and charges the shared resource budget.
  SessionCostsQuery costs(String rootThreadId);
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

/// A concrete root-scoped query borrow, not serializable state.
abstract interface class SessionCostsQuery {
  String get rootThreadId;
  ReadonlyLatestValue<SessionCostsState> get state;
  Future<void> load();
  void requestClose();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
