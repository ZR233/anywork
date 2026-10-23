import 'dart:async';

import '../domain/budgets.dart';
import '../domain/closing.dart';
import 'resource_budget.dart';
import 'resource_errors.dart';
import 'resource_lifetime.dart';

/// Keeps a concrete immutable read scope pinned until all admitted calls finish.
final class PinnedReadOwner<C> implements ResourceOwner {
  PinnedReadOwner({
    required this.lifetime,
    required this.owner,
    required Future<C> Function() open,
    required this.request,
    required this.closeNative,
    required this.retryNative,
  }) : attempt = lifetime.nextAttempt() {
    lifetime.admit();
    permit = lifetime.budget.acquire(ResourceKind.readModel,
      owner: owner, phase: ResourcePhase.opening);
    final completion = Completer<C>();
    opened = completion.future;
    _openSettled = opened.then<void>((_) {}, onError: (Object _, StackTrace __) {
      _retiring = true;
      if (_active == 0) unawaited(cleanup(retry: false));
    });
    try {
      lifetime.register(this);
    } catch (_) {
      permit.release();
      rethrow;
    }
    lifetime.accepted<C>(this, () async {
      final C connection;
      try {
        connection = await open();
      } catch (error, stack) {
        lifetime.lastCause = error;
        lifetime.lastStack = stack;
        _openFailed = true;
        _retiring = true;
        rethrow;
      }
      _connection = connection;
      permit.mark(_retiring ? ResourcePhase.retiring : ResourcePhase.active);
      if (_closing) _requestNative(connection);
      return connection;
    }).then<void>(completion.complete, onError: completion.completeError);
  }

  final ResourceLifetime lifetime;
  @override
  final String owner;
  @override
  final int attempt;
  late final ResourcePermit permit;
  final void Function(C) request;
  final Future<FeedCloseReport> Function(C) closeNative;
  final Future<FeedCloseReport> Function(C) retryNative;
  late final Future<C> opened;
  late final Future<void> _openSettled;
  final Completer<void> _closeRequested = Completer();
  C? _connection;
  int _active = 0;
  Completer<void>? _idle;
  bool _retiring = false;
  bool _closing = false;
  bool _requestingNative = false;
  bool _openFailed = false;
  bool _released = false;
  Future<void>? _cleaning;
  bool _cleaningDone = false;
  FeedCloseReport? _report;
  FeedCloseIssue? _callIssue;
  final List<FeedCloseIssue> _terminalIssues = [];

  @override
  bool get released => _released;
  bool get accepting => !_retiring && !_released && !lifetime.sealed;

  Future<T> use<T>(Future<T> Function(C) action) {
    lifetime.admit();
    if (!accepting) throw resourceCancelled;
    if (_active++ == 0) _idle = Completer<void>();
      try {
      return lifetime.accepted<T>(this, () async {
        try {
        final connection = await opened;
        if (_closing) throw resourceCancelled;
        return await action(connection);
      } finally {
          _finishUse();
        }
    });
    } catch (_) {
      _finishUse();
      rethrow;
  }
  }

  void _finishUse() {
    if (--_active == 0) {
      _idle!.complete();
      if (_retiring) unawaited(cleanup(retry: false));
    }
  }

  /// Source advancement stops new admission, but lets original-version reads finish.
  void retire() {
    if (_retiring) return;
    _retiring = true;
    if (!_released) permit.mark(ResourcePhase.retiring);
    if (_active == 0) unawaited(cleanup(retry: false));
  }

  @override
  void requestClose() {
    _retiring = true;
    _closing = true;
    if (!_closeRequested.isCompleted) _closeRequested.complete();
    if (_released) return;
    permit.mark(_report?.outcome is UnresolvedFeedCloseOutcome || _callIssue != null
        || _terminalIssues.isNotEmpty ? ResourcePhase.unresolved : ResourcePhase.retiring);
    final connection = _connection;
    if (connection != null) _requestNative(connection);
  }

  void _requestNative(C connection) {
    if (_requestingNative || _report?.outcome is CleanFeedCloseOutcome) return;
    _requestingNative = true;
    try {
      request(connection);
    } catch (error, stack) {
      lifetime.lastCause = error;
      lifetime.lastStack = stack;
      _callIssue = resourceCleanupIssue(error, CleanupRecovery.retryClose);
    } finally {
      _requestingNative = false;
    }
  }

  @override
  Future<void> cleanup({required bool retry}) {
    if (_released) return Future.value();
    if (_cleaning != null && (!_cleaningDone || !retry)) return _cleaning!;
    _cleaningDone = false;
    final completion = Completer<void>();
    _cleaning = completion.future;
    _clean(retry: retry).then((_) {
      _cleaningDone = true;
      completion.complete();
    }, onError: (Object error, StackTrace stack) {
      lifetime.lastCause = error;
      lifetime.lastStack = stack;
      _callIssue = resourceCleanupIssue(error, CleanupRecovery.retryClose);
      if (!_released) permit.mark(ResourcePhase.unresolved);
      _cleaningDone = true;
      completion.complete();
    });
    return completion.future;
  }

  void _rememberReport(FeedCloseReport report) {
    if (_report != null && report.feedId != _report!.feedId) {
      throw resourceProtocol('The read close report changed its scope identity.');
    }
    _report = report;
    if (report.outcome case UnresolvedFeedCloseOutcome(:final issues)) {
      for (final issue in issues) {
        if (issue.recovery == CleanupRecovery.terminal && !_terminalIssues.contains(issue)) {
          _terminalIssues.add(issue);
        }
      }
    }
  }

  Future<void> _clean({required bool retry}) async {
    _retiring = true;
    if (!_closing && _active != 0) {
      await Future.any([_idle!.future, _closeRequested.future]);
    }
    requestClose();
    await _openSettled;
    if (_openFailed) {
      if (_active != 0) await _idle!.future;
      _released = true;
      permit.release();
      return;
    }
    final connection = _connection!;
    final native = Future<void>.sync(() async {
      final outcome = _report?.outcome;
      final recoverable = outcome is UnresolvedFeedCloseOutcome &&
          outcome.issues.any((issue) => issue.recovery != CleanupRecovery.terminal);
      if (outcome is CleanFeedCloseOutcome) return;
      if (outcome is UnresolvedFeedCloseOutcome && !(retry && recoverable)
          && _callIssue == null) return;
      try {
        _rememberReport(await (retry ? retryNative(connection) : closeNative(connection)));
        _callIssue = null;
      } catch (error, stack) {
        lifetime.lastCause = error;
        lifetime.lastStack = stack;
        _callIssue = resourceCleanupIssue(error, CleanupRecovery.retryClose);
      }
    });
    await Future.wait([native, if (_active != 0) _idle!.future]);
    if (_report?.outcome is CleanFeedCloseOutcome && _callIssue == null
        && _terminalIssues.isEmpty) {
      _released = true;
      permit.release();
    } else {
      permit.mark(ResourcePhase.unresolved);
    }
  }

  @override
  List<FeedCloseIssue> get issues {
    final issues = <FeedCloseIssue>[
      if (_report?.outcome case UnresolvedFeedCloseOutcome(:final issues)) ...issues,
      if (_callIssue case final issue?) issue,
      if (_active != 0 || _connection == null && !_openFailed
          || _cleaning != null && !_cleaningDone)
        resourcePendingIssue('readPending'),
    ];
    for (final issue in _terminalIssues) {
      if (!issues.contains(issue)) issues.add(issue);
    }
    return List.unmodifiable(issues);
  }
}
