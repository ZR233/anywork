//! Standalone stdin tool over an explicitly shared process-input capability.
mod definition;
mod input;
pub use definition::write_stdin_definition;
pub use input::{WriteStdinInput, parse_and_validate_stdin_input};

use crate::process::{
    CancellationToken, CommandInputOutcome, CommandOutputSnapshot, InputRequest, InputTarget,
    MAX_MODEL_BODY_BYTES, ProcessInput, input::ExecInputError,
};
use pl_agent_tool::{Tool, ToolDefinition};
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
        target_receipt: String,
        status: String,
    },
    Observed {
        snapshot: Box<CommandOutputSnapshot>,
        target_receipt: String,
        requested_body_bytes: usize,
        outcome: InputOutcome,
    },
}

impl StdinResult {
    pub fn result(&self, receipt: Option<&str>) -> pl_agent_tool::ToolResult<String> {
        match self {
            Self::Terminal {
                target_receipt,
                status,
            } => {
                let detail = "Target is terminal; historical stdin close state is unavailable. No input was sent and no process was started.";
                pl_agent_tool::ToolResult::from_data(
                    serde_json::json!({
                        "taskId": receipt,
                        "targetTaskId": target_receipt,
                        "status": status,
                        "inputReceipt": {"acceptedBytes": 0, "outcome": "notSent", "detail": detail},
                    }),
                    vec![detail.into()],
                )
            }
            Self::Observed {
                snapshot,
                target_receipt,
                ..
            } => {
                let data = serde_json::json!({
                    "taskId": receipt,
                    "targetTaskId": target_receipt,
                    "inputReceipt": snapshot.input_receipt,
                });
                pl_agent_tool::ToolResult::from_data(data.clone(), vec![data.to_string()])
            }
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
                return Ok(StdinResult::Terminal {
                    target_receipt: input.task_id,
                    status,
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
