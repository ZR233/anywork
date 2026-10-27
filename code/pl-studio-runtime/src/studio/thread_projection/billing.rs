//! Billing uses producer receipts and committed timestamps, never current pricing.
use anyhow::Result;
use pl_core::thread::{AttemptOutcome, ThreadEffectBatch, journal::AttemptUpdate};
use pl_protocol::InferenceBillingRecord;

#[derive(serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AuxiliaryBillingReceipt {
    pub billing: InferenceBillingRecord,
    pub succeeded: bool,
}

impl AuxiliaryBillingReceipt {
    /// v3 adds explicit no-charge accounting, without reinterpreting older Disabled records.
    pub(crate) const VERSION: u32 = 3;

    pub(crate) fn into_payload(self) -> Result<pl_core::context::OpaquePayload> {
        Ok(pl_core::context::OpaquePayload::new(
            "pl.studio.auxiliary-billing",
            Self::VERSION,
            serde_json::to_string(&self)?,
        )?)
    }
}

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
            let receipt = crate::compaction::decode_receipt(
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
                context_window: receipt.context_window,
                accounting: receipt.accounting,
                prompt_generation: None,
                prompt_cache_policy: None,
                prefix_changed_reason: None,
                orchestration: Default::default(),
                timing: None,
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
                _ => super::super::storage::calls::CallStatus::Failed,
            },
            auxiliary: false,
        });
    }
    Ok(facts)
}

fn attempt_billing(
    attempt: &AttemptUpdate,
    recorded_at: i64,
) -> Result<Option<InferenceBillingRecord>> {
    pl_model::runtime::model_attempt_billing(attempt, recorded_at).map_err(anyhow::Error::new)
}

