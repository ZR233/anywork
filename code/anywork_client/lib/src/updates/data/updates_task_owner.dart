import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/updates_state.dart';
import 'update_task.dart';

/// One real native task, including an opening reply and both RPC completions.
/// Its permit outlives start ACK, finish and the caller's deadline observation.
final class UpdatesTaskOwner implements ResourceOwner {
  UpdatesTaskOwner({required this.lifetime, required this.owner,
      required this.operationId, required Future<UpdateTaskConnection> Function() open,
      required void Function() beforeStart}) : _open = open, attempt = lifetime.nextAttempt() {
    lifetime.admit();
    permit = lifetime.budget.acquire(ResourceKind.readModel,
      owner: owner, phase: ResourcePhase.opening);
    final result = Completer<UpdatesReadTarget>();
    completion = result.future;
    _settled = completion.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    try { lifetime.register(this); } catch (_) { permit.release(); rethrow; }
    // The complete native responsibility exists before open can call back/seal.
    final launch = Completer<void>();
    lifetime.run(owner, () async {
      await launch.future;
      return await _drive(_open, beforeStart);
    }).then<void>(result.complete, onError: result.completeError);
    launch.complete();
  }

  final ResourceLifetime lifetime;
  @override
  final String owner;
  final OperationId operationId;
  final Future<UpdateTaskConnection> Function() _open;
  @override
  final int attempt;
  late final ResourcePermit permit;
  late final Future<UpdatesReadTarget> completion;
  late final Future<void> _settled;
  final Completer<void> _opened = Completer<void>();
  final Completer<void> _decision = Completer<void>();
  final List<({String stage, Object cause, StackTrace stack})> _causes = [];
  final List<FeedCloseIssue> _terminal = [];
  final List<FeedCloseIssue> _foreignIssues = [];
  UpdateTaskConnection? _connection;
  UpdateTaskIdentity? _identity;
  Future<void>? _startSettled;
  Future<void>? _finishSettled;
  Object? _startError;
  StackTrace? _startStack;
  bool _openRejected = false;
  bool _closing = false;
  bool _cancelSent = false;
  bool startIssued = false;
  bool _hasTarget = false;
  bool _released = false;
  Future<void>? _cleaning;
  bool _cleaningDone = false;
  UpdateTaskCloseReport? _report;
  FeedCloseIssue? _callIssue;
  FeedCloseIssue? _cancelIssue;

  @override
  bool get released => _released;
  bool get hasConnection => _connection != null;

  void remember(Object error, StackTrace stack, String stage) {
    _causes.add((stage: stage, cause: error, stack: stack));
    lifetime.lastCause = error; lifetime.lastStack = stack;
  }

  void terminal(Object error, StackTrace stack, String stage) {
    remember(error, stack, stage);
    final issue = resourceCleanupIssue(error is CommandDispatchFailure ? error.failure : error,
      CleanupRecovery.terminal);
    if (!_terminal.contains(issue)) _terminal.add(issue);
    if (!_released) permit.mark(ResourcePhase.unresolved);
  }

  void decisionComplete() {
    if (!_decision.isCompleted) _decision.complete();
  }

