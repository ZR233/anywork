import 'dart:async';

/// Coalesces same-tick source notifications into one trailing microtask.
///
/// Riverpod forbids writing a provider's state while another provider is still
/// building, yet a canonical source can publish during such a build: settings
/// pages observe the same configuration/models collections that their own
/// build reads. Observers therefore only record "something changed" and let one
/// microtask decide whether the write is still admissible.
///
/// The owner supplies the commit closure and re-checks its own admission rules
/// there (alive flag, build generation/lifetime, initialising guard, current
/// `state.asData`); [mark] never publishes on its own and never touches a
/// provider. Multiple notifications in one tick collapse into a single commit,
/// so a commit reads the latest canonical values instead of replaying stale
/// ones.
///
/// Scope: this is a settings-local scheduling detail shared by the settings view
/// models, not a cross-feature bus.
final class CoalescedPublish {
  CoalescedPublish(this._commit);

  /// Applies the pending change; owners re-check admission inside.
  final void Function() _commit;

  bool _scheduled = false;
  bool _disposed = false;

  /// Records a change and schedules one microtask when none is pending.
  void mark() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(_drain);
  }

  void _drain() {
    _scheduled = false;
    if (_disposed) return;
    _commit();
  }

  /// Drops pending work and stops publishing (owner disposal or rebind).
  void dispose() {
    _disposed = true;
  }
}
