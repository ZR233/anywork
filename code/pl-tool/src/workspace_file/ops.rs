use crate::tool_error;
use pl_protocol::Result;
use serde_json::Value;

use pl_output::OutputTruncation;

use super::backend::*;
use super::patch::apply_patch_to_backend;
use super::schema::*;

#[derive(Debug, Clone, PartialEq)]
pub struct WorkspaceFileToolExecution {
    pub success: bool,
    pub output: String,
    pub model_output: String,
    pub exit_code: Option<i32>,
    pub truncated: OutputTruncation,
}

impl WorkspaceFileToolExecution {
    fn json(output: Value) -> Result<Self> {
        let output = serde_json::to_string(&output).map_err(|error| {
            tool_error(
                "workspace_file",
                format!("failed to encode output: {error}"),
            )
        })?;
        Ok(Self {
            success: true,
            model_output: pl_output::bounded_text(&output, 64 * 1024, 0).text,
            output,
            exit_code: Some(0),
            truncated: OutputTruncation::empty(),
        })
    }
}

/// 应用一段补丁原文，并把补丁工具的结构化结果编码成工具输出。
pub(super) async fn execute_workspace_patch_tool<B>(
    backend: &B,
    patch: &str,
) -> Result<WorkspaceFileToolExecution>
where
    B: WorkspaceFileBackend,
{
    let cwd = backend.default_cwd().await?;
    let output = apply_patch_to_backend(backend, cwd, patch).await?;
    let value = serde_json::to_value(output).map_err(|error| {
        tool_error(
            TOOL_APPLY_PATCH,
            format!("failed to encode apply_patch output: {error}"),
        )
    })?;
    WorkspaceFileToolExecution::json(value)
}
