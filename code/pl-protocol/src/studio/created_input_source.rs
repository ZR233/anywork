use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

/// Actual original creation projection identity, paired with the accepted input receipt.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CreatedInputExecutionIdentity {
    pub thread_id: String,
    pub input_id: String,
    pub runtime_epoch: String,
    pub incarnation: u64,
}
