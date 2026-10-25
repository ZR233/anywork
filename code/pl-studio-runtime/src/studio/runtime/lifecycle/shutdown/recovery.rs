//! Retry permission is derived only from the original domain owner/typed shutdown phase.
//! It does not turn arbitrary anyhow errors or observer timeouts into restart permission.

use std::sync::Arc;

use pl_protocol::studio::CleanupRecovery;

use super::super::framework::{FrameworkShutdownFailure, PersistenceShutdownFailure};
use super::supervision::{FailureCause, StageId};
use crate::studio::runtime::background_task::BackgroundTaskFailure;
use crate::studio::runtime::draft_commands::DraftCommandsCloseFailure;
use crate::studio::runtime::read_scopes::ReadScopesCloseFailure;

pub(super) fn can_retry(id: StageId, cause: &FailureCause) -> bool {
    let FailureCause::Failed(error) = cause else {
        return false;
    };
    match id {
        StageId::DetailReads => {
            error
                .downcast_ref::<ReadScopesCloseFailure>()
                .is_some_and(|failure| {
                    failure.call_error.is_none()
                        && failure.call_failures.is_empty()
                        && !failure.scope_issues.is_empty()
                        && failure
                            .scope_issues
                            .iter()
                            .all(|issue| issue.recovery == CleanupRecovery::RetryClose)
                })
        }
        StageId::ToolRefresh => {
            // stop_tool_refresh can fail at exactly two awaits: the retained background join,
            // or RejectedToolOwners::retry. Only the latter has the original ToolError lease.
            let background_join =
                error.is::<Arc<BackgroundTaskFailure>>() || error.is::<BackgroundTaskFailure>();
            !background_join
                && error
                    .chain()
                    .any(|source| source.is::<Arc<pl_core::tool::opaque::ToolError>>())
        }
        StageId::Bots => error
            .downcast_ref::<crate::bots::FeishuError>()
            .is_some_and(crate::bots::FeishuError::retryable),
        StageId::AgentFramework => framework_retry(error),
        // wait_for_drain currently erases recoverable write failures and terminal released-dirty
        // incarnations into the same anyhow error. Without that owner's typed distinction, do
        // not grant retry merely because the error arose before writer shutdown.
        StageId::Persistence => matches!(
            error.downcast_ref::<PersistenceShutdownFailure>(),
            Some(PersistenceShutdownFailure::Flush(_))
        ),
        // These jobs are once-only or have no proven original recovery contract. In particular,
        // rerunning drained title/probe maps cannot repair their already consumed join failures.
        StageId::ModelCatalog
        | StageId::Recovery
        | StageId::ModelRefresh
        | StageId::Title
        | StageId::McpStartupReconcile
        | StageId::McpHealth
        | StageId::McpStop
        | StageId::McpStopped
        | StageId::LspState
        | StageId::LspStop
        | StageId::LspStopped
        | StageId::PersistenceObserver
        | StageId::Ssh
        | StageId::AgentProfiles
        | StageId::Store => false,
    }
}

fn framework_retry(error: &anyhow::Error) -> bool {
    if let Some(failure) = error.downcast_ref::<DraftCommandsCloseFailure>() {
        return !failure.issues.is_empty()
            && failure
                .issues
                .iter()
                .all(|issue| issue.recovery == CleanupRecovery::RetryClose)
            && failure.source.as_ref().is_none_or(|error| {
                error
                    .downcast_ref::<FrameworkShutdownFailure>()
                    .is_some_and(|failure| failure.retry_close)
            });
    }
    error
        .downcast_ref::<FrameworkShutdownFailure>()
        .is_some_and(|failure| failure.retry_close)
}
