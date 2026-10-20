//! 单个 provider usage 的精确状态 payload。

mod failed;
mod missing_credential;
mod ready;
mod unsupported;

pub use failed::FailedAccountUsage;
pub use missing_credential::MissingCredentialAccountUsage;
pub use ready::ReadyAccountUsage;
pub use unsupported::UnsupportedAccountUsage;

use serde::{Deserialize, Serialize};

use super::AccountUsageData;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum AccountUsageState {
    Unsupported(UnsupportedAccountUsage),
    MissingCredential(MissingCredentialAccountUsage),
    Ready(ReadyAccountUsage),
    Failed(FailedAccountUsage),
}

impl AccountUsageState {
    pub fn unsupported() -> Self {
        Self::Unsupported(UnsupportedAccountUsage)
    }

    pub fn missing_credential(message: impl Into<String>) -> Self {
        Self::MissingCredential(MissingCredentialAccountUsage::new(message))
    }

    pub fn ready(data: AccountUsageData) -> Self {
        Self::Ready(ReadyAccountUsage::new(data))
    }

    pub fn failed(error: pl_protocol::StateError) -> Self {
        Self::Failed(FailedAccountUsage::new(error))
    }
}
