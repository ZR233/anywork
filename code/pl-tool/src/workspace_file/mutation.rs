//! Target-independent policy adaptation for the independent filesystem tools.
use crate::workspace_file::{ExecutorWorkspaceFileBackend, WorkspaceFileBackend};
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
pub struct WorkspaceMutationTool {
    definition: pl_agent_tool::ToolDefinition,
    kind: WorkspaceMutationKind,
    backend: Arc<ExecutorWorkspaceFileBackend>,
    workspace: ToolWorkspace,
}

#[derive(Debug, Clone, Copy)]
pub enum WorkspaceMutationKind {
    CreateDirectory,
    Delete,
    Copy,
    Move,
}

impl WorkspaceMutationKind {
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
        match self {
            Self::CreateDirectory => {
                pl_tool_filesystem::create_directory::definition::<ExecutorMutationCapability>()
            }
            Self::Delete => {
                pl_tool_filesystem::delete_path::definition::<ExecutorMutationCapability>()
            }
            Self::Copy => pl_tool_filesystem::copy_path::definition::<ExecutorMutationCapability>(),
            Self::Move => pl_tool_filesystem::move_path::definition::<ExecutorMutationCapability>(),
        }
    }
}

impl WorkspaceMutationTool {
    pub fn new(
        kind: WorkspaceMutationKind,
        definition: pl_agent_tool::ToolDefinition,
        backend: Arc<ExecutorWorkspaceFileBackend>,
        workspace: ToolWorkspace,
    ) -> Self {
        Self {
            definition,
            kind,
            backend: Arc::new(backend.as_ref().clone().with_workspace(workspace.clone())),
            workspace,
        }
    }
}

impl pl_agent_tool::Tool for WorkspaceMutationTool {
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
        let _guard = tokio::select! {
            biased;
            _ = context.cancellation.cancelled() => return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled)),
            guard = self.workspace.write_lock() => guard,
        };
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let granted = self.backend.for_grant(&context.grant);
        let backend = ExecutorMutationCapability {
            backend: granted
                .map(Arc::new)
                .unwrap_or_else(|| self.backend.clone()),
            workspace: self.workspace.clone(),
            tool: self.kind.name(),
        };
        let text = match self.kind {
            WorkspaceMutationKind::CreateDirectory => {
                pl_tool_filesystem::create_directory::CreateDirectoryTool::new()
                    .execute(
                        decode_json(input.content()).map_err(ToolError::new)?,
                        backend,
                    )
                    .await
                    .map_err(ToolError::new)?
            }
            WorkspaceMutationKind::Delete => pl_tool_filesystem::delete_path::DeletePathTool::new()
                .execute(
                    decode_json(input.content()).map_err(ToolError::new)?,
                    backend,
                )
                .await
                .map_err(|error| mutation_error(self.kind.name(), error))?,
            WorkspaceMutationKind::Copy => pl_tool_filesystem::copy_path::CopyPathTool::new()
                .execute(
                    decode_json(input.content()).map_err(ToolError::new)?,
                    backend,
                )
                .await
                .map_err(|error| mutation_error(self.kind.name(), error))?,
            WorkspaceMutationKind::Move => pl_tool_filesystem::move_path::MovePathTool::new()
                .execute(
                    decode_json(input.content()).map_err(ToolError::new)?,
                    backend,
                )
                .await
                .map_err(|error| mutation_error(self.kind.name(), error))?,
        };
        Ok(ToolOutput::new(
            OpaquePayload::text(text.clone()),
            vec![ContextContent::Text { text: text.into() }],
        ))
    }
}

fn mutation_error(tool: &str, error: MutationError<PureError>) -> ToolError {
    ToolError::new(match error {
        MutationError::Backend(error) => error,
        MutationError::RequiresDirectory => tool_error(tool, "delete mode requires a directory"),
        MutationError::DestinationExists(_) => tool_error(tool, "destination already exists"),
        error => tool_error(tool, error),
    })
}

struct ExecutorMutationCapability {
    backend: Arc<ExecutorWorkspaceFileBackend>,
    workspace: ToolWorkspace,
    tool: &'static str,
}

impl ExecutorMutationCapability {
    async fn stat(&self, path: &str) -> Result<Option<crate::workspace_file::WorkspaceFileStat>> {
        self.backend
            .inspect_path(path.to_string(), None)
            .await
            .map_err(crate::workspace_file::file_error)
    }
}
impl MutationBackend for ExecutorMutationCapability {
    type Error = PureError;
    type Path = String;
    async fn resolve_existing(&self, path: &str) -> Result<String> {
        if self.tool == "delete_path" || self.tool == "move_path" {
            let target = self
                .backend
                .path_request(path.into(), None)
                .map_err(crate::workspace_file::file_error)?;
            let target = self
                .backend
                .bound(target, true)
                .await
                .map_err(crate::workspace_file::file_error)?;
            self.backend.ensure_writable(&target).await?;
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
        let target = self
            .backend
            .path_request(path.into(), None)
            .map_err(crate::workspace_file::file_error)?;
        let target = self
            .backend
            .bound(target, true)
            .await
            .map_err(crate::workspace_file::file_error)?;
        self.backend.ensure_writable(&target).await?;
        Ok(path.to_string())
    }
    fn ensure_writable(&self, _path: &String) -> Result<()> {
        self.workspace.ensure_workspace_writable()
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
            .map_err(crate::workspace_file::file_error)
    }
    async fn remove_directory(&self, path: &String, recursive: bool) -> Result<()> {
        self.backend
            .remove_path(path.clone(), None, recursive)
            .await
            .map_err(crate::workspace_file::file_error)
    }
    async fn copy(&self, from: &String, to: &String, collision: PathCollision) -> Result<()> {
        let recursive = self.is_directory(from).await?;
        self.backend
            .copy_path(from.clone(), to.clone(), None, recursive, collision)
            .await
    }
    async fn rename(&self, from: &String, to: &String, collision: PathCollision) -> Result<()> {
        self.backend
            .rename_path(from.clone(), to.clone(), None, collision)
            .await
    }
}

#[cfg(test)]
#[path = "mutation_tests.rs"]
mod tests;
