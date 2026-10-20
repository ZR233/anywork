use serde::{Deserialize, Serialize};

use super::super::AccountUsageData;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadyAccountUsage {
    data: AccountUsageData,
}

impl ReadyAccountUsage {
    pub fn new(data: AccountUsageData) -> Self {
        Self { data }
    }

    pub fn data(&self) -> &AccountUsageData {
        &self.data
    }

    pub fn into_data(self) -> AccountUsageData {
        self.data
    }
}
