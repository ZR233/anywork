//! Directory creation over a host-authorized filesystem.
pub use crate::{MutationBackend, PathInput};
use pl_agent_tool::typed::TypedTool;
use std::marker::PhantomData;

#[derive(Debug, Default)]
pub struct CreateDirectoryTool<B>(PhantomData<fn() -> B>);
impl<B> CreateDirectoryTool<B> {
    pub fn new() -> Self {
        Self(PhantomData)
    }
}
impl<B: MutationBackend + 'static> TypedTool for CreateDirectoryTool<B> {
    const NAME: &'static str = "create_directory";
    const DESCRIPTION: &'static str = "Create a directory inside the workspace.";
    type Args = PathInput;
    type Context = B;
    type Output = String;
    type Error = B::Error;

    async fn execute(&self, input: PathInput, backend: B) -> Result<String, B::Error> {
        let path = backend.resolve_for_write(&input.path).await?;
        backend.ensure_writable(&path)?;
        backend.create_directory(&path).await?;
        Ok(format!("Created directory {}", backend.display_path(&path)))
    }
}
pub fn definition<B: MutationBackend + 'static>() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::typed::prepare_json::<CreateDirectoryTool<B>>()
        .expect("static file tool definition")
        .definition()
        .clone()
}
