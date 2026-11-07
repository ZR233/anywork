//! Path metadata projection shared by local and remote Thread tools.
use super::{WorkspaceFileBackend, WorkspaceFileStatRequest};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use std::sync::Arc;

/// A Thread-owned metadata reader with frozen backend access authority.
#[derive(Debug)]
pub struct ThreadStatPathTool<B> {
    backend: Arc<B>,
}

impl<B: WorkspaceFileBackend + 'static> ThreadStatPathTool<B> {
    /// Binds the operation to the host-selected workspace lease.
    pub fn new(backend: Arc<B>) -> Self {
        Self { backend }
    }
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct Receipt {
    path: String,
    exists: bool,
    #[serde(rename = "type", skip_serializing_if = "Option::is_none")]
    kind: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    len: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    readonly: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    modified_at: Option<i64>,
}

impl<B: WorkspaceFileBackend + 'static> pl_agent_tool::typed::TypedTool for ThreadStatPathTool<B> {
    const NAME: &'static str = THREAD_STAT_PATH_TOOL_NAME;
    const DESCRIPTION: &'static str = THREAD_STAT_PATH_TOOL_DESCRIPTION;
    type Args = crate::file::PathInput;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    async fn execute(
        &self,
        input: Self::Args,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }

        let granted = self.backend.for_grant(&context.grant);
        let backend = granted.as_ref().unwrap_or(self.backend.as_ref());
        let stat = backend
            .stat_optional(WorkspaceFileStatRequest {
                path: input.path.clone(),
                cwd: None,
            })
            .await
            .map_err(ToolError::new)?;
        let receipt = match stat {
            Some(stat) => Receipt {
                path: stat.path,
                exists: true,
                kind: Some(if stat.is_file {
                    "file"
                } else if stat.is_dir {
                    "directory"
                } else {
                    "other"
                }),
                len: stat.len,
                readonly: stat.readonly,
                modified_at: stat.modified_at,
            },
            None => Receipt {
                path: input.path,
                exists: false,
                kind: None,
                len: None,
                readonly: None,
                modified_at: None,
            },
        };
        let content = serde_json::to_string(&receipt).map_err(ToolError::new)?;
        Ok(ToolOutput::new(
            OpaquePayload::new("pl.tool.path-stat", 1, content.clone()).map_err(ToolError::new)?,
            vec![ContextContent::Text {
                text: content.into(),
            }],
        ))
    }
}

pub fn thread_stat_path_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        THREAD_STAT_PATH_TOOL_NAME,
        THREAD_STAT_PATH_TOOL_DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<crate::file::PathInput>(),
    )
    .expect("static tool definition")
}

const THREAD_STAT_PATH_TOOL_NAME: &str = "stat_path";
const THREAD_STAT_PATH_TOOL_DESCRIPTION: &str =
    "Return metadata for a workspace path, or exists: false when the path is absent.";
