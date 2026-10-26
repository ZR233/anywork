import '../state/timeline_view_state.dart';

/// Presentation metadata/intents only; VM does not borrow UI controllers.
abstract interface class TimelineActions {
  TimelineViewState? get value;
  Stream<TimelineViewState?> get changes;
  void enterHistory(String threadId);
  Future<void> loadOlder(String threadId, int generation, {bool retry = false});
  Future<void> returnLive(String threadId);
  Future<void> retryConnection(String threadId);
}
