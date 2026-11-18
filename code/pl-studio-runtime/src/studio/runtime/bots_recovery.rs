//! Bot auto-reply recovery from the complete Current owner.
//!
//! Current is the authority for admitted inputs, pending/terminal interactions and the bounded
//! obligations a live bot may still need to finish. This module never rebuilds global input/message
//! idempotency from history and never activates a model or tool.

use crate::InteractionStatus;
use anyhow::{Context, Result};
use pl_core::thread::interactions::{InteractionRecord, InteractionState};
use pl_core::thread::permissions::{PermissionRecord, PermissionState};

use super::StudioRuntime;
use crate::bots::{BotInputRead, BotInteractionFact, BotInteractionKind, BotInteractionRead};

impl StudioRuntime {
    pub(crate) async fn bot_input_fact(
        &self,
        thread_id: &str,
        input_id: &str,
    ) -> Result<BotInputRead> {
        let state = self.bot_current_state(thread_id).await?;
        if let Some(record) = state
            .inputs
            .iter()
            .find(|record| record.input.id == input_id)
        {
            return Ok(BotInputRead::Ready {
                delivery: record.delivery.clone(),
                state: record.state.clone(),
            });
        }
        if let Some(identity) = state
            .terminal_inputs
            .iter()
            .find(|identity| identity.id == input_id)
        {
            return Ok(BotInputRead::Ready {
                delivery: identity.delivery.clone(),
                state: identity.state.clone(),
            });
        }
        Ok(BotInputRead::Absent)
    }

    pub(crate) async fn bot_interaction_fact(
        &self,
        thread_id: &str,
        local_id: &str,
    ) -> Result<BotInteractionRead> {
        let state = self.bot_current_state(thread_id).await?;
        if let Some(record) = state.interactions.get(local_id) {
            return Ok(BotInteractionRead::Ready(interaction_fact(record)));
        }
        if let Some(record) = state.permissions.get(local_id) {
            return Ok(BotInteractionRead::Ready(permission_fact(record)));
        }
        Ok(BotInteractionRead::Absent)
    }

    async fn bot_current_state(&self, thread_id: &str) -> Result<pl_core::thread::ThreadSnapshot> {
        if let Some(handle) = self
            .session_of(thread_id)
            .and_then(|session| session.thread(thread_id))
        {
            return Ok(handle.snapshot());
        }
        let thread = self.read_protocol_thread(thread_id).await?;
        let current =
            crate::studio::thread_factory::recovery::load_current_read_only(&self.store, &thread)
                .await?
                .context("bot recovery has no complete current")?;
        Ok(current.state.to_paused_snapshot())
    }
}

fn interaction_fact(record: &InteractionRecord) -> BotInteractionFact {
    let status = match &record.state {
        InteractionState::Resolved(_) => InteractionStatus::Resolved,
        InteractionState::Cancelled => InteractionStatus::Cancelled,
        InteractionState::Pending => InteractionStatus::Pending,
    };
    BotInteractionFact {
        kind: BotInteractionKind::UserInput,
        status,
        continuation_input: record.continuation_id.clone(),
    }
}

fn permission_fact(record: &PermissionRecord) -> BotInteractionFact {
    let status = match record.state {
        PermissionState::Allowed | PermissionState::Denied => InteractionStatus::Resolved,
        PermissionState::Cancelled => InteractionStatus::Cancelled,
        PermissionState::Pending => InteractionStatus::Pending,
    };
    BotInteractionFact {
        kind: BotInteractionKind::Permission,
        status,
        continuation_input: None,
    }
}
