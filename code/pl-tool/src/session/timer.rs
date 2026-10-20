//! Session-scoped tools whose instances and cancellation follow their owning Thread.
use crate::tool_error;

use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, Tool, ToolError},
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
    pub fn declaration() -> pl_protocol::ToolSpec {
        pl_protocol::ToolSpec::function(
            "sleep",
            "Start a cancellable timer using the Thread task lifecycle. If it exceeds the one-second delivery window, use the returned taskId with wait alongside other tasks; any selected task or Thread message can wake wait first.",
            schemars::schema_for!(SleepInput).to_value(),
        )
    }
}
impl Tool for SleepTool {
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let input: SleepInput = serde_json::from_str(input.content()).map_err(ToolError::new)?;
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
