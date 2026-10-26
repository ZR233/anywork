import 'dart:async';

import 'package:anywork_client/resources.dart';

import 'adapter_failure.dart';

/// Owns one native handle and its local forwarding/query work, not business
/// state. A domain connection supplies only that handle's concrete operations.
final class AdapterResourceOwner {
  AdapterResourceOwner({
    required this.resource,
    required this._requestNativeClose,
    required this._closeNative,
    required this._retryNativeClose,
    required this._disposeNative,
    required this._cancelNativeStream,
    required this._mapFailure,
    this._expectedIdentity,
  });

  final String resource;
  final void Function() _requestNativeClose;
  final Future<FeedCloseReport> Function() _closeNative;
  final Future<FeedCloseReport> Function() _retryNativeClose;
  final void Function() _disposeNative;
  final Future<void> Function() _cancelNativeStream;
  final StudioFailure Function(Object) _mapFailure;
  final String? Function()? _expectedIdentity;

  final Set<Future<void>> _work = {};
  // Raw causes/stacks remain on this owner; never serialize or print them.
  // One current raw cause per fixed adapter stage, not an unbounded error log.
  final Map<String, (Object, StackTrace)> _causes = {};
  final List<FeedCloseIssue> _terminalNativeIssues = [];
  Future<void>? _cancellation;
  _AdapterCloseAttempt? _closing;
  FeedCloseReport? _nativeReport;
  FeedCloseReport? _currentReport;
  FeedCloseIssue? _nativeCallIssue;
  FeedCloseIssue? _cancellationIssue;
  FeedCloseIssue? _disposeIssue;
  bool _sealed = false;
  bool _disposeAttempted = false;
  bool _disposed = false;

  bool get isClosing => _sealed;
  bool get isDisposed => _disposed;

  void ensureOpen() {
    if (_sealed) throw adapterCancelled(resource);
  }

  /// The marker is installed before invoking an operation, including one that
  /// throws synchronously. Closing observes settlement, not a cancelled waiter.
  Future<T> query<T>(FutureOr<T> Function() operation) {
    ensureOpen();
    final settled = Completer<void>();
    _work.add(settled.future);
    return Future<T>.sync(operation)
        .then<T>(
          (value) {
            ensureOpen();
            return value;
          },
          onError: (Object error, StackTrace stack) {
            // An entered query may fail after close wins publication. Preserve its
            // original cause even though the caller must observe Cancelled.
            final original = failure(error, stack, source: 'query');
            Error.throwWithStackTrace(
              _sealed ? adapterCancelled(resource) : original,
              stack,
            );
          },
        )
        .whenComplete(() {
          _work.remove(settled.future);
          settled.complete();
        });
  }

  /// For a synchronous listen/open registration boundary. The caller must
  /// complete the returned callback in finally, even when native listen throws.
  void Function() registerOpening() {
    ensureOpen();
    final settled = Completer<void>();
    _work.add(settled.future);
    return () {
      if (settled.isCompleted) return;
      _work.remove(settled.future);
      settled.complete();
    };
  }

  void requestClose() {
    if (_sealed) return;
    _sealed = true;
    try {
      _requestNativeClose();
    } on Object catch (error, stack) {
      // The independent close RPC still runs. Its result proves whether native
      // cancellation/join actually succeeded; this exception does not prove it.
      _causes['request-close'] = (error, stack);
    }
  }

  /// Retain raw diagnostics on the actual owner, including conversion errors.
  /// An error mapper must not let another generated/unstructured error escape.
  StudioFailure failure(
    Object error,
    StackTrace stack, {
    String source = 'stream',
  }) {
    _causes[source] = (error, stack);
    try {
      return _mapFailure(error);
    } on Object catch (mappingError, mappingStack) {
      _causes['$source-mapping'] = (mappingError, mappingStack);
      return adapterFailure(
        mappingError,
        operation: '$resource-error-conversion',
      );
    }
  }

