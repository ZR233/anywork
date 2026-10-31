//! Product interaction routing reads only canonical Thread snapshots.
use super::{StudioThreadAssembler, decode_interaction_key};
use pl_protocol::{
    ChildInteractionSummary, InteractionRequest, InteractionResolution, InteractionStatus,
};

#[derive(Debug, thiserror::Error)]
pub enum StudioInteractionError {
    #[error(transparent)]
    Key(#[from] super::InteractionKeyError),
    #[error(transparent)]
    Permission(#[from] super::PermissionProjectionError),
    #[error(transparent)]
    Plan(#[from] super::PlanInteractionError),
    #[error(transparent)]
    User(#[from] super::UserInteractionError),
    #[error("interaction identity is missing, ambiguous or incompatible with the response")]
    Identity,
}

/// Projects one interaction from live or cold replay facts without activating execution.
///
/// # Errors
/// Rejects ambiguous identities and unsupported producer payload formats.
pub fn project_thread_interaction(
    thread_id: &str,
    local_id: &str,
    snapshot: &pl_core::thread::ThreadSnapshot,
) -> Result<Option<InteractionRequest>, StudioInteractionError> {
    match (
        snapshot.permissions.get(local_id),
        snapshot.interactions.get(local_id),
    ) {
        (Some(_), Some(_)) => Err(StudioInteractionError::Identity),
        (Some(permission), None) => Ok(Some(super::project_execution_permission(
            thread_id, permission,
        )?)),
        (None, Some(record)) => match record.request.payload.format() {
            crate::plan_tool::PLAN_CONFIRMATION_FORMAT => {
                Ok(Some(super::project_plan_confirmation(thread_id, record)?))
            }
            _ => Ok(Some(super::project_user_input(thread_id, record)?)),
        },
        (None, None) => Ok(None),
    }
}

/// Projects the pending user-input and tool-approval interactions visible to a direct parent.
///
/// The same predicate is used by the explicit list query and by the root-scoped product projection,
/// so Plan diagnostics and terminal records cannot drift between the two surfaces.
pub(crate) fn project_pending_child_interactions(
    thread_id: &str,
    snapshot: &pl_core::thread::ThreadSnapshot,
) -> Result<Vec<ChildInteractionSummary>, StudioInteractionError> {
    let mut summaries = Vec::new();
    for local_id in snapshot
        .interactions
        .keys()
        .chain(snapshot.permissions.keys())
    {
        let Some(interaction) = project_thread_interaction(thread_id, local_id, snapshot)? else {
            continue;
        };
        if interaction.status() != InteractionStatus::Pending
            || is_child_plan_diagnostic(snapshot, local_id)
        {
            continue;
        }
        summaries.push(ChildInteractionSummary::new(interaction));
    }
    Ok(summaries)
}

fn is_child_plan_diagnostic(snapshot: &pl_core::thread::ThreadSnapshot, local_id: &str) -> bool {
    snapshot.interactions.get(local_id).is_some_and(|record| {
        record.request.payload.format() == crate::plan_tool::PLAN_CONFIRMATION_FORMAT
    })
}

impl StudioThreadAssembler {
    /// Reads a current product interaction without constructing a second mutable interaction owner.
    ///
    /// # Errors
    /// Rejects malformed IDs, ambiguous records and unknown product payload encodings.
    pub fn read_product_interaction(
        &self,
        wire_id: &str,
    ) -> Result<Option<InteractionRequest>, StudioInteractionError> {
        let (thread_id, local_id) = decode_interaction_key(wire_id)?;
        let Some(thread) = self
            .0
            .state()
            .entries
            .get(thread_id)
            .map(|entry| entry.thread.clone())
        else {
            return Ok(None);
        };
        let snapshot = thread.snapshot();
        project_thread_interaction(thread_id, local_id, &snapshot)
    }

    /// Resolves the product's existing typed response envelope on the Thread encoded in its ID.
    ///
    /// # Errors
    /// Rejects wrong response kinds, stale records and failed canonical state transitions.
    /// Commits one decision for `wire_id` under the caller's operation identity.
    ///
    /// The identity is stored inside the decision fact itself, so a repeat is answered from the same
    /// record instead of needing a second operation table.
    pub async fn resolve_product_interaction(
        &self,
        wire_id: &str,
        operation_id: &str,
        response: InteractionResolution,
    ) -> Result<InteractionRequest, StudioInteractionError> {
        let current = self
            .read_product_interaction(wire_id)?
            .ok_or(StudioInteractionError::Identity)?;
        if current.status() != InteractionStatus::Pending {
            return if current.resolution().as_ref() == Some(&response) {
                Ok(current)
            } else {
                Err(StudioInteractionError::Identity)
            };
        }
        let operation_id = operation_id.to_owned();
        let resolved_at = crate::studio::unix_seconds();
        match response {
            InteractionResolution::ToolApproval(response)
                if current.kind() == pl_protocol::InteractionKind::ToolApproval =>
            {
                Ok(self
                    .resolve_tool_approval(
                        &current.scope.thread_id,
                        pl_protocol::ResolveToolApproval {
                            interaction_id: wire_id.into(),
                            expected_revision: current.revision,
                            operation_id,
                            resolved_at,
                            decision: response.decision,
                            reason: response.reason,
                        },
                    )
                    .await?)
            }
            InteractionResolution::UserInput(response)
                if current.kind() == pl_protocol::InteractionKind::UserInput =>
            {
                let command = pl_protocol::ResolveUserInput {
                    interaction_id: wire_id.into(),
                    expected_revision: current.revision,
                    operation_id,
                    resolved_at,
                    answers: response.answers,
                };
                match current.scope.purpose {
                    pl_protocol::InteractionPurpose::General => {
                        Ok(self.resolve_user_input(command).await?)
                    }
                    pl_protocol::InteractionPurpose::AgentSessionPlanConfirmation(_) => Ok(self
                        .resolve_plan_confirmation(&current.scope.thread_id, command)
                        .await?),
                }
            }
            InteractionResolution::ToolApproval(_) | InteractionResolution::UserInput(_) => {
                Err(StudioInteractionError::Identity)
            }
        }
    }
}
