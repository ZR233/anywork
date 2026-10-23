import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_values.dart';
import '../domain/selection.dart';
import 'workspace_access.dart';
import 'workspace_archive_capture_port.dart';
import 'workspace_command_cleanup.dart';
import 'workspace_commands.dart';
import 'workspace_directories.dart';
import 'workspace_directory_capture.dart';
import 'workspace_selection_owner.dart';
import 'thread_directory_owner.dart';

/// Archive is a real command with an original capture, not a UI lifetime.
final class WorkspaceArchives {
  WorkspaceArchives(this.directories, this.commands, this.selection, this.access, this.capturePort);
  final WorkspaceDirectories directories;
  final WorkspaceCommands commands;
  final WorkspaceSelectionOwner selection;
  final WorkspaceAccess access;
  final WorkspaceArchiveCapturePort capturePort;

  OperationTicket<Unit> project(String id) {
    directories.lifetime.admit();
    final frozen = selection.source.value;
    final work = _ProjectArchive(directories, selection, frozen, id, directories.captureOwned(), access);
    return commands.run<Unit>(label: 'workspace-archive-project', selection: true,
      key: (kind: WorkspaceWriteKind.project, id: id, path: null), capture: (scope) {
        scope.cleanup = work;
        work.capture(capturePort);
      }, action: work.run);
  }

  OperationTicket<ArchiveThreadResult> thread(String id) {
    directories.lifetime.admit();
    final frozen = selection.source.value;
    final work = _ThreadArchive(directories, selection, frozen, id, directories.captureOwned(), access,
      selection.selectedRootFor(frozen));
    return commands.run<ArchiveThreadResult>(label: 'workspace-archive-thread', selection: true,
      key: (kind: WorkspaceWriteKind.thread, id: id, path: null), capture: (scope) {
        scope.cleanup = work;
        work.capture(capturePort);
      }, action: work.run);
  }
}

sealed class _ArchiveWork implements WorkspaceCommandCleanup {
  _ArchiveWork(this.directories, this.selection, this.frozen, this.id, this.local, this.access);
  final WorkspaceDirectories directories;
  final WorkspaceSelectionOwner selection;
  final WorkspaceState frozen;
  final String id;
  final WorkspaceDirectoryCapture local;
  final WorkspaceAccess access;
  WorkspaceArchiveCapture? get external;
  bool get validResult;
  Future<CloseReport> afterArchived();
  bool coversSelection(WorkspaceState state);
  WorkspaceThreadDirectory? prepared;
  final Completer<void> _decision = Completer();
  final List<(Object, StackTrace)> _causes = [];
  bool _confirmed = false;
  bool _unknown = false;
  bool _confirmedCleanup = false;
  bool _released = false;
  bool _joiningDone = false;
  Future<void>? _joining;
  Future<void>? _externalWork;
  Future<void>? _localWork;
  Future<void>? _preparedWork;
  CloseReport? _externalReport;
  CloseReport? _localReport;
  CloseReport? _preparedReport;
  FeedCloseIssue? _terminal;

  void startConfirmed() {
    if (_confirmedCleanup) return;
    if (!validResult) throw resourceProtocol('Archive has no complete validated confirmation.');
    _confirmedCleanup = true;
    // Each independent leaf starts even if another call throws or is slow.
    _externalWork = _call('external-archive', afterArchived, (report) => _externalReport = report);
    _localWork = _call('captured-directory', () => local.closeConfirmed(), (report) => _localReport = report);
  }

  @override
  Future<CloseReport> finish({required bool confirmed, required bool unknown}) async {
    if (_decision.isCompleted) {
      if (_confirmed != confirmed || _unknown != unknown) throw const StudioFailure(code: StudioFailureCode.conflict,
        message: 'Archive confirmation conflicts with its original decision.', retryable: false, correlationId: 'workspace-archive');
      return await close();
    }
    _confirmed = confirmed; _unknown = unknown;
    if (unknown) {
      _terminal = resourceCleanupIssue(const StudioFailure(code: StudioFailureCode.unavailable,
        message: 'The original archive outcome is unknown; its capture is retained.',
        retryable: false, correlationId: 'workspace-archive'), CleanupRecovery.terminal);
    } else if (confirmed && !validResult) {
      _terminal = resourceCleanupIssue(resourceProtocol('Known archive success has no complete usable result; capture is retained.'),
        CleanupRecovery.terminal);
    } else if (confirmed) { startConfirmed(); }
    else {
      _released = true;
      final leaf = external;
      if (leaf != null) _externalWork = _call('external-release', () => leaf.releaseWithoutArchive(), (report) => _externalReport = report);
      _localWork = local.joinPreparation().then<void>((_) { _localReport = CloseReport(unresolved: []); });
    }
    // Prepared metadata is an original pure-read responsibility, never a UI or
    // evidence scope. Unknown retains it until the repository's actual seal.
    if (!unknown) _closePrepared(retry: false);
    _decision.complete();
    _join();
    await _joining;
    return report;
  }