  Future<UpdatesReadTarget> _drive(Future<UpdateTaskConnection> Function() open,
      void Function() beforeStart) async {
    final UpdateTaskConnection connection;
    try {
      connection = await open();
      _connection = connection;
      if (_closing) { requestClose(); unawaited(cleanup(retry: false)); }
    } catch (error, stack) {
      remember(error, stack, 'open');
      _openRejected = error is RejectedCommandDispatchFailure;
      if (!_openRejected) terminal(error, stack, 'unknown-open');
      rethrow;
    } finally { _opened.complete(); }
    try {
      final identity = connection.identity;
      if (identity.operationId != operationId || identity.runtimeEpoch.isEmpty || identity.taskId.isEmpty) {
        throw resourceProtocol('The update task belongs to another operation.');
      }
      _identity = identity;
    } catch (error, stack) {
      terminal(error, stack, 'identity'); rethrow;
    }
    if (_closing) {
      requestClose(); unawaited(cleanup(retry: false));
      throw const CommandDispatchFailure.rejected(failure: resourceCancelled);
    }
    permit.mark(ResourcePhase.active);
    // Install the complete finish observer before invoking start, including a
    // synchronous exception or reentrant close in either external callback.
    final finished = Completer<UpdatesReadTarget>();
    _finishSettled = finished.future.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      remember(error, stack, 'finish');
    });
    Future<UpdatesReadTarget>.sync(connection.finish).then<void>(finished.complete,
      onError: finished.completeError);
    try {
      beforeStart();
      if (_closing) throw const CommandDispatchFailure.rejected(failure: resourceCancelled);
      final started = Completer<void>();
      _startSettled = started.future.then<void>((_) {}, onError: (Object error, StackTrace stack) {
        _startError = error; _startStack = stack; remember(error, stack, 'start');
        if (error is RejectedCommandDispatchFailure) {
          if (_hasTarget) terminal(resourceProtocol('An update completed after its start was explicitly rejected.'),
            stack, 'contradictory-start');
          requestClose(); unawaited(cleanup(retry: false));
        }
      });
      startIssued = true;
      Future<void>.sync(connection.start).then<void>((_) => started.complete(), onError: started.completeError);
    } catch (error, stack) {
      _startError = error; _startStack = stack;
      requestClose(); unawaited(cleanup(retry: false));
      Error.throwWithStackTrace(error, stack);
    }
    try {
      // A lost start ACK does not cause another start or replace this finish.
      final target = await finished.future;
      _hasTarget = true;
      if (_startError is RejectedCommandDispatchFailure) {
        terminal(resourceProtocol('An update completed after its start was explicitly rejected.'),
          _startStack!, 'contradictory-start');
      }
      return target;
    } catch (error, stack) {
      final startError = _startError;
      if (startError is RejectedCommandDispatchFailure) {
        Error.throwWithStackTrace(startError, _startStack!);
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// Cancels the original handle, never whichever task becomes active later.
  @override
  void requestClose() {
    _closing = true;
    if (_released) return;
    permit.mark(_terminal.isNotEmpty || _callIssue != null || _cancelIssue != null ||
        _report?.outcome is UnresolvedFeedCloseOutcome ? ResourcePhase.unresolved : ResourcePhase.retiring);
    final connection = _connection;
    if (connection == null || _cancelSent || _report?.outcome is CleanFeedCloseOutcome) return;
    _cancelSent = true;
    try { connection.requestCancel(); } catch (error, stack) {
      remember(error, stack, 'cancel');
      _cancelIssue = resourceCleanupIssue(error, CleanupRecovery.retryClose);
    }
  }

  @override
  Future<void> cleanup({required bool retry}) {
    requestClose();
    if (_released) return Future.value();
    if (_cleaning != null && (!_cleaningDone || !retry)) return _cleaning!;
    final done = Completer<void>(); _cleaning = done.future; _cleaningDone = false;
    _clean(retry: retry).then<void>((_) { _cleaningDone = true; done.complete(); },
      onError: (Object error, StackTrace stack) {
        remember(error, stack, 'cleanup');
        _callIssue = resourceCleanupIssue(error, CleanupRecovery.retryClose);
        if (!_released) permit.mark(ResourcePhase.unresolved);
        _cleaningDone = true; done.complete();
      });
    return done.future;
  }

  void _acceptReport(UpdateTaskCloseReport report) {
    if (_identity == null || report.identity != _identity || report.identity.operationId != operationId) {
      if (report.outcome case UnresolvedFeedCloseOutcome(:final issues)) {
        for (final issue in issues) { if (!_foreignIssues.contains(issue)) _foreignIssues.add(issue); }
      }
      final error = resourceProtocol('The update close report belongs to another task.');
      terminal(error, StackTrace.current, 'close-identity'); throw error;
    }
    _report = report;
    if (report.outcome case UnresolvedFeedCloseOutcome(:final issues)) {
      for (final issue in issues) {
        if (issue.recovery == CleanupRecovery.terminal && !_terminal.contains(issue)) _terminal.add(issue);
      }
    }
  }

  Future<void> _clean({required bool retry}) async {
    await _opened.future;
    requestClose();
    final connection = _connection;
    final native = Future<void>.sync(() async {
      if (connection == null) return;
      final outcome = _report?.outcome;
      if (outcome is CleanFeedCloseOutcome) return;
      if (outcome is UnresolvedFeedCloseOutcome && _callIssue == null &&
          !(retry && outcome.issues.any((issue) => issue.recovery != CleanupRecovery.terminal))) return;
      try {
        _acceptReport(await (retry ? connection.retryClose() : connection.close()));
        _callIssue = null;
        // Clean proves the actual cancel/join goal, not a fabricated cancel ACK.
        if (_report?.outcome is CleanFeedCloseOutcome) _cancelIssue = null;
      } catch (error, stack) {
        remember(error, stack, 'native-close');
        _callIssue = resourceCleanupIssue(error, CleanupRecovery.retryClose);
      }
    });
    await Future.wait([native, _settled, _decision.future]);
    // These may have been installed during late open/start handoff.
    await Future.wait([if (_startSettled case final work?) work, if (_finishSettled case final work?) work]);
    if ((connection == null ? _openRejected : _report?.outcome is CleanFeedCloseOutcome) &&
        _terminal.isEmpty && _callIssue == null && _cancelIssue == null) {
      _released = true; permit.release();
    } else { permit.mark(ResourcePhase.unresolved); }
  }

  @override
  List<FeedCloseIssue> get issues {
    final values = <FeedCloseIssue>[
      if (_report?.outcome case UnresolvedFeedCloseOutcome(:final issues)) ...issues,
      if (_callIssue case final issue?) issue,
      if (_cancelIssue case final issue?) issue,
    ];
    for (final issue in [..._terminal, ..._foreignIssues]) { if (!values.contains(issue)) values.add(issue); }
    if (!_opened.isCompleted || !_decision.isCompleted || _cleaning != null && !_cleaningDone) {
      values.add(resourcePendingIssue('updateTaskPending'));
    }
    return List.unmodifiable(values);
  }
}
