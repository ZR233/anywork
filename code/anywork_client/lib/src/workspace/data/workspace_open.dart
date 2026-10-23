import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_values.dart';
import '../domain/selection.dart';
import 'workspace_directories.dart';
import 'workspace_commands.dart';
import 'workspace_selection_owner.dart';

/// Independently recorded native steps, not a transaction or parent receipt.
final class WorkspaceOpen {
  WorkspaceOpen(this.directories, this.selection, this.commands);
  final WorkspaceDirectories directories;
  final WorkspaceSelectionOwner selection;
  final WorkspaceCommands commands;
  OperationRecorder get operations => commands.operations;
  final Set<_OpenBatch> _owned = Set.identity();

  WorkspaceOpenBatch local(String path) => _open(null, path, null);
  WorkspaceOpenBatch remote(String alias, String path, {String? name}) => _open(alias, path, name);

  WorkspaceOpenBatch _open(String? alias, String path, String? name) {
    final lifetime = directories.lifetime;
    lifetime.admit();
    final intent = selection.reserve();
    final batch = _OpenBatch(lifetime.nextAttempt(), alias, path, name, intent);
    final prior = [for (final other in _owned) if (other.alias == alias && other.path == path) other];
    final ready = Completer<void>();
    ready.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _owned.add(batch);
    try {
      lifetime.run('workspace-open-batch', () async {
        try {
          await ready.future;
          await Future.wait([for (final other in prior) other.done.future]);
          final failure = prior.any((other) => other.unknown || other.terminal != null) ? _conflict : null;
          return await _run(batch, failure);
        } finally {
          if (!batch.done.isCompleted) batch.done.complete();
          selection.settleIntent(intent, unknown: batch.unknown || batch.terminal != null);
          if (!batch.unknown && batch.terminal == null) _owned.remove(batch);
        }
      }).then<void>(batch.completion.complete, onError: (Object error, StackTrace stack) {
        _remember(batch, error, stack);
        if (batch.allocated) {
          batch.terminal = resourceCleanupIssue(error, CleanupRecovery.terminal);
          _owned.add(batch);
          _notStarted(batch, resourceFailure(error));
          batch.completion.complete(WorkspaceOpenResult(steps: batch.steps,
            selection: WorkspaceOpenSelection.failed(error: resourceFailure(error))));
        } else { batch.completion.completeError(error, stack); }
      });
      // Whole work and the immutable path/alias/name precede reentrant observers.
      selection.publishIntent(intent);
      batch.opened = operations.begin<ProjectRecord>(target: 'workspace-open');
      if (name != null) batch.renamed = operations.begin<ProjectRecord>(target: 'workspace-open-rename');
      batch.activated = operations.begin<Unit>(target: 'workspace-open-activate');
      batch.allocated = true;
      ready.complete(); return batch;
    } catch (error, stack) {
      final failure = resourceFailure(error);
      batch.opened?.rejected(failure); batch.renamed?.rejected(failure); batch.activated?.rejected(failure);
      if (!ready.isCompleted) ready.completeError(error, stack);
      rethrow;
    }
  }

  Future<WorkspaceOpenResult> _run(_OpenBatch batch, StudioFailure? conflict) async {
    final opened = await _step<ProjectRecord>(batch, batch.opened!, () {
      if (conflict != null) throw CommandDispatchFailure.rejected(failure: conflict);
      return batch.alias == null ? directories.port.openProject(batch.path) : directories.port.openRemoteProject(batch.alias!, batch.path);
    }, key: (kind: batch.alias == null ? WorkspaceWriteKind.localPath : WorkspaceWriteKind.remotePath,
      id: batch.alias ?? '', path: batch.path), validate: (project) {
      if (project.sshAlias != batch.alias) throw resourceProtocol('Project open returned another host identity.');
    });
    batch.steps.add(WorkspaceOpenStep.opened(operationId: batch.opened!.ticket.id, result: opened));
    if (!_success(opened)) return _stopped(batch, _failure(opened));
    var project = _project(opened);
    final rename = batch.renamed;
    if (rename != null) {
      final original = project;
      final same = batch.name == original.name;
      final renamed = await _step<ProjectRecord>(batch, rename,
        () => same ? Future.value(original) : directories.port.renameProject(original.id, batch.name!),
        key: (kind: WorkspaceWriteKind.project, id: original.id, path: null), native: !same, validate: (value) {
          if (value.id != original.id || value.path != original.path || value.sshAlias != original.sshAlias) {
            throw resourceProtocol('Project rename changed the opened filesystem identity.');
          }
        });
      batch.steps.add(WorkspaceOpenStep.renamed(operationId: rename.ticket.id, result: renamed));
      if (!_success(renamed)) return _stopped(batch, _failure(renamed));
      project = _project(renamed);
    }
    final activated = await _step<Unit>(batch, batch.activated!, () async {
      await directories.port.activateProject(project.id); return const Unit();
    }, key: (kind: WorkspaceWriteKind.project, id: project.id, path: null));
    batch.steps.add(WorkspaceOpenStep.activated(operationId: batch.activated!.ticket.id, result: activated));
    if (!_success(activated)) return _stopped(batch, _failure(activated));
    WorkspaceOpenSelection result;
    try { result = WorkspaceOpenSelection.applied(value: await selection.defaultProject(project.id, batch.intent)); }
    catch (error, stack) {
      _remember(batch, error, stack);
      result = WorkspaceOpenSelection.failed(error: resourceFailure(error));
    }
    return WorkspaceOpenResult(steps: batch.steps, selection: result);
  }

