//! Producer-owned model binding migration and account identity through public API only.
use pl_core::context::OpaquePayload;
use pl_model::model::ModelInfo;
use pl_model::runtime::migration::migrate_payload;
use pl_model::{
    config::ModelRouteConfig,
    protocol::{ProtocolEndpoint, ProtocolKind, WireApi},
    runtime::{ModelRuntime, model_failure_receipt, model_request_receipt, model_response_receipt},
};
use serde_json::json;

fn current(payload: &OpaquePayload) -> OpaquePayload {
    migrate_payload(payload)
        .expect("producer migration succeeds")
        .unwrap_or_else(|| payload.clone())
}

fn legacy_binding() -> serde_json::Value {
    json!({
        "providerInstanceId": "deepseek",
        "requestedModel": "deepseek-v4-pro",
        "adapter": "deepSeek",
        "protocol": "responses",
        "isolation": "binding:stable-namespace",
        "purpose": "turn",
        "contextWindow": 128000,
        "maxContextWindow": 128000,
        "autoCompactLimit": 100000
    })
}

fn legacy_request_payload(version: u32) -> OpaquePayload {
    legacy_request_content(version, serde_json::Value::Null)
}

fn legacy_request_with_prompt(version: u32) -> OpaquePayload {
    legacy_request_content(
        version,
        json!({
            "scope": "turn",
            "generation": 7,
            "provider": "Display Name That Is Not An Account",
            "providerHash": "sha256:legacy-fingerprint",
            "model": "deepseek-v4-pro",
            "fixedPrefixHash": "fixed-prefix",
            "fixedPrefixSectionHashes": {"instructions": "section-hash"},
            "requestPropertiesHash": "request-properties",
            "toolSchemaHash": "tool-schema",
            "contextHash": "context-hash",
            "promptCachePolicy": "implicitPrefix",
            "prefixChangedReason": "providerChanged",
            "updatedAt": 1234
        }),
    )
}

fn legacy_request_content(version: u32, prompt: serde_json::Value) -> OpaquePayload {
    let content = json!({
        "binding": legacy_binding(),
        "tools": [],
        "toolChoice": "auto",
        "parallelToolCalls": false,
        "reasoning": null,
        "temperature": null,
        "maxTokens": null,
        "prompt": prompt
    })
    .to_string();
    OpaquePayload::new("pl.model.prepared-request", version, content).expect("payload is valid")
}

fn legacy_accounting() -> serde_json::Value {
    json!({
        "usage": {
            "inputTokens": null,
            "outputTokens": null,
            "cacheReadTokens": null,
            "cacheWriteTokens": null,
            "reasoningTokens": null,
            "totalTokens": null
        },
        "pricing": { "kind": "disabled" },
        "priceSnapshot": null,
        "requestStartedAt": null
    })
}

fn legacy_frame_payload(version: u32) -> OpaquePayload {
    let content = json!({
        "receipt": {
            "binding": legacy_binding(),
            "response": {
                "content": null,
                "reasoningContent": null,
                "model": "deepseek-v4-pro",
                "accounting": legacy_accounting()
            }
        },
        "bindings": [],
        "compatibilityFamily": null
    })
    .to_string();
    OpaquePayload::new("pl.model.assistant", version, content).expect("payload is valid")
}

