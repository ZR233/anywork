//! One stdin owner, cancellable writes and transport acknowledgements.
use super::*;

pub(super) struct CommandInput {
    pub(super) writer: Option<CommandWriter>,
    pub(super) accepted_bytes: u64,
    pub(super) close_state: crate::command::StdinCloseState,
}

pub use pl_tool_command::process::{CommandInputOutcome, CommandInputReceipt};

impl<B: CommandBackend> CommandProcessManager<B> {
    pub async fn write_stdin(
        &self,
        request: CommandWriteRequest,
    ) -> Result<CommandOutputSnapshot, PureError> {
        let Some(entry) = self.entry(&request.process_id).await else {
            return Err(tool_error(
                "write_stdin",
                format!(
                    "task '{}' has no live process. Inspect get_tool_task before starting another command.",
                    request.process_id
                ),
            ));
        };
        use crate::command::StdinCloseState;
        let mut receipt = CommandInputReceipt {
            accepted_bytes: 0,
            close_state: None,
            outcome: CommandInputOutcome::Complete,
            detail: None,
        };
        let locked = tokio::select! {
            biased;
            _ = request.cancellation.cancelled() => None,
            input = entry.stdin.lock() => Some(input),
        };
        if let Some(mut input) = locked {
            receipt.close_state = Some(input.close_state);
            let bytes = request.chars.as_bytes();
            if !bytes.is_empty()
                && (input.close_state != StdinCloseState::Open
                    || input.writer.is_none()
                    || !entry.can_accept_input().await)
            {
                receipt.outcome = CommandInputOutcome::Failed;
                receipt.detail = Some("exec.stdin_closed: target no longer accepts input; inspect the original exec task".into());
            } else {
                while (receipt.accepted_bytes as usize) < bytes.len() {
                    let Some(writer) = input.writer.as_mut() else {
                        break;
                    };
                    let written = tokio::select! {
                        biased;
                        _ = request.cancellation.cancelled() => { receipt.outcome = CommandInputOutcome::Cancelled; break; },
                        _ = entry.input_stopped.cancelled() => { receipt.outcome = CommandInputOutcome::Partial; receipt.detail = Some("target process exited while input was pending".into()); break; },
                        result = writer.write(&bytes[receipt.accepted_bytes as usize..]) => result,
                    };
                    match written {
                        Ok(0) => {
                            receipt.outcome = CommandInputOutcome::Partial;
                            receipt.detail = Some(std::io::ErrorKind::WriteZero.to_string());
                            break;
                        }
                        Ok(count) => {
                            receipt.accepted_bytes += count as u64;
                            input.accepted_bytes += count as u64;
                        }
                        Err(error) => {
                            receipt.outcome = CommandInputOutcome::Partial;
                            receipt.detail = Some(error.to_string());
                            break;
                        }
                    }
                }
                if receipt.accepted_bytes as usize == bytes.len()
                    && matches!(receipt.outcome, CommandInputOutcome::Complete)
                {
                    if request.close_stdin {
                        input.writer.take();
                        input.close_state = StdinCloseState::Closed;
                    } else if let Some(writer) = input.writer.as_mut() {
                        tokio::select! {
                            biased;
                            _ = request.cancellation.cancelled() => { receipt.outcome = CommandInputOutcome::Cancelled; },
                            _ = entry.input_stopped.cancelled() => {},
                            result = writer.flush() => { if let Err(error) = result { receipt.outcome = CommandInputOutcome::Partial; receipt.detail = Some(error.to_string()); } },
                        }
                    }
                }
                receipt.close_state = Some(input.close_state);
                if let Some(state) = receipt.close_state {
                    input.close_state = state;
                }
            }
        } else {
            receipt.outcome = CommandInputOutcome::Cancelled;
        }
        // The original exec may leave the resident map as soon as EOF makes it exit.
        // This input owner retains the same entry and its partial receipt across that race.
        wait_for_process_activity(&entry, request.yield_time).await;
        let mut snapshot = self
            .snapshot_entry(&entry, request.max_output_chars)
            .await?;
        snapshot.input_receipt = Some(receipt);
        Ok(snapshot)
    }
}
