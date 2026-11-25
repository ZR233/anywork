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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::storage::calls::CallStatus;

    #[test]
    fn retry_billing_does_not_copy_terminal_model_timing_or_double_count_transports() {
        let settlements = [(0, "failed", 22), (1, "failed", 23), (2, "succeeded", 15)]
            .into_iter().map(|(generation, outcome, total)| {
                let mut billing = serde_json::json!({
                    "inferenceId": pl_model::runtime::model_sub_attempt_id("call", generation), "recordedAt":100,
                    "purpose":"turn", "orchestration":{"transportAttempts":1},
                    "attempt":{"logicalRequestId":"call","coreAttemptId":"call","generation":generation,
                        "stage":"stream","outcome":outcome,"usageIsTerminal":true},
                    "accounting":{"usage":{"totalTokens":total},"pricing":{"kind":"noCharge"}}
                });
                if outcome == "succeeded" {
                    billing["modelObservation"] = serde_json::json!({"configuredModel":"configured","sentModel":"sent","reportedModel":"terminal-only"});
                    billing["timing"] = serde_json::json!({"firstOutputSource":"incremental","responseMillis":1000});
                }
                ModelSubAttemptSettlement {
                    turn_id: None, attempt_id:"call".into(), generation,
                    payload: pl_core::context::OpaquePayload::new("pl.model.sub-attempt-settlement", 2,
                        serde_json::json!({"attemptId":"call","logicalRequestId":"call","generation":generation,
                            "retry":generation,"billing":billing}).to_string()).unwrap(),
                }
            }).collect::<Vec<_>>();
        let facts = billing_facts(&ThreadEffectBatch {
            model_sub_attempt_settlements: settlements.into(),
            ..Default::default()
        })
        .unwrap();
        assert_eq!(facts.len(), 3);
        assert!(
            facts[..2]
                .iter()
                .all(|fact| fact.status == CallStatus::Failed
                    && fact.record.model_observation.is_none()
                    && fact.record.timing.is_none())
        );
        assert!(!facts[2].auxiliary);
        assert_eq!(
            facts[2].record.inference_id,
            pl_model::runtime::model_sub_attempt_id("call", 2)
        );
        assert_eq!(
            facts[2]
                .record
                .model_observation
                .as_ref()
                .unwrap()
                .reported_model
                .as_deref(),
            Some("terminal-only")
        );
        assert_eq!(facts[2].record.timing.unwrap().response_millis, 1000);
        assert_eq!(
            facts
                .iter()
                .map(|fact| fact.record.orchestration.transport_attempts)
                .sum::<u64>(),
            3
        );
    }
}