#[test]
fn legacy_prepared_request_keeps_frozen_source_and_identity() {
    assert!(model_request_receipt(&legacy_request_with_prompt(1)).is_err());
    let receipt = model_request_receipt(&current(&legacy_request_with_prompt(1)))
        .expect("legacy record with its real non-empty prompt migrates");
    assert_eq!(receipt.binding.account_id, "deepseek");
    assert_eq!(receipt.binding.model_id, "deepseek-v4-pro");
    assert_eq!(receipt.binding.protocol, ProtocolKind::DeepSeek);
    assert_eq!(receipt.binding.wire_api, WireApi::Responses);
    // The stored isolation namespace is a frozen fact and must survive the field rename.
    assert_eq!(receipt.binding.isolation, "binding:stable-namespace");
    assert_eq!(receipt.binding.context_window, Some(128_000));
    assert_eq!(receipt.binding.auto_compact_limit, Some(100_000));

    // The stable ID comes from the receipt's own binding, never from the old display name.
    let prompt = receipt.prompt.expect("legacy prompt is preserved");
    assert_eq!(prompt.account_id, "deepseek");
    assert_ne!(prompt.account_id, "Display Name That Is Not An Account");
    // The legacy fingerprint value is preserved verbatim; the next current pass rotates it.
    assert_eq!(prompt.account_hash, "sha256:legacy-fingerprint");
    assert_eq!(prompt.scope, "turn");
    assert_eq!(prompt.generation, 7);
    assert_eq!(prompt.model_id, "deepseek-v4-pro");
    assert_eq!(prompt.fixed_prefix_hash, "fixed-prefix");
    assert_eq!(
        prompt.fixed_prefix_section_hashes["instructions"],
        "section-hash"
    );
    assert_eq!(prompt.request_properties_hash, "request-properties");
    assert_eq!(prompt.tool_schema_hash, "tool-schema");
    assert_eq!(prompt.context_hash, "context-hash");
    assert_eq!(prompt.prompt_cache_policy, "implicitPrefix");
    assert_eq!(
        prompt.prefix_changed_reason,
        pl_protocol::PromptPrefixChangedReason::AccountChanged
    );
    assert_eq!(prompt.updated_at, 1234);

    // A migrated record re-serializes as current prepared-request v2 and reads back unchanged.
    let reread_payload = OpaquePayload::new(
        "pl.model.prepared-request",
        2,
        json!({
            "binding": {
                "accountId": receipt.binding.account_id,
                "modelId": receipt.binding.model_id,
                "protocol": "deep_seek",
                "wireApi": "responses",
                "isolation": receipt.binding.isolation,
                "purpose": receipt.binding.purpose,
                "contextWindow": receipt.binding.context_window,
                "maxContextWindow": receipt.binding.max_context_window,
                "autoCompactLimit": receipt.binding.auto_compact_limit
            },
            "tools": [],
            "toolChoice": receipt.tool_choice,
            "parallelToolCalls": receipt.parallel_tool_calls,
            "reasoning": null,
            "temperature": null,
            "maxTokens": null,
            "prompt": serde_json::to_value(&prompt).unwrap()
        })
        .to_string(),
    )
    .expect("payload is valid");
    let reread =
        model_request_receipt(&reread_payload).expect("current prepared-request v2 decodes");
    assert_eq!(reread.binding.account_id, "deepseek");
    assert_eq!(reread.binding.model_id, "deepseek-v4-pro");
    assert_eq!(
        serde_json::to_value(reread.prompt.expect("prompt survives")).unwrap(),
        serde_json::to_value(&prompt).unwrap()
    );
}

#[test]
fn current_prepared_request_is_read_without_legacy_fields() {
    let migrated =
        model_request_receipt(&current(&legacy_request_payload(1))).expect("legacy migrates");
    let current = OpaquePayload::new(
        "pl.model.prepared-request",
        2,
        json!({
            "binding": {
                "accountId": migrated.binding.account_id,
                "modelId": migrated.binding.model_id,
                "protocol": "deep_seek",
                "wireApi": "responses",
                "isolation": migrated.binding.isolation,
                "purpose": "turn",
                "contextWindow": 128000,
                "maxContextWindow": 128000,
                "autoCompactLimit": 100000
            },
            "tools": [],
            "toolChoice": "auto",
            "parallelToolCalls": false,
            "reasoning": null,
            "temperature": null,
            "maxTokens": null,
            "prompt": null
        })
        .to_string(),
    )
    .expect("payload is valid");
    let receipt = model_request_receipt(&current).expect("current record decodes");
    assert_eq!(receipt.binding.account_id, migrated.binding.account_id);
    assert_eq!(receipt.binding.model_id, migrated.binding.model_id);
    assert_eq!(receipt.binding.protocol, ProtocolKind::DeepSeek);
    assert_eq!(receipt.binding.wire_api, WireApi::Responses);
}

#[test]
fn unknown_prepared_request_versions_fail_closed() {
    assert!(model_request_receipt(&legacy_request_payload(98)).is_err());
    assert!(model_request_receipt(&legacy_request_payload(99)).is_err());
}

