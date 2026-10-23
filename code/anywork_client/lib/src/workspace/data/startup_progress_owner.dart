import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/startup_values.dart';
import 'startup_port.dart';

/// Internal owner. Never exported from workspace's domain or ports barrel.
final class StartupProgressOwner {
  StartupProgressOwner({
    required this.port,
    required this.attemptId,
    required this.onStage,
  });

  final StartupPort port;
  final int attemptId;
  final void Function(StartupStage) onStage;
  final Completer<void> _opened = Completer<void>();
  final Completer<void> _ended = Completer<void>();
  FeedConnection<StartupProgressFrame>? _connection;
  StreamSubscription<StartupProgressFrame>? _subscription;
  Future<void> _tail = Future.value();
  Future<void>? _cancel;
  Future<void>? _cleanup;
  FeedCloseReport? _nativeReport;
  StudioFailure? _failure;
  final List<(Object, StackTrace)> _causes = [];
  StackTrace? _stack;
  FeedCloseIssue? _cancelIssue;
  FeedCloseIssue? _nativeIssue;
  FeedCloseIssue? _processingIssue;
  int _delivery = 0;
  int _pendingFrames = 0;
  bool _closing = false;
  bool _terminalReceived = false;
  bool _nativeClean = false;
  bool _cancelComplete = false;
  bool _openedOnce = false;

  bool get complete =>
      _opened.isCompleted &&
      _nativeClean &&
      _cancelComplete &&
      _pendingFrames == 0 &&
      _cleanup == null &&
      _cancelIssue == null &&
      _nativeIssue == null &&
      _processingIssue == null;

  bool get pending =>
      !_opened.isCompleted || _cleanup != null || _pendingFrames != 0;

  List<FeedCloseIssue> get issues => [
    if (_nativeReport?.outcome case UnresolvedFeedCloseOutcome(:final issues))
      ...issues,
    if (_nativeIssue case final issue?) issue,
    if (_cancelIssue case final issue?) issue,
    if (_processingIssue case final issue?) issue,
  ];

  Future<void> open() async {
    if (_openedOnce) throw StateError('Startup progress can only be opened once');
    _openedOnce = true;
    try {
      final connection = await port.openStartupProgress(attemptId);
      _connection = connection;
      if (_closing) {
        requestClose();
        throw _cancelled;
      }
      // Actual listen, not the events getter, claims the native subscription.
      _subscription = connection.events.listen(
        _receive,
        onError: (Object error, StackTrace stack) {
          _recordFailure(error, stack);
          requestClose();
        },
        onDone: () {
          if (!_ended.isCompleted) _ended.complete();
        },
      );
    } finally {
      _opened.complete();
      if (_connection == null) {
        _nativeClean = true;
        _cancelComplete = true;
        if (!_ended.isCompleted) _ended.complete();
      }
    }
  }

  void _receive(StartupProgressFrame frame) {
    // Feed credit bounds queued Data to two; there is no second progress stream.
    _pendingFrames++;
    var processing = false;
    _tail = _tail.then((_) async {
      if (_closing || _failure != null) return;
      if (_terminalReceived) throw _protocol('Data after terminal control');
      switch (frame) {
        case DataStartupProgressFrame(:final deliverySequence, :final stage):
          if (deliverySequence != _delivery + 1) {
            throw _protocol('Non-contiguous startup delivery');
          }
          // Native phases are event ordered, not enum ordered.
          // Admission above is side-effect free. Once the callback starts,
          // closing cannot erase a real callback or ACK failure.
          processing = true;
          onStage(stage);
          if (_closing) return;
          await _connection!.ackThrough(deliverySequence);
          _delivery = deliverySequence;
        case FailureStartupProgressFrame(:final error):
          _terminalReceived = true;
          _failure = error;
        case ClosedStartupProgressFrame(:final reason):
          _terminalReceived = true;
          if (reason != StartupCloseReason.completed) {
            _failure = _cancelled;
          }
      }
    }).catchError((Object error, StackTrace stack) {
      _recordFailure(error, stack, processing: processing);
      requestClose();
    }).whenComplete(() {
      _pendingFrames--;
    });
  }

  void _recordFailure(Object error, StackTrace stack, {bool processing = false}) {
    _causes.add((error, stack));
    _stack ??= stack;
    _failure ??= error is StudioFailure
        ? error
        : _protocol('Startup progress conversion or consumption failed');
    if (processing) {
      _processingIssue ??= _issue(error, 'startupProgressProcessingFailed', CleanupRecovery.terminal,
        fallbackMessage: 'Startup stage processing or acknowledgement failed.');
    }
  }

