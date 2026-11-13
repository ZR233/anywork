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
    pub failure: Option<pl_patch::PatchFailure>,
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
            failure: None,
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
    let output = match apply_patch_to_backend(backend, cwd.clone(), patch).await {
        Ok(output) => output,
        Err(failure) => {
            let mut value = serde_json::to_value(&failure)
                .map_err(|error| tool_error(TOOL_APPLY_PATCH, error))?;
            value["cwd"] = cwd.into();
            let mut result = WorkspaceFileToolExecution::json(value)?;
            result.failure = Some(failure);
            result.success = false;
            result.exit_code = Some(1);
            return Ok(result);
        }
    };
    let value = serde_json::to_value(output).map_err(|error| {
        tool_error(
            TOOL_APPLY_PATCH,
            format!("failed to encode apply_patch output: {error}"),
        )
    })?;
    WorkspaceFileToolExecution::json(value)
}
