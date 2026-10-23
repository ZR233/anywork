import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/updates.dart';
import 'package:anywork_client/updates_ports.dart';
import 'package:anywork_client/workspace.dart';

import '../../platform/studio_platform.dart';

/// A local capability, never a canonical Disabled/Idle update value.
bool get productionUpdatesEnabled =>
    isWindowsPlatform &&
    (const bool.fromEnvironment('dart.vm.product') ||
        const bool.fromEnvironment('ANYWORK_DRIVER')) &&
    !const bool.fromEnvironment('ANYWORK_DEMO');

typedef _UpdatesTarget = ({ProductReadOrigin origin, UpdatesReadRef reference});

/// Explicit app startup gate. The Updates Repository still owns the one real
/// automatic task, its operation/permit, all progress, cancellation and join.
final class AutomaticUpdatesStartup {
  AutomaticUpdatesStartup({
    required UpdatesRepository updates,
    required UpdatesLifecycle lifecycle,
    required bool enabled,
  }) : _updates = updates,
       _lifecycle = lifecycle,
       _enabled = enabled;

  final UpdatesRepository _updates;
  final UpdatesLifecycle _lifecycle;
  final bool _enabled;
  Future<OperationTicket<Unit>?>? _starting;
  OperationTicket<Unit>? _ticket;
  Completer<void>? _changed;
  Observation? _observation;
  StudioFailure? _gateFailure;
  bool _readDemanded = false;
  bool _sealed = false;

  /// The caller must hold the actual StartupRepository Ready result. Neither a
  /// VM build nor local platform availability is a runtime-ready substitute.
  Future<OperationTicket<Unit>?> startAfterRuntimeReady(RuntimeReady ready) {
    if (_sealed) return Future.error(_cancelled);
    final existing = _starting;
    if (existing != null) return existing;
    final completion = Completer<OperationTicket<Unit>?>();
    final task = completion.future;
    _starting = task;
    // Retain responsibility before any observer/read/command can call out.
    // Explicit retry can only follow joined reads; any retained observation
    // must cancel before a new one. A returned ticket is never started again.
    unawaited(Future<OperationTicket<Unit>?>.sync(_completeStart).then<void>((ticket) {
      completion.complete(ticket);
      if (identical(_starting, task)) _starting = null;
    }, onError: (Object error, StackTrace stack) {
      completion.completeError(error, stack);
      if (identical(_starting, task)) _starting = null;
    }));
    return task;
  }

  _UpdatesTarget? _target(UpdatesState value) {
    final projection = value.projection;
    final stamp = projection.stamp;
    final header = projection.header;
    if (projection.sync.phase != ResourceSyncPhase.ready || stamp == null || header == null) return null;
    return (origin: stamp.origin, reference: header.reference);
  }

  bool _canonicalReady(UpdatesState value) {
    final target = _target(value);
    final current = value.value;
    return target != null && current is ReadyReadValue<UpdatesValue, UpdatesReadRef> &&
        current.current.origin == target.origin && current.current.reference == target.reference;
  }

  void _checkFailure(UpdatesState value) {
    if (value.projection.sync.error case final failure?) throw failure;
    if (value.projection.sync.phase == ResourceSyncPhase.closed) throw _cancelled;
    final current = value.value;
    final target = _target(value);
    if (target != null && current is FailedReadValue<UpdatesValue, UpdatesReadRef> &&
        current.origin == target.origin && current.reference == target.reference) {
      final previous = current.previous;
      // Rebinding to a new header can mark the previous materialization stale.
      // That is not a failed read of this new target: demand its current value.
      // A loadValue Future which actually fails is still propagated unchanged.
      if (current.error.code == StudioFailureCode.superseded && previous != null &&
          (previous.origin != current.origin || previous.reference != current.reference)) return;
      throw current.error;
    }
  }

  void _wake() {
    final changed = _changed;
    if (changed != null && !changed.isCompleted) changed.complete();
  }

  void _observe(UpdatesState value) {
    if (_readDemanded && !_sealed && _gateFailure == null) {
      try { _checkFailure(value); }
      on StudioFailure catch (failure) { _gateFailure = failure; }
    }
    // A later source recovery cannot erase a failure from this original gate
    // or implicitly retry it. Only a new explicit start may clear the failure.
    _wake();
  }

  Future<OperationTicket<Unit>?> _completeStart() async {
    try {
      // If a previous observation cancellation threw, retain and finish that
      // same responsibility before registering another one, even with a ticket.
      _cancelObservation();
      final ticket = await _waitAndStart();
      _cancelObservation();
      return ticket;
    } catch (error, stack) {
      // Preserve the original typed subscription/read/admission failure. A
      // cancellation failure keeps its observation for explicit cleanup/close;
      // it must not overwrite the original error or create a second observer.
      try { _cancelObservation(); } catch (_) { /* Still retained for close. */ }
      Error.throwWithStackTrace(error, stack);
    } finally {
      _changed = null;
      _readDemanded = false;
      _gateFailure = null;
    }
  }

  Future<OperationTicket<Unit>?> _waitAndStart() async {
    if (_sealed) return null;
    if (_ticket case final ticket?) return ticket;
    if (!_enabled || !_updates.controls.enabled) return null;
    _changed = Completer<void>();
    final watched = _updates.state.watchLatest(_observe);
    _observation = watched.observation;
    if (_sealed) return null;
    // Register first, then issue the explicit read which starts the sole feed.
    // Do not reject an explicit retry from a stale previous FailedReadValue
    // before the Repository has had this read demand to recover its source.
    var readTarget = _target(_updates.state.value);
    _readDemanded = true;
    await Future<void>.sync(_updates.loadValue);
    while (true) {
      final changed = Completer<void>();
      _changed = changed;
      final current = _updates.state.value;
      if (_gateFailure case final failure?) throw failure;
      if (_sealed) return null;
      _checkFailure(current);
      // A notification/earlier read is not admission evidence. Recheck the
      // complete current origin/ref immediately before dispatch, with no
      // await or external callback between this check and the command.
      if (_canonicalReady(current)) {
        if (_sealed) return null;
        final ticket = _lifecycle.startAutomaticOnce();
        _ticket = ticket;
        return ticket;
      }
      final target = _target(current);
      if (target != null && target != readTarget) {
        // A new header during the original read may still need its own pure
        // materialization. This never retries a failed read or business start
        // and cannot supply a later value as the result of an earlier action.
        readTarget = target;
        await Future<void>.sync(_updates.loadValue);
      } else {
        await changed.future;
      }
    }
  }

  void _cancelObservation() {
    final observation = _observation;
    if (observation == null) return;
    observation.cancel();
    _observation = null;
  }

  void seal() {
    if (_sealed) return;
    _sealed = true;
    // Wake a waiting gate, but never pretend an in-flight read has joined.
    _wake();
  }

  Future<CloseReport> close({DateTime? deadline}) async {
    seal();
    // A cleared slot has already joined; an in-flight original includes every
    // admitted read, with no eager-error branch abandoning it. Domain close
    // still owns native processing, stream cancellation and accepted task join.
    final original = _starting;
    if (original != null) {
      await original.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    }
    _cancelObservation();
    return CloseReport(unresolved: const []);
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) => close(deadline: deadline);

  static const _cancelled = StudioFailure(
    code: StudioFailureCode.cancelled,
    message: 'Automatic update startup is sealed.',
    retryable: false,
    correlationId: '',
  );
}
