//! Deletion with explicit file, empty-directory or recursive-directory intent.
pub use crate::{MutationBackend, MutationError};
use pl_agent_tool::typed::TypedTool;
use std::marker::PhantomData;

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DeletePathInput {
    /// Workspace-relative or permitted absolute path.
    pub path: String,
    /// Explicit file or directory deletion mode.
    pub mode: DeleteMode,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
pub enum DeleteMode {
    File,
    EmptyDirectory,
    RecursiveDirectory,
}

#[derive(Debug, Default)]
pub struct DeletePathTool<B>(PhantomData<fn() -> B>);
impl<B> DeletePathTool<B> {
    pub fn new() -> Self {
        Self(PhantomData)
    }
}
impl<B: MutationBackend + 'static> TypedTool for DeletePathTool<B> {
    const NAME: &'static str = "delete_path";
    const DESCRIPTION: &'static str = "Delete a file or directory using an explicit file, emptyDirectory, or recursiveDirectory mode.";
    type Args = DeletePathInput;
    type Context = B;
    type Output = String;
    type Error = MutationError<B::Error>;

    async fn execute(&self, input: Self::Args, backend: B) -> Result<String, Self::Error> {
        let path = backend
            .resolve_existing(&input.path)
            .await
            .map_err(MutationError::Backend)?;
        backend
            .ensure_writable(&path)
            .map_err(MutationError::Backend)?;
        match (
            backend
                .is_directory(&path)
                .await
                .map_err(MutationError::Backend)?,
            input.mode,
        ) {
            (false, DeleteMode::File) => backend.remove_file(&path).await,
            (false, _) => return Err(MutationError::RequiresDirectory),
            (true, DeleteMode::File) => return Err(MutationError::RequiresFile),
            (true, mode) => {
                backend
                    .remove_directory(&path, mode == DeleteMode::RecursiveDirectory)
                    .await
            }
        }
        .map_err(MutationError::Backend)?;
        Ok(format!("Deleted {}", backend.display_path(&path)))
    }
}
pub fn definition<B: MutationBackend + 'static>() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::typed::prepare_json::<DeletePathTool<B>>()
        .expect("static file tool definition")
        .definition()
        .clone()
}
