use anyhow::Result;

use super::super::StudioRuntime;

impl StudioRuntime {
    pub async fn check_account_usage(&self, account_id: &str) -> Result<()> {
        self.account_usage.check(account_id).await
    }
}
