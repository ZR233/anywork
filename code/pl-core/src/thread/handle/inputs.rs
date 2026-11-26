//! Priority Tier-1 user input admission and serial queue execution commands.
use super::*;

impl ThreadHandle {
    /// Accepts a typed, idempotent Resume control without manufacturing user input.
    pub async fn resume_execution(
        &self,
        request: ResumeRequest,
        options: input::InputDriverOptions,
    ) -> Result<ContinuationOperation, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::Resume(request, options, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    pub async fn read_resume(
        &self,
        request: ResumeRequest,
    ) -> Result<ContinuationRead, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::ReadResume(request, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Enables execution of pending immediate inputs after recovery, pause or failure.
    ///
    /// # Errors
    /// Returns a closed owner error without consuming pending input.
    pub async fn drive_pending(
        &self,
        options: input::InputDriverOptions,
    ) -> Result<(), ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::DrivePending(options, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Pauses future execution of pending inputs. Use `interrupt` separately to cancel an active Turn.
    ///
    /// # Errors
    /// Returns an error if the owner is no longer reachable.
    pub async fn pause_execution(&self) -> Result<(), ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::PauseExecution(reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)
    }

    /// Saves immutable input under immediate-only semantics: starts execution when idle (if `drive`
    /// is provided), or softly preempts preparing/streaming steps and wakes waits during a Turn.
    ///
    /// # Errors
    /// Rejects conflicting identities, closed owners and cold-storage pressure.
    pub async fn submit_input(
        &self,
        input: input::ThreadInput,
        drive: Option<input::InputDriverOptions>,
    ) -> Result<input::InputRecord, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::SubmitInput(input, drive, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Explicitly discards a pending input without pretending it was sent to a model.
    ///
    /// # Errors
    /// Rejects missing, consumed or currently preparing input identities.
    pub async fn discard_input(&self, id: String) -> Result<input::InputRecord, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::DiscardInput(id, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }
}
