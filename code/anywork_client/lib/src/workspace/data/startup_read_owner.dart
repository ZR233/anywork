import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/startup_values.dart';
import 'startup_port.dart';

/// One pin and its accepted calls. A deadline only bounds the caller's wait.
final class StartupReadOwner {
  StartupReadOwner({
    required this.port,
    required this.reference,
    required this.permit,
    required this.id,
  });

  final StartupPort port;
  final RuntimeStartupReadRef reference;
  final ResourcePermit permit;
  final AttemptId id;
  final Completer<void> _opened = Completer<void>();
  final Completer<void> _workDone = Completer<void>();
  final List<(Object, StackTrace)> _causes = [];
  RuntimeStartupReadConnection? _connection;
  FeedCloseReport? _report;
  FeedCloseIssue? _closeIssue;
  Future<void>? _cleanup;
  bool _closing = false;
  bool _nativeClean = false;

  bool get complete =>
      _nativeClean && _workDone.isCompleted && _cleanup == null;
  bool get pending => !_workDone.isCompleted || _cleanup != null;
  List<FeedCloseIssue> get issues => [
    if (_report?.outcome case UnresolvedFeedCloseOutcome(:final issues)) ...issues,
    if (_closeIssue case final issue?) issue,
  ];

  Future<T> read<T>(
    Future<T> Function(RuntimeStartupReadConnection, RuntimeStartupReadHeader) read,
  ) async {
    try {
      final connection = await port.openStartupRead(reference);
      _connection = connection;
      _opened.complete();
      if (_closing) {
        requestClose();
        throw _cancelled;
      }
      permit.mark(ResourcePhase.active);
      final header = await connection.header();
      if (header.reference != reference || header.scope.scopeId.isEmpty) {
        throw _protocol('Startup read scope does not match its frozen reference');
      }
      if (_closing) throw _cancelled;
      final result = await read(connection, header);
      if (_closing) throw _cancelled;
      return result;
    } catch (error, stack) {
      _causes.add((error, stack));
      if (error is StudioFailure) rethrow;
      Error.throwWithStackTrace(_protocol('Startup detail reading failed'), stack);
    } finally {
      if (!_opened.isCompleted) {
        _opened.complete();
        _nativeClean = true;
      }
      _workDone.complete();
    }
  }

  Future<String> text(ReadText value) async {
    if (_closing) throw _cancelled;
    if (value case InlineReadText(:final text)) return text;
    final deferred = value as DeferredReadText;
    final buffer = StringBuffer();
    var offset = 0;
    while (true) {
      if (_closing) throw _cancelled;
      final chunk = await _connection!.text(deferred.fieldId, offset: offset);
      final bytes = utf8.encode(chunk.text).length;
      if (chunk.fieldId != deferred.fieldId ||
          chunk.offset != offset ||
          bytes > 65536 ||
          offset + bytes > deferred.utf8Bytes) {
        throw _protocol('Invalid startup UTF-8 chunk identity or length');
      }
      buffer.write(chunk.text);
      final end = offset + bytes;
      if (chunk.nextOffset == null) {
        if (end != deferred.utf8Bytes) {
          throw _protocol('Incomplete startup text');
        }
        return buffer.toString();
      }
      if (bytes == 0 || chunk.nextOffset != end || end >= deferred.utf8Bytes) {
        throw _protocol('Startup text did not advance at a UTF-8 boundary');
      }
      offset = end;
    }
  }

  Future<StartupActiveTurnReadPage> activeTurns({
    required int offset,
    required int limit,
  }) {
    if (_closing) throw _cancelled;
    return _connection!.activeTurns(offset: offset, limit: limit);
  }

  void requestClose() {
    _closing = true;
    if (!permit.isReleased) permit.mark(ResourcePhase.retiring);
    if (_nativeClean) return;
    try {
    _connection?.requestClose();
    } catch (error, stack) {
      _causes.add((error, stack));
      _closeIssue = FeedCloseIssue(
        diagnostic: StudioShutdownIssue(
          stage: 'startup-read',
          code: error is StudioFailure ? error.code.name : 'startupReadCancellationFailed',
          message: error is StudioFailure ? error.message : 'Startup read cancellation failed.',
          retryable: error is StudioFailure && error.retryable,
          correlationId: error is StudioFailure ? error.correlationId : '',
        ),
        recovery: CleanupRecovery.retryClose,
      );
    }
  }

  Future<void> close({bool retry = false}) {
    requestClose();
    if (_cleanup case final task?) return task;
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
    if (connection != null && !_nativeClean) {
      if (retry && _closeIssue == null) {
        if (_report?.outcome case UnresolvedFeedCloseOutcome(:final issues)) {
          if (issues.every((issue) => issue.recovery == CleanupRecovery.terminal)) {
            await _workDone.future;
            return;
          }
        }
      }
      try {
        final report = await (retry ? connection.retryClose() : connection.close());
        if (report.feedId.isEmpty ||
            (_report != null && _report!.feedId != report.feedId)) {
          throw _protocol('Startup read close identity mismatch');
        }
        if (report.outcome case UnresolvedFeedCloseOutcome(:final issues)) {
          if (issues.isEmpty) throw _protocol('Empty unresolved startup read report');
        }
        _report = report;
        _closeIssue = null;
        _nativeClean = report.outcome is CleanFeedCloseOutcome;
      } catch (error, stack) {
        _causes.add((error, stack));
        _closeIssue = FeedCloseIssue(
          diagnostic: StudioShutdownIssue(
            stage: 'startup-read',
            code: error is StudioFailure ? error.code.name : 'startupReadCloseFailed',
            message: error is StudioFailure ? error.message : 'Startup read cleanup failed.',
            retryable: error is StudioFailure && error.retryable,
            correlationId: error is StudioFailure ? error.correlationId : '',
          ),
          recovery: CleanupRecovery.retryClose,
        );
      }
    }
    await _workDone.future;
  }

  static StudioFailure _protocol(String message) => StudioFailure(
    code: StudioFailureCode.protocol,
    message: message,
    retryable: false,
    correlationId: '',
  );

  static const _cancelled = StudioFailure(
    code: StudioFailureCode.cancelled,
    message: 'Startup reading is closing.',
    retryable: false,
    correlationId: '',
  );
}
