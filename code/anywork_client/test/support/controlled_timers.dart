import 'dart:async';

/// Controls the existing Zone timer boundary. It neither replaces production
/// retry policy nor advances timers implicitly when another Future is awaited.
final class ControlledTimers {
  final _pending = <_ControlledTimer>[];
  Completer<_ControlledTimer>? _scheduled;

  ZoneSpecification get specification => ZoneSpecification(
    createTimer: (self, parent, zone, delay, callback) {
      final timer = _ControlledTimer(delay, () => zone.runGuarded(callback));
      final waiting = _scheduled;
      if (waiting == null) {
        _pending.add(timer);
      } else {
        _scheduled = null;
        waiting.complete(timer);
      }
      return timer;
    },
  );

  bool get hasPending => _pending.any((timer) => timer.isActive);

  Future<Duration> fireNext() async {
    _pending.removeWhere((timer) => !timer.isActive);
    final timer = _pending.isNotEmpty
        ? _pending.removeAt(0)
        : await (_scheduled ??= Completer<_ControlledTimer>()).future;
    timer.fire();
    return timer.delay;
  }
}

final class _ControlledTimer implements Timer {
  _ControlledTimer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;

  void fire() {
    if (!isActive) throw StateError('The controlled timer was cancelled');
    isActive = false;
    tick++;
    callback();
  }

  @override
  void cancel() => isActive = false;
}
