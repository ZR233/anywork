//! SSH transport/policy adaptation for the same independent filesystem tools.
use super::RemoteWorkspaceFileBackend;
use crate::{tool_error, workspace::ToolWorkspace};
use pl_agent_tool::typed::{TypedTool, decode_json};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use pl_protocol::{PureError, Result};
use pl_tool_filesystem::{MutationBackend, MutationError, PathCollision};
use std::sync::Arc;

#[derive(Debug, Clone)]
pub struct RemoteWorkspaceMutationTool {
    definition: pl_agent_tool::ToolDefinition,
    kind: RemoteMutationKind,
    backend: Arc<RemoteWorkspaceFileBackend>,
    workspace: ToolWorkspace,
}

#[derive(Debug, Clone, Copy)]
pub enum RemoteMutationKind {
    CreateDirectory,
    Delete,
    Copy,
    Move,
}

impl RemoteMutationKind {
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
    pub fn definition(self) -> pl_agent_tool::ToolDefinition {
        let definition = match self {
            Self::CreateDirectory => {
                pl_tool_filesystem::create_directory::definition::<RemoteMutationCapability>()
            }
            Self::Delete => {
                pl_tool_filesystem::delete_path::definition::<RemoteMutationCapability>()
            }
            Self::Copy => pl_tool_filesystem::copy_path::definition::<RemoteMutationCapability>(),
            Self::Move => pl_tool_filesystem::move_path::definition::<RemoteMutationCapability>(),
        };
        // Retain transport-specific model guidance; the domain owns the schema.
        let description = match self {
            Self::CreateDirectory => "Create a directory inside the workspace.",
            Self::Delete => {
                "Delete a workspace file, empty directory, or recursive directory using an explicit mode."
            }
            Self::Copy => "Copy a file inside the workspace.",
            Self::Move => "Move or rename a file or directory inside the workspace.",
        };
        let pl_agent_tool::InputFormat::JsonSchema(schema) = definition.input() else {
            unreachable!("file mutations have JSON input");
        };
        pl_agent_tool::ToolDefinition::json(definition.name(), description, schema.clone())
            .expect("static file mutation definition")
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
}

impl pl_agent_tool::Tool for RemoteWorkspaceMutationTool {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;
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
        self.workspace
            .ensure_workspace_writable()
            .map_err(ToolError::new)?;
        let _guard = self.workspace.write_lock().await;
        let backend = RemoteMutationCapability {
            backend: self.backend.clone(),
            workspace: self.workspace.clone(),
            tool: self.kind.name(),
        };
        let text = match self.kind {
            RemoteMutationKind::CreateDirectory => {
                pl_tool_filesystem::create_directory::CreateDirectoryTool::new()
                    .execute(
                        decode_json(input.content()).map_err(ToolError::new)?,
                        backend,
                    )
                    .await
                    .map_err(ToolError::new)?
            }
            RemoteMutationKind::Delete => pl_tool_filesystem::delete_path::DeletePathTool::new()
                .execute(
                    decode_json(input.content()).map_err(ToolError::new)?,
                    backend,
                )
                .await
                .map_err(|error| remote_mutation_error(self.kind.name(), error))?,
            RemoteMutationKind::Copy => pl_tool_filesystem::copy_path::CopyPathTool::new()
                .execute(
                    decode_json(input.content()).map_err(ToolError::new)?,
                    backend,
                )
                .await
                .map_err(|error| remote_mutation_error(self.kind.name(), error))?,
            RemoteMutationKind::Move => pl_tool_filesystem::move_path::MovePathTool::new()
                .execute(
                    decode_json(input.content()).map_err(ToolError::new)?,
                    backend,
                )
                .await
                .map_err(|error| remote_mutation_error(self.kind.name(), error))?,
        };
        Ok(ToolOutput::new(
            OpaquePayload::text(text.clone()),
            vec![ContextContent::Text { text: text.into() }],
        ))
    }
}