#[test]
fn legacy_assistant_frame_migrates_its_binding() {
    let legacy = legacy_frame_payload(2);
    let output = pl_core::model::ModelStepOutput {
        content: vec![pl_core::context::ContextContent::Opaque { payload: legacy }],
        attempt_id: "old".into(),
        base_context_revision: 0,
        tool_calls: vec![],
        private_context: None,
        usage: Default::default(),
    };
    assert!(model_response_receipt(&output).is_err());
    let output = pl_core::model::ModelStepOutput {
        attempt_id: "attempt".into(),
        base_context_revision: 0,
        content: vec![pl_core::context::ContextContent::Opaque {
            payload: current(&legacy_frame_payload(2)),
        }],
        tool_calls: Vec::new(),
        private_context: None,
        usage: Default::default(),
    };
    let receipt = model_response_receipt(&output)
        .expect("legacy frame decodes")
        .expect("frame exists");
    assert_eq!(receipt.binding.account_id, "deepseek");
    assert_eq!(receipt.binding.model_id, "deepseek-v4-pro");
    assert_eq!(receipt.binding.protocol, ProtocolKind::DeepSeek);
    assert_eq!(receipt.binding.wire_api, WireApi::Responses);
    assert_eq!(receipt.binding.isolation, "binding:stable-namespace");
    assert_eq!(receipt.response.model, "deepseek-v4-pro");
    assert_eq!(
        receipt.response.accounting.pricing,
        pl_protocol::PricingOutcome::Disabled
    );
    let mut frame = json!({"receipt": &receipt, "bindings": [], "compatibilityFamily": null});
    for version in [3, 4] {
        let mut historical = output.clone();
        historical.content = vec![pl_core::context::ContextContent::Opaque {
            payload: current(
                &OpaquePayload::new("pl.model.assistant", version, frame.to_string()).unwrap(),
            ),
        }];
        let decoded = model_response_receipt(&historical).unwrap().unwrap();
        assert_eq!(decoded.response.accounting, receipt.response.accounting);
    }
    frame["receipt"]["response"]["accounting"]["pricing"] = json!({"kind":"noCharge"});
    for version in [3, 4] {
        let mut current = output.clone();
        current.content = vec![pl_core::context::ContextContent::Opaque {
            payload: OpaquePayload::new("pl.model.assistant", version, frame.to_string()).unwrap(),
        }];
        let payload = match &current.content[0] {
            pl_core::context::ContextContent::Opaque { payload } => payload,
            _ => unreachable!(),
        };
        let migrated = migrate_payload(payload);
        let decoded = migrated.and_then(|_| model_response_receipt(&current));
        if version == 3 {
            assert!(
                decoded.is_err(),
                "NoCharge is not valid in a historical frame"
            );
        } else {
            assert_eq!(
                decoded.unwrap().unwrap().response.accounting.pricing,
                pl_protocol::PricingOutcome::NoCharge
            );
        }
    }
}

#[test]
fn unknown_assistant_frame_versions_fail_closed() {
    for version in [1, 98, 99] {
        let output = pl_core::model::ModelStepOutput {
            attempt_id: "attempt".into(),
            base_context_revision: 0,
            content: vec![pl_core::context::ContextContent::Opaque {
                payload: legacy_frame_payload(version),
            }],
            tool_calls: Vec::new(),
            private_context: None,
            usage: Default::default(),
        };
        assert!(
            model_response_receipt(&output).is_err(),
            "version {version} must not be silently accepted"
        );
    }
}

