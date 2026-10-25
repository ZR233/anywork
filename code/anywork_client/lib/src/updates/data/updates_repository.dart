import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/update_values.dart';
import '../domain/updates_repository.dart';
import '../domain/updates_state.dart';
import 'updates_actions.dart';
import 'updates_lifecycle.dart';
import 'updates_mirror.dart';
import 'updates_port.dart';
import 'updates_read_pins.dart';
import 'updates_reader.dart';

/// Both capabilities borrow the same domain owner. U3 alone decides platform
/// enablement, explicitly starts automatic work, and owns application exit.
({UpdatesRepository repository, UpdatesLifecycle lifecycle})
createUpdatesRepository({
  required UpdatesPort port,
  required ResourceBudget budget,
  required OperationRecorder operations,
  required UpdateControls controls,
}) {
  final owner = _UpdatesRepository(port, budget, operations, controls);
  return (repository: owner, lifecycle: owner);
}

final class _UpdatesRepository implements UpdatesRepository, UpdatesLifecycle {
  _UpdatesRepository(
    UpdatesPort port,
    ResourceBudget budget,
    OperationRecorder operations,
    this.controls,
  ) : _tasks = ResourceLifetime(budget),
      _reads = ResourceLifetime(budget) {
    _mirror = UpdatesMirror(port, _reads);
    final pins = UpdatesReadPins(port, _mirror, _reads);
    _mirror.adopted = pins.adopted;
    _reader = UpdatesReads(_mirror, pins, _reads);
    _actions = UpdatesActions(
      port,
      _mirror,
      _reader,
      _tasks,
      operations,
      controls,
    );
  }

  @override
  final UpdateControls controls;
  final ResourceLifetime _tasks;
  final ResourceLifetime _reads;
  late final UpdatesMirror _mirror;
  late final UpdatesReads _reader;
  late final UpdatesActions _actions;
  Future<void>? _closing;
  bool _closingDone = false;
  bool _closeStarted = false;
  bool _readsStarted = false;
  bool _publisherClosed = false;
  bool _sealed = false;
  DateTime? _firstDeadline;
  late int _closeAttempt;
  final List<FeedCloseIssue> _closeIssues = [];
  final List<(Object, StackTrace)> _causes = [];

  @override
  ReadonlyLatestValue<UpdatesState> get state => _mirror.source.readonly;
  void _admit() {
    if (_sealed) throw resourceCancelled;
  }

  @override
  OperationTicket<Unit> check() {
    _admit();
    return _actions.check();
  }

  @override
  OperationTicket<UpdatePreparationResult> prepare() {
    _admit();
    return _actions.prepare();
  }

  @override
  OperationTicket<Unit> cancelPreparation() {
    _admit();
    return _actions.cancelPreparation();
  }

  @override
  OperationTicket<Unit> startAutomaticOnce() {
    _admit();
    return _actions.automaticOnce();
  }

  @override
  Future<void> loadValue() {
    _admit();
    return _reader.value();
  }

  @override
  Future<UpdateSummary> loadSummary() {
    _admit();
    return _reader.summary();
  }

  @override
  Future<UpdateDetails> loadDetails() {
    _admit();
    return _reader.details();
  }

  @override
  void seal() {
    // Stop external business/read/observation admission first. The read lifetime
    // stays open for the original accepted tasks' remaining finish-target work.
    if (_sealed) return;
    _sealed = true;
    try {
      _mirror.source.seal();
    } catch (error, stack) {
      _causes.add((error, stack));
      _closeIssues.add(resourceCleanupIssue(error, CleanupRecovery.terminal));
    } finally {
      _tasks.seal();
    }
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) {
    if (!_closeStarted) {
      _closeStarted = true;
      _firstDeadline = deadline;
      _closeAttempt = _tasks.nextAttempt();
      _beginClose(retry: false);
    } else {
      seal();
    }
    return _observe(_effectiveDeadline(deadline));
  }

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) {
    if (!_closeStarted)
      throw resourceProtocol(
        'Close Updates before retrying its original cleanup.',
      );
    _beginClose(retry: true);
    return _observe(_effectiveDeadline(deadline));
  }

  DateTime? _effectiveDeadline(DateTime? requested) {
    final first = _firstDeadline;
    return first == null
        ? requested
        : requested != null && requested.isBefore(first)
        ? requested
        : first;
  }

  void _beginClose({required bool retry}) {
    if (_closing != null && (!_closingDone || !retry)) return;
    final done = Completer<void>();
    _closing = done.future;
    _closingDone = false;
    // Register the original closing Future before synchronous seal callbacks.
    seal();
    unawaited(
      Future<void>.sync(() => _join(retry: retry)).then<void>(
        (_) {
          _closingDone = true;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          _causes.add((error, stack));
          _closeIssues.add(
            resourceCleanupIssue(error, CleanupRecovery.terminal),
          );
          _closingDone = true;
          done.complete();
        },
      ),
    );
  }

  Future<void> _join({required bool retry}) async {
    // No deadline is applied to the real responsibility. Only _observe stops
    // waiting; this exact work continues and may then enter phase two.
    final tasks = await _tasks.close(retry: retry);
    _actions.reconcileCleanup();
    if (!tasks.complete || _actions.unresolved.isNotEmpty) return;
    final readRetry = _readsStarted && retry;
    _readsStarted = true;
    final reads = await _reads.close(retry: readRetry);
    if (reads.complete && !_publisherClosed) {
      _mirror.source.close();
      _publisherClosed = true;
    }
  }

  Future<CloseReport> _observe(DateTime? deadline) async {
    final closing = _closing!;
    if (deadline == null) {
      await closing;
    } else {
      final elapsed = Completer<void>();
      final remaining = deadline.difference(DateTime.now());
      final timer = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        () => elapsed.complete(),
      );
      try {
        await Future.any([closing, elapsed.future]);
      } finally {
        timer.cancel();
      }
    }
    // §27: merely inspect phase two when tasks have not joined. In particular,
    // do not seal/close it just to obtain a deadline report.
    final unresolved = <UnresolvedResource>[
      ..._tasks.snapshotReport().unresolved,
      ..._actions.unresolved,
      ..._reads.snapshotReport().unresolved,
      if (_closeIssues.isNotEmpty)
        UnresolvedResource(
          owner: 'updates-close',
          attemptId: AttemptId(_closeAttempt),
          issues: _closeIssues,
        ),
    ];
    if (!_publisherClosed && unresolved.isEmpty) {
      unresolved.add(
        UnresolvedResource(
          owner: 'updates-close',
          attemptId: AttemptId(_closeAttempt),
          issues: [
            !_closingDone
                ? resourcePendingIssue('updatesClosePending')
                : resourceCleanupIssue(
                    resourceProtocol(
                      'Updates has not completed both close phases.',
                    ),
                    CleanupRecovery.terminal,
                  ),
          ],
        ),
      );
    }
    return CloseReport(unresolved: unresolved);
  }
}