  /// Waits for actual stream completion and all accepted stage/ACK work.
  Future<void> finish() async {
    await _ended.future;
    await _tail;
    if (_failure case final failure?) {
      Error.throwWithStackTrace(failure, _stack ?? StackTrace.current);
    }
    if (!_terminalReceived && !_closing) {
      throw _protocol('Startup progress ended without terminal control');
    }
    if (_closing) throw _cancelled;
  }

  void requestClose() {
    _closing = true;
    if (_nativeClean) return;
    try {
    _connection?.requestClose();
    } catch (error, stack) {
      _causes.add((error, stack));
      _nativeIssue = _issue(
        error,
        'startupCancellationRequestFailed',
        CleanupRecovery.retryClose,
      );
    }
  }

  Future<void> close({bool retry = false}) {
    requestClose();
    if (_cleanup case final pending?) return pending;
    if (complete) return Future.value();
    final task = _close(retry);
    _cleanup = task;
    unawaited(task.whenComplete(() {
      if (identical(_cleanup, task)) _cleanup = null;
    }));
    return task;
  }

  Future<void> _close(bool retry) async {
    await _opened.future;
    final connection = _connection;
    if (connection == null) return;
    // Both paths install error handlers before either is awaited.
    final native = _closeNative(connection, retry);
    final cancellation = _cancelSubscription();
    await Future.wait([native, cancellation]);
    await _tail;
  }

  Future<void> _cancelSubscription() async {
    if (_cancelComplete || _cancelIssue != null) return;
    try {
      await (_cancel ??= _subscription?.cancel() ?? Future.value());
      _cancelComplete = true;
      if (!_ended.isCompleted) _ended.complete();
    } catch (error, stack) {
      _causes.add((error, stack));
      _stack ??= stack;
      _cancelIssue = _issue(
        error,
        'startupStreamCancellationFailed',
        CleanupRecovery.terminal,
      );
      // Dart cancel has no independently proven retry capability.
      if (!_ended.isCompleted) _ended.complete();
    }
  }

  Future<void> _closeNative(
    FeedConnection<StartupProgressFrame> connection,
    bool retry,
  ) async {
    if (_nativeClean) return;
    if (retry && _nativeIssue == null) {
      if (_nativeReport?.outcome case UnresolvedFeedCloseOutcome(:final issues)) {
      if (issues.every((issue) => issue.recovery == CleanupRecovery.terminal)) {
        return;
        }
      }
    }
    try {
      final report = await (retry ? connection.retryClose() : connection.close());
      if (report.feedId.isEmpty ||
          (_nativeReport != null && report.feedId != _nativeReport!.feedId)) {
        throw _protocol('Startup close report identity mismatch');
      }
      if (report.outcome case UnresolvedFeedCloseOutcome(:final issues)) {
        if (issues.isEmpty) throw _protocol('Empty unresolved startup close report');
      }
      _nativeReport = report;
      _nativeIssue = null;
      _nativeClean = report.outcome is CleanFeedCloseOutcome;
    } catch (error, stack) {
      _causes.add((error, stack));
      _stack ??= stack;
      _nativeIssue = _issue(
        error,
        'startupProgressCloseFailed',
        CleanupRecovery.retryClose,
      );
    }
  }

  static FeedCloseIssue _issue(
    Object error,
    String code,
    CleanupRecovery recovery, {
    String fallbackMessage = 'Startup cleanup failed.',
  }) => FeedCloseIssue(
    diagnostic: StudioShutdownIssue(
      stage: 'startup-progress',
      code: error is StudioFailure ? error.code.name : code,
      message: error is StudioFailure ? error.message : fallbackMessage,
      retryable: error is StudioFailure && error.retryable,
      correlationId: error is StudioFailure ? error.correlationId : '',
    ),
    recovery: recovery,
  );

  static StudioFailure _protocol(String message) => StudioFailure(
    code: StudioFailureCode.protocol,
    message: message,
    retryable: false,
    correlationId: '',
  );

  static const _cancelled = StudioFailure(
    code: StudioFailureCode.cancelled,
    message: 'Startup progress is closing.',
    retryable: false,
    correlationId: '',
  );
}