  Future<FeedCloseReport> close() {
    requestClose();
    return (_closing ?? _startJoin(retry: false)).future;
  }

  /// Detaching this owner's output observes the same close attempt, but is not
  /// a second native cleanup operation. An Unresolved report stays authoritative
  /// on close/retryClose instead of becoming another output cancel exception.
  Future<void> cancelOutputObservation() {
    requestClose();
    final attempt = _closing ?? _startJoin(retry: false);
    return _observeOutputCancellation(attempt);
  }

  Future<void> _observeOutputCancellation(_AdapterCloseAttempt attempt) async {
    try {
      await attempt.future;
    } on Object catch (error, stack) {
      final retained = attempt.retainedNativeFailure;
      // Only _join's no-usable-identity path installs this evidence, after
      // retaining the raw cause and retryClose issue on this actual attempt.
      // An unrelated output/join failure must still reach the cancelling caller.
      if (retained == null || !identical(error, retained.failure)) {
        Error.throwWithStackTrace(error, stack);
      }
    }
  }

  Future<FeedCloseReport> retryClose() {
    requestClose();
    final current = _currentReport;
    if (_disposed || current?.outcome is CleanFeedCloseOutcome) {
      return Future.value(current!);
    }
    // Only a running attempt is shared. A completed recoverable report/error
    // must not permanently capture the explicit recovery entry point.
    if (_joining) return _closing!.future;
    return _startJoin(retry: true).future;
  }

  bool _joining = false;

  _AdapterCloseAttempt _startJoin({required bool retry}) {
    final attempt = _AdapterCloseAttempt();
    // Install the shared responsibility BEFORE invoking any native/cancel
    // callback; a synchronous reentrant close observes this very attempt.
    _closing = attempt;
    _joining = true;
    unawaited(
      _join(retry: retry, attempt: attempt).then<void>(
        attempt.completion.complete,
        onError: attempt.completion.completeError,
      ),
    );
    return attempt;
  }

