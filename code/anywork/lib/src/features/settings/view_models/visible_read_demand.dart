import 'dart:async';

import 'package:anywork_client/resources.dart';

/// Presentation-only demand for one typed read. The Repository owns the actual
/// scope/Future and its join. At most one read is borrowed here; newer demand
/// replaces only the next target. A failed target is not retried by rebuilds.
final class VisibleReadDemand<K extends Object> {
  VisibleReadDemand({required this.read, required this.changed});

  final Future<void> Function(K target) read;
  final void Function(K target, StudioFailure? error, bool current) changed;
  K? _target;
  K? _attempted;
  bool _visible = false;
  bool _disposed = false;
  bool _reading = false;
  bool _needed = true;

  bool get reading => _reading;

  void remember(K target) {
    if (!_reading) _attempted = target;
  }

  void target(K? target, {bool needed = true}) {
    _target = target;
    _needed = needed;
    _pump();
  }

  void visible(bool value) {
    _visible = value;
    _pump();
  }

  void retry() {
    if (_reading) return;
    _attempted = null;
    _pump();
  }

  void dispose() {
    _disposed = true;
    _visible = false;
    _target = null;
    // Never cancel a Repository-owned read or close its scope from a VM.
  }

  void _pump() {
    final frozen = _target;
    if (_disposed || !_visible || !_needed || _reading || frozen == null || frozen == _attempted) return;
    final previousAttempt = _attempted;
    _attempted = frozen;
    _reading = true;
    changed(frozen, null, true);
    // Publishing local pending can synchronously hide/dispose this VM or
    // replace the target. Nothing has been handed to the Repository yet.
    if (_disposed || !_visible || !_needed || frozen != _target) {
      _reading = false;
      _attempted = previousAttempt;
      if (!_disposed) { changed(frozen, null, false); _pump(); }
      return;
    }
    unawaited(_run(frozen));
  }

  Future<void> _run(K frozen) async {
    StudioFailure? error;
    var hasResult = false;
    try { await read(frozen); hasResult = true; }
    on StudioFailure catch (failure) { error = failure; hasResult = true; }
    finally {
      _reading = false;
      if (!_disposed) {
        changed(frozen, error, hasResult && frozen == _target);
        _pump();
      }
    }
  }
}