  Future<void> _call(String label, Future<CloseReport> Function() action, void Function(CloseReport) save) =>
    Future<CloseReport>.sync(action).then<void>(save, onError: (Object error, StackTrace stack) {
      _causes.add((error, stack)); directories.lifetime.lastCause = error; directories.lifetime.lastStack = stack;
      save(CloseReport(unresolved: [UnresolvedResource(owner: label, attemptId: AttemptId(local.attempt),
        issues: [resourceCleanupIssue(error, CleanupRecovery.retryClose)])]));
    });

  void _closePrepared({required bool retry}) {
    final owner = prepared;
    if (owner != null && _preparedReport?.complete != true && (!retry || _recoverable(_preparedReport))) {
      _preparedWork = _call('archive-prepared-metadata', () => owner.close(retry: retry), (report) => _preparedReport = report);
    }
  }

  bool _recoverable(CloseReport? value) => value?.unresolved.any((resource) =>
    resource.issues.any((issue) => issue.recovery != CleanupRecovery.terminal)) ?? false;
  bool _awaiting(CloseReport? value) => value?.unresolved.any((resource) =>
    resource.issues.any((issue) => issue.recovery == CleanupRecovery.awaitCompletion)) ?? false;

  void _join() {
    _joiningDone = false;
    _joining = Future.wait([if (_externalWork != null) _externalWork!, if (_localWork != null) _localWork!,
      if (_preparedWork != null) _preparedWork!]).then<void>((_) { _joiningDone = true; });
  }

  @override
  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    if (!await waitWorkspaceCompletion(_decision.future, deadline)) return report;
    if (_joiningDone) {
      final leaf = external;
      var observe = false;
      if ((_released || _confirmedCleanup) && leaf != null && (retry ? _recoverable(_externalReport) : _awaiting(_externalReport))) {
        _externalWork = _call('external-archive-observe', () => retry ? leaf.retryCleanup() :
          _confirmedCleanup ? afterArchived() : leaf.releaseWithoutArchive(), (report) => _externalReport = report);
        observe = true;
      }
      if (_confirmedCleanup && (retry ? _recoverable(_localReport) : _awaiting(_localReport))) {
        _localWork = _call('captured-directory-observe', () => local.closeConfirmed(retry: retry), (report) => _localReport = report);
        observe = true;
      }
      if (!_unknown && (retry ? _recoverable(_preparedReport) : _awaiting(_preparedReport))) {
        _closePrepared(retry: retry); observe = true;
      }
      if (observe) _join();
    }
    if (_joining case final original?) await waitWorkspaceCompletion(original, deadline);
    return report;
  }

  @override
  CloseReport get report => CloseReport(unresolved: [
    if (_terminal != null || !_decision.isCompleted || !_joiningDone)
      UnresolvedResource(owner: 'workspace-archive:$id', attemptId: AttemptId(local.attempt), issues: [
        if (_terminal case final issue?) issue,
        if (!_decision.isCompleted || !_joiningDone) resourcePendingIssue('archiveWorkPending'),
      ]),
    if (_externalReport case final value?) ...value.unresolved,
    if (_localReport case final value?) ...value.unresolved,
    if (_preparedReport case final value?) ...value.unresolved,
  ]);

  @override
  bool holdsRemoval(WorkspaceState state) => state.selectionGeneration == frozen.selectionGeneration &&
    coversSelection(state);
}

final class _ProjectArchive extends _ArchiveWork {
  _ProjectArchive(super.directories, super.selection, super.frozen, super.id, super.local, super.access);
  WorkspaceProjectArchiveCapture? leaf;
  ProjectRecord? archived;
  bool _valid = false;
  @override
  WorkspaceArchiveCapture? get external => leaf;
  @override
  bool get validResult => _valid;
  void capture(WorkspaceArchiveCapturePort port) {
    leaf = port.captureProject(id, frozenSelection: frozen);
    local.prepareProjectReads();
  }
  Future<Unit> run(WorkspaceCommandScope<Unit> scope) async {
    final original = await directories.readProject(id);
    if (original.id != id) throw resourceProtocol('Archive preparation read another Project.');
    await Future.wait([Future<void>.sync(() => local.prepareProject(id)), Future<void>.sync(() => leaf!.prepare(original))]);
    access.project(id);
    final result = await scope.invoke(() => directories.port.archiveProject(id));
    archived = result; scope.confirm(value: const Unit());
    if (result.id != id || result.path != original.path || result.sshAlias != original.sshAlias) {
      throw resourceProtocol('Archive returned another original Project.');
    }
    _valid = true; startConfirmed();
    await selection.afterProjectRemoval(frozen, id);
    return const Unit();
  }
  @override
  Future<CloseReport> afterArchived() => leaf!.afterArchived(archived!);
  @override
  bool coversSelection(WorkspaceState state) => state.selection.projectId == id;
}

