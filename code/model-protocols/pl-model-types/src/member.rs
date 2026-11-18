use serde::{Deserialize, Serialize};
/// The provider's explicit terminal state, independent from the enclosing attempt outcome.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ModelMemberState {
    Completed,
    Interrupted,
}
