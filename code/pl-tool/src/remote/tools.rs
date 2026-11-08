use std::sync::Arc;

use crate::tool_error;
use pl_protocol::Result;

use crate::file::{CopyMoveInput, DeleteMode, DeletePathInput, PathCollision, PathInput};
use crate::workspace::ToolWorkspace;
use pl_agent_tool::typed::{decode_json, input_schema_for};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};

use super::RemoteWorkspaceFileBackend;

#[derive(Debug, Clone)]
pub struct RemoteWorkspaceMutationTool {
    definition: pl_agent_tool::ToolDefinition,
    kind: RemoteMutationKind,
    backend: Arc<RemoteWorkspaceFileBackend>,
    workspace: ToolWorkspace,
}

impl RemoteWorkspaceMutationTool {
    fn name(&self) -> &str {
        self.kind.name()
    }
}

#[derive(Debug, Clone, Copy)]
pub enum RemoteMutationKind {
    CreateDirectory,
    Delete,
    Copy,
    Move,
}

impl RemoteMutationKind {
    pub fn definition(self) -> pl_agent_tool::ToolDefinition {
        pl_agent_tool::ToolDefinition::json(self.name(), self.description(), self.schema())
            .expect("static mutation definition")
    }

    pub fn all() -> &'static [Self] {
        &[Self::CreateDirectory, Self::Delete, Self::Copy, Self::Move]
    }

    fn name(self) -> &'static str {
        match self {
            Self::CreateDirectory => "create_directory",
            Self::Delete => "delete_path",
            Self::Copy => "copy_path",
            Self::Move => "move_path",
        }
    }

    fn description(self) -> &'static str {
        match self {
            Self::CreateDirectory => "Create a directory inside the workspace.",
            Self::Delete => {
                "Delete a workspace file, empty directory, or recursive directory using an explicit mode."
            }
            Self::Copy => "Copy a file inside the workspace.",
            Self::Move => "Move or rename a file or directory inside the workspace.",
        }
    }

    fn schema(self) -> serde_json::Value {
        match self {
            Self::CreateDirectory => input_schema_for::<PathInput>(),
            Self::Delete => input_schema_for::<DeletePathInput>(),
            Self::Copy | Self::Move => input_schema_for::<CopyMoveInput>(),
        }
    }
}

impl RemoteWorkspaceMutationTool {
    pub fn new(
        kind: RemoteMutationKind,
        definition: pl_agent_tool::ToolDefinition,
        backend: Arc<RemoteWorkspaceFileBackend>,
        workspace: ToolWorkspace,
    ) -> Self {
        Self {
            definition,
            kind,
            backend,
            workspace,
        }
    }
    async fn execute_input(&self, input: &str) -> std::result::Result<ToolOutput, ToolError> {
        self.workspace
            .ensure_workspace_writable()
            .map_err(ToolError::new)?;
        let _guard = self.workspace.write_lock().await;

        let text = match self.kind {
            RemoteMutationKind::CreateDirectory => self
                .create_directory(decode_json(input).map_err(ToolError::new)?)
                .await
                .map_err(ToolError::new)?,
            RemoteMutationKind::Delete => self
                .delete(decode_json(input).map_err(ToolError::new)?)
                .await
                .map_err(ToolError::new)?,
            RemoteMutationKind::Copy => self
                .copy_or_move(decode_json(input).map_err(ToolError::new)?, false)
                .await
                .map_err(ToolError::new)?,
            RemoteMutationKind::Move => self
                .copy_or_move(decode_json(input).map_err(ToolError::new)?, true)
                .await
                .map_err(ToolError::new)?,
        };
        Ok(text_result(text))
    }
}
impl pl_agent_tool::Tool for RemoteWorkspaceMutationTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> std::result::Result<ToolOutput, ToolError> {
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let input = input.content();
        self.execute_input(input).await
    }
}

impl RemoteWorkspaceMutationTool {
    async fn create_directory(&self, input: PathInput) -> Result<String> {
        self.workspace
            .ensure_relative_path_writable(None, &input.path)?;
        self.backend
            .create_directory(input.path.clone(), None)
            .await?;
        Ok(format!("Created directory {}", input.path))
    }

    async fn delete(&self, input: DeletePathInput) -> Result<String> {
        self.workspace
            .ensure_relative_path_writable(None, &input.path)?;
        let stat = self
            .backend
            .stat_optional(input.path.clone(), None)
            .await
            .map_err(super::workspace::remote_file_error)?
            .ok_or_else(|| tool_error(self.name(), "path does not exist"))?;
        match (stat.is_dir, input.mode) {
            (false, DeleteMode::File)
            | (true, DeleteMode::EmptyDirectory)
            | (true, DeleteMode::RecursiveDirectory) => {}
            (false, DeleteMode::EmptyDirectory | DeleteMode::RecursiveDirectory) => {
                return Err(tool_error(self.name(), "delete mode requires a directory"));
            }
            (true, DeleteMode::File) => {
                return Err(tool_error(
                    self.name(),
                    "delete mode file cannot delete a directory",
                ));
            }
        }
        self.backend
            .remove_path(
                input.path.clone(),
                None,
                matches!(input.mode, DeleteMode::RecursiveDirectory),
            )
            .await
            .map_err(super::workspace::remote_file_error)?;
        Ok(format!("Deleted {}", input.path))
    }

    async fn copy_or_move(&self, input: CopyMoveInput, moving: bool) -> Result<String> {
        if moving {
            self.workspace
                .ensure_relative_path_writable(None, &input.from)?;
        }
        self.workspace
            .ensure_relative_path_writable(None, &input.to)?;
        let source = self
            .backend
            .stat_optional(input.from.clone(), None)
            .await
            .map_err(super::workspace::remote_file_error)?
            .ok_or_else(|| tool_error(self.name(), "source does not exist"))?;
        if let Some(target) = self
            .backend
            .stat_optional(input.to.clone(), None)
            .await
            .map_err(super::workspace::remote_file_error)?
        {
            if matches!(input.collision, PathCollision::FailIfExists) {
                return Err(tool_error(self.name(), "destination already exists"));
            }
            self.backend
                .remove_path(input.to.clone(), None, target.is_dir)
                .await
                .map_err(super::workspace::remote_file_error)?;
        }
        if moving {
            self.backend
                .rename_path(input.from.clone(), input.to.clone(), None)
                .await?;
            Ok(format!("Moved {} to {}", input.from, input.to))
        } else {
            self.backend
                .copy_path(input.from.clone(), input.to.clone(), None, source.is_dir)
                .await?;
            Ok(format!("Copied {} to {}", input.from, input.to))
        }
    }
}

fn text_result(text: String) -> ToolOutput {
    ToolOutput::new(
        OpaquePayload::text(text.clone()),
        vec![ContextContent::Text { text: text.into() }],
    )
}
