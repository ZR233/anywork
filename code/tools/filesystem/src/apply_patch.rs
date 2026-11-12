//! Raw Codex patches, using `pl-patch` as the sole grammar and algorithm.
use pl_patch::{PatchBackend, PatchFailure, PatchOutput, PatchReport};
use std::marker::PhantomData;

pub const NAME: &str = "apply_patch";
pub const DESCRIPTION: &str = "The `apply_patch` tool can be used to edit files. This is a FREEFORM tool, so do not wrap the patch in JSON. The input is a complete Codex-style patch beginning with *** Begin Patch and ending with *** End Patch; each file operation uses one of *** Add File: <path>, *** Delete File: <path>, or *** Update File: <path> (optionally followed by *** Move to: <path>). Do not use ---/+++ unified diff, *** File: metadata, or natural-language edit instructions such as Insert after. Update hunk lines start with a control prefix: space for context, `-` for deletion, `+` for addition; preserve a leading `-` or `+` in the file content after that prefix. If a previous patch failed, read the target file again and retry with a smaller patch based on current content.";

pub fn definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::grammar(
        NAME,
        DESCRIPTION,
        "lark",
        pl_patch::APPLY_PATCH_LARK_GRAMMAR,
    )
    .expect("static patch definition")
}

/// Executes one patch at its physical target and returns ordered, structured facts.
/// This capability does not expose transport, workspace grants or file contents.
pub trait PatchExecutor: Send + Sync {
    fn execute_patch(
        &self,
        cwd: String,
        patch: &str,
    ) -> impl Future<Output = Result<PatchReport, PatchFailure>> + Send;
}
impl<B: PatchBackend + Send + Sync> PatchExecutor for B {
    async fn execute_patch(&self, _cwd: String, patch: &str) -> Result<PatchReport, PatchFailure> {
        pl_patch::apply_patch(patch, self)
            .await
            .map(|outcome| outcome.report(self))
            .map_err(|error| {
                error.failure().cloned().unwrap_or_else(|| PatchFailure {
                    diagnostic: error.to_string(),
                    applied_changes: Vec::new(),
                    changes_may_be_incomplete: false,
                })
            })
    }
}

pub struct PatchContext<B> {
    pub backend: B,
    pub cwd: String,
}

pub struct ApplyPatchTool<B> {
    definition: pl_agent_tool::ToolDefinition,
    backend: PhantomData<fn() -> B>,
}
impl<B> Default for ApplyPatchTool<B> {
    fn default() -> Self {
        Self {
            definition: definition(),
            backend: PhantomData,
        }
    }
}

impl<B: PatchExecutor + 'static> pl_agent_tool::Tool for ApplyPatchTool<B> {
    type Input = String;
    type Context = PatchContext<B>;
    type Output = PatchOutput;
    type Error = PatchFailure;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        patch: String,
        context: Self::Context,
    ) -> Result<PatchOutput, PatchFailure> {
        apply_patch(&context.backend, context.cwd, &patch).await
    }
}

/// Applies once, preserving `pl-patch`'s ordered partial-failure diagnostics.
pub async fn apply_patch<B: PatchExecutor>(
    backend: &B,
    cwd: String,
    patch: &str,
) -> Result<PatchOutput, PatchFailure> {
    let report = backend.execute_patch(cwd.clone(), patch).await?;
    Ok(report.into_output(cwd))
}
