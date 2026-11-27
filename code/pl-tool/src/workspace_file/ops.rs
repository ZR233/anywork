use crate::tool_error;
use pl_protocol::Result;
use serde_json::Value;

use super::backend::*;
use super::patch::apply_patch_to_backend;
use super::schema::*;

#[derive(Debug, Clone, PartialEq)]
pub(super) struct WorkspacePatchResult {
    pub failure: Option<pl_patch::PatchFailure>,
    pub data: Value,
    pub model_output: String,
}

impl WorkspacePatchResult {
    fn new(data: Value, failure: Option<pl_patch::PatchFailure>) -> Self {
        Self {
            failure,
            model_output: pl_output::bounded_text(&data.to_string(), 64 * 1024, 0).text,
            data,
        }
    }
}

/// 应用一段补丁原文，并把补丁工具的结构化结果编码成工具输出。
pub(super) async fn execute_workspace_patch_tool<B>(
    backend: &B,
    patch: &str,
) -> Result<WorkspacePatchResult>
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
            return Ok(WorkspacePatchResult::new(value, Some(failure)));
        }
    };
    let value = serde_json::to_value(output).map_err(|error| {
        tool_error(
            TOOL_APPLY_PATCH,
            format!("failed to encode apply_patch output: {error}"),
        )
    })?;
    Ok(WorkspacePatchResult::new(value, None))
}
