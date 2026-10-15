//! Stop commands target the canonical Thread owner and validate identity inside its mailbox.
use super::super::{StudioInterruptPromptResponse, StudioRuntime, StudioStopPromptResponse};
use anyhow::Result;

impl StudioRuntime {
    pub async fn stop_prompt(&self, thread_id: String) -> Result<StudioStopPromptResponse> {
        self.read_owned_thread(&thread_id).await?;
        let stopped = match self.threads.thread(&thread_id) {
            Some(thread) => thread.interrupt_turn(None).await?,
            None => false,
        };
        Ok(StudioStopPromptResponse { thread_id, stopped })
    }

    /// Interrupts only the expected Turn; a delayed request cannot cancel a later Turn.
    pub async fn interrupt_prompt(
        &self,
        operation_id: String,
        thread_id: String,
        expected_turn_id: String,
    ) -> Result<StudioInterruptPromptResponse> {
        Self::validate_operation_id(&operation_id)?;
        self.read_owned_thread(&thread_id).await?;
        let interrupted = match self.threads.thread(&thread_id) {
            Some(thread) => thread
                .interrupt_turn(Some(expected_turn_id.clone()))
                .await
                .map_err(|error| match error {
                    pl_core::thread::ThreadError::InvalidIdentity => {
                        anyhow::Error::new(pl_protocol::studio::StudioError::invalid_argument(
                            "expected Turn does not match the active Turn",
                        ))
                    }
                    error => anyhow::Error::new(error),
                })?,
            None => false,
        };
        let mut receipt = self.command_receipt(
            operation_id,
            interrupted,
            Vec::new(),
            pl_protocol::studio::CommandEffectPoint::Immediate,
            false,
        );
        // interrupt_turn acknowledges the cancellation request. The matching
        // Turn must still stop in the owner stream before it is effective.
        receipt.effective = false;
        receipt.requires_identity_observation = true;
        Ok(StudioInterruptPromptResponse {
            thread_id,
            turn_id: expected_turn_id,
            interrupted,
            receipt,
        })
    }
}
