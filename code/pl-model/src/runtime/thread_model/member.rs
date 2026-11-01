//! Model-owned encoding for an independently ended presentation member.
use pl_core::model::{ModelCompletedMember, ModelError, ModelFailureKind};
use serde::{Deserialize, Serialize};

use crate::completion::CompletionPresentationItem;

pub(crate) const MEMBER_RECEIPT_FORMAT: &str = "pl.model.completed-member";
pub(crate) const MEMBER_RECEIPT_VERSION: u32 = 1;

/// The provider's explicit terminal state, independent from the enclosing attempt outcome.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ModelMemberState {
    Completed,
    Interrupted,
}

/// The same normalized member retained for the final response, without context or usage advancement.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelMemberReceipt {
    pub item: CompletionPresentationItem,
    pub state: ModelMemberState,
}

impl ModelMemberReceipt {
    pub(crate) fn encode(
        item: &CompletionPresentationItem,
        state: ModelMemberState,
    ) -> Result<pl_core::context::OpaquePayload, serde_json::Error> {
        // Borrow the accumulator's frozen member. Encoding the reliable envelope must not retain
        // another owned presentation body beside the canonical final/failure member.
        #[derive(Serialize)]
        struct ReceiptRef<'a> {
            item: &'a CompletionPresentationItem,
            state: ModelMemberState,
        }
        Ok(pl_core::context::OpaquePayload::new(
            MEMBER_RECEIPT_FORMAT,
            MEMBER_RECEIPT_VERSION,
            serde_json::to_string(&ReceiptRef { item, state })?,
        )
        .expect("static member format"))
    }
}

/// Decodes only this producer's current member format and verifies its real outer identity.
///
/// # Errors
/// Unknown formats remain explicit; malformed contents and identity conflicts are not empty output.
pub fn model_member_receipt(
    member: &ModelCompletedMember,
) -> Result<ModelMemberReceipt, ModelError> {
    if member.payload.format() != MEMBER_RECEIPT_FORMAT
        || member.payload.version() != MEMBER_RECEIPT_VERSION
    {
        return Err(super::failure(
            ModelFailureKind::UnsupportedContent,
            std::io::Error::other("unsupported model member receipt"),
        ));
    }
    let receipt: ModelMemberReceipt = serde_json::from_str(member.payload.content())
        .map_err(|source| super::failure(ModelFailureKind::InvalidResponse, source))?;
    if receipt.item.provider_item_id.is_empty() || receipt.item.provider_item_id != member.member_id
    {
        return Err(super::failure(
            ModelFailureKind::InvalidResponse,
            std::io::Error::other("model member receipt differs from its admitted identity"),
        ));
    }
    Ok(receipt)
}
