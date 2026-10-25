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
  bool _cleaningDone = false;
  bool _closedOnce = false;
  Object? lastCause;
  StackTrace? lastStack;

  bool get sealed => _sealed;
  int nextAttempt() => ++_sequence;

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
    if (!_closedOnce || (retry && _cleaningDone)) {
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
    } else {
      seal();
    }
    final cleaning = _cleaning!;
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

  Future<void> _cleanup({required bool retry}) async {
    final closing = [
      for (final resource in List.of(_resources))
        Future<void>.sync(() => resource.cleanup(retry: retry)).then(
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
    _removeReleased();
  }

  void _removeReleased() => _resources.removeWhere(
    (resource) =>
        resource.released &&
        resource.issues.isEmpty &&
        !_resourceIssues.containsKey(resource),
  );

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
