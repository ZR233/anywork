/// A conservative monotonic observation of the *native* first exit deadline.
///
/// Created before beginExit. The returned native remainder is never treated as
/// a fresh thirty seconds, and even time spent obtaining it is deducted. This
/// may shorten the observed budget slightly; it cannot extend the native limit.
final class ExitDeadline {
  ExitDeadline() : _clock = Stopwatch()..start();

  final Stopwatch _clock;
  int? _nativeRemainderMs;

  void anchor(int remainingMs) {
    if (_nativeRemainderMs != null) {
      throw StateError('The first native exit deadline is immutable');
    }
    if (remainingMs < 0 || remainingMs > 30000) {
      throw ArgumentError.value(remainingMs, 'remainingMs');
    }
    _nativeRemainderMs = remainingMs;
  }

  int get remainingMs {
    final remainder = (_nativeRemainderMs ?? 0) - _clock.elapsedMilliseconds;
    return remainder > 0 ? remainder : 0;
  }

  int get cleanupMs => (remainingMs - 2000).clamp(0, 28000).toInt();
  Duration get remaining => Duration(milliseconds: remainingMs);
  Duration get cleanup => Duration(milliseconds: cleanupMs);

  /// Repository APIs accept a wall-clock observation bound. It is regenerated
  /// only from the decreasing monotonic remainder, never from a new allowance.
  DateTime get cleanupDeadline => DateTime.now().add(cleanup);
}
