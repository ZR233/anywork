import 'dart:async';

import '../domain/closing.dart';
import '../domain/failures.dart';
import '../domain/identity.dart';
import 'resource_budget.dart';
import 'resource_errors.dart';

abstract interface class ResourceOwner {
  int get attempt;
  String get owner;
  bool get released;
  void requestClose();
  Future<void> cleanup({required bool retry});
  List<FeedCloseIssue> get issues;
}

/// Tracks admitted feed/read work, not business state or UI futures.
final class ResourceLifetime {
  ResourceLifetime(this.budget);
  final ResourceBudget budget;
  bool _sealed = false;
  int _sequence = 0;
  final Map<int, _ResourceWork> _work = {};
  final Set<ResourceOwner> _resources = Set.identity();
  final List<void Function()> _sealCallbacks = [];
  final Map<ResourceOwner, FeedCloseIssue> _resourceIssues = Map.identity();
  final List<UnresolvedResource> _terminalIssues = [];
  Future<void>? _cleaning;
  Future<void>? _retrying;
  bool _cleaningDone = false;
  bool _closedOnce = false;
  Object? lastCause;
  StackTrace? lastStack;

  bool get sealed => _sealed;
  int nextAttempt() => ++_sequence;

  /// The close responsibility this lifetime is currently joining, if any. A
  /// later explicit retry installs a newer one, so a caller that must join the
  /// original work to its real end follows this instead of stopping at a
  /// snapshot taken before that retry finished.
  Future<void>? get closing => _cleaning;

  void admit() {
    if (_sealed) throw resourceCancelled;
  }

  /// Synchronous admission hooks only; async work belongs to accepted/ResourceOwner.
  void onSeal(void Function() callback) {
    if (_sealed) {
      _sealOne(callback);
    } else {
      _sealCallbacks.add(callback);
    }
  }

  void register(ResourceOwner resource) {
    admit();
    _removeReleased();
    admit();
    _resources.add(resource);
  }

  /// Ordinary domain work: one complete responsibility, registered before action.
  Future<T> run<T>(String label, Future<T> Function() action) {
    admit();
    final id = nextAttempt();
    final result = Completer<T>();
    final work = _ResourceWork(id, label);
    _work[id] = work;
    unawaited(
      Future<T>.sync(action).then(
        (value) {
          _work.remove(id);
          work.done.complete();
          result.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          lastCause = error;
          lastStack = stack;
          _work.remove(id);
          work.done.complete();
          result.completeError(error, stack);
        },
      ),
    );
    return result.future;
  }

