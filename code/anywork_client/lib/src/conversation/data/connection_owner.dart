import 'dart:async';

import '../../../resources_ports.dart';

const conversationCancelled = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'The original conversation owner is closing.',
  retryable: false,
  correlationId: 'conversation-cancelled',
);

StudioFailure conversationFailure(Object error) => switch (error) {
  StudioFailure() => error,
  ResourceBudgetExceeded() => error.failure,
  _ => const StudioFailure(
    code: StudioFailureCode.internal,
    message: 'The conversation resource failed.',
    retryable: false,
    correlationId: 'conversation-resource',
  ),
};

/// The object a diagnostic-visible state retains for [error].
///
/// A canonical typed failure keeps its [conversationFailure] projection, so its
/// code/retryable/correlationId stay available. Anything else keeps the original
/// object: reading its runtime type is the only evidence, and no message,
/// `toString()` or stack is copied.
Object conversationDiagnosticError(Object error) => switch (error) {
  StudioFailure() => error,
  ResourceBudgetExceeded() => error.failure,
  final unknown => unknown,
};

FeedCloseIssue conversationIssue(
  String stage,
  Object error,
  CleanupRecovery recovery,
) {
  final failure = conversationFailure(error);
  return FeedCloseIssue(
    diagnostic: StudioShutdownIssue(
      stage: stage,
      code: failure.code.name,
      message: failure.message,
      retryable: failure.retryable,
      correlationId: failure.correlationId,
    ),
    recovery: recovery,
  );
}

/// One real opening/handle. No business reducer, payload cache or replacement open.
/// Registered completion precedes adapter invocation, including synchronous errors.
final class ConversationConnectionOwner<C> {
  ConversationConnectionOwner({
    required this.label,
    required this.attemptId,
    required ResourceBudget budget,
    required ResourceKind kind,
    required void Function(C) requestClose,
    required Future<FeedCloseReport> Function(C) close,
    required Future<FeedCloseReport> Function(C) retryClose,
  }) : _budget = budget,
       _permit = budget.acquire(
         kind,
         owner: label,
         phase: ResourcePhase.opening,
       ),
       _requestNativeClose = requestClose,
       _nativeClose = close,
       _nativeRetry = retryClose {
    _opened.future.ignore();
  }

  final String label;
  final AttemptId attemptId;
  final ResourceBudget _budget;
  final ResourcePermit _permit;
  final void Function(C) _requestNativeClose;
  final Future<FeedCloseReport> Function(C) _nativeClose;
  final Future<FeedCloseReport> Function(C) _nativeRetry;
  final Completer<C> _opened = Completer<C>();
  final Completer<void> _openSettled = Completer<void>();
  final Set<Future<void>> _work = {};
  final List<Future<void> Function()> _cancel = [];
  final Map<int, FeedCloseIssue> _localIssues = {};
  // Owner-local evidence, never published or serialized. Later cleanup or
  // notification failures must not overwrite the original processing cause.
  final List<({FeedCloseIssue issue, Object cause, StackTrace stack})>
  _processingFailures = [];
  final Set<FeedCloseIssue> _terminalNative = {};
  C? _connection;
  Future<void>? _joining;
  Future<FeedCloseReport>? _nativeJoining;
  FeedCloseReport? _nativeReport;
  FeedCloseIssue? _nativeError;
  String? _expectedFeedId;
  bool _started = false;
  bool _closing = false;
  bool _nativeDone = false;
  bool _nativeRequested = false;
  bool _cancelStarted = false;
  bool _released = false;
  int _cancelSequence = 0;
  Object? lastCause;
  StackTrace? lastStack;
  StudioFailure? _synthesized;
  Object? _synthesizedCause;

  /// The original object behind [failure] when it is the synthesized projection
  /// of an unknown adapter error. Consumed once so a later failure cannot reuse a
  /// stale cause.
  Object? takeDiagnosticCause(StudioFailure failure) {
    if (!identical(failure, _synthesized)) return null;
    final cause = _synthesizedCause;
    _synthesized = null;
    _synthesizedCause = null;
    return cause;
  }

  bool get isClosing => _closing;
  bool get released => _released;
  int get pendingWork => _work.length;
  Future<C> get opened => _opened.future;
  C? get connection => _connection;

  /// Only an actually entered processing callback/ACK uses this path. Ordinary
  /// query failures and cancellation before callback entry are not terminal.
  void recordProcessingFailure(String stage, Object error, StackTrace stack) {
    _processingFailures.add((
      issue: conversationIssue(stage, error, CleanupRecovery.terminal),
      cause: error,
      stack: stack,
    ));
    lastCause = error;
    lastStack = stack;
  }

