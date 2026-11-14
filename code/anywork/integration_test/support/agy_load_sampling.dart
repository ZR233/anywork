// Diagnostic sampling only. Requests coalesce while capture is running; accepted
// work is joined before a separately owned final capture. No process is cancelled.
final class AgyLoadSampling {
  AgyLoadSampling(this.capture);

  final Future<void> Function() capture;
  Future<void>? _worker;
  bool _accepting = true;
  bool _pending = false;
  bool _inFlight = false;
  bool _finalStarted = false;
  Object? _error;
  StackTrace? _stack;
  int _requested = 0;
  int _started = 0;
  int _completed = 0;
  int _coalesced = 0;
  int _rejected = 0;

  Map<String, Object?> get diagnostics => {
    'requested': _requested,
    'started': _started,
    'completed': _completed,
    'coalesced': _coalesced,
    'rejectedAfterClose': _rejected,
    'accepting': _accepting,
    'pending': _pending,
    'inFlight': _inFlight,
    'finalStarted': _finalStarted,
    'errorType': _error?.runtimeType.toString(),
  };

  void request() {
    if (!_accepting) {
      _rejected++;
      return;
    }
    _requested++;
    if (_inFlight) {
      _pending = true;
      _coalesced++;
      return;
    }
    _inFlight = true;
    _worker = _run();
  }

  Future<void> _capture() async {
    _started++;
    try {
      await capture();
    } catch (error, stack) {
      _error ??= error;
      _stack ??= stack;
    } finally {
      _completed++;
    }
  }

  Future<void> _run() async {
    try {
      do {
        _pending = false;
        await _capture();
      } while (_pending);
    } finally {
      _inFlight = false;
    }
  }

  void closeAdmission() => _accepting = false;

  Future<void> drain() async {
    await _worker;
    _rethrow();
  }

  Future<void> finalSample() async {
    if (_accepting || _finalStarted) {
      throw StateError('Final sample requires closed admission and one owner');
    }
    _finalStarted = true;
    await _worker;
    _requested++;
    _inFlight = true;
    try {
      await _capture();
    } finally {
      _inFlight = false;
    }
    _rethrow();
  }

  void _rethrow() {
    if (_error case final error?) {
      Error.throwWithStackTrace(error, _stack!);
    }
  }
}
