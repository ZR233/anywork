import 'dart:async';

import '../../models.dart';
import '../../studio_ports.dart';
import '../contracts/stamps.dart';
import '../lifecycle/resource_budget.dart';
import '../observation/latest_value.dart';
import 'stores/canonical_clock.dart';
import 'stores/updater_store.dart';

/// A command result for host actions, independent of the canonical update state.
final class StudioUpdateInstallResult {
  const StudioUpdateInstallResult({this.readyVersion});
  final String? readyVersion;
}

enum StudioUpdateRequestPhase {
  idle,
  checking,
  preparing,
  cancelling,
  cancelled,
  ready,
  failed,
}

/// Client request feedback; download and installation facts remain canonical.
final class StudioUpdateRequest {
  const StudioUpdateRequest(this.phase, {this.error});
  final StudioUpdateRequestPhase phase;
  final Object? error;
  bool get pending =>
      phase == StudioUpdateRequestPhase.checking ||
      phase == StudioUpdateRequestPhase.preparing ||
      phase == StudioUpdateRequestPhase.cancelling;
}

/// Application-owned update operations. Observers cannot start or dispose them.
/// Canonical snapshots always enter [updater]'s one reducer.
final class StudioUpdateClient {
  StudioUpdateClient({
    required this.api,
    required this.updater,
    required this.enabled,
    ResourceBudget? budget,
    this.onBackgroundError,
  }) : budget = budget ?? ResourceBudget();

  final StudioUpdateApi api;
  final UpdaterStore updater;
  final bool enabled;
  final ResourceBudget budget;
  final void Function(Object, StackTrace)? onBackgroundError;
  final request = LatestValue<StudioUpdateRequest>(
    const StudioUpdateRequest(StudioUpdateRequestPhase.idle),
  );
  final Map<int, _UpdateAttempt> _attempts = {};
  final Map<int, _UpdateRpc> _rpcs = {};
  final Map<String, Object> _cleanupFailures = {};
  Observation? _observation;
  ResourcePermit? _observationPermit;
  ResourcePermit? _automaticPermit;
  Future<void>? _automaticTask;
  Future<void>? _automaticStopTask;
  Future<void>? _checkTask;
  Future<StudioUpdateInstallResult>? _installTask;
  Future<CloseReport>? _closing;
  _UpdateAttempt? _active;
  int _sequence = 0;
  int _rpcSequence = 0;
  bool _automaticStarted = false;
  bool _automaticStopRunning = false;
  bool _attached = false;
  bool _closed = false;

  LatestValue<CanonicalClockState<UpdaterStateSnapshot>> get source =>
      updater.source;

