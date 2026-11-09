//! Standalone exec declaration, strict input validation and process orchestration.
mod definition;
mod input;
mod output;
pub use crate::process::input::ExecInputError;
pub use definition::exec_definition;
pub use input::{ExecInput, ValidatedExecInput, parse_and_validate_exec_input};
pub use output::ExecOutcome;

use crate::process::{
    CancellationToken, CommandOutputSnapshot, MAX_MODEL_BODY_BYTES, ProcessExecutor, ProcessRequest,
};
use pl_agent_tool::{Tool, ToolDefinition};
use std::{marker::PhantomData, time::Duration};

const DEFAULT_TIMEOUT_SECS: u64 = 60;

/// Frozen access decision plus the capability for this invocation's process owner.
pub struct ExecContext<P> {
    pub process: P,
    pub allow_workspace_escape: bool,
    pub cancellation: CancellationToken,
}

#[derive(Debug)]
pub struct ExecResult {
    pub snapshot: CommandOutputSnapshot,
    pub requested_body_bytes: usize,
}

#[derive(Debug, thiserror::Error)]
pub enum ExecError<E: std::error::Error + 'static> {
    #[error(transparent)]
    InvalidInput(#[from] ExecInputError),
    #[error(transparent)]
    Process(E),
}

#[derive(Debug)]
pub struct ExecTool<P> {
    definition: ToolDefinition,
    process: PhantomData<fn() -> P>,
}

impl<P> ExecTool<P> {
    /// The host passes its already-prepared declaration; no schema is rebuilt.
    pub fn new(definition: ToolDefinition) -> Self {
        Self {
            definition,
            process: PhantomData,
        }
    }
}

impl<P: ProcessExecutor> Tool for ExecTool<P> {
    type Input = String;
    type Context = ExecContext<P>;
    type Output = ExecResult;
    type Error = ExecError<P::Error>;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        raw: String,
        context: ExecContext<P>,
    ) -> Result<ExecResult, Self::Error> {
        let input = parse_and_validate_exec_input(&raw)?.into_input();
        let requested_body_bytes = input.max_output_chars.unwrap_or(MAX_MODEL_BODY_BYTES);
        let snapshot = context
            .process
            .run(ProcessRequest {
                command: input.command,
                cwd: input.cwd,
                timeout: Duration::from_secs(input.timeout_seconds.unwrap_or(DEFAULT_TIMEOUT_SECS)),
                max_output_bytes: requested_body_bytes.min(MAX_MODEL_BODY_BYTES),
                allow_workspace_escape: context.allow_workspace_escape,
                cancellation: context.cancellation,
            })
            .await
            .map_err(ExecError::Process)?;
        Ok(ExecResult {
            snapshot,
            requested_body_bytes,
        })
    }
}
