import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/resources_ports.dart';

import '../domain/remote_values.dart';
import 'remote_observation.dart';
import 'remote_port.dart';

/// Owns one immutable native page until its cursor is handed to its query and
/// its read scope has really joined. It never issues ContinueDirectory itself.
final class RemotePageOwner {
  RemotePageOwner({
    required this.port,
    required this.alias,
    required this.path,
    required this.cursor,
    required this.id,
    required this.permit,
    required this.onCursor,
  });
  final RemotePort port;
  final String alias;
  final String? path;
  final String? cursor;
  final AttemptId id;
  final ResourcePermit permit;
  final void Function(String? previous, String? next) onCursor;
  final Completer<void> _settled = Completer<void>();
  final List<(Object, StackTrace)> _causes = [];
  RemoteDirectoryReadConnection? _connection;
  RemoteDirectoryReadHeader? _header;
  FeedCloseReport? _report;
  final Set<FeedCloseIssue> _handoffIssues = {};
  final Set<FeedCloseIssue> _closeIssues = {};
  final Map<FeedCloseIssue, (Object, StackTrace)> _cleanupCauses = {};
  Future<void>? _cleanup;
  bool _closing = false;
  bool _handedOff = false;
  bool _nativeClean = false;
  bool _started = false;

  bool get handedOff => _handedOff;
  bool get pending => !_settled.isCompleted || _cleanup != null;
  bool get complete =>
      _settled.isCompleted && _handedOff && _nativeClean && _cleanup == null;
  List<FeedCloseIssue> get issues => [
    ..._handoffIssues,
    if (_report?.outcome case UnresolvedFeedCloseOutcome(:final issues))
      ...issues,
    ..._closeIssues,
  ];

  Future<RemoteDirectoryListing> run() async {
    if (_started || _settled.isCompleted) {
      throw remoteProtocol('Remote native page can only be requested once');
    }
    _started = true;
    try {
      // This Future and owner are registered before entering the adapter.
      _connection = await port.openDirectory(alias, path: path, cursor: cursor);
      permit.mark(ResourcePhase.active);
      final header = await _readHeader();
      await _handoff(header);
      if (_closing) throw remoteCancelled();
      final canonicalPath = await _text(header.path);
      if (cursor != null && path != null && canonicalPath != path) {
        throw remoteProtocol(
          'Remote continuation returned a different directory',
        );
      }
      final parent = header.parent == null ? null : await _text(header.parent!);
      final entries = <RemoteDirectoryEntry>[];
      var offset = 0;
      while (offset < header.pageEntryCount) {
        if (_closing) throw remoteCancelled();
        final page = await _connection!.entries(offset: offset);
        final end = offset + page.items.length;
        if (page.scopeId != header.scopeId ||
            page.offset != offset ||
            page.items.length > 32 ||
            end > header.pageEntryCount ||
            page.items.isEmpty ||
            (page.nextOffset == null && end != header.pageEntryCount) ||
            (page.nextOffset != null &&
                (page.nextOffset != end || end >= header.pageEntryCount))) {
          throw remoteProtocol(
            'Invalid remote native-page materialization boundary',
          );
        }
        for (final item in page.items) {
          final value = RemoteDirectoryEntry(
            name: await _text(item.name),
            path: await _text(item.path),
            isDirectory: item.isDirectory,
            isSymlink: item.isSymlink,
          );
          // The existing native picker boundary owns the directory/symlink
          // policy; all four returned fields are mapped without fallback.
          entries.add(value);
        }
        offset = end;
      }
      if (_closing) throw remoteCancelled();
      return RemoteDirectoryListing(
        path: canonicalPath,
        parent: parent,
        entries: List.unmodifiable(entries),
        nextCursor: _nextCursor,
      );
    } catch (error, stack) {
      _causes.add((error, stack));
      if (error is StudioFailure) rethrow;
      Error.throwWithStackTrace(
        remoteProtocol('Remote page reading failed'),
        stack,
      );
    } finally {
      if (_connection == null) {
        // The adapter owns any unknown opening candidate. No business replay.
        _handedOff = true;
        _nativeClean = true;
      }
      _settled.complete();
    }
  }

  String? _nextCursor;

  void cancelBeforeOpen() {
    if (_started) {
      requestClose();
      return;
    }
    _closing = true;
    _handedOff = true;
    _nativeClean = true;
    if (!_settled.isCompleted) _settled.complete();
  }

  Future<RemoteDirectoryReadHeader> _readHeader() async {
    final header = _header ?? await _connection!.header();
    if (header.scopeId.isEmpty || header.pageEntryCount < 0) {
      throw remoteProtocol('Invalid remote page scope identity');
    }
    _header = header;
    return header;
  }

