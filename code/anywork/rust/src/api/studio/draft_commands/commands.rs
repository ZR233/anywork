//! Registration and recovery of the original two native command owners.
use super::handles::{wrap_admission, wrap_creation};
use super::types::BridgeDraftCommandBeginFailure;
use super::{BridgeAttachmentAdmission, BridgeThreadCreation};
use crate::api::studio::bridge_runtime::installed_bridge;
use crate::api::studio::types::{
    BridgeAttachmentAdmissionContext, BridgeAttachmentDraftSource, BridgeError,
    BridgeStartNewThreadRequest,
};

pub async fn begin_attachment_admission(
    operation_id: String,
    context: BridgeAttachmentAdmissionContext,
    sources: Vec<BridgeAttachmentDraftSource>,
) -> Result<BridgeAttachmentAdmission, BridgeDraftCommandBeginFailure> {
    let bridge = installed_bridge().map_err(BridgeDraftCommandBeginFailure::from)?;
    let job = bridge
        .studio
        .begin_attachment_admission(
            operation_id,
            pl_protocol::studio::AdmitAttachmentDraftsRequest {
                context: context.into(),
                sources: sources.into_iter().map(Into::into).collect(),
            },
        )
        .map_err(|error| BridgeDraftCommandBeginFailure::from(BridgeError::from(error)))?;
    wrap_admission(job).map_err(|error| BridgeDraftCommandBeginFailure::UnknownOutcome { error })
}

pub async fn find_attachment_admission(
    operation_id: String,
) -> Result<Option<BridgeAttachmentAdmission>, BridgeError> {
    installed_bridge()?
        .studio
        .find_attachment_admission(operation_id)?
        .map(wrap_admission)
        .transpose()
}

pub async fn begin_thread_creation(
    operation_id: String,
    request: BridgeStartNewThreadRequest,
) -> Result<BridgeThreadCreation, BridgeDraftCommandBeginFailure> {
    let mode = pl_protocol::ThreadModeId::new(request.mode)
        .map_err(|error| BridgeError::from(anyhow::anyhow!(error)))?;
    let workspace_mode = match request.workspace_mode.as_deref().map(str::trim) {
        None | Some("") | Some("local") => pl_protocol::ThreadWorkspaceMode::Local,
        Some("worktree") => pl_protocol::ThreadWorkspaceMode::Worktree,
        Some(_) => {
            return Err(
                BridgeError::from(pl_protocol::studio::StudioError::invalid_argument(
                    "workspaceMode must be local or worktree",
                ))
                .into(),
            );
        }
    };
    let job = installed_bridge()
        .map_err(BridgeDraftCommandBeginFailure::from)?
        .studio
        .begin_thread_creation(pl_protocol::studio::BeginThreadCreationRequest {
            operation_id,
            project_id: request.project_id,
            request: pl_protocol::studio::CreateThreadRequest {
                title: None,
                input: request.input.into(),
                mode: mode.label().to_string(),
                route: pl_protocol::studio::NewThreadModelRoute {
                    account_id: request.account_id,
                    model_id: request.model_id,
                    effort: request.effort,
                },
                delegation_mode: Some(request.delegation_mode.into()),
                delegation_preference: Some(request.delegation_preference.into()),
                workspace_mode,
            },
        })
        .map_err(|error| BridgeDraftCommandBeginFailure::from(BridgeError::from(error)))?;
    wrap_creation(job).map_err(|error| BridgeDraftCommandBeginFailure::UnknownOutcome { error })
}

pub async fn find_thread_creation(
    operation_id: String,
) -> Result<Option<BridgeThreadCreation>, BridgeError> {
    installed_bridge()?
        .studio
        .find_thread_creation(operation_id)?
        .map(wrap_creation)
        .transpose()
}
