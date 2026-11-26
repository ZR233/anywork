//! Resource errors retain their underlying source across the product boundary.
use crate::agent::worktree::WorktreeError;
use crate::studio::session_data_error::SessionDataError;
use crate::thread_assembler::ThreadAssemblyError;

#[derive(Debug, thiserror::Error)]
#[error("workspace preparation failed")]
pub(super) struct WorkspacePreparationFailure(#[source] pub(super) anyhow::Error);

pub(super) fn workspace_error(
    operation: &'static str,
    source: impl Into<anyhow::Error>,
) -> ThreadAssemblyError {
    resource_error(operation, WorkspacePreparationFailure(source.into()))
}

pub(in crate::studio) fn is_workspace_preparation_failure(failure: &anyhow::Error) -> bool {
    if SessionDataError::find(failure).is_some() {
        return false;
    }
    failure.chain().any(|cause| {
        cause.is::<WorkspacePreparationFailure>()
            || cause.is::<WorktreeError>()
            || cause.is::<super::ReviewWorkspaceError>()
            || matches!(
                cause.downcast_ref::<ThreadAssemblyError>(),
                Some(
                    ThreadAssemblyError::Workspace { .. }
                        | ThreadAssemblyError::ChildWorkspacePreparation { .. }
                )
            )
    })
}

pub(super) fn resource_error(
    operation: &'static str,
    source: impl Into<anyhow::Error>,
) -> ThreadAssemblyError {
    ThreadAssemblyError::Resource {
        operation,
        // anyhow's allocation-preserving Into<Box<dyn Error>> hides the original root type.
        // Reallocate through its official conversion so typed boundary classification survives.
        source: source
            .into()
            .reallocate_into_boxed_dyn_error_without_backtrace(),
    }
}