fn remote_mutation_error(tool: &str, error: MutationError<PureError>) -> ToolError {
    ToolError::new(match error {
        MutationError::Backend(error) => error,
        MutationError::RequiresDirectory => tool_error(tool, "delete mode requires a directory"),
        MutationError::DestinationExists(_) => tool_error(tool, "destination already exists"),
        error => tool_error(tool, error),
    })
}

struct RemoteMutationCapability {
    backend: Arc<RemoteWorkspaceFileBackend>,
    workspace: ToolWorkspace,
    tool: &'static str,
}

impl RemoteMutationCapability {
    async fn stat(&self, path: &str) -> Result<Option<crate::workspace_file::WorkspaceFileStat>> {
        self.backend
            .stat_optional(path.to_string(), None)
            .await
            .map_err(super::workspace::remote_file_error)
    }
    async fn replace_destination(&self, path: &str) -> Result<()> {
        if let Some(target) = self.stat(path).await? {
            self.backend
                .remove_path(path.to_string(), None, target.is_dir)
                .await
                .map_err(super::workspace::remote_file_error)?;
        }
        Ok(())
    }
    async fn prepare_destination(&self, path: &str, collision: PathCollision) -> Result<()> {
        match collision {
            PathCollision::FailIfExists => {
                if self.stat(path).await?.is_some() {
                    return Err(tool_error(self.tool, "destination already exists"));
                }
                Ok(())
            }
            PathCollision::Overwrite => self.replace_destination(path).await,
        }
    }
}
impl MutationBackend for RemoteMutationCapability {
    type Error = PureError;
    type Path = String;
    async fn resolve_existing(&self, path: &str) -> Result<String> {
        if self.tool == "delete_path" || self.tool == "move_path" {
            self.workspace.ensure_relative_path_writable(None, path)?;
        }
        self.stat(path).await?.ok_or_else(|| {
            tool_error(
                self.tool,
                if self.tool == "delete_path" {
                    "path does not exist"
                } else {
                    "source does not exist"
                },
            )
        })?;
        Ok(path.to_string())
    }
    async fn resolve_for_write(&self, path: &str) -> Result<String> {
        self.workspace.ensure_relative_path_writable(None, path)?;
        Ok(path.to_string())
    }
    fn ensure_writable(&self, path: &String) -> Result<()> {
        self.workspace.ensure_relative_path_writable(None, path)
    }
    fn display_path(&self, path: &String) -> String {
        path.clone()
    }
    fn diagnostic_path(&self, path: &String) -> String {
        path.clone()
    }
    async fn is_directory(&self, path: &String) -> Result<bool> {
        self.stat(path)
            .await?
            .map(|stat| stat.is_dir)
            .ok_or_else(|| tool_error(self.tool, "path does not exist"))
    }
    async fn exists(&self, path: &String) -> Result<bool> {
        Ok(self.stat(path).await?.is_some())
    }
    async fn create_directory(&self, path: &String) -> Result<()> {
        self.backend.create_directory(path.clone(), None).await
    }
    async fn remove_file(&self, path: &String) -> Result<()> {
        self.backend
            .remove_path(path.clone(), None, false)
            .await
            .map_err(super::workspace::remote_file_error)
    }
    async fn remove_directory(&self, path: &String, recursive: bool) -> Result<()> {
        self.backend
            .remove_path(path.clone(), None, recursive)
            .await
            .map_err(super::workspace::remote_file_error)
    }
    async fn copy(&self, from: &String, to: &String, collision: PathCollision) -> Result<()> {
        let recursive = self.is_directory(from).await?;
        // The helper's copy/rename protocol has no atomic no-clobber flag:
        // recheck here, never delete for FailIfExists, and retain that known
        // check-to-operation race rather than claim exclusion across clients.
        self.prepare_destination(to, collision).await?;
        self.backend
            .copy_path(from.clone(), to.clone(), None, recursive)
            .await
    }
    async fn rename(&self, from: &String, to: &String, collision: PathCollision) -> Result<()> {
        self.prepare_destination(to, collision).await?;
        self.backend
            .rename_path(from.clone(), to.clone(), None)
            .await
    }
}

#[cfg(test)]
#[path = "tools_tests.rs"]
mod tests;