  Future<CommandResult<T>> _step<T>(_OpenBatch batch, OperationWriter<T> writer,
      Future<T> Function() action, {required WorkspaceWriteKey key, bool native = true, void Function(T)? validate}) async {
    final OperationTicket<T> ticket;
    try {
      ticket = commands.run<T>(label: 'workspace-open:${key.kind.name}', key: key, existing: writer, action: (scope) async {
        final value = native ? await scope.invoke(action) : await action();
        scope.confirm(); validate?.call(value); scope.confirm(value: value);
        return value;
      });
    } catch (error, stack) {
      // run can fail synchronously only before its handed-off action starts.
      // Never turn a later ticket/native success into a local rejection.
      _remember(batch, error, stack);
      writer.rejected(resourceFailure(error));
    return await writer.ticket.result;
    }
    final result = await ticket.result;
    if (result is UnknownOutcomeCommandResult<T>) {
      batch.unknown = true; batch.failure = result.error;
    }
    return result;
  }

  WorkspaceOpenResult _stopped(_OpenBatch batch, StudioFailure reason) {
    _notStarted(batch, reason);
    return WorkspaceOpenResult(steps: batch.steps, selection: WorkspaceOpenSelection.notAttempted(reason: reason));
  }

  void _notStarted(_OpenBatch batch, StudioFailure reason) {
    final hasRename = batch.steps.any((step) => step is RenamedWorkspaceOpenStep ||
      step is NotStartedWorkspaceOpenStep && step.stage == WorkspaceOpenStage.rename);
    if (batch.renamed != null && !hasRename) {
      batch.renamed!.rejected(reason);
      batch.steps.add(WorkspaceOpenStep.notStarted(operationId: batch.renamed!.ticket.id, stage: WorkspaceOpenStage.rename, error: reason));
    }
    final hasActivate = batch.steps.any((step) => step is ActivatedWorkspaceOpenStep ||
      step is NotStartedWorkspaceOpenStep && step.stage == WorkspaceOpenStage.activate);
    if (!hasActivate) {
      batch.activated!.rejected(reason);
      batch.steps.add(WorkspaceOpenStep.notStarted(operationId: batch.activated!.ticket.id, stage: WorkspaceOpenStage.activate, error: reason));
    }
  }

  bool _success<T>(CommandResult<T> result) => result is AcknowledgedCommandResult<T> || result is CommittedCommandResult<T>;
  ProjectRecord _project(CommandResult<ProjectRecord> result) => switch (result) {
    AcknowledgedCommandResult(:final value) || CommittedCommandResult(:final value) => value,
    _ => throw resourceProtocol('A failed open step has no usable Project result.'),
  };
  StudioFailure _failure<T>(CommandResult<T> result) => switch (result) {
    RejectedCommandResult<T>(:final error) || UnknownOutcomeCommandResult<T>(:final error) ||
    SyncFailedCommandResult<T>(:final error) || AcknowledgedSyncFailedCommandResult<T>(:final error) => error,
    _ => throw resourceProtocol('A successful open step has no failure.'),
  };
  void _remember(_OpenBatch batch, Object error, StackTrace stack) {
    batch.causes.add((error, stack)); batch.failure = error is CommandDispatchFailure ? error.failure : resourceFailure(error);
    directories.lifetime.lastCause = error; directories.lifetime.lastStack = stack;
  }
  List<UnresolvedResource> get unresolved => [for (final batch in _owned)
    if (batch.terminal != null) UnresolvedResource(owner: 'workspace-open-batch', attemptId: AttemptId(batch.attempt), issues: [
      if (batch.terminal case final issue?) issue,
    ])];

  static const _conflict = StudioFailure(code: StudioFailureCode.conflict,
    message: 'The original project open retains an unknown result.', retryable: false, correlationId: 'workspace');
}

final class _OpenBatch implements WorkspaceOpenBatch {
  _OpenBatch(this.attempt, this.alias, this.path, this.name, this.intent) {
    completion.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  }
  final int attempt;
  final String? alias;
  final String path;
  final String? name;
  final WorkspaceIntentStamp intent;
  final Completer<WorkspaceOpenResult> completion = Completer();
  final Completer<void> done = Completer();
  final List<WorkspaceOpenStep> steps = [];
  final List<(Object, StackTrace)> causes = [];
  OperationWriter<ProjectRecord>? opened;
  OperationWriter<ProjectRecord>? renamed;
  OperationWriter<Unit>? activated;
  bool allocated = false;
  bool unknown = false;
  StudioFailure? failure;
  FeedCloseIssue? terminal;
  @override
  List<OperationObservation> get operations => List.unmodifiable([
    if (opened case final writer?) writer.ticket, if (renamed case final writer?) writer.ticket,
    if (activated case final writer?) writer.ticket,
  ]);
  @override
  Future<WorkspaceOpenResult> get result => completion.future;
}
