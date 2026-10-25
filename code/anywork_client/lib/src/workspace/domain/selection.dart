import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import 'directory_values.dart';

part 'selection.freezed.dart';

@freezed
abstract class WorkspaceSelection with _$WorkspaceSelection {
  @Assert('threadId == null || projectId != null')
  @Assert('!needsOpen || threadId != null')
  const factory WorkspaceSelection({
    required String? projectId,
    required String? threadId,
    required bool needsOpen,
  }) = _WorkspaceSelection;
}

@freezed
abstract class WorkspaceState with _$WorkspaceState {
  const factory WorkspaceState({
    required WorkspaceSelection selection,
    required int selectionGeneration,
    required bool sealed,
  }) = _WorkspaceState;
}

@freezed
abstract class WorkspaceIntentStamp with _$WorkspaceIntentStamp {
  const factory WorkspaceIntentStamp({required int generation}) =
      _WorkspaceIntentStamp;
}

enum SelectionDisposition { selected, unchanged, superseded }

@freezed
abstract class WorkspaceSelectionResult with _$WorkspaceSelectionResult {
  const factory WorkspaceSelectionResult({
    required WorkspaceIntentStamp intent,
    required WorkspaceSelection selection,
    required SelectionDisposition disposition,
  }) = _WorkspaceSelectionResult;
}

@freezed
final class ArchiveThreadResult with _$ArchiveThreadResult {
  ArchiveThreadResult({
    required this.archivedRootId,
    required List<String> removedThreadIds,
    required this.nextRoot,
  }) : removedThreadIds = List.unmodifiable(removedThreadIds);
  final String archivedRootId;
  final List<String> removedThreadIds;
  final WorkspaceThreadRecord? nextRoot;
}

enum WorkspaceOpenStage { open, rename, activate }

@Freezed(toStringOverride: false)
sealed class WorkspaceOpenStep with _$WorkspaceOpenStep {
  const factory WorkspaceOpenStep.opened({
    required OperationId operationId,
    required CommandResult<ProjectRecord> result,
  }) = OpenedWorkspaceOpenStep;
  const factory WorkspaceOpenStep.renamed({
    required OperationId operationId,
    required CommandResult<ProjectRecord> result,
  }) = RenamedWorkspaceOpenStep;
  const factory WorkspaceOpenStep.activated({
    required OperationId operationId,
    required CommandResult<Unit> result,
  }) = ActivatedWorkspaceOpenStep;
  const factory WorkspaceOpenStep.notStarted({
    required OperationId operationId,
    required WorkspaceOpenStage stage,
    required StudioFailure error,
  }) = NotStartedWorkspaceOpenStep;
}

@Freezed(toStringOverride: false)
sealed class WorkspaceOpenSelection with _$WorkspaceOpenSelection {
  const factory WorkspaceOpenSelection.applied({
    required WorkspaceSelectionResult value,
  }) = AppliedWorkspaceOpenSelection;
  const factory WorkspaceOpenSelection.notAttempted({
    required StudioFailure reason,
  }) = NotAttemptedWorkspaceOpenSelection;
  const factory WorkspaceOpenSelection.failed({required StudioFailure error}) =
      FailedWorkspaceOpenSelection;
}

@Freezed(toStringOverride: false)
final class WorkspaceOpenResult with _$WorkspaceOpenResult {
  WorkspaceOpenResult({
    required List<WorkspaceOpenStep> steps,
    required this.selection,
  }) : steps = List.unmodifiable(steps);
  final List<WorkspaceOpenStep> steps;
  final WorkspaceOpenSelection selection;
}

/// A borrowed observation of independently owned operations, not a transaction.
abstract interface class WorkspaceOpenBatch {
  List<OperationObservation> get operations;
  Future<WorkspaceOpenResult> get result;
}
