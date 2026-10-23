import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/remote_repository.dart';
import 'remote_observation.dart';
import 'remote_page_owner.dart';
import 'remote_port.dart';

/// One fixed alias/directory intent; a new directory requires a new query owner.
final class RemoteDirectoryOwner implements RemoteDirectoryQuery {
  RemoteDirectoryOwner({
    required this.port,
    required this.budget,
    required this.alias,
    required this.initialPath,
    required this.id,
    required this.permit,
    required this.onClean,
  });
  final RemotePort port;
  final ResourceBudget budget;
  final String alias;
  final String? initialPath;
  final AttemptId id;
  final ResourcePermit permit;
  final void Function(RemoteDirectoryOwner) onClean;
  final Map<AttemptId, RemotePageOwner> _pages = {};
  final Set<String> _cursors = {};
  final Map<String, Set<FeedCloseIssue>> _cursorIssues = {};
  final Map<String, Map<FeedCloseIssue, (Object, StackTrace)>> _cursorCauses = {};
  final Map<String, Future<void>> _cursorCalls = {};
  final List<(Object, StackTrace)> _causes = [];
  RemoteValue<RemoteDirectoryState>? _source;
  Future<void>? _loading;
  Future<void>? _work;
  Future<void>? _cleanup;
  int _sequence = 0;
  int _generation = 0;
  bool _sealed = false;
  bool _closeStarted = false;
  bool _workSettled = true;
  bool _continuationUnknown = false;

  bool get complete => _sealed && _workSettled && _pages.isEmpty &&
      _cursors.isEmpty && _cleanup == null && _terminalIssues.isEmpty;

  @override
  ReadonlyLatestValue<RemoteDirectoryState> get state {
    final source = _source;
    if (source == null) throw remoteProtocol('Remote query has not returned its first page');
    return source.readonly;
  }

  Future<void> initialize() => _load(null);

