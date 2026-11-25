typedef TimelineFileDownloadStart = TimelineFileDownload Function({
  required String itemId,
  required int index,
  required String destination,
});

abstract interface class TimelineFileDownload {
  /// Single-subscription stream of cumulative bytes written.
  Stream<int> get progress;

  /// Completes successfully after the final file has been committed. Failure
  /// and early termination complete with an error.
  Future<void> get finished;

  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
}
