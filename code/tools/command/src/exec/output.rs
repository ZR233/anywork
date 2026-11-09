use crate::exec::ExecResult;
use crate::process::{
    CommandCaptureFailure, CommandCaptureStream, CommandOutputLimit, CommandProcessFinalResult,
};
use serde::Serialize;

/// Domain outcome; reliable storage obligations and host error categories stay
/// with the host. In particular, cancellation still wins over a capture fault.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecOutcome {
    Succeeded,
    Cancelled,
    CaptureFailed,
    OutputLimit(CommandOutputLimit),
    Failed,
}

impl ExecResult {
    pub fn outcome(&self) -> ExecOutcome {
        match self.snapshot.state.final_result() {
            Some(CommandProcessFinalResult::Cancelled) => ExecOutcome::Cancelled,
            _ if matches!(
                self.snapshot.output_failure,
                Some(
                    CommandCaptureFailure::Read { .. }
                        | CommandCaptureFailure::Write { .. }
                        | CommandCaptureFailure::Flush { .. }
                )
            ) =>
            {
                ExecOutcome::CaptureFailed
            }
            Some(CommandProcessFinalResult::Failed { .. })
                if self.snapshot.output_limit_exceeded().is_some() =>
            {
                ExecOutcome::OutputLimit(self.snapshot.output_limit_exceeded().expect("checked"))
            }
            Some(CommandProcessFinalResult::Succeeded { .. }) => ExecOutcome::Succeeded,
            _ => ExecOutcome::Failed,
        }
    }

    /// Shapes the domain record after the host has retained any available
    /// streams. Durable references are opaque serializable values, not product DTOs.
    pub fn encode<R: Serialize>(
        &self,
        resources: &[(CommandCaptureStream, R)],
        receipt: Option<String>,
    ) -> Result<String, serde_json::Error> {
        crate::process::output::projection(
            &self.snapshot,
            resources,
            receipt,
            self.requested_body_bytes,
            None,
        )
    }
}
