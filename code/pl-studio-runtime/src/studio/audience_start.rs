//! Immutable audience cuts and Turn starts derived from the original Thread write.
//!
//! These receipts prove ordering, not permission to send. The bot binding owner alone activates
//! an authorization after the exact cut is durable. No model fact, timeline revision or wall clock
//! can substitute for the matching effect/checkpoint pair here.

use anyhow::{Result, ensure};
use pl_core::{
    context::OpaquePayload,
    thread::{TurnState, cold::ThreadWrite, extensions::ExtensionChange},
};
use pl_protocol::BotAuthorizationId;
use serde::{Deserialize, Serialize};

use super::storage::history::{FactReceiptWrite, HistoryStore};
use super::thread_projection::order::receipt_id;

pub(crate) const AUDIENCE_START_EXTENSION: &str = "studio.audience-start";
const AUDIENCE_START_FORMAT: &str = "pl.studio.audience-start";
pub(crate) const AUDIENCE_START_RECEIPT: &str = "audience-start";
pub(crate) const TURN_START_RECEIPT: &str = "turn-start";
pub(crate) const FORMAT_VERSION: u32 = 1;
/// Each identity describes exactly one cut/start, never a mutable progress record.
pub(crate) const RECEIPT_REVISION: u64 = 1;

/// Frozen by the bot's durable prepare operation before it asks the Thread owner for a cut.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct AudienceStartIntent {
    pub operation_id: String,
    pub thread_id: String,
    pub authorization: BotAuthorizationId,
    pub binding_revision: u64,
}

impl AudienceStartIntent {
    pub(crate) fn validate(&self) -> Result<()> {
        ensure!(
            !self.operation_id.is_empty()
                && !self.thread_id.is_empty()
                && !self.authorization.chat_id.is_empty()
                && self.authorization.generation > 0,
            "audience start identity is incomplete"
        );
        crate::bots::validate_bot_id(&self.authorization.bot_id)?;
        Ok(())
    }

    pub(crate) fn encode(&self) -> Result<OpaquePayload> {
        self.validate()?;
        Ok(OpaquePayload::new(
            AUDIENCE_START_FORMAT,
            FORMAT_VERSION,
            serde_json::to_string(self)?,
        )?)
    }

    pub(crate) fn decode(payload: &OpaquePayload) -> Result<Self> {
        ensure!(
            payload.format() == AUDIENCE_START_FORMAT && payload.version() == FORMAT_VERSION,
            "unsupported audience start intent encoding"
        );
        let intent: Self = serde_json::from_str(payload.content())?;
        intent.validate()?;
        Ok(intent)
    }

