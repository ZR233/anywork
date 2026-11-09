//! Anywork policy/lease and output adaptation for the independent file tools.
use super::{helpers::*, input::*, path::WorkspacePaths};
use crate::{tool_error, workspace::ToolWorkspace};
use pl_agent_tool::typed::TypedTool;
use pl_core::tool::opaque::{CallContext, ToolError};
use pl_protocol::{PureError, Result};
use pl_tool_filesystem::{MutationBackend, MutationError};
use std::path::PathBuf;

pub(super) struct LocalMutationCapability {
    paths: WorkspacePaths,
    workspace: ToolWorkspace,
}

impl LocalMutationCapability {
    async fn check_destination(
        &self,
        path: &PathBuf,
        collision: PathCollision,
        tool: &str,
    ) -> Result<()> {
        if collision == PathCollision::FailIfExists && tokio::fs::try_exists(path).await? {
            return Err(tool_error(
                tool,
                MutationError::<PureError>::DestinationExists(path.display().to_string()),
            ));
        }
        Ok(())
    }
}

impl MutationBackend for LocalMutationCapability {
    type Error = PureError;
    type Path = PathBuf;

    async fn resolve_existing(&self, path: &str) -> Result<PathBuf> {
        self.paths.resolve_existing(path).await
    }
    async fn resolve_for_write(&self, path: &str) -> Result<PathBuf> {
        self.paths.resolve_for_write(path).await
    }
    fn ensure_writable(&self, path: &PathBuf) -> Result<()> {
        self.workspace.ensure_path_writable(path)
    }
    fn display_path(&self, path: &PathBuf) -> String {
        self.paths.display_relative(path)
    }
    fn diagnostic_path(&self, path: &PathBuf) -> String {
        path.display().to_string()
    }
    async fn is_directory(&self, path: &PathBuf) -> Result<bool> {
        Ok(tokio::fs::metadata(path).await?.is_dir())
    }
    async fn exists(&self, path: &PathBuf) -> Result<bool> {
        Ok(tokio::fs::try_exists(path).await?)
    }
    async fn create_directory(&self, path: &PathBuf) -> Result<()> {
        Ok(tokio::fs::create_dir_all(path).await?)
    }
    async fn remove_file(&self, path: &PathBuf) -> Result<()> {
        tokio::fs::remove_file(path).await?;
        self.workspace.notify_deleted(path).await;
        Ok(())
    }
    async fn remove_directory(&self, path: &PathBuf, recursive: bool) -> Result<()> {
        if recursive {
            crate::workspace::path_safety::remove_dir_all_no_follow_async(self.paths.root(), path)
                .await
                .map_err(|error| tool_error("delete_path", error))?;
        } else {
            tokio::fs::remove_dir(path).await?;
        }
        self.workspace.notify_deleted(path).await;
        Ok(())
    }
    async fn copy(&self, from: &PathBuf, to: &PathBuf, collision: PathCollision) -> Result<()> {
        if let Some(parent) = to.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        // This recheck is not atomic with the OS operation; it must not be
        // represented as cross-process no-clobber.
        self.check_destination(to, collision, "copy_path").await?;
        tokio::fs::copy(from, to).await?;
        self.workspace.notify_changed(to).await;
        Ok(())
    }
    async fn rename(&self, from: &PathBuf, to: &PathBuf, collision: PathCollision) -> Result<()> {
        if let Some(parent) = to.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        self.check_destination(to, collision, "move_path").await?;
        tokio::fs::rename(from, to).await?;
        self.workspace.notify_deleted(from).await;
        self.workspace.notify_changed(to).await;
        Ok(())
    }
}

fn mutation_error(tool: &str, error: MutationError<PureError>) -> PureError {
    match error {
        MutationError::Backend(error) => error,
        error => tool_error(tool, error),
    }
}

macro_rules! host_mutation {
    ($host:ident, $domain:path, $input:ty, $map:expr) => {
        #[derive(Debug, Clone)]
        pub struct $host {
            workspace: ToolWorkspace,
        }
        impl $host {
            pub fn new(workspace: ToolWorkspace) -> Self {
                Self { workspace }
            }
        }
        impl TypedTool for $host {
            const NAME: &'static str = <$domain as TypedTool>::NAME;
            const DESCRIPTION: &'static str = <$domain as TypedTool>::DESCRIPTION;
            type Args = $input;
            type Context = CallContext;
            type Output = pl_core::tool::ToolOutput;
            type Error = ToolError;
            async fn execute(
                &self,
                input: Self::Args,
                context: CallContext,
            ) -> std::result::Result<Self::Output, ToolError> {
                self.workspace
                    .ensure_workspace_writable()
                    .map_err(ToolError::new)?;
                let _guard = self.workspace.write_lock().await;
                let paths = workspace(&self.workspace, &context)
                    .await
                    .map_err(ToolError::new)?;
                let backend = LocalMutationCapability {
                    paths,
                    workspace: self.workspace.clone(),
                };
                let result = <$domain>::new()
                    .execute(input, backend)
                    .await
                    .map_err($map)
                    .map_err(ToolError::new)?;
                Ok(text_output(result))
            }
        }
    };
}
host_mutation!(
    CreateDirectoryTool,
    pl_tool_create_directory::CreateDirectoryTool<LocalMutationCapability>,
    PathInput,
    |error| error
);
host_mutation!(
    DeletePathTool,
    pl_tool_delete_path::DeletePathTool<LocalMutationCapability>,
    DeletePathInput,
    |error| mutation_error("delete_path", error)
);
host_mutation!(
    CopyPathTool,
    pl_tool_copy_path::CopyPathTool<LocalMutationCapability>,
    CopyMoveInput,
    |error| mutation_error("copy_path", error)
);
host_mutation!(
    MovePathTool,
    pl_tool_move_path::MovePathTool<LocalMutationCapability>,
    CopyMoveInput,
    |error| mutation_error("move_path", error)
);

pub fn create_directory_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_tool_create_directory::definition::<LocalMutationCapability>()
}
pub fn delete_path_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_tool_delete_path::definition::<LocalMutationCapability>()
}
pub fn copy_path_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_tool_copy_path::definition::<LocalMutationCapability>()
}
pub fn move_path_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_tool_move_path::definition::<LocalMutationCapability>()
}

#[cfg(test)]
#[path = "mutation_tests.rs"]
mod tests;