  /// New work still needs admission and this exact registered, unreleased owner.
  /// Late handoff after seal remains inside its original registered Future.
  Future<T> accepted<T>(ResourceOwner resource, Future<T> Function() action) {
    admit();
    if (!_resources.contains(resource)) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'The resource owner is not registered in this lifetime.',
        retryable: false,
        correlationId: 'resources',
      );
    }
    final label = resource.owner;
    if (resource.released) throw resourceCancelled;
    // run rechecks seal after reading owner diagnostics; no string bypass exists.
    return run(label, action);
  }

  void _sealOne(void Function() callback) {
    try {
      callback();
    } catch (error, stack) {
      lastCause = error;
      lastStack = stack;
      _terminalIssues.add(
        UnresolvedResource(
          owner: 'resource-lifetime:seal',
          attemptId: AttemptId(nextAttempt()),
          issues: [resourceCleanupIssue(error, CleanupRecovery.terminal)],
        ),
      );
    }
  }

  void seal() {
    if (_sealed) return;
    _sealed = true;
    final callbacks = List.of(_sealCallbacks);
    _sealCallbacks.clear();
    for (final callback in callbacks) {
      _sealOne(callback);
    }
    // One failure cannot prevent independent owners receiving cancellation.
    for (final resource in List.of(_resources)) {
      try {
        resource.requestClose();
      } catch (error, stack) {
        lastCause = error;
        lastStack = stack;
        _resourceIssues[resource] = resourceCleanupIssue(
          error,
          CleanupRecovery.retryClose,
        );
      }
    }
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    final cleaning = retry ? _acceptRetry() : _startOrJoin();
    if (deadline == null) {
      await cleaning;
    } else {
      final timer = Completer<void>();
      final remaining = deadline.difference(DateTime.now());
      final alarm = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        () => timer.complete(),
      );
      try {
        await Future.any([cleaning, timer.future]);
      } finally {
        alarm.cancel();
      }
    }
    // A deadline only stops this observation, never the registered work.
    return snapshotReport();
  }

  /// The original close responsibility: start the first pass, or join the pass
  /// this lifetime is currently joining. An accepted retry is a newer
  /// responsibility of the same owners, so a plain close waits for it too.
  Future<void> _startOrJoin() {
    if (!_closedOnce) return _startPass(retry: false);
    seal();
    if (_retrying case final accepted?) return accepted;
    return _cleaning!;
  }

  Future<void> _startPass({required bool retry}) {
    _closedOnce = true;
    _cleaningDone = false;
    final done = Completer<void>();
    _cleaning = done.future;
    // Publish cleanup responsibility before seal callbacks can reenter close.
    seal();
    unawaited(
      Future<void>.sync(() => _cleanup(retry: retry)).then(
        (_) {
          _cleaningDone = true;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          lastCause = error;
          lastStack = stack;
          _terminalIssues.add(
            UnresolvedResource(
              owner: 'resource-lifetime:cleanup',
              attemptId: AttemptId(nextAttempt()),
              issues: [resourceCleanupIssue(error, CleanupRecovery.terminal)],
            ),
          );
          _cleaningDone = true;
          done.complete();
        },
      ),
    );
    return done.future;
  }

  /// Accepts exactly one explicit retry of these same registered owners.
  ///
  /// A retry that arrives while a pass is in flight is retained here instead of
  /// being folded into that pass: once the pass really ends, one retry pass
  /// follows on the same owners. A pass that already ended the whole
  /// responsibility is not repeated. Concurrent and overlapping retries join
  /// this one accepted retry instead of queueing more passes, and a caller
  /// deadline only bounds its own observation of it.
  Future<void> _acceptRetry() {
    if (_retrying case final accepted?) return accepted;
    final inFlight = _closedOnce && !_cleaningDone ? _cleaning : null;
    final done = Completer<void>();
    final accepted = done.future;
    _retrying = accepted;

    void settle() {
      if (identical(_retrying, accepted)) _retrying = null;
      if (!done.isCompleted) done.complete();
    }

    // A lifetime that was never closed has no earlier responsibility whose end
    // could be reused, so the explicit retry is its first pass. Afterwards,
    // nothing left registered means the responsibility already exited and the
    // same accepted retry must not repeat it.
    Future<void> retryPass() async {
      if (_closedOnce && !_pendingOwners) return;
      try {
        await _startPass(retry: true);
      } catch (_) {
        /* owners keep their own issues; the pass reports its own failure */
      }
    }

    if (inFlight == null) {
      // Install the retry responsibility in this same turn, so a concurrent
      // close observes it instead of the pass it replaced.
      unawaited(retryPass().whenComplete(settle));
    } else {
      // A pass never fails here: its terminal failure becomes an unresolved
      // resource of this lifetime, so the retained retry always gets its turn.
      unawaited(inFlight.whenComplete(retryPass).whenComplete(settle));
    }
    return accepted;
  }

  bool get _pendingOwners => _resources.isNotEmpty || _work.isNotEmpty;

  Future<void> _cleanup({required bool retry}) async {
    // One released owner can start work owned by another registered owner — a
    // capture releasing its attachment borrow, for example. Keep closing the
    // remaining owners until none of them becomes released, so the final report
    // is the real end state instead of the first pass' snapshot. Admission is
    // sealed here, so the registered set only shrinks and this always ends.
    var passRetry = retry;
    while (true) {
      final closing = [
        for (final resource in List.of(_resources))
          Future<void>.sync(() => resource.cleanup(retry: passRetry)).then(
            (_) {
              if (resource.released && resource.issues.isEmpty) {
                _resourceIssues.remove(resource);
              }
            },
            onError: (Object error, StackTrace stack) {
              lastCause = error;
              lastStack = stack;
              _resourceIssues[resource] = resourceCleanupIssue(
                error,
                CleanupRecovery.retryClose,
              );
            },
          ),
      ];
      await Future.wait(closing);
      // Late open handoff remains part of the same registered owner/work set.
      while (_work.isNotEmpty) {
        await Future.wait([for (final work in _work.values) work.done.future]);
      }
      if (_removeReleased() == 0) return;
      // Only the caller's first complete pass may advance the one explicit
      // retry it asked for. A later pass exists only because another owner
      // became released; retrying the same unresolved handle again here would
      // turn one explicit retry into several native calls.
      passRetry = false;
    }
  }

  int _removeReleased() {
    final released = [
      for (final resource in _resources)
        if (resource.released &&
            resource.issues.isEmpty &&
            !_resourceIssues.containsKey(resource))
          resource,
    ];
    _resources.removeAll(released);
    return released.length;
  }

  List<FeedCloseIssue> _issuesFor(ResourceOwner resource) {
    final issues = List<FeedCloseIssue>.of(resource.issues);
    final local = _resourceIssues[resource];
    if (local != null && !issues.contains(local)) issues.add(local);
    if (issues.isEmpty) issues.add(resourcePendingIssue('resourcePending'));
    return issues;
  }

  /// Snapshots registered responsibilities without starting or changing cleanup.
  ///
  /// An empty report does not mean admission is sealed or the lifetime is closed.
  CloseReport snapshotReport() => CloseReport(
    unresolved: [
      ..._terminalIssues,
      for (final resource in _resources)
        if (!resource.released ||
            _resourceIssues.containsKey(resource) ||
            resource.issues.isNotEmpty)
          UnresolvedResource(
            owner: resource.owner,
            attemptId: AttemptId(resource.attempt),
            issues: _issuesFor(resource),
          ),
      for (final work in _work.values)
        UnresolvedResource(
          owner: work.owner,
          attemptId: AttemptId(work.attempt),
          issues: [resourcePendingIssue('workPending')],
        ),
    ],
  );
}

final class _ResourceWork {
  _ResourceWork(this.attempt, this.owner);
  final int attempt;
  final String owner;
  final Completer<void> done = Completer();
}