  UpdaterStateSnapshot get state {
    final observed = updater.state.value;
    if (!enabled) {
      return DisabledUpdaterStateSnapshot(
        revision: observed?.revision ?? 0,
        updatedAt:
            observed?.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
    return observed ??
        UpdaterStateSnapshot.idle(
          revision: 0,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
  }

  List<UnresolvedResource> get unresolvedResources => _report().unresolved;

  /// Called once by application assembly, after this owner is installed.
  void attach() {
    if (_closed) throw StateError('Update client is closed');
    if (_attached) return;
    if (!enabled) {
      _attached = true;
      return;
    }
    _observationPermit = budget.acquire(
      ResourceKind.observer,
      owner: 'updater',
    );
    final registration = source.watchLatest((_) => _startAutomaticOnce());
    _observation = registration.observation;
    _attached = true;
    _startAutomaticOnce();
  }

  void _startAutomaticOnce() {
    if (_closed ||
        !enabled ||
        _automaticStarted ||
        updater.state.value == null) {
      return;
    }
    ResourcePermit? permit;
    Completer<void>? completed;
    try {
      // The producer outlives its start RPC. Its permit remains held until a
      // real cancellation ACK, including an unknown startup outcome.
      permit = budget.acquire(
        ResourceKind.observer,
        owner: 'automatic-update',
        phase: ResourcePhase.opening,
      );
      _automaticPermit = permit;
      _automaticStarted = true;
      completed = Completer<void>();
      _automaticTask = completed.future;
      final rpc = _rpc('automatic-start', api.startAutomaticUpdate);
      unawaited(_completeAutomaticStart(rpc, completed));
    } catch (error, stack) {
      // Admission failed before a transport call; there is no producer to stop.
      _automaticStarted = false;
      _automaticPermit = null;
      permit?.release();
      completed?.complete();
      onBackgroundError?.call(error, stack);
    }
  }

  Future<void> _completeAutomaticStart(
    Future<void> rpc,
    Completer<void> completed,
  ) async {
    try {
      await rpc;
      if (!_closed) _automaticPermit?.mark(ResourcePhase.active);
    } catch (error, stack) {
      // A lost reply does not prove that the producer never started. Do not
      // replay startup; shutdown must still obtain its cancellation ACK.
      _automaticPermit?.mark(ResourcePhase.unresolved);
      onBackgroundError?.call(error, stack);
    } finally {
      completed.complete();
    }
  }

  Future<T> _rpc<T>(String name, Future<T> Function() action) {
    final id = ++_rpcSequence;
    final permit = budget.acquire(
      ResourceKind.pendingOperation,
      owner: 'update-rpc:$name:$id',
    );
    final rpc = _UpdateRpc(id, name, permit);
    _rpcs[id] = rpc;
    return _runRpc(rpc, action);
  }

  Future<T> _runRpc<T>(_UpdateRpc rpc, Future<T> Function() action) async {
    try {
      return await action();
    } finally {
      rpc.permit.release();
      _rpcs.remove(rpc.id);
      // Joining completion is separate from the business result. An ended
      // query failure is reported to its caller and owns no remaining resource.
      rpc.done.complete();
    }
  }

  Future<void> check() {
    if (_closed || !enabled || _isInstalling(state)) return Future.value();
    if (_checkTask case final pending?) return pending;
    final completed = Completer<void>();
    _checkTask = completed.future;
    request.publish(
      const StudioUpdateRequest(StudioUpdateRequestPhase.checking),
    );
    unawaited(() async {
      try {
        final snapshot = await _rpc('check', api.check);
        if (!_closed) {
          updater.apply(snapshot);
          request.publish(
            const StudioUpdateRequest(StudioUpdateRequestPhase.idle),
          );
        }
        completed.complete();
      } catch (error, stack) {
        if (!_closed)
          request.publish(
            StudioUpdateRequest(StudioUpdateRequestPhase.failed, error: error),
          );
        completed.completeError(error, stack);
      } finally {
        _checkTask = null;
      }
    }());
    return completed.future;
  }

  Future<StudioUpdateInstallResult> install() {
    if (_installTask case final pending?) return pending;
    final snapshot = state;
    final update = snapshot.update;
    if (_closed ||
        !enabled ||
        update == null ||
        snapshot is InstallerLaunchedUpdaterStateSnapshot) {
      return Future.value(const StudioUpdateInstallResult());
    }
    if (_attempts.isNotEmpty) {
      return Future.error(
        StateError('A prior update operation still needs cleanup'),
      );
    }
    final ResourcePermit permit;
    try {
      permit = budget.acquire(
        ResourceKind.pendingOperation,
        owner: 'update:${_sequence + 1}',
        phase: ResourcePhase.opening,
      );
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    // Install ownership exists before the first transport await. A late native
    // operation always belongs to this attempt, even after application close.
    final attempt = _UpdateAttempt(++_sequence, permit);
    _attempts[attempt.id] = attempt;
    _active = attempt;
    final completed = Completer<StudioUpdateInstallResult>();
    final task = completed.future;
    _installTask = task;
    attempt.task = task;
    request.publish(
      const StudioUpdateRequest(StudioUpdateRequestPhase.preparing),
    );
    unawaited(() async {
      try {
        completed.complete(
          await _install(attempt, snapshot.revision, update.version),
        );
      } catch (error, stack) {
        if (!_closed)
          request.publish(
            StudioUpdateRequest(StudioUpdateRequestPhase.failed, error: error),
          );
        completed.completeError(error, stack);
      } finally {
        if (identical(_installTask, task)) _installTask = null;
        if (identical(_active, attempt)) _active = null;
      }
    }());
    return task;
  }

  Future<StudioUpdateInstallResult> _install(
    _UpdateAttempt attempt,
    int revision,
    String version,
  ) async {
    try {
      final operation = await api.startPreparation(
        expectedRevision: revision,
        version: version,
      );
      attempt.operation = operation;
      attempt.opened.complete(operation);
      if (_closed || attempt.cancelRequested) {
        await _cancelAttempt(attempt);
        return const StudioUpdateInstallResult();
      }
      attempt.permit.mark(ResourcePhase.active);
      await for (final snapshot in operation.events) {
        if (!_closed) updater.apply(snapshot);
      }
      await operation.finishPreparation();
      attempt.joined = true;
      if (_closed || attempt.cancelRequested)
        return const StudioUpdateInstallResult();
      if (state is ReadyUpdaterStateSnapshot &&
          state.update?.version == version) {
        request.publish(
          const StudioUpdateRequest(StudioUpdateRequestPhase.ready),
        );
        return StudioUpdateInstallResult(readyVersion: version);
      }
      final failure = state;
      request.publish(
        StudioUpdateRequest(
          failure is InstallFailedUpdaterStateSnapshot &&
                  failure.error.code == 'cancelled'
              ? StudioUpdateRequestPhase.cancelled
              : StudioUpdateRequestPhase.failed,
        ),
      );
      return const StudioUpdateInstallResult();
    } catch (error, stack) {
      if (attempt.operation == null &&
          error is! StudioUpdatePreparationRejected) {
        // A lost reply cannot prove that the native owner was never created.
        attempt.cleanupFailure = error;
      } else if (attempt.operation != null) {
        try {
          await _cancelAttempt(attempt);
        } catch (cleanupError) {
          attempt.cleanupFailure = cleanupError;
        }
      }
      if (!_closed) {
        // Failed command/observation only: canonical resync never invents Ready.
        try {
          updater.apply(await api.read());
        } catch (_) {
          /* Preserve the original failure. */
        }
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      if (!attempt.opened.isCompleted) attempt.opened.complete(null);
      if ((attempt.operation == null && attempt.cleanupFailure == null) ||
          attempt.joined) {
        attempt.operation?.dispose();
        attempt.permit.release();
        _attempts.remove(attempt.id);
      } else {
        attempt.cleanupFailure ??= StateError(
          'Update completion was not confirmed',
        );
        attempt.permit.mark(ResourcePhase.unresolved);
      }
      if (!_closed && attempt.cancelRequested && attempt.joined) {
        request.publish(
          const StudioUpdateRequest(StudioUpdateRequestPhase.cancelled),
        );
      }
    }
  }

  Future<void> _cancelAttempt(_UpdateAttempt attempt) {
    if (attempt.joined) return Future.value();
    return attempt.cancelTask ??= _cancel(attempt);
  }

  Future<void> _cancel(_UpdateAttempt attempt) async {
    final operation = attempt.operation ?? await attempt.opened.future;
    if (operation == null) {
      if (attempt.cleanupFailure case final error?) throw error;
      return;
    }
    attempt.permit.mark(ResourcePhase.retiring);
    try {
      await operation.cancel();
      attempt.joined = true;
      attempt.cleanupFailure = null;
    } catch (error) {
      attempt.cleanupFailure = error;
      attempt.permit.mark(ResourcePhase.unresolved);
      rethrow;
    }
  }

  Future<void> cancelInstall() async {
    if (_closed) return;
    final active = _active;
    if (active != null) {
      active.cancelRequested = true;
      request.publish(
        const StudioUpdateRequest(StudioUpdateRequestPhase.cancelling),
      );
      await _cancelAttempt(active);
      if (!_closed)
        request.publish(
          const StudioUpdateRequest(StudioUpdateRequestPhase.cancelled),
        );
    } else if (enabled) {
      request.publish(
        const StudioUpdateRequest(StudioUpdateRequestPhase.cancelling),
      );
      try {
        await _rpc('automatic-cancel', api.cancelAutomaticUpdate);
        if (!_closed)
          request.publish(
            const StudioUpdateRequest(StudioUpdateRequestPhase.cancelled),
          );
      } catch (error) {
        if (!_closed)
          request.publish(
            StudioUpdateRequest(StudioUpdateRequestPhase.failed, error: error),
          );
        rethrow;
      }
    }
  }

  /// Every caller joins the first close and its original absolute deadline.
  Future<CloseReport> close({DateTime? deadline}) =>
      _closing ??= _close(deadline);

  Future<CloseReport> retryCleanup({DateTime? deadline}) {
    if (!_closed)
      throw StateError('Close the update client before retrying cleanup');
    for (final attempt in _attempts.values) {
      attempt.cancelTask = null;
    }
    if (!_automaticStopRunning && _automaticPermit != null) {
      _automaticStopTask = null;
    }
    return _close(deadline);
  }

  Future<CloseReport> _close(DateTime? deadline) async {
    _closed = true;
    _observation?.cancel();
    _observationPermit?.release();
    for (final rpc in _rpcs.values) {
      rpc.permit.mark(ResourcePhase.retiring);
    }
    final work = _joinOwners();
    try {
      final remaining = deadline?.difference(DateTime.now());
      if (remaining == null) {
        await work;
      } else {
        await work.timeout(remaining.isNegative ? Duration.zero : remaining);
      }
    } catch (error) {
      _cleanupFailures['update-close'] = error;
      for (final attempt in _attempts.values) {
        attempt.permit.mark(ResourcePhase.unresolved);
      }
      for (final rpc in _rpcs.values) {
        rpc.permit.mark(ResourcePhase.unresolved);
      }
    }
    return _report();
  }

  Future<void> _joinOwners() async {
    await Future.wait([
      _stopAutomatic(),
      if (_checkTask case final pending?) _joinCheck(pending),
      for (final rpc in List.of(_rpcs.values)) rpc.done.future,
      for (final attempt in List.of(_attempts.values)) _stopAttempt(attempt),
    ]);
    _cleanupFailures.remove('update-close');
  }

  Future<void> _joinCheck(Future<void> pending) async {
    try {
      await pending;
    } catch (_) {
      // The check Future has reached its real terminal state. Its caller keeps
      // the business failure; it is not a failed native-resource cancellation.
    }
  }

  Future<void> _stopAutomatic() {
    if (!_automaticStarted || _automaticPermit == null) return Future.value();
    if (_automaticStopTask case final pending?) return pending;
    _automaticStopRunning = true;
    return _automaticStopTask = _joinAutomaticStop();
  }

  Future<void> _joinAutomaticStop() async {
    try {
      await _automaticTask;
      await _rpc('automatic-close', api.cancelAutomaticUpdate);
      _automaticPermit?.release();
      _automaticPermit = null;
      _cleanupFailures.remove('automatic-update');
    } catch (error) {
      _cleanupFailures['automatic-update'] = error;
      _automaticPermit?.mark(ResourcePhase.unresolved);
    } finally {
      _automaticStopRunning = false;
    }
  }

  Future<void> _stopAttempt(_UpdateAttempt attempt) async {
    try {
      await attempt.opened.future;
      await _cancelAttempt(attempt);
      try {
        await attempt.task;
      } catch (error) {
        // A cancelled command may fail its progress stream. The real native
        // cancel ACK, rather than that command result, proves resource cleanup.
        if (!attempt.joined) rethrow;
      }
      if (attempt.joined && _attempts.containsKey(attempt.id)) {
        attempt.operation?.dispose();
        attempt.permit.release();
        _attempts.remove(attempt.id);
      }
    } catch (error) {
      attempt.cleanupFailure = error;
      if (!attempt.permit.isReleased)
        attempt.permit.mark(ResourcePhase.unresolved);
    }
  }

  CloseReport _report() => CloseReport(
    unresolved: [
      if (_closed && _automaticPermit != null)
        UnresolvedResource(
          owner: 'automatic-update',
          attemptId: const AttemptId(0),
          reason:
              _cleanupFailures['automatic-update'] ??
              StateError('Automatic update cancellation is pending'),
        ),
      if (_closed)
        for (final rpc in _rpcs.values)
          UnresolvedResource(
            owner: 'update-rpc:${rpc.name}',
            attemptId: AttemptId(rpc.id),
            reason: StateError('Update RPC has not reached its terminal state'),
          ),
      for (final attempt in _attempts.values)
        UnresolvedResource(
          owner: 'update:${attempt.id}',
          attemptId: AttemptId(attempt.id),
          reason:
              attempt.cleanupFailure ??
              StateError('Update owner is still joining'),
        ),
      for (final entry in _cleanupFailures.entries)
        if (entry.key != 'automatic-update' || _automaticPermit == null)
          UnresolvedResource(
            owner: entry.key,
            attemptId: const AttemptId(0),
            reason: entry.value,
          ),
    ],
  );
}

final class _UpdateRpc {
  _UpdateRpc(this.id, this.name, this.permit);
  final int id;
  final String name;
  final ResourcePermit permit;
  final Completer<void> done = Completer();
}

final class _UpdateAttempt {
  _UpdateAttempt(this.id, this.permit);
  final int id;
  final ResourcePermit permit;
  final Completer<StudioUpdateOperation?> opened = Completer();
  StudioUpdateOperation? operation;
  Future<StudioUpdateInstallResult>? task;
  Future<void>? cancelTask;
  Object? cleanupFailure;
  bool joined = false;
  bool cancelRequested = false;
}

bool _isInstalling(UpdaterStateSnapshot state) =>
    state is DownloadingUpdaterStateSnapshot ||
    state is VerifyingUpdaterStateSnapshot ||
    state is InstallerLaunchedUpdaterStateSnapshot;