#[test]
fn legacy_failure_receipts_migrate_and_unknown_versions_fail_closed() {
    let legacy = pl_core::context::OpaquePayload::new(
        "pl.model.failure",
        2,
        json!({
            "providerFailure": null,
            "message": "transport failed",
            "binding": legacy_binding(),
            "accounting": legacy_accounting(),
            "modelObservation": null,
            "presentationItems": [],
            "partialProgress": null
        })
        .to_string(),
    )
    .expect("payload is valid");
    let historical = pl_core::model::ModelError {
        details: Some(Box::new(legacy.clone())),
        kind: pl_core::model::ModelFailureKind::Unavailable,
        usage: Box::default(),
        source: None,
    };
    assert!(model_failure_receipt(&historical).is_err());
    let error = pl_core::model::ModelError {
        details: Some(Box::new(current(&legacy))),
        kind: pl_core::model::ModelFailureKind::Unavailable,
        usage: Box::default(),
        source: None,
    };
    let receipt = model_failure_receipt(&error)
        .expect("legacy failure migrates")
        .expect("receipt exists");
    assert_eq!(receipt.binding.account_id, "deepseek");
    assert_eq!(receipt.binding.model_id, "deepseek-v4-pro");
    assert_eq!(receipt.binding.isolation, "binding:stable-namespace");
    assert_eq!(receipt.message, "transport failed");
    assert_eq!(
        receipt.accounting.pricing,
        pl_protocol::PricingOutcome::Disabled
    );
    let mut current = serde_json::to_value(&receipt).unwrap();
    for version in [3, 4] {
        let historical = pl_core::model::ModelError {
            details: Some(Box::new(
                pl_model::runtime::migration::migrate_payload(
                    &OpaquePayload::new("pl.model.failure", version, current.to_string()).unwrap(),
                )
                .unwrap()
                .unwrap_or_else(|| {
                    OpaquePayload::new("pl.model.failure", version, current.to_string()).unwrap()
                }),
            )),
            kind: pl_core::model::ModelFailureKind::Unavailable,
            usage: Box::default(),
            source: None,
        };
        assert_eq!(
            model_failure_receipt(&historical)
                .unwrap()
                .unwrap()
                .accounting,
            receipt.accounting
        );
    }
    current["accounting"]["pricing"] = json!({"kind":"noCharge"});
    for version in [3, 4] {
        let frozen = pl_core::model::ModelError {
            details: Some(Box::new(
                OpaquePayload::new("pl.model.failure", version, current.to_string()).unwrap(),
            )),
            kind: pl_core::model::ModelFailureKind::Unavailable,
            usage: Box::default(),
            source: None,
        };
        let decoded = migrate_payload(frozen.details.as_ref().unwrap())
            .and_then(|_| model_failure_receipt(&frozen));
        if version == 3 {
            assert!(
                decoded.is_err(),
                "NoCharge is not valid in a historical failure receipt"
            );
        } else {
            assert_eq!(
                decoded.unwrap().unwrap().accounting.pricing,
                pl_protocol::PricingOutcome::NoCharge
            );
        }
    }

    let unknown = pl_core::context::OpaquePayload::new(
        "pl.model.failure",
        99,
        json!({ "message": "unknown" }).to_string(),
    )
    .expect("payload is valid");
    let error = pl_core::model::ModelError {
        details: Some(Box::new(unknown)),
        kind: pl_core::model::ModelFailureKind::Unavailable,
        usage: Box::default(),
        source: None,
    };
    assert!(model_failure_receipt(&error).is_err());
}

#[test]
fn runtime_requires_an_explicit_stable_account_id() {
    let endpoint =
        ProtocolEndpoint::compatible("Display name is not an identity", "http://127.0.0.1:1");
    let model = ModelInfo::compatible("model");
    assert!(ModelRuntime::new_with_account_id("  ", endpoint.clone(), model.clone()).is_err());
    let runtime = ModelRuntime::new_with_account_id("account-stable", endpoint, model)
        .expect("explicit account id is valid");
    assert_eq!(runtime.account_id(), "account-stable");
}

#[test]
fn route_selector_serializes_account_and_model_identity() {
    let route = ModelRouteConfig {
        account_id: pl_model::config::AccountId::new("deepseek").unwrap(),
        model_id: "deepseek-flash".into(),
        effort: None,
    };
    let value = serde_json::to_value(&route).unwrap();
    assert_eq!(value["account_id"], "deepseek");
    assert_eq!(value["model_id"], "deepseek-flash");
    assert!(value.get("provider").is_none());
    assert!(value.get("model").is_none());
    assert_eq!(
        route.key().unwrap(),
        pl_model::config::AccountModelKey {
            account_id: "deepseek".into(),
            model_id: "deepseek-flash".into()
        }
    );
}

