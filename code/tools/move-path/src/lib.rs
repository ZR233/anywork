//! Move with explicit destination collision behavior.
use pl_agent_tool::typed::TypedTool;
pub use pl_tool_filesystem::{CopyMoveInput, MutationBackend, MutationError, PathCollision};
use std::marker::PhantomData;

#[derive(Debug, Default)]
pub struct MovePathTool<B>(PhantomData<fn() -> B>);
impl<B> MovePathTool<B> {
    pub fn new() -> Self {
        Self(PhantomData)
    }
}
impl<B: MutationBackend + 'static> TypedTool for MovePathTool<B> {
    const NAME: &'static str = "move_path";
    const DESCRIPTION: &'static str =
        "Move a workspace file or directory with explicit destination collision behavior.";
    type Args = CopyMoveInput;
    type Context = B;
    type Output = String;
    type Error = MutationError<B::Error>;

    async fn execute(&self, input: Self::Args, backend: B) -> Result<String, Self::Error> {
        let from = backend
            .resolve_existing(&input.from)
            .await
            .map_err(MutationError::Backend)?;
        let to = backend
            .resolve_for_write(&input.to)
            .await
            .map_err(MutationError::Backend)?;
        backend
            .ensure_writable(&from)
            .map_err(MutationError::Backend)?;
        backend
            .ensure_writable(&to)
            .map_err(MutationError::Backend)?;
        if input.collision == PathCollision::FailIfExists
            && backend.exists(&to).await.map_err(MutationError::Backend)?
        {
            return Err(MutationError::DestinationExists(
                backend.diagnostic_path(&to),
            ));
        }
        backend
            .rename(&from, &to, input.collision)
            .await
            .map_err(MutationError::Backend)?;
        Ok(format!(
            "Moved {} to {}",
            backend.display_path(&from),
            backend.display_path(&to)
        ))
    }
}
pub fn definition<B: MutationBackend + 'static>() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::typed::prepare_json::<MovePathTool<B>>()
        .expect("static file tool definition")
        .definition()
        .clone()
}