final class _ThreadArchive extends _ArchiveWork {
  _ThreadArchive(super.directories, super.selection, super.frozen, super.id, super.local, super.access, this.selectedRoot);
  final String? selectedRoot;
  WorkspaceThreadArchiveCapture? leaf;
  ArchiveThreadResult? archived;
  CommitReceipt? receipt;
  bool _valid = false;
  @override
  WorkspaceArchiveCapture? get external => leaf;
  @override
  bool get validResult => _valid;
  void capture(WorkspaceArchiveCapturePort port) { leaf = port.captureThread(id, frozenSelection: frozen); }
  Future<ArchiveThreadResult> run(WorkspaceCommandScope<ArchiveThreadResult> scope) async {
    final owner = directories.openScope(ThreadDirectoryScope.thread(threadId: id));
    prepared = owner;
    final original = (await owner.reads.lookup(id)).value;
    if (!original.isRoot || original.archived) throw const StudioFailure(code: StudioFailureCode.invalidArgument,
      message: 'Only an unarchived root Thread can be archived.', retryable: false, correlationId: 'workspace');
    await leaf!.prepare(original);
    access.thread(id);
    final epoch = owner.mirror.current?.origin.ownerEpoch;
    if (epoch == null) throw const StudioFailure(code: StudioFailureCode.unavailable,
      message: 'The original archive metadata source is unavailable.', retryable: true, correlationId: 'workspace');
    final reply = await scope.invoke(() => directories.port.archiveThread(id, operationId: scope.operationId));
    archived = reply.result; receipt = reply.receipt;
    scope.confirm(value: reply.result);
    final result = reply.result;
    final removed = result.removedThreadIds.toSet();
    final next = result.nextRoot;
    if (result.archivedRootId != id || !removed.contains(id) || removed.length != result.removedThreadIds.length ||
        removed.any((value) => value.isEmpty) || next != null &&
          (!next.isRoot || next.archived || next.projectId != original.projectId || removed.contains(next.id))) {
      throw resourceProtocol('Archive returned an invalid original tree or successor.');
    }
    final targets = reply.receipt.targets;
    if (targets.length != 1 || targets.single is! ResourceStamp || reply.receipt.requiresIdentityObservation) {
      throw resourceProtocol('Archive has an unexpected observation contract.');
    }
    final target = targets.single as ResourceStamp;
    if (target.resourceKey != 'thread-directory' || target.ownerEpoch != epoch || target.revision < 0) {
      throw resourceProtocol('Archive receipt belongs to another directory source.');
    }
    scope.confirm(value: result, receipt: reply.receipt);
    local.confirmThread(removed);
    _valid = true; startConfirmed();
    selection.afterThreadArchive(frozen, result);
    await owner.mirror.source.waitFor((state) {
      owner.lifetime.admit();
      if (state.projection.sync.phase == ResourceSyncPhase.failed) throw state.projection.sync.error!;
      if (state.projection.stamp?.ownerEpoch != epoch) throw const StudioFailure(code: StudioFailureCode.superseded,
        message: 'The original archive directory owner was replaced.', retryable: true, correlationId: 'workspace');
      if (state.projection.sync.phase == ResourceSyncPhase.ready && state.projection.header?.reference == null) {
        throw const StudioFailure(code: StudioFailureCode.unavailable,
          message: 'The original archive directory watermark is unavailable.', retryable: true, correlationId: 'workspace');
      }
      return state.projection.sync.phase == ResourceSyncPhase.ready &&
        (state.projection.header?.directoryRevision ?? -1) >= target.revision;
    });
    return result;
  }
  @override
  Future<CloseReport> afterArchived() => leaf!.afterArchived(archived!);
  @override
  bool coversSelection(WorkspaceState state) => _valid ? archived!.removedThreadIds.contains(state.selection.threadId) :
    state.selection.threadId == id || state.selection.threadId == frozen.selection.threadId && selectedRoot == id;
}
