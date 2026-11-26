/// Observation ended before a replacement metadata baseline was established.
final class ThreadStateResyncCancelled implements Exception {
  const ThreadStateResyncCancelled(this.threadId);
  final String threadId;
  @override
  String toString() => 'Thread state resync cancelled (thread=$threadId)';
}
