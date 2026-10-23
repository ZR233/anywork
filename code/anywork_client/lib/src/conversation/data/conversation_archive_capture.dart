import 'dart:async';

import '../../../resources.dart';
import '../../../workspace.dart' show ArchiveThreadResult, ProjectRecord, WorkspaceState, WorkspaceThreadRecord;
import '../../../workspace_ports.dart'
    show WorkspaceArchiveCapture, WorkspaceProjectArchiveCapture, WorkspaceThreadArchiveCapture;
import 'connection_owner.dart';
import 'session_metadata.dart';
import 'session_owner.dart';
import 'session_ui_demand.dart';

typedef ConversationArchiveRetire = Future<CloseReport> Function(
  ConversationArchiveSession original, {DateTime? deadline, required bool retry});

/// References only objects already owned at synchronous capture. A metadata
/// reservation admits a pure read, not a Session/source or archive operation.
final class ConversationArchiveSession {
  ConversationArchiveSession(this.owner, this.repositoryGeneration, {required bool prepareMembership})
      : demand = owner.uiDemand, thread = owner.frozenThread, disposed = owner.isDisposed,
        metadata = prepareMembership && !owner.isDisposed ? owner.reserveArchiveMetadata() : null;
  final ConversationSessionOwner owner;
  final int repositoryGeneration;
  final ConversationUiDemand? demand;
  final WorkspaceThreadRecord? thread;
  final bool disposed;
  final ConversationMetadataBorrow? metadata;
  WorkspaceThreadRecord? membership;

  Future<void> prepareMembership() async {
    if (disposed) return;
    final known = thread;
    if (known != null) {
      membership = known;
      metadata?.release();
      return;
    }
    final borrow = metadata;
    if (borrow == null) throw conversationCancelled;
    membership = await borrow.read();
  }

  void releasePreparation() => metadata?.release();

  Future<CloseReport> joinPreparation({DateTime? deadline, bool retry = false}) =>
      metadata?.owner.observeCleanup(deadline: deadline, retry: retry) ??
      Future.value(CloseReport(unresolved: []));
}

abstract class _ConversationArchiveCapture implements WorkspaceArchiveCapture {
  _ConversationArchiveCapture(this.id, this.frozenSelection, this.attemptId,
      List<ConversationArchiveSession> sessions, this.retire)
      : sessions = List.unmodifiable(sessions);
  final String id;
  final WorkspaceState frozenSelection;
  final AttemptId attemptId;
  final List<ConversationArchiveSession> sessions;
  final ConversationArchiveRetire retire;
  Object? _original;
  Object? _confirmation;
  Future<void>? _preparing;
  bool _prepared = false;
  bool _preparationDone = false;
  bool _released = false;
  List<ConversationArchiveSession> _retiring = const [];

  Future<void> prepareOriginal(Object original, Future<void> Function() action) {
    if (_released || _confirmation != null || _original != null && _original != original) {
      return Future.error(_captureConflict);
    }
    if (_preparing case final pending?) return pending;
    final done = Completer<void>();
    _original = original;
    _preparing = done.future;
    done.future.ignore();
    Future<void>.sync(action).then((_) {
      _preparationDone = true;
      if (_released) { done.completeError(conversationCancelled); return; }
      _prepared = true; done.complete();
    }, onError: (Object error, StackTrace stack) {
      _preparationDone = true; done.completeError(error, stack);
    });
    return done.future;
  }

  Future<CloseReport> confirm(Object result, bool Function(ConversationArchiveSession) matches,
      {DateTime? deadline}) {
    if (_released || !_prepared) return Future.error(_captureConflict);
    final previous = _confirmation;
    if (previous != null && previous != result) return Future.error(_captureConflict);
    if (previous == null) {
      // Freeze confirmation and the exact cleanup set before external callbacks.
      _confirmation = result;
      _retiring = [for (final session in sessions) if (matches(session)) session];
    }
    return _cleanup(deadline: deadline, retry: false);
  }

  @override
  Future<CloseReport> releaseWithoutArchive({DateTime? deadline}) {
    if (_confirmation != null) return Future.error(_captureConflict);
    _released = true;
    for (final session in sessions) { session.releasePreparation(); }
    return _cleanup(deadline: deadline, retry: false);
  }

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) => _cleanup(deadline: deadline, retry: true);

  Future<CloseReport> _cleanup({DateTime? deadline, required bool retry}) async {
    final closing = Future.wait([
      for (final session in sessions) session.joinPreparation(deadline: deadline, retry: retry),
      for (final session in _retiring) retire(session, deadline: deadline, retry: retry),
    ]);
    closing.ignore(); // The original Future below still delivers every failure.
    if (_preparing case final preparing?) {
      await observeConversationCompletion(preparing.then<void>((_) {}, onError: (Object _, StackTrace __) {}), deadline);
    }
    final reports = await closing;
    return conversationCloseReport([
      for (final report in reports) ...report.unresolved,
      if (_preparing != null && !_preparationDone) UnresolvedResource(owner: 'conversation-archive:$id',
        attemptId: attemptId, issues: [const FeedCloseIssue(diagnostic: StudioShutdownIssue(
          stage: 'conversationArchive', code: 'preparePending', message: 'The original archive preparation is still in flight.',
          retryable: true, correlationId: 'conversation-archive'), recovery: CleanupRecovery.awaitCompletion)]),
    ]);
  }
}

final class ConversationProjectArchiveCapture extends _ConversationArchiveCapture
    implements WorkspaceProjectArchiveCapture {
  ConversationProjectArchiveCapture(super.id, super.frozenSelection, super.attemptId, super.sessions, super.retire);

  @override
  Future<void> prepare(ProjectRecord originalProject) => prepareOriginal(originalProject, () async {
    if (originalProject.id != id) throw _captureConflict;
    await Future.wait([for (final session in sessions) session.prepareMembership()]);
  });

  @override
  Future<CloseReport> afterArchived(ProjectRecord archivedProject, {DateTime? deadline}) {
    if (archivedProject.id != id) return Future.error(_captureConflict);
    return confirm(archivedProject, (session) => session.membership?.projectId == id, deadline: deadline);
  }
}

final class ConversationThreadArchiveCapture extends _ConversationArchiveCapture
    implements WorkspaceThreadArchiveCapture {
  ConversationThreadArchiveCapture(super.id, super.frozenSelection, super.attemptId, super.sessions, super.retire);

  @override
  Future<void> prepare(WorkspaceThreadRecord originalRoot) => prepareOriginal(originalRoot, () async {
    if (originalRoot.id != id || !originalRoot.isRoot) throw _captureConflict;
    // Fixed Thread IDs plus the native complete result determine this cleanup;
    // no Project-wide scan or membership read is necessary for unrelated owners.
  });

  @override
  Future<CloseReport> afterArchived(ArchiveThreadResult result, {DateTime? deadline}) {
    if (result.archivedRootId != id) return Future.error(_captureConflict);
    if (_confirmation != null && _confirmation != result) return Future.error(_captureConflict);
    if (!result.removedThreadIds.contains(id)) return Future.error(const StudioFailure(
      code: StudioFailureCode.protocol, message: 'The archive result omitted its original root.',
      retryable: false, correlationId: 'conversation-archive-result'));
    final removed = result.removedThreadIds.toSet();
    return confirm(result, (session) => removed.contains(session.owner.threadId), deadline: deadline);
  }
}

const _captureConflict = StudioFailure(code: StudioFailureCode.conflict,
  message: 'The archive capture no longer matches its original target or confirmation.',
  retryable: false, correlationId: 'conversation-archive-capture');