#[test]
fn producer_migration_preserves_opaque_material_precision_and_is_idempotent() {
    let mut raw: serde_json::Value =
        serde_json::from_str(legacy_frame_payload(2).content()).unwrap();
    let vendor = "{ \"opaque\": 9007199254740993, \"text\": \"原始材料\" }";
    let binding = pl_core::model::ModelToolCall {
        rejection: None,
        call_id: "call-frozen".into(),
        tool_id: "tool-frozen".into(),
        arguments: OpaquePayload::new("application/json", 1, vendor).unwrap(),
    };
    raw["bindings"] = serde_json::to_value(vec![&binding]).unwrap();
    raw["receipt"]["response"]["toolCalls"] =
        serde_json::to_value(vec![pl_model::completion::ToolCall::function_raw(
            "item-frozen",
            "tool-name",
            vendor.into(),
            "call-frozen",
        )])
        .unwrap();
    raw["receipt"]["response"]["vendorExtension"] = json!({"raw": vendor});
    raw["futureNumeric"] = json!(0);
    raw["receipt"]["binding"]["futureBinding"] = json!([vendor]);
    let exact = raw.to_string().replace(
        "\"futureNumeric\":0",
        "\"futureNumeric\":123456789012345678901234567890.123456789",
    );
    let original = OpaquePayload::new("pl.model.assistant", 2, exact).unwrap();
    let upgraded = migrate_payload(&original).unwrap().unwrap();
    let current: serde_json::Value = serde_json::from_str(upgraded.content()).unwrap();
    assert!(
        upgraded
            .content()
            .contains("123456789012345678901234567890.123456789")
    );
    assert_eq!(current["receipt"]["response"], raw["receipt"]["response"]);
    assert_eq!(
        current["receipt"]["binding"]["futureBinding"],
        json!([vendor])
    );
    assert!(migrate_payload(&upgraded).unwrap().is_none());
    let output = pl_core::model::ModelStepOutput {
        attempt_id: "attempt-frozen".into(),
        base_context_revision: 7,
        content: vec![pl_core::context::ContextContent::Opaque { payload: upgraded }],
        tool_calls: vec![binding],
        private_context: None,
        usage: Default::default(),
    };
    let receipt = model_response_receipt(&output).unwrap().unwrap();
    assert_eq!(receipt.response.tool_calls[0].payload_text(), vendor);
    assert!(
        migrate_payload(&OpaquePayload::new("vendor.opaque", 99, vendor).unwrap())
            .unwrap()
            .is_none()
    );
    raw["receipt"]["binding"]["accountId"] = json!("conflicting-account");
    assert!(
        migrate_payload(&OpaquePayload::new("pl.model.assistant", 2, raw.to_string()).unwrap())
            .is_err()
    );
    for version in [1, 99] {
        assert!(migrate_payload(&legacy_frame_payload(version)).is_err());
    }
    let mut request: serde_json::Value =
        serde_json::from_str(legacy_request_with_prompt(1).content()).unwrap();
    request["prompt"]["accountHash"] = json!("conflicting-fingerprint");
    assert!(
        migrate_payload(
            &OpaquePayload::new("pl.model.prepared-request", 1, request.to_string()).unwrap()
        )
        .is_err()
    );
}

#[tokio::test]
async fn assistant_request_reconstruction_requires_explicit_producer_preparation() {
    use pl_core::{
        context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource},
        model::{ModelRequest, ToolCallMode},
    };
    let runtime = ModelRuntime::new_with_account_id(
        "deepseek",
        ProtocolEndpoint::compatible("fixture", "http://127.0.0.1:1"),
        ModelInfo::compatible("deepseek-v4-pro"),
    )
    .unwrap();
    let model = pl_model::runtime::ThreadModel::new(runtime, None);
    let mut raw: serde_json::Value =
        serde_json::from_str(legacy_frame_payload(2).content()).unwrap();
    raw["receipt"]["response"]["content"] = json!("frozen answer");
    let payload = OpaquePayload::new("pl.model.assistant", 2, raw.to_string()).unwrap();
    let request = |payload: OpaquePayload| ModelRequest {
        thread_id: "thread".into(),
        turn_id: "turn".into(),
        attempt_id: "request".into(),
        context: ContextSnapshot {
            revision: 7,
            records: vec![
                ContextRecord {
                    id: "user".into(),
                    turn_id: None,
                    source: ContextSource::User,
                    content: vec![ContextContent::Text {
                        text: "question".into(),
                    }],
                    tool_calls: vec![],
                },
                ContextRecord {
                    id: "assistant".into(),
                    turn_id: None,
                    source: ContextSource::Assistant,
                    content: vec![
                        ContextContent::Text {
                            text: "frozen answer".into(),
                        },
                        ContextContent::Opaque { payload },
                    ],
                    tool_calls: vec![],
                },
            ]
            .into(),
        },
        tools: Default::default(),
        tool_call_mode: ToolCallMode::Parallel,
        solo_tool_ids: Default::default(),
        committed_private_context: None,
        resources: None,
        cancellation: Default::default(),
        progress: None,
    };
    assert!(
        model
            .estimate_input(&request(payload.clone()), None)
            .await
            .is_err()
    );
    let upgraded = migrate_payload(&payload).unwrap().unwrap();
    assert!(model.estimate_input(&request(upgraded), None).await.is_ok());
}