    pub(crate) fn receipt_id(&self) -> String {
        receipt_id(AUDIENCE_START_RECEIPT, &self.operation_id)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct AudienceStartReceipt {
    pub version: u32,
    pub intent: AudienceStartIntent,
    pub extension_revision: u64,
    pub sequence: u64,
    pub excluded_turn_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct TurnStartReceipt {
    pub version: u32,
    pub thread_id: String,
    pub turn_id: String,
    pub input_id: Option<String>,
    pub sequence: u64,
}

impl HistoryStore {
    pub(crate) async fn audience_start_receipt(
        &self,
        intent: &AudienceStartIntent,
    ) -> Result<Option<AudienceStartReceipt>> {
        intent.validate()?;
        ensure!(
            intent.thread_id == self.thread_id(),
            "audience receipt Thread mismatch"
        );
        let Some(fact) = self
            .verified_fact_receipt(
                &intent.receipt_id(),
                RECEIPT_REVISION,
                AUDIENCE_START_RECEIPT,
            )
            .await?
        else {
            return Ok(None);
        };
        let receipt: AudienceStartReceipt = serde_json::from_str(&fact.payload)?;
        ensure!(
            receipt.version == FORMAT_VERSION
                && receipt.intent == *intent
                && receipt.extension_revision > 0
                && receipt.sequence == fact.write_sequence
                && receipt
                    .excluded_turn_id
                    .as_ref()
                    .is_none_or(|id| !id.is_empty()),
            "audience start receipt conflicts with its durable identity"
        );
        Ok(Some(receipt))
    }

    pub(crate) async fn turn_start_receipt(
        &self,
        turn_id: &str,
    ) -> Result<Option<TurnStartReceipt>> {
        ensure!(!turn_id.is_empty(), "Turn start identity is empty");
        let Some(fact) = self
            .verified_fact_receipt(
                &receipt_id(TURN_START_RECEIPT, turn_id),
                RECEIPT_REVISION,
                TURN_START_RECEIPT,
            )
            .await?
        else {
            return Ok(None);
        };
        let receipt: TurnStartReceipt = serde_json::from_str(&fact.payload)?;
        ensure!(
            receipt.version == FORMAT_VERSION
                && receipt.thread_id == self.thread_id()
                && receipt.turn_id == turn_id
                && receipt.sequence == fact.write_sequence
                && receipt.input_id.as_ref().is_none_or(|id| !id.is_empty()),
            "Turn start receipt conflicts with its durable identity"
        );
        Ok(Some(receipt))
    }
}

/// Called only for an original, trusted core write, never from reconstructed timeline items or a
/// migration snapshot. The original history transaction commits these receipts with its checkpoint.
pub(crate) fn receipt_writes(write: &ThreadWrite) -> Result<Vec<FactReceiptWrite>> {
    let effect = &write.effect;
    let checkpoint = &write.checkpoint;
    ensure!(
        !effect.thread_id.is_empty()
            && effect.sequence > 0
            && checkpoint.thread_id == effect.thread_id
            && checkpoint.state_revision == effect.sequence
            && checkpoint.history_fence == effect.sequence
            && checkpoint.state.commit_sequence == effect.sequence,
        "audience receipt requires the matching Thread effect and checkpoint"
    );
    let mut receipts = Vec::new();
    if let Some(turn) = &effect.turn
        && turn.state == TurnState::Running
    {
        // The production owner changes a Turn to Running only at its actual start. Restart settles
        // Running to Interrupted; subsequent model progress does not create another Running effect.
        ensure!(
            !turn.turn_id.is_empty()
                && turn.model_steps == 0
                && turn.elapsed_ms.is_none()
                && checkpoint.state.turns.iter().any(|current| current == turn),
            "Turn start effect does not match its transfer checkpoint"
        );
        let receipt = TurnStartReceipt {
            version: FORMAT_VERSION,
            thread_id: effect.thread_id.clone(),
            turn_id: turn.turn_id.clone(),
            input_id: turn.input_id.clone(),
            sequence: effect.sequence,
        };
        receipts.push(FactReceiptWrite {
            item_id: receipt_id(TURN_START_RECEIPT, &turn.turn_id),
            revision: RECEIPT_REVISION,
            kind: TURN_START_RECEIPT,
            payload: serde_json::to_string(&receipt)?,
        });
    }
    for change in effect.extensions.iter() {
        match change {
            ExtensionChange::Put { id, record } if id == AUDIENCE_START_EXTENSION => {
                ensure!(
                    record.revision > 0 && checkpoint.state.extensions.get(id) == Some(record),
                    "audience start extension does not match its transfer checkpoint"
                );
                let intent = AudienceStartIntent::decode(&record.payload)?;
                ensure!(
                    intent.thread_id == effect.thread_id,
                    "audience start belongs to another Thread"
                );
                let owner = super::model_route::verified_bot_owner(None, Some(&checkpoint.state))?;
                ensure!(
                    owner.as_deref() == Some(intent.authorization.bot_id.as_str()),
                    "audience start differs from the frozen bot owner"
                );
                let mut running = checkpoint
                    .state
                    .turns
                    .iter()
                    .filter(|turn| turn.state == TurnState::Running);
                let excluded_turn_id = running.next().map(|turn| turn.turn_id.clone());
                ensure!(
                    running.next().is_none(),
                    "audience cut has more than one running Turn"
                );
                let receipt = AudienceStartReceipt {
                    version: FORMAT_VERSION,
                    intent,
                    extension_revision: record.revision,
                    sequence: effect.sequence,
                    excluded_turn_id,
                };
                receipts.push(FactReceiptWrite {
                    item_id: receipt.intent.receipt_id(),
                    revision: RECEIPT_REVISION,
                    kind: AUDIENCE_START_RECEIPT,
                    payload: serde_json::to_string(&receipt)?,
                });
            }
            ExtensionChange::Delete { id, .. } if id == AUDIENCE_START_EXTENSION => {
                anyhow::bail!("audience start slot cannot be deleted");
            }
            ExtensionChange::Put { .. } | ExtensionChange::Delete { .. } => {}
        }
    }
    Ok(receipts)
}