  Future<void> _handoff(RemoteDirectoryReadHeader header) async {
    if (_handedOff) return;
    final next = header.nextCursor == null
        ? null
        : await _text(header.nextCursor!);
    // Cursor ownership moves even if the query no longer has publishing rights.
    onCursor(cursor, next);
    _nextCursor = next;
    _handedOff = true;
    _resolve(_handoffIssues);
  }

  Future<String> _text(ReadText value) async {
    // Do not seal this small recovery read before extracting a late native
    // cursor. Closing its page first would destroy the only cleanup capability.
    if (value case InlineReadText(:final text)) return text;
    final deferred = value as DeferredReadText;
    var offset = 0;
    final text = StringBuffer();
    while (true) {
      final chunk = await _connection!.text(deferred.fieldId, offset: offset);
      final length = utf8.encode(chunk.text).length;
      final end = offset + length;
      if (chunk.fieldId != deferred.fieldId ||
          chunk.offset != offset ||
          length > 65536 ||
          end > deferred.utf8Bytes) {
        throw remoteProtocol(
          'Remote UTF-8 chunk identity or byte length mismatch',
        );
      }
      text.write(chunk.text);
      if (chunk.nextOffset == null) {
        if (end != deferred.utf8Bytes)
          throw remoteProtocol('Incomplete remote text');
        return text.toString();
      }
      if (length == 0 || chunk.nextOffset != end || end >= deferred.utf8Bytes) {
        throw remoteProtocol('Remote text continuation did not advance');
      }
      offset = end;
    }
  }

  void requestClose() {
    _closing = true;
    if (!permit.isReleased) permit.mark(ResourcePhase.retiring);
    // Before handoff the still-readable pin is the late cursor's cleanup owner.
    if (!_handedOff || _nativeClean) return;
    try {
      _connection?.requestClose();
    } catch (error, stack) {
      _record(
        _closeIssues,
        error,
        stack,
        'remote-page-cancel',
        CleanupRecovery.retryClose,
      );
    }
  }

  Future<void> close({bool retry = false}) {
    requestClose();
    if (_cleanup case final task?) return task;
    if (complete) return Future.value();
    final task = _close(retry);
    _cleanup = task;
    unawaited(
      task.whenComplete(() {
        if (identical(_cleanup, task)) _cleanup = null;
      }),
    );
    return task;
  }

  Future<void> _close(bool retry) async {
    await _settled.future;
    final connection = _connection;
    if (connection == null) return;
    if (!_handedOff) {
      if (_handoffIssues.any(
        (issue) => issue.recovery == CleanupRecovery.terminal,
      ))
        return;
      try {
        // Pure reads on the original immutable pin, never another native browse.
        await _handoff(await _readHeader());
      } catch (error, stack) {
        // Cancelled is the port's explicit sealed-scope result. Such a pin
        // cannot admit recovery reads; do not advertise a nonexistent retry.
        final recovery =
            error is StudioFailure && error.code == StudioFailureCode.cancelled
            ? CleanupRecovery.terminal
            : CleanupRecovery.retryClose;
        _record(
          _handoffIssues,
          error,
          stack,
          'remote-cursor-handoff',
          recovery,
        );
        return;
      }
    }
    if (_nativeClean) return;
    if (retry && _closeIssues.isEmpty) {
      if (_report?.outcome case UnresolvedFeedCloseOutcome(:final issues)) {
        if (issues.every((issue) => issue.recovery == CleanupRecovery.terminal))
          return;
      }
    }
    try {
      connection.requestClose();
      final report = await (retry
          ? connection.retryClose()
          : connection.close());
      if (report.feedId.isEmpty ||
          (_report != null && _report!.feedId != report.feedId)) {
        throw remoteProtocol('Remote page close report identity mismatch');
      }
      if (report.outcome case UnresolvedFeedCloseOutcome(:final issues)) {
        if (issues.isEmpty)
          throw remoteProtocol('Empty unresolved remote page report');
      }
      _report = report;
      _resolve(_closeIssues);
      _nativeClean = report.outcome is CleanFeedCloseOutcome;
    } catch (error, stack) {
      _record(
        _closeIssues,
        error,
        stack,
        'remote-page-close',
        CleanupRecovery.retryClose,
      );
    }
  }

  void _record(
    Set<FeedCloseIssue> issues,
    Object error,
    StackTrace stack,
    String stage,
    CleanupRecovery recovery,
  ) {
    final issue = remoteIssue(error, stage, recovery);
    issues.add(issue);
    _cleanupCauses.putIfAbsent(issue, () => (error, stack));
  }

  void _resolve(Set<FeedCloseIssue> issues) {
    for (final issue in issues) {
      _cleanupCauses.remove(issue);
    }
    issues.clear();
  }
}
