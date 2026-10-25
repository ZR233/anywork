import '../domain/closing.dart';

/// All implementations own their concrete typed frames and native cleanup.
/// Getter access does not claim the stream; the first actual listen does.
abstract interface class FeedConnection<TFrame> {
  Stream<TFrame> get events;
  Future<void> ackThrough(int deliverySequence);
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
