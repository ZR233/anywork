import 'dart:async';

import 'package:anywork_client/bots.dart';
import 'package:anywork_client/resources.dart';

import '../../platform/error_log.dart';

/// Application-owned resident demand for the Bots source.
///
/// Bots is not page-scoped: one resident subscription lives for the whole Run,
/// so a GUI observer or a Settings round trip can never be its only demand. A
/// Settings visit adds and removes only its own demand; nothing in a feature
/// closes this one, and the Bots Repository keeps the single feed.
///
/// The demand is established after the real RuntimeReady result, like the
/// Workspace selection binding and automatic updates. The Repository publishes
/// readiness/failure and retry on its canonical state; this owner only retains
/// the original Future so application close joins it instead of abandoning it.
final class ResidentBotsDemand {
  ResidentBotsDemand(this._bots);

  final BotsRepository _bots;
  Future<void>? _starting;
  bool _sealed = false;

  /// Registers the one resident demand. Re-entrant attach joins the original
  /// Future; a sealed demand accepts no further start.
  void startAfterRuntimeReady() {
    if (_sealed || _starting != null) return;
    late final Future<void> starting;
    starting = Future<void>.sync(() => _bots.synchronize()).then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        // Canonical Bots state carries this failure and its explicit retry; the
        // retained Future is joined by close, never replayed. The raw cause is
        // also kept in the local diagnostics instead of disappearing silently.
        recordDartError(error, stack, stage: 'resident-bots-demand');
        if (identical(_starting, starting)) _starting = null;
      },
    );
    _starting = starting;
  }

  void seal() {
    _sealed = true;
  }

  Future<CloseReport> close({DateTime? deadline}) async {
    seal();
    final original = _starting;
    if (original != null) {
      // An in-flight resident demand is joined, not cancelled: the Repository,
      // not this participant, owns feed cancellation and its close report.
      await original;
    }
    return CloseReport(unresolved: const []);
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      close(deadline: deadline);
}