  Future<void> _cancelOnce() =>
      _cancellation ??= Future<void>.sync(_cancelNativeStream).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          _cancellationIssue = adapterCloseIssue(
            failure(error, stack, source: 'stream-cancel'),
            stage: '$resource-stream-cancel',
            // Dart cancellation has no independently proven retry operation.
            recovery: CleanupRecovery.terminal,
          );
        },
      );

  Future<FeedCloseReport> _join({
    required bool retry,
    required _AdapterCloseAttempt attempt,
  }) async {
    _joining = true;
    FeedCloseReport? report;
    Object? nativeError;
    StackTrace? nativeStack;
    try {
      final previous = _nativeReport;
      final outcome = previous?.outcome;
      final canRetryNative =
          outcome is UnresolvedFeedCloseOutcome &&
          outcome.issues.any(
            (issue) => issue.recovery != CleanupRecovery.terminal,
          );
      final shouldCallNative =
          previous == null ||
          retry && (canRetryNative || _nativeCallIssue != null);

      // Install completion/error observers for BOTH independent paths in the
      // same synchronous turn, before awaiting either one.
      final join = shouldCallNative
          ? Future<FeedCloseReport>.sync(
                  retry ? _retryNativeClose : _closeNative,
                )
                .then<void>(
                  (value) {
                    _validateReport(value);
                    report = value;
                    _nativeReport = value;
                    _nativeCallIssue = null;
                    if (value.outcome case UnresolvedFeedCloseOutcome(
                      :final issues,
                    )) {
                      for (final issue in issues) {
                        if (issue.recovery == CleanupRecovery.terminal &&
                            !_terminalNativeIssues.contains(issue)) {
                          _terminalNativeIssues.add(issue);
                        }
                      }
                    }
                  },
                  onError: (Object error, StackTrace stack) {
                    nativeError = error;
                    nativeStack = stack;
                    _causes['native-close'] = (error, stack);
                  },
                )
                .catchError((Object error, StackTrace stack) {
                  // Validation errors thrown by the success handler need their own
                  // observation; do not release the handle on malformed reports.
                  nativeError = error;
                  nativeStack = stack;
                  _causes['native-close'] = (error, stack);
                })
          : Future<void>.sync(() {
              report = previous;
            });
      final cancellation = _cancelOnce();
      final localWork = Future.wait<void>(_work.toList(growable: false));
      await Future.wait<void>([join, cancellation, localWork]);

      if (nativeError != null) {
        final nativeFailure = failure(
          nativeError!,
          nativeStack!,
          source: 'native-close',
        );
        _nativeCallIssue = adapterCloseIssue(
          nativeFailure,
          stage: '$resource-native-close',
          recovery: CleanupRecovery.retryClose,
        );
        // A failed retry must not erase the earlier native issues. Before the
        // first usable identity exists there is no legitimate report envelope;
        // retain the owner and propagate the typed call error instead.
        report = previous;
        if (report == null) {
          final identity = _expectedIdentity?.call();
          if (identity == null || identity.isEmpty) {
            attempt.retainedNativeFailure = (
              failure: nativeFailure,
              issue: _nativeCallIssue!,
              cause: nativeError!,
              stack: nativeStack!,
            );
            Error.throwWithStackTrace(nativeFailure, nativeStack!);
          }
          report = FeedCloseReport(
            feedId: identity,
            outcome: FeedCloseOutcome.unresolved(issues: [_nativeCallIssue!]),
          );
        }
      }
      final native = report!;
      final issues = <FeedCloseIssue>[
        if (native.outcome case UnresolvedFeedCloseOutcome(:final issues))
          ...issues,
        if (_nativeCallIssue case final issue?)
          if (native.outcome is! UnresolvedFeedCloseOutcome ||
              !(native.outcome as UnresolvedFeedCloseOutcome).issues.contains(
                issue,
              ))
            issue,
        ?_cancellationIssue,
        ?_disposeIssue,
      ];
      for (final terminal in _terminalNativeIssues) {
        if (!issues.contains(terminal)) issues.add(terminal);
      }
      if (issues.isEmpty && !_disposeAttempted) {
        _disposeAttempted = true;
        try {
          _disposeNative();
          _disposed = true;
          // Retain the fixed-stage diagnostics on this owner after resource
          // release; Clean proves join/disposal, not that a late query succeeded.
        } on Object catch (error, stack) {
          final issue = adapterCloseIssue(
            failure(error, stack, source: 'dispose'),
            stage: '$resource-dispose',
            recovery: CleanupRecovery.terminal,
          );
          _disposeIssue = issue;
          issues.add(issue);
        }
      }
      return _currentReport = FeedCloseReport(
        feedId: native.feedId,
        outcome: issues.isEmpty
            ? const FeedCloseOutcome.clean()
            : FeedCloseOutcome.unresolved(issues: List.unmodifiable(issues)),
      );
    } finally {
      _joining = false;
    }
  }

  void _validateReport(FeedCloseReport report) {
    final expected = _expectedIdentity?.call();
    final outcome = report.outcome;
    if (report.feedId.isEmpty ||
        expected != null && report.feedId != expected ||
        outcome is UnresolvedFeedCloseOutcome && outcome.issues.isEmpty) {
      throw adapterProtocol('$resource-close-report');
    }
  }
}

/// One actual owner close attempt, not a parallel exception/operation registry.
/// Keep its evidence bound to its completion even if explicit retryClose starts
/// another attempt before an output cancellation continuation resumes.
final class _AdapterCloseAttempt {
  final completion = Completer<FeedCloseReport>();
  ({
    StudioFailure failure,
    FeedCloseIssue issue,
    Object cause,
    StackTrace stack,
  })?
  retainedNativeFailure;

  Future<FeedCloseReport> get future => completion.future;
}
