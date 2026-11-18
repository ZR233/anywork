//! 交互决议只消费当前 owner 的交互；历史记录不参与命令准入。
use super::super::{StudioResolveInteractionResponse, StudioRuntime};
use super::{UserThreadAction, ensure_thread_not_archived};
use crate::{InteractionRequest, InteractionResolution, InteractionStatus};
use anyhow::Result;

impl StudioRuntime {
    /// Decide the interaction currently held by its owner. A consumed decision is no longer
    /// actionable; operation IDs correlate commands and do not promise permanent replay.
    pub async fn resolve_interaction(
        &self,
        operation_id: String,
        host_thread_id: String,
        expected_revision: u64,
        interaction_id: String,
        resolution: InteractionResolution,
    ) -> Result<StudioResolveInteractionResponse> {
        Self::validate_operation_id(&operation_id)?;
        let lifecycle_guard = self.lifecycle_lock.lock().await;
        // Materialization restores Current once. All admission below uses that owner only.
        let (thread_id, _) = crate::thread_assembler::decode_interaction_key(&interaction_id)?;
        Box::pin(self.ensure_thread_owner(thread_id)).await?;
        let interaction = self
            .current_interaction(&interaction_id)?
            .ok_or_else(|| crate::StudioError::not_found("interaction"))?;
        let owner = self
            .ensure_interaction_host(&host_thread_id, &interaction)
            .await?;
        ensure_thread_not_archived(&owner, UserThreadAction::Respond)?;
        if owner.parent_thread_id.is_some()
            && matches!(
                interaction.scope.purpose,
                crate::InteractionPurpose::AgentSessionPlanConfirmation(_)
            )
        {
            return Err(interaction_error(
                crate::thread_assembler::StudioInteractionError::Plan(
                    crate::thread_assembler::PlanInteractionError::NotRoot,
                ),
            ));
        }
        if interaction.status() != InteractionStatus::Pending
            || interaction.revision != expected_revision
        {
            return Err(crate::StudioError::new(crate::StudioErrorCode::StaleRevision,
                "The interaction is no longer pending at the observed revision", false)
                .with_reason(crate::StudioErrorReason::StaleInteraction,
                    serde_json::json!({"interactionId": interaction_id,
                        "expectedRevision": expected_revision, "currentRevision": interaction.revision}))
                .into());
        }
        let user_answered = matches!(resolution, InteractionResolution::UserInput(_));
        let interaction = self
            .require_session(&owner.id)?
            .resolve_product_interaction(
                &interaction_id,
                expected_revision,
                &operation_id,
                resolution,
            )
            .await
            .map_err(interaction_error)?;
        if user_answered {
            self.agent_facility
                .product_events
                .record_user_message(&owner.id, crate::studio::unix_seconds());
        }
        drop(lifecycle_guard);
        self.notify_host_interaction_decided(&interaction).await?;
        let mut receipt = self.command_receipt(
            operation_id,
            true,
            vec![self.resource_stamp(
                format!("interaction:{}", interaction.interaction_id),
                interaction.revision,
            )],
            crate::CommandEffectPoint::Immediate,
            false,
        );
        receipt.requires_identity_observation = true;
        Ok(StudioResolveInteractionResponse {
            thread_id: owner.id,
            interaction,
            receipt,
        })
    }

    pub(in crate::studio::runtime) fn current_interaction(
        &self,
        interaction_id: &str,
    ) -> Result<Option<InteractionRequest>> {
        let (thread_id, _) = crate::thread_assembler::decode_interaction_key(interaction_id)?;
        self.session_of(thread_id)
            .map(|session| {
                session
                    .read_product_interaction(interaction_id)
                    .map_err(anyhow::Error::from)
            })
            .transpose()
            .map(Option::flatten)
    }

    /// Requires `host_thread_id` to be a main session the user may access.
    ///
    /// The child interaction projection and the decision entry share this single check, so a child id
    /// can neither decide nor list interactions of its own subtree.
    pub(in crate::studio::runtime) async fn ensure_root_host(
        &self,
        host_thread_id: &str,
    ) -> Result<crate::studio::ThreadRecord> {
        use crate::{StudioError, StudioErrorCode, StudioErrorReason};
        if host_thread_id.trim().is_empty() {
            return Err(anyhow::Error::new(StudioError::invalid_argument(
                "hostThreadId is required",
            )));
        }
        let host = self.read_owned_thread(host_thread_id).await?;
        if host.parent_thread_id.is_some() {
            return Err(anyhow::Error::new(
                StudioError::new(
                    StudioErrorCode::PermissionDenied,
                    "A child session cannot host interaction decisions",
                    false,
                )
                .with_reason(
                    StudioErrorReason::InteractionNotHosted,
                    serde_json::json!({ "hostThreadId": host.id, "hostIsChild": true }),
                ),
            ));
        }
        Ok(host)
    }

    /// Verifies that `host_thread_id` may act for the interaction's owning session.
    /// Returns the owning Thread's record, which the caller also needs for its own checks.
    async fn ensure_interaction_host(
        &self,
        host_thread_id: &str,
        interaction: &InteractionRequest,
    ) -> Result<crate::studio::ThreadRecord> {
        use crate::{StudioError, StudioErrorCode, StudioErrorReason};
        let host = self.ensure_root_host(host_thread_id).await?;
        let owner = self.read_owned_thread(&interaction.scope.thread_id).await?;
        if owner.id != host.id && owner.parent_thread_id.as_deref() != Some(host.id.as_str()) {
            return Err(anyhow::Error::new(
                StudioError::new(
                    StudioErrorCode::PermissionDenied,
                    "The interaction does not belong to this session or its direct children",
                    false,
                )
                .with_reason(
                    StudioErrorReason::InteractionNotHosted,
                    serde_json::json!({
                        "hostThreadId": host.id,
                        "interactionThreadId": owner.id,
                    }),
                ),
            ));
        }
        Ok(owner)
    }
}

/// Maps a product interaction failure onto the typed Studio error the transports expose.
///
/// Every rejection a caller can provoke becomes a 4xx-worthy typed reason instead of a redacted
/// internal failure: a missing owner, a stale record, a wrong kind and a child Plan record are
/// distinct, actionable outcomes.
fn interaction_error(error: crate::thread_assembler::StudioInteractionError) -> anyhow::Error {
    use crate::thread_assembler::StudioInteractionError as Source;
    use crate::{StudioError, StudioErrorCode, StudioErrorReason};
    match error {
        Source::Identity => anyhow::Error::new(
            StudioError::new(
                StudioErrorCode::Conflict,
                "The interaction identity, revision or kind does not match its record",
                false,
            )
            .with_reason(StudioErrorReason::StaleInteraction, serde_json::json!({})),
        ),
        Source::Plan(crate::thread_assembler::PlanInteractionError::NotRoot) => anyhow::Error::new(
            StudioError::new(
                StudioErrorCode::PermissionDenied,
                "A child Plan confirmation stays a diagnostic and is not decidable",
                false,
            )
            .with_reason(
                StudioErrorReason::InteractionNotHosted,
                serde_json::json!({}),
            ),
        ),
        other => anyhow::Error::new(other),
    }
}
