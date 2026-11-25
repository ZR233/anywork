//! Billing uses producer receipts and committed timestamps, never current pricing.
use crate::InferenceBillingRecord;
use anyhow::Result;
use pl_core::thread::{AttemptOutcome, ThreadEffectBatch, journal::AttemptUpdate};

#[derive(serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AuxiliaryBillingReceipt {
    pub billing: InferenceBillingRecord,
    pub succeeded: bool,
}

impl AuxiliaryBillingReceipt {
    /// v4 retains explicit first-content provenance without inventing historical timing.
    pub(crate) const VERSION: u32 = 4;

    pub(crate) fn into_payload(self) -> Result<pl_core::context::OpaquePayload> {
        Ok(pl_core::context::OpaquePayload::new(
            "pl.studio.auxiliary-billing",
            Self::VERSION,
            serde_json::to_string(&self)?,
        )?)
    }
}

#[derive(Debug, Clone)]
pub(in crate::studio) struct BillingFact {
    pub status: super::super::storage::calls::CallStatus,
    pub record: InferenceBillingRecord,
    pub auxiliary: bool,
}

pub(in crate::studio) fn billing_facts(commit: &ThreadEffectBatch) -> Result<Vec<BillingFact>> {
    let mut facts = Vec::new();
    for change in commit.extensions.iter() {
        if let pl_core::thread::extensions::ExtensionChange::Put { record, .. } = change
            && record.payload.format() == "pl.studio.auxiliary-billing"
        {
            let receipt =
                decode_auxiliary_receipt(record.payload.version(), record.payload.content())?;
            facts.push(BillingFact {
                status: if receipt.succeeded {
                    super::super::storage::calls::CallStatus::Committed
                } else {
                    super::super::storage::calls::CallStatus::Failed
                },
                record: receipt.billing,
                auxiliary: true,
            });
        }
        if let pl_core::thread::extensions::ExtensionChange::Put { record, .. } = change
            && record.payload.format() == "pl.studio.compaction"
        {
            // 生产端拥有版本化解码；投影只消费当前语义。
            let receipt = crate::context_preparation::decode_receipt(
                record.payload.version(),
                record.payload.content(),
            )?;
            let status = if receipt.error.is_none() {
                super::super::storage::calls::CallStatus::Committed
            } else {
                super::super::storage::calls::CallStatus::Failed
            };
            let billing = InferenceBillingRecord {
                inference_id: receipt.inference_id,
                purpose: Some(receipt.binding.purpose),
                account_id: receipt.binding.account_id.clone(),
                // 辅助调用没有账号显示名快照；显示名不参与统计归组。
                account_display_name: None,
                // 冻结的目录配置模型，不用发送模型冒充。
                model_id: Some(receipt.binding.model_id.clone()),
                model_observation: receipt.model_observation,
                effort: receipt.reasoning_effort,
                requested_service_tier: receipt.requested_service_tier,
                context_window: receipt.context_window,
                accounting: receipt.accounting,
                prompt_generation: None,
                prompt_cache_policy: None,
                prefix_changed_reason: None,
                orchestration: Default::default(),
                timing: receipt.timing,
                recorded_at: commit.committed_at,
            };
            facts.push(BillingFact {
                record: billing,
                status,
                auxiliary: true,
            });
        }
    }
    if let Some(attempt) = &commit.attempt
        && let Some(record) = attempt_billing(attempt, commit.committed_at)?
    {
        facts.push(BillingFact {
            record,
            status: match &attempt.outcome {
                AttemptOutcome::Committed(_) => super::super::storage::calls::CallStatus::Committed,
                AttemptOutcome::Rejected { .. } => {
                    super::super::storage::calls::CallStatus::Rejected
                }
                AttemptOutcome::Cancelled { .. } => {
                    super::super::storage::calls::CallStatus::Cancelled
                }
                AttemptOutcome::Interrupted => {
                    super::super::storage::calls::CallStatus::Interrupted
                }
                _ => super::super::storage::calls::CallStatus::Failed,
            },
            auxiliary: false,
        });
    }
    let mut attempts = Vec::new();
    for fact in facts {
        append_transport_attempts(&mut attempts, fact);
    }
    Ok(attempts)
}

/// Derives one billing fact per paid transport attempt from the model-owned receipt.
/// Failed generations are auxiliary to context/throughput, but remain real requests for
/// consumption and cost statistics. The terminal generation keeps the original call ID.
fn append_transport_attempts(facts: &mut Vec<BillingFact>, mut terminal: BillingFact) {
    let retries = std::mem::take(&mut terminal.record.accounting.retry_attempts);
    terminal.record.orchestration.transport_attempts = terminal
        .record
        .orchestration
        .transport_attempts
        .saturating_sub(retries.len() as u64);
    for (ordinal, accounting) in retries.into_iter().enumerate() {
        let mut record = terminal.record.clone();
        record.inference_id = format!("{}:transport-retry:{ordinal}", record.inference_id);
        record.accounting = accounting;
        // Only the terminal response owns this model observation and clock.
        record.model_observation = None;
        record.timing = None;
        record.orchestration = Default::default();
        record.orchestration.transport_attempts = 1;
        append_transport_attempts(
            facts,
            BillingFact {
                status: super::super::storage::calls::CallStatus::Failed,
                record,
                auxiliary: true,
            },
        );
    }
    facts.push(terminal);
}

fn attempt_billing(
    attempt: &AttemptUpdate,
    recorded_at: i64,
) -> Result<Option<InferenceBillingRecord>> {
    pl_model::runtime::model_attempt_billing(attempt, recorded_at).map_err(anyhow::Error::new)
}

fn decode_auxiliary_receipt(version: u32, content: &str) -> Result<AuxiliaryBillingReceipt> {
    anyhow::ensure!(
        version == AuxiliaryBillingReceipt::VERSION,
        "unsupported auxiliary billing version"
    );
    Ok(serde_json::from_str(content)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::storage::calls::CallStatus;

    #[test]
    fn retry_billing_does_not_copy_terminal_model_timing_or_double_count_transports() {
        let record: InferenceBillingRecord = serde_json::from_value(serde_json::json!({
            "inferenceId":"call", "recordedAt":100,
            "modelObservation":{"configuredModel":"configured","sentModel":"sent","reportedModel":"terminal-only"},
            "timing":{"firstOutputSource":"incremental","responseMillis":1000},
            "orchestration":{"transportAttempts":4},
            "accounting":{"usage":{"totalTokens":15},"pricing":{"kind":"noCharge"},
                "retryAttempts":[
                    {"usage":{"totalTokens":22},"pricing":{"kind":"noCharge"}},
                    {"usage":{"totalTokens":23},"pricing":{"kind":"noCharge"}}
                ]
            }
        })).unwrap();
        let mut facts = Vec::new();
        append_transport_attempts(
            &mut facts,
            BillingFact {
                record,
                status: CallStatus::Committed,
                auxiliary: false,
            },
        );
        assert_eq!(facts.len(), 3);
        assert!(facts[..2].iter().all(|fact| fact.auxiliary
            && fact.status == CallStatus::Failed
            && fact.record.model_observation.is_none()
            && fact.record.timing.is_none()));
        assert!(!facts[2].auxiliary);
        assert_eq!(facts[2].record.inference_id, "call");
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
            4
        );
    }
}
