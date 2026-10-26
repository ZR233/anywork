use super::super::StudioRuntime;
use anyhow::Result;
use pl_protocol::products::read::account_usage::AccountUsageCheckResult;
use std::future::Future;

impl StudioRuntime {
    /// Expected identity is checked by the original query owner before network work and merge.
    /// Its returned snapshot is the command's own result, never a subsequent latest read.
    pub fn check_account_usage_cas(
        &self,
        account_id: String,
        expected_usage_query_revision: u64,
    ) -> impl Future<Output = Result<AccountUsageCheckResult>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime
                .account_usage
                .check_expected(&account_id, expected_usage_query_revision)
                .await?;
            let target = super::AccountUsageReadTarget {
                origin: runtime.usage_source.origin().clone(),
                reference: material.reference,
            };
            Ok(AccountUsageCheckResult {
                target,
                account_id,
                usage_query_revision: expected_usage_query_revision,
            })
        })
    }
}
