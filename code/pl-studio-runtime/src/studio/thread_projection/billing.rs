//! Billing uses producer receipts and committed timestamps, never current pricing.
use crate::InferenceBillingRecord;
use anyhow::Result;
use pl_core::model::ModelSubAttemptSettlement;
use pl_core::thread::ThreadEffectBatch;

#[derive(Debug, Clone)]
pub(in crate::studio) struct BillingFact {
    pub status: super::super::storage::calls::CallStatus,
    pub record: InferenceBillingRecord,
    pub auxiliary: bool,
    pub turn_id: Option<String>,
    pub settlement: pl_core::context::OpaquePayload,
}

fn sub_attempt_fact(settlement: &ModelSubAttemptSettlement) -> Result<BillingFact> {
    use super::super::storage::calls::CallStatus;
    use pl_model::completion::InferenceAttemptOutcome;
    let receipt = pl_model::runtime::model_sub_attempt_receipt(settlement)?;
    let metadata = receipt
        .billing
        .attempt
        .as_ref()
        .expect("validated settlement metadata");
    Ok(BillingFact {
        status: match metadata.outcome {
            InferenceAttemptOutcome::Succeeded => CallStatus::Committed,
            InferenceAttemptOutcome::Failed => CallStatus::Failed,
            InferenceAttemptOutcome::Cancelled => CallStatus::Cancelled,
        },
        turn_id: settlement.turn_id.clone(),
        settlement: settlement.payload.clone(),
        auxiliary: matches!(
            receipt.billing.purpose.as_deref(),
            Some("title" | "review" | "compaction")
        ),
        record: receipt.billing,
    })
}

pub(in crate::studio) fn billing_facts(commit: &ThreadEffectBatch) -> Result<Vec<BillingFact>> {
    commit
        .model_sub_attempt_settlements
        .iter()
        .map(sub_attempt_fact)
        .collect()
}
