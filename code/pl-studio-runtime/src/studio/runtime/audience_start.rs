//! Bot-owner access to a canonical cut. This does not activate an output authorization.

use anyhow::{Context, Result, ensure};
use pl_core::thread::extensions::ExtensionMutation;

use super::StudioRuntime;
use crate::studio::audience_start::{
    AUDIENCE_START_EXTENSION, AudienceStartIntent, AudienceStartReceipt, TurnStartReceipt,
};

pub(crate) enum AudienceStartPreparation {
    /// Core has accepted this exact slot value; the receipt is not yet proven durable.
    Pending {
        extension_revision: u64,
    },
    Saved(AudienceStartReceipt),
    /// A later generation occupies the slot. It must never be replaced by this old request.
    Superseded,
}

impl StudioRuntime {
    /// Used only by the bot's managed prepare operation, after its original binding/auth CAS.
    /// A caller cancellation cannot retract the command already sent to core; retry first recovers
    /// its immutable receipt or matching current slot instead of establishing a later cut.
    pub(crate) async fn prepare_bot_audience_start(
        &self,
        intent: &AudienceStartIntent,
    ) -> Result<AudienceStartPreparation> {
        Self::validate_operation_id(&intent.operation_id)?;
        intent.validate()?;
        let thread = self.read_protocol_thread(&intent.thread_id).await?;
        ensure!(
            thread.parent_thread_id.is_none(),
            "child Thread has no bot audience cut"
        );
        if let Some(receipt) = self.bot_audience_start_fact(intent).await? {
            return Ok(AudienceStartPreparation::Saved(receipt));
        }
        let owner = self.ensure_thread_owner(&intent.thread_id).await?;
        let state = owner.snapshot();
        let crate::studio::thread_audience::ThreadAudienceOwner::Bot(bot) =
            crate::studio::thread_audience::frozen_owner(&thread, &state)?
        else {
            anyhow::bail!("audience cut requires a proven frozen bot channel");
        };
        ensure!(
            bot.bot_id() == intent.authorization.bot_id,
            "audience cut bot owner mismatch"
        );
        ensure!(
            crate::studio::thread_audience::supports_public_frontend(&state)?,
            "frozen bot instructions require an explicitly new conversation"
        );
        let current = state.extensions.get(AUDIENCE_START_EXTENSION);
        if let Some(record) = current {
            let previous = AudienceStartIntent::decode(&record.payload)?;
            ensure!(
                previous.thread_id == intent.thread_id
                    && previous.authorization.bot_id == intent.authorization.bot_id
                    && previous.authorization.chat_id == intent.authorization.chat_id,
                "audience cut scope cannot change within a Thread"
            );
            if previous.authorization.generation > intent.authorization.generation {
                return Ok(AudienceStartPreparation::Superseded);
            }
            if previous.authorization.generation == intent.authorization.generation {
                ensure!(
                    previous == *intent,
                    "audience generation already has a different cut"
                );
                return self
                    .audience_start_after_commit(intent, record.revision)
                    .await;
            }
            ensure!(
                previous.operation_id != intent.operation_id,
                "audience operation cannot change its generation"
            );
        }
        let records = owner
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: AUDIENCE_START_EXTENSION.to_owned(),
                expected_revision: current.map(|record| record.revision),
                payload: intent.encode()?,
            }])
            .await?;
        let committed = records
            .get(AUDIENCE_START_EXTENSION)
            .context("committed audience cut is missing")?;
        ensure!(
            AudienceStartIntent::decode(&committed.payload)? == *intent,
            "committed audience cut differs from its request"
        );
        self.audience_start_after_commit(intent, committed.revision)
            .await
    }

    async fn audience_start_after_commit(
        &self,
        intent: &AudienceStartIntent,
        extension_revision: u64,
    ) -> Result<AudienceStartPreparation> {
        match self.bot_audience_start_fact(intent).await? {
            Some(receipt) => Ok(AudienceStartPreparation::Saved(receipt)),
            None => Ok(AudienceStartPreparation::Pending { extension_revision }),
        }
    }

    /// Cold proof read: missing proof is pending/unavailable, never evidence of non-admission.
    pub(crate) async fn bot_audience_start_fact(
        &self,
        intent: &AudienceStartIntent,
    ) -> Result<Option<AudienceStartReceipt>> {
        self.store
            .history(&intent.thread_id)
            .await?
            .audience_start_receipt(intent)
            .await
    }

    pub(crate) async fn bot_turn_start_fact(
        &self,
        thread_id: &str,
        turn_id: &str,
    ) -> Result<Option<TurnStartReceipt>> {
        self.store
            .history(thread_id)
            .await?
            .turn_start_receipt(turn_id)
            .await
    }

    /// Reads the frozen definition, never the current prompt catalog. Old privacy promises stay old.
    pub(crate) async fn bot_thread_supports_public_frontend(
        &self,
        thread_id: &str,
    ) -> Result<bool> {
        let state = self.read_thread_state(thread_id).await?;
        crate::studio::thread_audience::supports_public_frontend(&state)
    }
}