  @override
  Future<void> loadMore() {
    if (_sealed) throw remoteCancelled();
    if (_loading case final task?) return task;
    // A published next cursor does not prove the previous page pin has joined.
    if (_continuationUnknown || _pages.isNotEmpty) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The previous native page did not complete; close this query before navigating again.',
        retryable: false,
        correlationId: '',
      );
    }
    final cursor = _source?.value.nextCursor;
    if (cursor == null) return Future.value();
    return _load(cursor);
  }

  Future<void> _load(String? cursor) {
    if (_sealed) throw remoteCancelled();
    final ResourcePermit pagePermit;
    try {
      pagePermit = budget.acquire(
        ResourceKind.readModel,
        owner: 'remote-page',
        phase: ResourcePhase.opening,
      );
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
    final generation = ++_generation;
    final owner = RemotePageOwner(
      port: port,
      alias: alias,
      path: _source?.value.path ?? initialPath,
      cursor: cursor,
      id: AttemptId(++_sequence),
      permit: pagePermit,
      onCursor: (previous, next) {
        if (previous != null) {
          _cursors.remove(previous);
          _cursorIssues.remove(previous);
          _cursorCauses.remove(previous);
        }
        if (next != null) _cursors.add(next);
      },
    );
    _pages[owner.id] = owner;
    final settled = Completer<void>();
    _work = settled.future;
    _workSettled = false;
    final result = Completer<void>();
    final task = result.future;
    _loading = task;
    unawaited(task.then<void>((_) {
      _finishPage(task, settled);
    }, onError: (Object error, StackTrace stack) {
      _finishPage(task, settled);
    }));
    if (_source case final source?) {
      source.publish(source.value.copyWith(loading: true, error: null));
    }
    unawaited(_runPage(owner, generation).then<void>((_) {
      result.complete();
    }, onError: (Object error, StackTrace stack) {
      result.completeError(error, stack);
    }));
    return task;
  }

  void _finishPage(Future<void> task, Completer<void> settled) {
    if (identical(_loading, task)) _loading = null;
    _workSettled = true;
    settled.complete();
  }

  Future<void> _runPage(RemotePageOwner owner, int generation) async {
    try {
      if (_sealed || generation != _generation) {
        owner.cancelBeforeOpen();
        throw remoteCancelled();
      }
      final listing = await owner.run();
      if (!_sealed && generation == _generation) {
        final value = RemoteDirectoryState(
          alias: alias,
          path: listing.path,
          parent: listing.parent,
          entries: List.unmodifiable(listing.entries),
          nextCursor: listing.nextCursor,
          loading: false,
          error: null,
        );
        final source = _source;
        if (source == null) {
          _source = RemoteValue(value, budget, 'remote-directory');
          permit.mark(ResourcePhase.active);
        } else {
          // Native pagination replaces the current page, never appends a scan.
          source.publish(value);
        }
      }
    } catch (error, stack) {
      _causes.add((error, stack));
      _continuationUnknown = true;
      if (!_sealed && generation == _generation && _source != null) {
        _source!.publish(_source!.value.copyWith(
          loading: false,
          nextCursor: null,
          error: error is StudioFailure ? error : remoteProtocol('Remote page failed'),
        ));
      }
      rethrow;
    } finally {
      await owner.close();
      _releasePage(owner);
    }
  }

  void _releasePage(RemotePageOwner owner) {
    if (!owner.complete) {
      owner.permit.mark(ResourcePhase.unresolved);
      return;
    }
    owner.permit.release();
    _pages.remove(owner.id);
  }

  @override
  void requestClose() {
    if (_sealed) return;
    _sealed = true;
    ++_generation;
    _source?.close();
    permit.mark(ResourcePhase.retiring);
    for (final owner in _pages.values) {
      owner.requestClose();
    }
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) {
    requestClose();
    if (!_closeStarted) {
      _closeStarted = true;
      beginCleanup(retry: false);
    }
    return _wait(deadline);
  }

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) {
    if (!_closeStarted) throw remoteProtocol('Close the remote query before retrying cleanup');
    beginCleanup(retry: true);
    return _wait(deadline);
  }

  /// Repository-wide barrier: all admitted opens/reads hand off their cursors
  /// before the repository starts closing any newly collected native cursor.
  Future<bool> settleAccepted({required bool retry}) async {
    await _work;
    await Future.wait([
      for (final owner in List.of(_pages.values))
        owner.close(retry: retry).then((_) => _releasePage(owner)),
    ]);
    return _pages.values.every((owner) => owner.handedOff);
  }

  final List<FeedCloseIssue> _terminalIssues = [];

  void beginCleanup({required bool retry}) {
    requestClose();
    _closeStarted = true;
    if (_cleanup != null || complete) return;
    final task = _close(retry);
    _cleanup = task;
    unawaited(task.then<void>((_) {
      if (identical(_cleanup, task)) _cleanup = null;
      _releaseIfComplete();
    }, onError: (Object error, StackTrace stack) {
      _causes.add((error, stack));
      _terminalIssues.add(remoteIssue(error, 'remote-query-join', CleanupRecovery.terminal));
      if (identical(_cleanup, task)) _cleanup = null;
    }));
  }

  Future<void> _close(bool retry) async {
    if (!await settleAccepted(retry: retry)) return;
    await Future.wait([
      for (final cursor in List.of(_cursors)) _closeCursor(cursor),
    ]);
  }

  Future<void> _closeCursor(String cursor) {
    if (_cursorCalls[cursor] case final task?) return task;
    final task = _releaseCursor(cursor);
    _cursorCalls[cursor] = task;
    unawaited(task.then<void>((_) {
      if (identical(_cursorCalls[cursor], task)) _cursorCalls.remove(cursor);
    }));
    return task;
  }

  Future<void> _releaseCursor(String cursor) async {
    try {
      await port.closeDirectory(alias, cursor);
      _cursors.remove(cursor);
      _cursorIssues.remove(cursor);
      _cursorCauses.remove(cursor);
    } catch (error, stack) {
      final issue = remoteIssue(
        error,
        'remote-directory-cursor',
        CleanupRecovery.retryClose,
      );
      _cursorIssues.putIfAbsent(cursor, () => {}).add(issue);
      _cursorCauses.putIfAbsent(cursor, () => {}).putIfAbsent(issue, () => (error, stack));
    }
  }

  void _releaseIfComplete() {
    if (complete && _terminalIssues.isEmpty) {
      if (!permit.isReleased) {
      permit.release();
        onClean(this);
      }
    } else if (!permit.isReleased) {
      permit.mark(ResourcePhase.unresolved);
    }
  }

  Future<CloseReport> _wait(DateTime? deadline) async {
    final task = _cleanup;
    if (task != null) {
      try {
        if (deadline == null) {
          await task;
        } else {
          final remaining = deadline.difference(DateTime.now());
          await task.timeout(remaining.isNegative ? Duration.zero : remaining);
        }
      } on TimeoutException {
        // Original completion stays owned and is not replaced by this timeout.
      } catch (_) {
        // The handler registered by beginCleanup retains the terminal cause
        // and issue; close still returns the complete typed current report.
      }
    }
    return report;
  }

  CloseReport get report => CloseReport(unresolved: [
    for (final page in _pages.values)
      UnresolvedResource(
        owner: 'remote-page',
        attemptId: page.id,
        issues: [
          ...page.issues,
          if (page.pending || page.issues.isEmpty) _pending,
        ],
      ),
    if (!_workSettled || _cursors.isNotEmpty || _cursorCalls.isNotEmpty ||
        _terminalIssues.isNotEmpty)
      UnresolvedResource(
        owner: 'remote-directory',
        attemptId: id,
        issues: [
          for (final issues in _cursorIssues.values) ...issues,
          ..._terminalIssues,
          if (!_workSettled || _cursorCalls.isNotEmpty) _pending,
          if (_workSettled && _cursorCalls.isEmpty && _cursors.isNotEmpty &&
              _cursorIssues.isEmpty)
            FeedCloseIssue(
              diagnostic: const StudioShutdownIssue(
                stage: 'remote-directory',
                code: 'cursorStillOwned',
                message: 'Native cursor cleanup is waiting for accepted page handoff.',
                retryable: true,
                correlationId: '',
              ),
              recovery: _pages.values.any((page) => !page.handedOff &&
                  page.issues.any((issue) => issue.recovery == CleanupRecovery.terminal))
                  ? CleanupRecovery.terminal : CleanupRecovery.retryClose,
            ),
        ],
      ),
  ]);

  static const _pending = FeedCloseIssue(
    diagnostic: StudioShutdownIssue(
      stage: 'remote-directory',
      code: 'awaitingCompletion',
      message: 'Accepted remote directory work is still running.',
      retryable: true,
      correlationId: '',
    ),
    recovery: CleanupRecovery.awaitCompletion,
  );
}
