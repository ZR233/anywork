//! Standalone stdin tool over an explicitly shared process-input capability.
mod definition;
mod input;
pub use definition::write_stdin_definition;
pub use input::{WriteStdinInput, parse_and_validate_stdin_input};

use pl_agent_tool::{Tool, ToolDefinition};
use pl_tool_process::{
    CancellationToken, CommandInputOutcome, CommandOutputSnapshot, InputRequest, InputTarget,
    MAX_MODEL_BODY_BYTES, ProcessInput, input::ExecInputError,
};
use std::marker::PhantomData;

pub struct StdinContext<P> {
    pub processes: P,
    pub cancellation: CancellationToken,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputOutcome {
    Complete,
    Cancelled,
    Incomplete,
}

#[derive(Debug)]
pub enum StdinResult {
    Terminal {
        receipt_json: String,
    },
    Observed {
        snapshot: Box<CommandOutputSnapshot>,
        target_receipt: String,
        requested_body_bytes: usize,
        outcome: InputOutcome,
    },
}

impl StdinResult {
    pub fn encode(&self, receipt: Option<String>) -> Result<String, serde_json::Error> {
        match self {
            Self::Terminal { receipt_json } => Ok(receipt_json.clone()),
            Self::Observed {
                snapshot,
                target_receipt,
                requested_body_bytes,
                ..
            } => pl_tool_process::output::projection::<()>(
                snapshot,
                &[],
                receipt,
                *requested_body_bytes,
                Some(target_receipt),
            ),
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum StdinError<E: std::error::Error + 'static> {
    #[error(transparent)]
    InvalidInput(#[from] ExecInputError),
    #[error(transparent)]
    Process(E),
    #[error("stdin invocation cancelled before input was sent")]
    Cancelled,
    #[error(transparent)]
    Encoding(#[from] serde_json::Error),
}

#[derive(Debug)]
pub struct WriteStdinTool<P> {
    definition: ToolDefinition,
    processes: PhantomData<fn() -> P>,
}

impl<P> WriteStdinTool<P> {
    pub fn new(definition: ToolDefinition) -> Self {
        Self {
            definition,
            processes: PhantomData,
        }
    }
}

impl<P: ProcessInput> Tool for WriteStdinTool<P> {
    type Input = String;
    type Context = StdinContext<P>;
    type Output = StdinResult;
    type Error = StdinError<P::Error>;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        raw: String,
        context: StdinContext<P>,
    ) -> Result<StdinResult, Self::Error> {
        let input = parse_and_validate_stdin_input(&raw)?;
        let target = context
            .processes
            .resolve(&input.task_id, input.chars.is_empty() && input.close_stdin)
            .map_err(StdinError::Process)?;
        let target = match target {
            InputTarget::Terminal { status } => {
                let receipt = serde_json::json!({
                    "targetTaskId": input.task_id, "status": status,
                    "acceptedBytes": 0, "deliveryPending": false,
                    "detail": "Target is terminal; historical stdin close state is unavailable. No input was sent and no process was started."
                });
                return Ok(StdinResult::Terminal {
                    receipt_json: serde_json::to_string(&receipt)?,
                });
            }
            InputTarget::Live(target) => target,
        };
        if context.cancellation.is_cancelled() {
            return Err(StdinError::Cancelled);
        }
        let requested_body_bytes = input.max_output_chars.unwrap_or(MAX_MODEL_BODY_BYTES);
        let snapshot = context
            .processes
            .write(InputRequest {
                target,
                chars: input.chars,
                close_stdin: input.close_stdin,
                max_output_bytes: requested_body_bytes.min(MAX_MODEL_BODY_BYTES),
                cancellation: context.cancellation,
            })
            .await
            .map_err(StdinError::Process)?;
        let outcome = match snapshot
            .input_receipt
            .as_ref()
            .map(|receipt| receipt.outcome)
        {
            Some(CommandInputOutcome::Cancelled) => InputOutcome::Cancelled,
            Some(CommandInputOutcome::Partial | CommandInputOutcome::Failed) => {
                InputOutcome::Incomplete
            }
            _ => InputOutcome::Complete,
        };
        Ok(StdinResult::Observed {
            snapshot: Box::new(snapshot),
            target_receipt: input.task_id,
            requested_body_bytes,
            outcome,
        })
    }
}
