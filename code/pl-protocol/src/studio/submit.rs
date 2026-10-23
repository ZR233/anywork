//! Prompt admission results keep dispatch certainty separate from error classification.
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::{StudioCommandReceipt, StudioError};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SubmitPromptReceipt {
    pub thread_id: String,
    pub input_id: String,
    pub cursor: u64,
    pub request_digest: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", deny_unknown_fields)]
pub enum SubmitPromptOutcome {
    Returned { value: SubmitPromptReceipt },
    Rejected { error: StudioError },
    UnknownOutcome { error: StudioError },
    CommittedButUnobserved { receipt: StudioCommandReceipt, error: StudioError },
    ConfirmedWithoutReceipt { error: StudioError },
}
