use crate::tool_error;
use pl_protocol::Result;
use schemars::JsonSchema;
use serde::Deserialize;
use serde_json::{Value, json};

use crate::deserialize_tool_input;
use pl_output::OutputTruncation;

use super::backend::*;
use super::patch::apply_patch_to_backend;
use super::schema::*;

const DEFAULT_LIST_FILES_LIMIT: usize = 100;
const MAX_LIST_FILES_LIMIT: usize = 200;

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

pub async fn execute_workspace_file_tool<B>(
    backend: &B,
    name: &str,
    arguments: Value,
) -> Result<Option<WorkspaceFileToolExecution>>
where
    B: WorkspaceFileBackend,
{
    let Some(kind) = WorkspaceFileToolKind::from_name(name) else {
        return Ok(None);
    };
    let value = match kind {
        WorkspaceFileToolKind::ListFiles => list_files(backend, arguments).await?,
        WorkspaceFileToolKind::ApplyPatch => apply_patch(backend, arguments).await?,
    };
    Ok(Some(WorkspaceFileToolExecution::json(value)?))
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct ListFilesInput {
    /// Directory to list; defaults to the current working directory.
    path: Option<String>,
    #[serde(flatten)]
    working_directory: WorkingDirectoryInput,
    /// Optional file glob; omitted or blank uses `*`.
    glob: Option<String>,
    #[serde(flatten)]
    pagination: PaginationInput,
    /// Include directory entries in addition to files.
    include_dirs: Option<bool>,
}

async fn list_files<B>(backend: &B, arguments: Value) -> Result<Value>
where
    B: WorkspaceFileBackend,
{
    let input: ListFilesInput = deserialize_tool_input(TOOL_LIST_FILES, arguments)?;
    let path = path_or_current(input.path);
    let glob = input
        .glob
        .filter(|glob| !glob.trim().is_empty())
        .unwrap_or_else(|| "*".to_string());
    let include_dirs = input.include_dirs.unwrap_or(false);
    let limit = input.pagination.limit.unwrap_or(DEFAULT_LIST_FILES_LIMIT);
    if !(1..=MAX_LIST_FILES_LIMIT).contains(&limit) {
        return Err(tool_error(
            TOOL_LIST_FILES,
            format!("limit must be between 1 and {MAX_LIST_FILES_LIMIT}"),
        ));
    }
    let result = backend
        .list(WorkspaceFileListRequest {
            path: path.clone(),
            cwd: input.working_directory.cwd,
            glob: glob.clone(),
            max_files: limit,
            include_dirs,
            cursor: input.pagination.cursor,
        })
        .await?;
    let files = result.files;
    let next_cursor = result.next_cursor;
    let result_hash = pl_core::context::content_hash(serde_json::to_string(&files)?.as_bytes());
    Ok(json!({
        "path": path,
        "glob": glob,
        "includeDirs": include_dirs,
        "files": files,
        "count": files.len(),
        "nextCursor": next_cursor,
        "cursorReset": false,
        "resultHash": result_hash,
    }))
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct ApplyPatchInput {
    /// Complete Codex-style patch text.
    input: String,
    #[serde(flatten)]
    working_directory: WorkingDirectoryInput,
}

async fn apply_patch<B>(backend: &B, arguments: Value) -> Result<Value>
where
    B: WorkspaceFileBackend,
{
    let input: ApplyPatchInput = deserialize_tool_input(TOOL_APPLY_PATCH, arguments)?;
    let cwd = match input.working_directory.cwd {
        Some(cwd) => cwd,
        None => backend.default_cwd().await?,
    };
    let output = apply_patch_to_backend(backend, cwd, &input.input).await?;
    serde_json::to_value(output).map_err(|error| {
        tool_error(
            TOOL_APPLY_PATCH,
            format!("failed to encode apply_patch output: {error}"),
        )
    })
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
struct WorkingDirectoryInput {
    /// Optional working directory used to resolve relative paths.
    cwd: Option<String>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
struct PaginationInput {
    /// Maximum results in this page.
    #[schemars(range(min = 1, max = 200))]
    limit: Option<usize>,
    /// Exact nextCursor from the corresponding previous page; omit on the first page.
    cursor: Option<String>,
}

fn path_or_current(path: Option<String>) -> String {
    path.filter(|path| !path.trim().is_empty())
        .unwrap_or_else(|| ".".to_string())
}