/// Current-only auxiliary receipt projection boundary.
pub(super) fn decode_auxiliary_receipt_for_projection(
    version: u32,
    content: &str,
) -> Result<AuxiliaryBillingReceipt> {
    decode_auxiliary_receipt(version, content)
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
    use pl_core::thread::ThreadEffectBatch;
    use pl_core::thread::extensions::{ExtensionChange, ExtensionRecord};

    /// 最小 effect batch：只携带扩展变更，用于走真实 `billing_facts` 入口。
    fn batch(extension_id: &str, payload: pl_core::context::OpaquePayload) -> ThreadEffectBatch {
        ThreadEffectBatch {
            committed_at: 42,
            permissions: Default::default(),
            wake_messages_through: None,
            inputs: Default::default(),
            tasks: Default::default(),
            thread_id: "thread".into(),
            sequence: 1,
            context: None,
            private_context: None,
            attempt: None,
            turn: None,
            discovered_tools: None,
            deliveries: Default::default(),
            delivery_repairs: Default::default(),
            extensions: vec![ExtensionChange::Put {
                id: extension_id.into(),
                record: ExtensionRecord {
                    revision: 1,
                    payload,
                },
            }]
            .into(),
            inbox: Default::default(),
            consumed_messages: None,
            interactions: Default::default(),
            replacements: Default::default(),
            runtime_facts: None,
            lifecycle: None,
        }
    }

    /// HEAD 真实 v1 辅助计费载荷（camelCase，含 provider 展示名与冻结观察）。
    const LEGACY_AUX_BUDGET: &str = r#"{
        "billing": {
            "inferenceId": "title-call",
            "purpose": "title",
            "providerInstanceId": "deepseek",
            "provider": "DeepSeek",
            "model": "deepseek-flash-sent",
            "modelObservation": {
                "configuredModel": "deepseek-flash",
                "sentModel": "deepseek-flash-sent",
                "reportedModel": null
            },
            "reasoningEffort": "high",
            "contextWindow": 128000,
            "accounting": {
                "usage": { "inputTokens": 10, "outputTokens": 20, "cacheReadTokens": 0, "cacheWriteTokens": 0, "reasoningTokens": 0, "totalTokens": 30 },
                "pricing": { "kind": "estimated", "cost": { "currency": "USD", "amount": 1.5 }, "cacheSavings": null },
                "priceSnapshot": null,
                "requestStartedAt": null
            },
            "promptGeneration": 3,
            "promptCachePolicy": "implicit_prefix",
            "prefixChangedReason": "providerChanged",
            "recordedAt": 100
        },
        "succeeded": true
    }"#;

    #[test]
    fn auxiliary_billing_v1_converts_account_identity_and_keeps_frozen_facts() {
        let payload = pl_core::context::OpaquePayload::new(
            "pl.studio.auxiliary-billing",
            1,
            LEGACY_AUX_BUDGET,
        )
        .unwrap();
        assert!(billing_facts(&batch("studio.auxiliary-billing.title", payload.clone())).is_err());
        let payload = crate::studio::producer_migration::normalize(&payload)
            .unwrap()
            .unwrap();
        let facts = billing_facts(&batch("studio.auxiliary-billing.title", payload)).unwrap();
        assert_eq!(facts.len(), 1);
        let record = &facts[0].record;
        assert_eq!(record.account_id, "deepseek");
        assert_eq!(record.account_display_name.as_deref(), Some("DeepSeek"));
        // 配置模型只来自冻结观察；旧 `model`（发送模型）不得冒充。
        assert_eq!(record.model_id.as_deref(), Some("deepseek-flash"));
        assert_eq!(record.effort.as_deref(), Some("high"));
        assert_eq!(record.context_window, Some(128_000));
        assert_eq!(record.prompt_generation, Some(3));
        assert_eq!(
            record.prefix_changed_reason,
            Some(pl_protocol::PromptPrefixChangedReason::AccountChanged)
        );
        assert_eq!(record.accounting.usage.output_tokens, Some(20));
        let cost = record
            .accounting
            .estimated_costs()
            .into_iter()
            .next()
            .unwrap();
        assert_eq!(cost.amount, 1.5);
        assert!(facts[0].auxiliary);
    }

    #[test]
    fn auxiliary_billing_v1_without_observation_keeps_configured_model_unknown() {
        let legacy = LEGACY_AUX_BUDGET
            .replace(
                r#""modelObservation": {
                "configuredModel": "deepseek-flash",
                "sentModel": "deepseek-flash-sent",
                "reportedModel": null
            },"#,
                "",
            )
            .replace(
                r#""reasoningEffort": "high","#,
                r#""reasoningEffort": null,"#,
            );
        let payload =
            pl_core::context::OpaquePayload::new("pl.studio.auxiliary-billing", 1, legacy).unwrap();
        assert!(billing_facts(&batch("studio.auxiliary-billing.title", payload.clone())).is_err());
        let payload = crate::studio::producer_migration::normalize(&payload)
            .unwrap()
            .unwrap();
        let facts = billing_facts(&batch("studio.auxiliary-billing.title", payload)).unwrap();
        let record = &facts[0].record;
        assert!(
            record.model_id.is_none(),
            "sent model never becomes configured"
        );
        assert_eq!(record.account_id, "deepseek");
    }

    /// HEAD 真实 v1 压缩回执载荷（camelCase binding）。
    const LEGACY_COMPACTION: &str = r#"{
        "inferenceId": "compact-call",
        "binding": {
            "providerInstanceId": "deepseek",
            "requestedModel": "deepseek-flash",
            "adapter": "deepSeek",
            "protocol": "responses",
            "isolation": "binding-namespace",
            "purpose": "compaction",
            "contextWindow": 128000,
            "maxContextWindow": 200000,
            "autoCompactLimit": 115200
        },
        "reasoningEffort": "high",
        "contextWindow": 128000,
        "turnId": "turn",
        "accounting": {
            "usage": { "inputTokens": 1, "outputTokens": 2, "cacheReadTokens": 0, "cacheWriteTokens": 0, "reasoningTokens": 0, "totalTokens": 3 },
            "pricing": { "kind": "estimated", "cost": { "currency": "USD", "amount": 0.25 }, "cacheSavings": null },
            "priceSnapshot": null,
            "requestStartedAt": null
        },
        "modelObservation": null,
        "implementation": null,
        "error": null
    }"#;

    #[test]
    fn compaction_receipt_v1_converts_legacy_binding_into_current_account_semantics() {
        let payload =
            pl_core::context::OpaquePayload::new("pl.studio.compaction", 1, LEGACY_COMPACTION)
                .unwrap();
        assert!(billing_facts(&batch("studio.compaction.latest", payload.clone())).is_err());
        let payload = crate::studio::producer_migration::normalize(&payload)
            .unwrap()
            .unwrap();
        let facts = billing_facts(&batch("studio.compaction.latest", payload)).unwrap();
        assert_eq!(facts.len(), 1);
        let record = &facts[0].record;
        assert_eq!(record.account_id, "deepseek");
        // binding.requestedModel 是冻結的目录配置模型。
        assert_eq!(record.model_id.as_deref(), Some("deepseek-flash"));
        assert_eq!(record.effort.as_deref(), Some("high"));
        assert_eq!(record.context_window, Some(128_000));
        assert_eq!(record.accounting.usage.output_tokens, Some(2));
        assert!(facts[0].auxiliary);
    }

    #[test]
    fn unsupported_auxiliary_versions_fail_without_guessing() {
        let payload =
            pl_core::context::OpaquePayload::new("pl.studio.auxiliary-billing", 9, "{}").unwrap();
        assert!(billing_facts(&batch("studio.auxiliary-billing.title", payload)).is_err());
    }
}
