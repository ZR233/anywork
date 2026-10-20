import 'composer_models.dart';
import 'failure_models.dart';
import 'studio_enums.dart';

enum ThreadPreparationStage {
  checkingProject,
  preparingWorkspace,
  resolvingRepository,
  creatingWorktree,
  initializingSession,
  submittingPrompt;

  int get step => switch (this) {
    checkingProject => 0,
    preparingWorkspace || resolvingRepository || creatingWorktree => 1,
    initializingSession => 2,
    submittingPrompt => 3,
  };
}

final class ThreadPreparationProgress {
  const ThreadPreparationProgress({
    required this.projectId,
    required this.inputId,
    required this.stage,
    this.workspacePath,
    this.branch,
  });

  final String projectId;
  final String inputId;
  final ThreadPreparationStage stage;
  final String? workspacePath;
  final String? branch;

  @override
  bool operator ==(Object other) =>
      other is ThreadPreparationProgress &&
      projectId == other.projectId &&
      inputId == other.inputId &&
      stage == other.stage &&
      workspacePath == other.workspacePath &&
      branch == other.branch;

  @override
  int get hashCode =>
      Object.hash(projectId, inputId, stage, workspacePath, branch);
}

sealed class NewThreadStartEvent {
  const NewThreadStartEvent();
}

final class NewThreadStartProgress extends NewThreadStartEvent {
  const NewThreadStartProgress(this.progress);
  final ThreadPreparationProgress progress;
}

final class NewThreadStartSucceeded extends NewThreadStartEvent {
  const NewThreadStartSucceeded(this.result);
  final StartNewThreadResult result;
}

/// A definite negative command outcome, including failures after compensation.
/// Transport errors or EOF without this outcome remain unknown.
final class NewThreadStartFailed extends NewThreadStartEvent
    implements Exception {
  const NewThreadStartFailed(this.error);
  final StudioFailure error;

  @override
  String toString() => error.toString();
}

enum NewThreadPreparationPhase { preparing, failed, unknownOutcome }

/// One frozen submission's display mirror, independent of later draft edits.
final class NewThreadPreparation {
  const NewThreadPreparation({
    required this.projectId,
    required this.inputId,
    required this.workspaceMode,
    this.progress,
    this.phase = NewThreadPreparationPhase.preparing,
    this.failure,
  });

  final String projectId;
  final String inputId;
  final ThreadWorkspaceMode workspaceMode;
  final ThreadPreparationProgress? progress;
  final NewThreadPreparationPhase phase;
  final Object? failure;

  NewThreadPreparation withProgress(ThreadPreparationProgress value) =>
      NewThreadPreparation(
        projectId: projectId,
        inputId: inputId,
        workspaceMode: workspaceMode,
        progress: value,
      );

  NewThreadPreparation withFailure(Object error, {required bool known}) =>
      NewThreadPreparation(
        projectId: projectId,
        inputId: inputId,
        workspaceMode: workspaceMode,
        progress: progress,
        phase: known
            ? NewThreadPreparationPhase.failed
            : NewThreadPreparationPhase.unknownOutcome,
        failure: error,
      );

  @override
  bool operator ==(Object other) =>
      other is NewThreadPreparation &&
      projectId == other.projectId &&
      inputId == other.inputId &&
      workspaceMode == other.workspaceMode &&
      progress == other.progress &&
      phase == other.phase &&
      failure == other.failure;

  @override
  int get hashCode =>
      Object.hash(projectId, inputId, workspaceMode, progress, phase, failure);
}
