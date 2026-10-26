import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_values.dart';
import 'directory_collection.dart';
import 'thread_directory_owner.dart';

/// A frozen set of actual Workspace query objects, not Sidebar member IDs.
final class WorkspaceDirectoryCapture {
  WorkspaceDirectoryCapture(List<WorkspaceThreadDirectory> owners, this.attempt)
    : owners = List.unmodifiable(owners);
  final List<WorkspaceThreadDirectory> owners;
  final int attempt;
  final Map<WorkspaceThreadDirectory, Future<WorkspaceThreadRecord>>
  _membership = Map.identity();
  final Map<WorkspaceThreadDirectory, WorkspaceThreadRecord> _resolved =
      Map.identity();
  final Map<WorkspaceThreadDirectory, CloseReport> _reports = Map.identity();
  List<WorkspaceThreadDirectory>? _closing;

  /// Admission is synchronous in the original capture, before a later UI seal.
  void prepareProjectReads() {
    for (final owner in owners) {
      final scope = owner.mirror.scope;
      if (scope is! SingleThreadDirectoryScope) continue;
      WorkspaceThreadRecord? known;
      final state = owner.mirror.source.value;
      final window = directoryWindow(state.threads);
      if (window != null) {
        for (final row in window.rows.values) {
          final value = directoryPrevious(row);
          if (value?.origin == window.origin &&
              value?.value.id == scope.threadId) {
            known = value!.value;
            break;
          }
        }
      }
      final read = known != null
          ? Future.value(known)
          : Future<WorkspaceThreadRecord>.sync(
              () => owner.reads
                  .lookup(scope.threadId)
                  .then((record) => record.value),
            );
      _membership[owner] = read;
      unawaited(read.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    }
  }

  Future<void> prepareProject(String projectId) async {
    await Future.wait([
      for (final entry in _membership.entries)
        entry.value.then<void>((value) {
          final scope = entry.key.mirror.scope as SingleThreadDirectoryScope;
          if (value.id != scope.threadId)
            throw resourceProtocol(
              'Captured metadata resolved another Thread.',
            );
          _resolved[entry.key] = value;
        }),
    ]);
    _closing = [
      for (final owner in owners)
        if (owner.mirror.scope case QueryThreadDirectoryScope(
          :final query,
        )) ...[
          if (query.projectId == projectId) owner,
        ] else if (_resolved[owner]?.projectId == projectId)
          owner,
    ];
  }

  void confirmThread(Set<String> removed) {
    _closing = [
      for (final owner in owners)
        if (owner.mirror.scope case SingleThreadDirectoryScope(:final threadId))
          if (removed.contains(threadId)) owner,
    ];
  }

  Future<void> joinPreparation() async {
    // A failed value read is still joined. Its typed cause belongs to prepare;
    // it does not authorize closing the caller's original UI query on rejection.
    await Future.wait([
      for (final read in _membership.values)
        read.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    ]);
  }

  Future<CloseReport> closeConfirmed({
    DateTime? deadline,
    bool retry = false,
  }) async {
    final closing = _closing;
    if (closing == null)
      throw resourceProtocol(
        'Archive query membership has not been confirmed.',
      );
    await Future.wait([
      for (final owner in closing)
        if (_reports[owner]?.complete != true)
          Future<CloseReport>.sync(
            () => owner.close(deadline: deadline, retry: retry),
          ).then<void>(
            (report) {
              _reports[owner] = report;
            },
            onError: (Object error, StackTrace stack) {
              owner.lifetime.lastCause = error;
              owner.lifetime.lastStack = stack;
              _reports[owner] = CloseReport(
                unresolved: [
                  UnresolvedResource(
                    owner: 'workspace-captured-query',
                    attemptId: AttemptId(attempt),
                    issues: [
                      resourceCleanupIssue(error, CleanupRecovery.retryClose),
                    ],
                  ),
                ],
              );
            },
          ),
    ]);
    return CloseReport(
      unresolved: [for (final report in _reports.values) ...report.unresolved],
    );
  }
}