  void start(Future<C> Function() open) {
    if (_started) throw StateError('An opening owner cannot start twice');
    _started = true;
    if (_closing) {
      _opened.completeError(conversationCancelled);
      _openSettled.complete();
      return;
    }
    unawaited(
      Future<C>.sync(open).then(
        (connection) {
          _connection = connection;
          _permit.mark(
            _closing ? ResourcePhase.retiring : ResourcePhase.active,
          );
          if (_closing) {
            _requestNative();
            _opened.completeError(conversationCancelled);
          } else {
            _opened.complete(connection);
          }
          _openSettled.complete();
        },
        onError: (Object error, StackTrace stack) {
          lastCause = error;
          lastStack = stack;
          _opened.completeError(error, stack);
          _openSettled.complete();
        },
      ),
    );
  }

  void expectFeedId(String feedId) {
    if (feedId.isEmpty ||
        (_expectedFeedId != null && _expectedFeedId != feedId)) {
      throw const StudioFailure(
        code: StudioFailureCode.protocol,
        message: 'A connection changed its original identity.',
        retryable: false,
        correlationId: 'conversation-close-identity',
      );
    }
    _expectedFeedId = feedId;
  }

  /// Synchronous registration of a stream/consumer completion, not another queue.
  Future<T> supervise<T>(Future<T> Function() action) {
    if (_closing) return Future.error(conversationCancelled);
    return _record(action);
  }

  Future<T> _record<T>(Future<T> Function() action) {
    final result = Completer<T>();
    final done = Completer<void>();
    _work.add(done.future);
    unawaited(
      Future<T>.sync(action).then(
        (value) {
          _work.remove(done.future);
          done.complete();
          result.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          lastCause = error;
          lastStack = stack;
          _work.remove(done.future);
          done.complete();
          result.completeError(error, stack);
        },
      ),
    );
    return result.future;
  }

  /// All detail calls use the existing common 64 pending-operation permits.
  Future<T> call<T>(Future<T> Function(C) query) {
    if (_closing) return Future.error(conversationCancelled);
    final ResourcePermit permit;
    try {
      permit = _budget.acquire(
        ResourceKind.pendingOperation,
        owner: '$label:query',
      );
    } catch (error, stack) {
      return Future.error(
        error is ResourceBudgetExceeded ? error.failure : error,
        stack,
      );
    }
    return _record(() async {
      try {
        final connection = await opened;
        if (_closing) throw conversationCancelled;
        final value = await query(connection);
        if (_closing) throw conversationCancelled;
        return value;
      } catch (error, stack) {
        lastCause = error;
        lastStack = stack;
        final failure = conversationFailure(error);
        // An unknown adapter error has no typed projection of its own. Retain the
        // original object next to the synthesized failure so the caller that
        // publishes a diagnostic can keep the real identity instead of the
        // internal projection (design/26 §26.9).
        if (!identical(failure, error)) {
          _synthesized = failure;
          _synthesizedCause = error;
        }
        Error.throwWithStackTrace(failure, stack);
      } finally {
        permit.release();
      }
    });
  }

  void onRequestClose(Future<void> Function() cancel) {
    if (_closing) {
      _startCancel(cancel);
    } else {
      _cancel.add(cancel);
    }
  }

  void requestClose() {
    if (_closing) return;
    _closing = true;
    _permit.mark(ResourcePhase.retiring);
    _requestNative();
    if (!_cancelStarted) {
      _cancelStarted = true;
      final callbacks = List.of(_cancel);
      _cancel.clear();
      for (final cancel in callbacks) {
        _startCancel(cancel);
      }
    }
  }

  void _startCancel(Future<void> Function() cancel) {
    final index = ++_cancelSequence;
    // Cancellation and native join are both started before either is awaited.
    final task = _record(() async {
      try {
        await cancel();
      } catch (error, stack) {
        lastCause = error;
        lastStack = stack;
        // StreamSubscription cancellation has no independently retryable cleanup.
        _localIssues[index] = conversationIssue(
          'streamCancellation',
          error,
          CleanupRecovery.terminal,
        );
      }
    });
    task.ignore();
  }

  void _requestNative() {
    final connection = _connection;
    if (connection == null) return;
    if (!_nativeRequested) {
      _nativeRequested = true;
      try {
        _requestNativeClose(connection);
      } catch (error, stack) {
        lastCause = error;
        lastStack = stack;
        _nativeError = conversationIssue(
          'requestClose',
          error,
          CleanupRecovery.retryClose,
        );
      }
    }
    if (_nativeJoining == null) _startNative(retry: false);
  }

