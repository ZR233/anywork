//! Session-scoped tools whose instances and cancellation follow their owning Thread.
use crate::tool_error;

use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use schemars::JsonSchema;
use serde::Deserialize;
use std::time::Duration;

/// An independently scheduled timer, subject to the same session task lifecycle.
#[derive(Debug, Default)]
pub struct SleepTool;

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SleepInput {
    /// Delay in milliseconds before publishing task completion.
    #[schemars(range(min = 1, max = 86400000))]
    pub duration_ms: u64,
}

impl SleepTool {
    pub fn declaration() -> pl_agent_tool::ToolDefinition {
        sleep_tool_definition()
    }
}
impl pl_agent_tool::typed::TypedTool for SleepTool {
    const NAME: &'static str = SLEEP_TOOL_NAME;
    const DESCRIPTION: &'static str = SLEEP_TOOL_DESCRIPTION;
    type Args = SleepInput;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    async fn execute(
        &self,
        input: Self::Args,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if !(1..=86_400_000).contains(&input.duration_ms) {
            return Err(ToolError::new(tool_error(
                "sleep",
                "durationMs must be between 1 and 86400000",
            )));
        }
        tokio::select! {
            biased;
            _ = context.cancellation.cancelled() => {
                return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
            }
            _ = tokio::time::sleep(Duration::from_millis(input.duration_ms)) => {},
        }
        Ok(ToolOutput::new(
            OpaquePayload::text("Timer elapsed."),
            vec![ContextContent::Text {
                text: "Timer elapsed.".into(),
            }],
        ))
    }
}

pub fn sleep_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        SLEEP_TOOL_NAME,
        SLEEP_TOOL_DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<SleepInput>(),
    )
    .expect("static tool definition")
}

const SLEEP_TOOL_NAME: &str = "sleep";
const SLEEP_TOOL_DESCRIPTION: &str = "Start a cancellable timer using the Thread task lifecycle. If it exceeds the one-second delivery window, use the returned taskId with wait alongside other tasks; any selected task or Thread message can wake wait first.";
