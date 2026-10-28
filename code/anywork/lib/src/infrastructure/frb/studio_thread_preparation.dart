part of 'studio_api.dart';

NewThreadStartEvent _newThreadStartEventFromFrb(
  frb.BridgeNewThreadStartEvent event,
) {
  return event.when(
    progress: (progress) => NewThreadStartProgress(
      ThreadPreparationProgress(
        projectId: progress.projectId,
        inputId: progress.inputId,
        stage: switch (progress.stage) {
          frb.BridgeThreadPreparationStage.checkingProject =>
            ThreadPreparationStage.checkingProject,
          frb.BridgeThreadPreparationStage.preparingWorkspace =>
            ThreadPreparationStage.preparingWorkspace,
          frb.BridgeThreadPreparationStage.resolvingRepository =>
            ThreadPreparationStage.resolvingRepository,
          frb.BridgeThreadPreparationStage.creatingWorktree =>
            ThreadPreparationStage.creatingWorktree,
          frb.BridgeThreadPreparationStage.initializingSession =>
            ThreadPreparationStage.initializingSession,
          frb.BridgeThreadPreparationStage.submittingPrompt =>
            ThreadPreparationStage.submittingPrompt,
        },
        workspacePath: progress.workspacePath,
        branch: progress.branch,
      ),
    ),
    succeeded: (response) => NewThreadStartSucceeded(
      StartNewThreadResult(
        thread: _threadFromFrb(response.thread),
        receipt: SubmitPromptReceipt(
          threadId: response.receipt.threadId,
          inputId: response.receipt.inputId,
          cursor: response.receipt.revision.toInt(),
        ),
      ),
    ),
    failed: (error) => NewThreadStartFailed(
      StudioFailure(
        code: _studioFailureCode(error.code),
        message: error.message,
        retryable: error.retryable,
        correlationId: error.correlationId,
        detailsJson: error.detailsJson,
        reason: _failureReasonFromDetails(error.detailsJson),
      ),
    ),
  );
}
