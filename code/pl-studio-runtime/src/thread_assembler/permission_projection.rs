//! Typed Studio approval projection over authoritative core permission facts.
use super::{SessionRuntime, approval::ApprovalPrompt};
use crate::{
    CancelInteraction, InteractionCommand, InteractionRequest, InteractionScope,
    ResolveToolApproval, ToolApprovalResolution, ToolApprovalResolutionPayload,
};
use pl_core::{
    context::OpaquePayload,
    thread::permissions::{
        PermissionDecision, PermissionRecord, PermissionResolution, PermissionState,
    },
};

#[derive(Debug, thiserror::Error)]
pub enum PermissionProjectionError {
    #[error(transparent)]
    Key(#[from] super::InteractionKeyError),
    #[error("unsupported approval payload {format} version {version}")]
    Unsupported { format: String, version: u32 },
    #[error("approval payload is invalid")]
    Decode(#[from] serde_json::Error),
    #[error("approval payload identity or decision contradicts its core record")]
    Identity,
    #[error("approval thread is not resident: {0}")]
    MissingThread(String),
    #[error("approval record is not present: {0}")]
    MissingPermission(String),
    #[error("approval projection transition failed")]
    Projection(#[from] crate::InteractionTransitionError),
    #[error("approval resolution was rejected by its Thread")]
    Thread(#[from] pl_core::thread::ThreadError),
    #[error("approval response could not be frozen")]
    Payload(#[from] pl_core::context::PayloadError),
}

fn require_format(
    payload: &OpaquePayload,
    expected: &str,
) -> Result<(), PermissionProjectionError> {
    super::interaction_projection::require_format(payload, expected).map_err(Into::into)
}

pub(crate) const APPROVAL_RESPONSE_FORMAT: &str = "pl.studio.tool-approval-response";

/// The canonical decision stored with a permission record. Storage normalizes legacy responses
/// before starting a recovered Thread.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct StoredApprovalDecision {
    /// The decision itself, kept as the shared protocol shape so the transport needs no new DTO.
    pub(crate) decision: ToolApprovalResolutionPayload,
    /// The operation identity the decision was accepted under; absent on legacy rows.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) operation_id: Option<String>,
}

impl StoredApprovalDecision {
    /// Freezes one accepted decision together with its operation identity.
    fn freeze(decision: ToolApprovalResolutionPayload, operation_id: String) -> Self {
        Self {
            decision,
            operation_id: Some(operation_id),
        }
    }
}

/// Freezes one accepted approval decision into the payload its permission record stores.
///
/// This is the single write side of that payload, so the record's read side and every durable replay
/// decode exactly what was written instead of an ad-hoc JSON literal that can drift from it.
///
/// # Errors
/// Rejects payload values the core envelope cannot freeze.
fn approval_response_payload(
    decision: ToolApprovalResolutionPayload,
    operation_id: String,
) -> Result<OpaquePayload, PermissionProjectionError> {
    Ok(OpaquePayload::new(
        APPROVAL_RESPONSE_FORMAT,
        1,
        serde_json::to_string(&StoredApprovalDecision::freeze(decision, operation_id))?,
    )?)
}

/// Projects saved approval content without consulting current tool schemas or policy renderers.
///
/// # Errors
/// Rejects unknown content encodings and contradictory records while leaving raw history intact.
pub fn project_execution_permission(
    thread_id: &str,
    record: &PermissionRecord,
) -> Result<InteractionRequest, PermissionProjectionError> {
    if matches!(
        record.state,
        PermissionState::Pending | PermissionState::Cancelled
    ) && record.response.is_some()
    {
        return Err(PermissionProjectionError::Identity);
    }
    require_format(&record.payload, "pl.studio.tool-approval")?;
    let prompt: ApprovalPrompt = serde_json::from_str(record.payload.content())?;
    if prompt.name != record.tool_id {
        return Err(PermissionProjectionError::Identity);
    }
    let wire_id = super::interaction_key::encode(thread_id, &record.id);
    let projected = InteractionRequest::tool_approval(
        wire_id.clone(),
        InteractionScope {
            thread_id: thread_id.into(),
            turn_id: record.turn_id.clone(),
            item_id: Some(record.call_id.clone()),
            tool_id: Some(record.call_id.clone()),
            agent_path: Some(thread_id.into()),
            purpose: Default::default(),
        },
        crate::ToolApprovalRequest {
            name: prompt.name,
            arguments: serde_json::Value::String(prompt.arguments.content().into()),
            working_directory: prompt.working_directory,
            parent_agent_id: None,
        },
        record.created_at,
    );
    let command = match record.state {
        PermissionState::Pending => None,
        PermissionState::Allowed | PermissionState::Denied => {
            let expected = match record.state {
                PermissionState::Allowed => ToolApprovalResolution::Approved,
                PermissionState::Denied => ToolApprovalResolution::Denied,
                PermissionState::Pending | PermissionState::Cancelled => {
                    return Err(PermissionProjectionError::Identity);
                }
            };
            let reason = match &record.response {
                Some(payload) => {
                    require_format(payload, APPROVAL_RESPONSE_FORMAT)?;
                    let response: StoredApprovalDecision = serde_json::from_str(payload.content())?;
                    if response.decision.decision != expected {
                        return Err(PermissionProjectionError::Identity);
                    }
                    response.decision.reason
                }
                None => None,
            };
            Some(InteractionCommand::ResolveToolApproval(
                ResolveToolApproval {
                    interaction_id: wire_id.clone(),
                    expected_revision: 1,
                    operation_id: format!("permission:{}:{}", record.id, record.revision),
                    resolved_at: record.updated_at,
                    decision: expected,
                    reason,
                },
            ))
        }
        PermissionState::Cancelled => Some(InteractionCommand::Cancel(CancelInteraction {
            interaction_id: wire_id.clone(),
            expected_revision: 1,
            operation_id: format!("permission:{}:{}", record.id, record.revision),
            reason: "The original execution permission is no longer active.".into(),
            cancelled_at: record.updated_at,
        })),
    };
    super::interaction_projection::replay(projected, command, record.revision, record.updated_at)
        .map_err(Into::into)
}

impl SessionRuntime {
    /// Resolves a typed UI decision on the resident canonical owner and returns its resulting DTO.
    ///
    /// # Errors
    /// Rejects missing owners, unknown payload formats, stale revisions and expired execution leases.
    pub async fn resolve_tool_approval(
        &self,
        thread_id: &str,
        mut resolution: ResolveToolApproval,
    ) -> Result<InteractionRequest, PermissionProjectionError> {
        let (owner, local_id) = super::decode_interaction_key(&resolution.interaction_id)?;
        if owner != thread_id {
            return Err(PermissionProjectionError::Identity);
        }
        resolution.interaction_id = local_id.to_owned();
        let thread = {
            self.0
                .state()
                .members
                .entries
                .get(thread_id)
                .and_then(|entry| {
                    let native = entry.native().ok()?;
                    Some(native.thread.clone())
                })
        }
        .ok_or_else(|| PermissionProjectionError::MissingThread(thread_id.into()))?;
        let snapshot = thread.snapshot();
        let current = snapshot
            .permissions
            .get(&resolution.interaction_id)
            .ok_or_else(|| {
                PermissionProjectionError::MissingPermission(resolution.interaction_id.clone())
            })?;
        project_execution_permission(thread_id, current)?;
        let decision = match resolution.decision {
            ToolApprovalResolution::Approved => PermissionDecision::Allow,
            ToolApprovalResolution::Denied => PermissionDecision::Deny,
        };
        // The operation identity is frozen into the decision payload: a repeat is answered from the
        // same record, and another operation cannot silently replace it.
        let payload = approval_response_payload(
            ToolApprovalResolutionPayload {
                decision: resolution.decision,
                reason: resolution.reason,
            },
            resolution.operation_id,
        )?;
        let record = thread
            .resolve_execution_permission(PermissionResolution {
                id: resolution.interaction_id,
                expected_revision: resolution.expected_revision,
                decision,
                payload: Some(payload),
            })
            .await?;
        project_execution_permission(thread_id, &record)
    }
}

impl From<super::interaction_projection::DecodeError> for PermissionProjectionError {
    fn from(error: super::interaction_projection::DecodeError) -> Self {
        use super::interaction_projection::DecodeError;
        match error {
            DecodeError::Unsupported { format, version } => Self::Unsupported { format, version },
            DecodeError::Json(error) => Self::Decode(error),
        }
    }
}
impl From<super::interaction_projection::ReplayError> for PermissionProjectionError {
    fn from(error: super::interaction_projection::ReplayError) -> Self {
        use super::interaction_projection::ReplayError;
        match error {
            ReplayError::Transition(error) => Self::Projection(error),
            ReplayError::Revision => Self::Identity,
        }
    }
}
