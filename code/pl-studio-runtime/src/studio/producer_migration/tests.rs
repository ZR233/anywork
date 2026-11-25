use super::normalize;
use crate::studio::thread_projection::billing_facts;
use pl_core::thread::ThreadEffectBatch;
use pl_core::thread::extensions::{ExtensionChange, ExtensionRecord};

/// 最小 effect batch：只携带扩展变更，用于走真实 `billing_facts` 入口。
fn batch(extension_id: &str, payload: pl_core::context::OpaquePayload) -> ThreadEffectBatch {
    ThreadEffectBatch {
        committed_at: 42,
        permissions: Default::default(),
        wake_messages_through: None,
        inputs: Default::default(),
        continuations: Default::default(),
        tasks: Default::default(),
        thread_id: "thread".into(),
        sequence: 1,
        context: None,
        private_context: None,
        attempt: None,
        model_members: Default::default(),
        model_member_starts: Default::default(),
        model_member_content_available: Default::default(),
        model_connection_events: Default::default(),
        context_compactions: Default::default(),
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
    let payload =
        pl_core::context::OpaquePayload::new("pl.studio.auxiliary-billing", 1, LEGACY_AUX_BUDGET)
            .unwrap();
    assert!(billing_facts(&batch("studio.auxiliary-billing.title", payload.clone())).is_err());
    let payload = normalize(&payload).unwrap().unwrap();
    let facts = billing_facts(&batch("studio.auxiliary-billing.title", payload)).unwrap();
    assert_eq!(facts.len(), 1);
    let record = &facts[0].record;
    assert_eq!(record.account_id, "deepseek");
    assert_eq!(record.account_display_name.as_deref(), Some("DeepSeek"));
    // 配置模型只来自冻结观察；旧 `model`（发送模型）不得冒充。
    assert_eq!(record.model_id.as_deref(), Some("deepseek-flash"));
    assert_eq!(record.effort.as_deref(), Some("high"));
    assert_eq!(record.requested_service_tier, None);
    assert_eq!(record.context_window, Some(128_000));
    assert_eq!(record.prompt_generation, Some(3));
    assert_eq!(
        record.prefix_changed_reason,
        Some(crate::PromptPrefixChangedReason::AccountChanged)
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
    let payload = normalize(&payload).unwrap().unwrap();
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
        pl_core::context::OpaquePayload::new("pl.studio.compaction", 1, LEGACY_COMPACTION).unwrap();
    assert!(billing_facts(&batch("studio.compaction.latest", payload.clone())).is_err());
    let payload = normalize(&payload).unwrap().unwrap();
    let facts = billing_facts(&batch("studio.compaction.latest", payload)).unwrap();
    assert_eq!(facts.len(), 1);
    let record = &facts[0].record;
    assert_eq!(record.account_id, "deepseek");
    // binding.requestedModel 是冻結的目录配置模型。
    assert_eq!(record.model_id.as_deref(), Some("deepseek-flash"));
    assert_eq!(record.effort.as_deref(), Some("high"));
    assert_eq!(record.requested_service_tier, None);
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