  void _startNative({required bool retry}) {
    final connection = _connection;
    if (connection == null) return;
    _nativeDone = false;
    final task = Future<FeedCloseReport>.sync(
      () => retry ? _nativeRetry(connection) : _nativeClose(connection),
    );
    _nativeJoining = task;
    unawaited(
      task.then(
        (report) {
          if (report.feedId.isEmpty ||
              (_expectedFeedId != null && report.feedId != _expectedFeedId)) {
            _nativeError = conversationIssue(
              'nativeCloseIdentity',
              const StudioFailure(
                code: StudioFailureCode.protocol,
                message: 'The close report belongs to another connection.',
                retryable: false,
                correlationId: 'conversation-close-identity',
              ),
              CleanupRecovery.retryClose,
            );
            _nativeReport = null;
          } else {
            _nativeReport = report;
            _nativeError = null;
            if (report.outcome case UnresolvedFeedCloseOutcome(:final issues)) {
              _terminalNative.addAll(
                issues.where(
                  (issue) => issue.recovery == CleanupRecovery.terminal,
                ),
              );
            }
          }
          _nativeDone = true;
        },
        onError: (Object error, StackTrace stack) {
          lastCause = error;
          lastStack = stack;
          _nativeError = conversationIssue(
            'nativeClose',
            error,
            CleanupRecovery.retryClose,
          );
          _nativeDone = true;
        },
      ),
    );
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    if (_released) return CloseReport(unresolved: []);
    requestClose();
    var joining = _joining;
    if (joining == null) {
      joining = _join(retry: retry);
      _joining = joining;
      joining.whenComplete(() {
        if (identical(_joining, joining)) _joining = null;
      }).ignore();
    }
    await observeConversationCompletion(joining, deadline);
    return report();
  }

  Future<void> _join({required bool retry}) async {
    if (_released) return;
    await _openSettled.future;
    if (_connection != null) {
      _requestNative();
      if (retry && _nativeDone && _canRetryNative) {
        _startNative(retry: true);
      }
      try {
        await _nativeJoining;
      } catch (_) {
        /* original diagnostic is retained above */
      }
    }
    while (_work.isNotEmpty) {
      await Future.wait(List.of(_work));
    }
    if (_allClean) {
      _released = true;
      _permit.release();
    } else {
      _permit.mark(ResourcePhase.unresolved);
    }
  }

  bool get _allClean =>
      _openSettled.isCompleted &&
      _work.isEmpty &&
      _localIssues.isEmpty &&
      _processingFailures.isEmpty &&
      _terminalNative.isEmpty &&
      _nativeError == null &&
      (_connection == null ||
          (_nativeDone && _nativeReport?.outcome is CleanFeedCloseOutcome));

  bool get _canRetryNative {
    if (_nativeError != null) return true;
    final outcome = _nativeReport?.outcome;
    return outcome is UnresolvedFeedCloseOutcome &&
        outcome.issues.any(
          (issue) => issue.recovery != CleanupRecovery.terminal,
        );
  }

  CloseReport report() {
    if (_released) return CloseReport(unresolved: []);
    final issues = <FeedCloseIssue>[
      ..._localIssues.values,
      for (final failure in _processingFailures) failure.issue,
      ..._terminalNative,
      if (_nativeError case final issue?) issue,
      if (_nativeReport?.outcome case UnresolvedFeedCloseOutcome(:final issues))
        ...issues.where((issue) => !_terminalNative.contains(issue)),
    ];
    if (!_openSettled.isCompleted ||
        _work.isNotEmpty ||
        (_connection != null && !_nativeDone)) {
      issues.add(
        const FeedCloseIssue(
          diagnostic: StudioShutdownIssue(
            stage: 'conversationJoin',
            code: 'workPending',
            message: 'Original conversation work is still in flight.',
            retryable: true,
            correlationId: 'conversation-join',
          ),
          recovery: CleanupRecovery.awaitCompletion,
        ),
      );
    }
    if (issues.isEmpty) {
      issues.add(
        const FeedCloseIssue(
          diagnostic: StudioShutdownIssue(
            stage: 'conversationJoin',
            code: 'ownerPending',
            message: 'Original connection cleanup has not completed.',
            retryable: true,
            correlationId: 'conversation-join',
          ),
          recovery: CleanupRecovery.awaitCompletion,
        ),
      );
    }
    return CloseReport(
      unresolved: [
        UnresolvedResource(owner: label, attemptId: attemptId, issues: issues),
      ],
    );
  }
}

Future<void> observeConversationCompletion(
  Future<void> completion,
  DateTime? deadline,
) async {
  if (deadline == null) return completion;
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) return;
  try {
    await completion.timeout(remaining);
  } on TimeoutException {
    /* owner retains real completion */
  }
}

/// Index orchestration and the scope supervisor can observe the same real join.
/// Preserve every distinct issue, but do not duplicate one resource diagnostic.
CloseReport conversationCloseReport(Iterable<UnresolvedResource> resources) {
  final grouped = <(String, AttemptId), List<FeedCloseIssue>>{};
  for (final resource in resources) {
    final issues = grouped.putIfAbsent((
      resource.owner,
      resource.attemptId,
    ), () => []);
    for (final issue in resource.issues) {
      if (!issues.contains(issue)) issues.add(issue);
    }
  }
  return CloseReport(
    unresolved: [
      for (final entry in grouped.entries)
        UnresolvedResource(
          owner: entry.key.$1,
          attemptId: entry.key.$2,
          issues: entry.value,
        ),
    ],
  );
}
