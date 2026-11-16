/// A shared monotonic limit on waiting for resource cleanup.
///
/// The clock starts at construction. Expiry never cancels cleanup or releases
/// its owner; callers may inspect the unresolved report and retry explicitly.
final class ClientCloseBudget {
  /// Starts a budget for a non-negative timeout.
  ClientCloseBudget(this._timeout) {
    if (_timeout.isNegative) {
      throw ArgumentError.value(_timeout, 'timeout', 'must not be negative');
    }
    _clock.start();
  }

  final Duration _timeout;
  final Stopwatch _clock = Stopwatch();

  /// The time left, clamped to [Duration.zero].
  Duration get remaining {
    final remaining = _timeout - _clock.elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Whether the shared waiting budget has been exhausted.
  bool get expired => remaining == Duration.zero;
}
