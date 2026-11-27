//! Producer-owned model binding migration and account identity through public API only.
use pl_core::context::OpaquePayload;
use pl_model::model::ModelDefinition;
use pl_model::runtime::migration::migrate_payload;
use pl_model::{
    protocol::WireApi,
    runtime::{model_failure_receipt, model_request_receipt, model_response_receipt},
};
use serde_json::json;

fn current(payload: &OpaquePayload) -> OpaquePayload {
    migrate_payload(payload)
        .expect("producer migration succeeds")
        .unwrap_or_else(|| payload.clone())
}

#[test]
fn timing_provenance_upgrades_only_at_the_producer_boundary() {
    let frame = current(&legacy_frame_payload(2));
    let original: serde_json::Value = serde_json::from_str(frame.content()).unwrap();
    let binding = original["receipt"]["binding"].clone();
    for (format, old_version, new_version, mut value) in [
        ("pl.model.assistant", 4, 5, original),
        (
            "pl.model.failure",
            4,
            7,
            json!({
                "binding": binding, "accounting": legacy_accounting()
            }),
        ),
        (
            "pl.model.compaction",
            3,
            4,
            json!({
                "binding": binding,
                "item": {"type":"compaction","encryptedContent":"opaque-old-material"}
            }),
        ),
    ] {
        for has_timing in [false, true] {
            let owner = if format == "pl.model.assistant" {
                &mut value["receipt"]["response"]
            } else {
                &mut value
            };
            if has_timing {
                owner["timing"] = json!({"ttftMillis":9,"decodeMillis":11,"responseMillis":20});
            } else {
                owner.as_object_mut().unwrap().remove("timing");
            }
            let legacy = OpaquePayload::new(format, old_version, value.to_string()).unwrap();
            let migrated = migrate_payload(&legacy).unwrap().unwrap();
            assert_eq!(migrated.version(), new_version);
            let migrated_value: serde_json::Value =
                serde_json::from_str(migrated.content()).unwrap();
            let new_owner = if format == "pl.model.assistant" {
                &migrated_value["receipt"]["response"]
            } else {
                &migrated_value
            };
            if has_timing {
                assert_eq!(new_owner["timing"]["firstOutputSource"], "legacyUnknown");
                assert_eq!(new_owner["timing"]["ttftMillis"], 9);
                assert_eq!(new_owner["timing"]["decodeMillis"], 11);
                assert_eq!(new_owner["timing"]["responseMillis"], 20);
                let invalid_current =
                    OpaquePayload::new(format, new_version, value.to_string()).unwrap();
                assert!(
                    migrate_payload(&invalid_current).is_err(),
                    "new formats cannot silently default provenance"
                );
            } else {
                assert!(
                    new_owner.get("timing").is_none(),
                    "absent timing must remain absent"
                );
            }
            if format == "pl.model.compaction" {
                assert_eq!(migrated_value["item"], value["item"]);
            }
            assert!(migrate_payload(&migrated).unwrap().is_none());
        }
    }
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
    assert_eq!(
        receipt.binding.protocol,
        pl_model::protocol::providers::deepseek::ID
    );
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
        pl_model::runtime::PromptPrefixChangedReason::AccountChanged
    );
    assert_eq!(prompt.updated_at, 1234);

    // A migrated record re-serializes as current prepared-request v3 and reads back unchanged.
    let reread_payload = OpaquePayload::new(
        "pl.model.prepared-request",
        3,
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
        model_request_receipt(&reread_payload).expect("current prepared-request v3 decodes");
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
        3,
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
    assert_eq!(
        receipt.binding.protocol,
        pl_model::protocol::providers::deepseek::ID
    );
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
        turn_action: Default::default(),
        content: vec![pl_core::context::ContextContent::Opaque { payload: legacy }],
        attempt_id: "old".into(),
        base_context_revision: 0,
        tool_calls: vec![],
        private_context: None,
        usage: Default::default(),
    };
    assert!(model_response_receipt(&output).is_err());
    let output = pl_core::model::ModelStepOutput {
        turn_action: Default::default(),
        attempt_id: "attempt".into(),
        base_context_revision: 0,
        content: vec![pl_core::context::ContextContent::Opaque {
            payload: pl_model::runtime::migration::upgrade_assistant_frame(
                &legacy_frame_payload(2),
                "attempt",
                &[],
            )
            .unwrap()
            .payload,
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
    assert_eq!(
        receipt.binding.protocol,
        pl_model::protocol::providers::deepseek::ID
    );
    assert_eq!(receipt.binding.wire_api, WireApi::Responses);
    assert_eq!(receipt.binding.isolation, "binding:stable-namespace");
    assert_eq!(receipt.response.model, "deepseek-v4-pro");
    assert_eq!(
        receipt.response.accounting.pricing,
        pl_model::model::PricingOutcome::Disabled
    );
    let mut frame = json!({"receipt": &receipt, "bindings": [], "compatibilityFamily": null});
    for version in [3, 4] {
        let mut historical = output.clone();
        historical.content = vec![pl_core::context::ContextContent::Opaque {
            payload: pl_model::runtime::migration::upgrade_assistant_frame(
                &OpaquePayload::new("pl.model.assistant", version, frame.to_string()).unwrap(),
                &historical.attempt_id,
                &historical.tool_calls,
            )
            .unwrap()
            .payload,
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
        let decoded = pl_model::runtime::migration::upgrade_assistant_frame(
            payload,
            &current.attempt_id,
            &current.tool_calls,
        )
        .and_then(|upgraded| {
            current.content = vec![pl_core::context::ContextContent::Opaque {
                payload: upgraded.payload,
            }];
            model_response_receipt(&current)
        });
        if version == 3 {
            assert!(
                decoded.is_err(),
                "NoCharge is not valid in a historical frame"
            );
        } else {
            assert_eq!(
                decoded.unwrap().unwrap().response.accounting.pricing,
                pl_model::model::PricingOutcome::NoCharge
            );
        }
    }
}

#[test]
fn unknown_assistant_frame_versions_fail_closed() {
    for version in [1, 98, 99] {
        let output = pl_core::model::ModelStepOutput {
            turn_action: Default::default(),
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
        context_recovery: None,
    };
    assert!(model_failure_receipt(&historical).is_err());
    let error = pl_core::model::ModelError {
        details: Some(Box::new(current(&legacy))),
        kind: pl_core::model::ModelFailureKind::Unavailable,
        usage: Box::default(),
        source: None,
        context_recovery: None,
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
        pl_model::model::PricingOutcome::Disabled
    );
    let mut current = serde_json::to_value(&receipt).unwrap();
    for version in [3, 4, 5, 6] {
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
            context_recovery: None,
        };
        assert_eq!(
            model_failure_receipt(&historical)
                .unwrap()
                .unwrap()
                .accounting,
            receipt.accounting
        );
    }
    for legacy_kind in ["capacity", "configuration"] {
        // Version 5 wrote the broad category and snake_case enum field shown by
        // the previous production ProviderFailure serializer.
        let mut old = current.clone();
        old["providerFailure"] = json!({
            "context": {"stage":"stream", "requestId":"old-request", "recovery":"none"},
            "kind": legacy_kind,
            "code": "legacy-business-reason",
            "httpStatus": 429,
            "message": "original provider diagnosis",
            "retry": {"kind":"retryable", "retry_after_ms":45_000}
        });
        let payload = OpaquePayload::new("pl.model.failure", 5, old.to_string()).unwrap();
        let migrated = migrate_payload(&payload)
            .unwrap()
            .expect("v5 requires migration");
        let error = pl_core::model::ModelError {
            details: Some(Box::new(migrated)),
            kind: pl_core::model::ModelFailureKind::Unavailable,
            usage: Box::default(),
            source: None,
            context_recovery: None,
        };
        let restored = model_failure_receipt(&error).unwrap().unwrap();
        assert!(restored.settlements.is_empty());
        assert_eq!(restored.retry_count, None);
        assert_eq!(restored.accounting, receipt.accounting);
        let provider = restored.provider_failure.unwrap();
        assert_eq!(provider.kind, pl_protocol::ProviderFailureKind::Unknown);
        assert_eq!(provider.message, "original provider diagnosis");
        assert_eq!(provider.code.as_deref(), Some("legacy-business-reason"));
        assert_eq!(provider.context.request_id.as_deref(), Some("old-request"));
        assert_eq!(provider.retry.retry_after_ms(), Some(45_000));
        assert_eq!(
            provider.details.as_ref().unwrap()["legacyKind"],
            legacy_kind
        );
        let encoded = serde_json::to_value(&provider).unwrap();
        assert_eq!(encoded["retry"]["retryAfterMs"], 45_000);
        assert!(encoded["retry"].get("retry_after_ms").is_none());
    }
    current["accounting"]["pricing"] = json!({"kind":"noCharge"});
    for version in [3, 4, 5, 6] {
        let mut frozen = pl_core::model::ModelError {
            details: Some(Box::new(
                OpaquePayload::new("pl.model.failure", version, current.to_string()).unwrap(),
            )),
            kind: pl_core::model::ModelFailureKind::Unavailable,
            usage: Box::default(),
            source: None,
            context_recovery: None,
        };
        let decoded = migrate_payload(frozen.details.as_ref().unwrap()).and_then(|payload| {
            if let Some(payload) = payload {
                frozen.details = Some(Box::new(payload));
            }
            model_failure_receipt(&frozen)
        });
        if version == 3 {
            assert!(
                decoded.is_err(),
                "NoCharge is not valid in a historical failure receipt"
            );
        } else {
            assert_eq!(
                decoded.unwrap().unwrap().accounting.pricing,
                pl_model::model::PricingOutcome::NoCharge
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
        context_recovery: None,
    };
    assert!(model_failure_receipt(&error).is_err());
}

#[test]
fn runtime_requires_an_explicit_stable_account_id() {
    let endpoint = pl_model::protocol::providers::openai::compatible_endpoint(
        "Display name is not an identity",
        "http://127.0.0.1:1",
    );
    let model = ModelDefinition::compatible("model");
    assert!(pl_model::runtime::new_with_account_id("  ", endpoint.clone(), model.clone()).is_err());
    let runtime = pl_model::runtime::new_with_account_id("account-stable", endpoint, model)
        .expect("explicit account id is valid");
    assert_eq!(runtime.account_id(), "account-stable");
}

#[test]
fn producer_migration_preserves_opaque_material_precision_and_is_idempotent() {
    let mut raw: serde_json::Value =
        serde_json::from_str(legacy_frame_payload(2).content()).unwrap();
    let vendor = "{ \"opaque\": 9007199254740993, \"text\": \"原始材料\" }";
    let binding = pl_core::model::ModelToolCall {
        presentation_contract: None,
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
        turn_action: Default::default(),
        attempt_id: "attempt-frozen".into(),
        base_context_revision: 7,
        content: vec![pl_core::context::ContextContent::Opaque {
            payload: upgraded.clone(),
        }],
        tool_calls: vec![binding.clone()],
        private_context: None,
        usage: Default::default(),
    };
    assert!(model_response_receipt(&output).is_err());
    // Identity upgrading is a separate contextual pure function. It cannot infer the source from
    // arguments, array position or the old globally scoped call name.
    let identity_upgrade = pl_model::runtime::migration::upgrade_assistant_frame(
        &upgraded,
        "actual-source",
        std::slice::from_ref(&binding),
    )
    .unwrap();
    assert_eq!(identity_upgrade.payload.version(), 7);
    assert!(
        identity_upgrade
            .payload
            .content()
            .contains("123456789012345678901234567890.123456789")
    );
    assert_eq!(identity_upgrade.call_ids.len(), 1);
    let new_id = identity_upgrade.call_ids["call-frozen"].clone();
    assert_ne!(new_id, "call-frozen");
    let mut upgraded_output = output.clone();
    upgraded_output.attempt_id = "actual-source".into();
    upgraded_output.tool_calls[0].call_id = new_id;
    upgraded_output.content = vec![pl_core::context::ContextContent::Opaque {
        payload: identity_upgrade.payload,
    }];
    let receipt = model_response_receipt(&upgraded_output).unwrap().unwrap();
    assert_eq!(receipt.response.tool_calls[0].payload_text(), vendor);
    assert_eq!(receipt.response.tool_calls[0].call_id, "call-frozen");
    assert!(
        pl_model::runtime::migration::upgrade_assistant_frame(
            &upgraded,
            "",
            std::slice::from_ref(&binding)
        )
        .is_err()
    );
    let mut conflicting = binding.clone();
    conflicting.call_id = "unrelated-external-call".into();
    assert!(
        pl_model::runtime::migration::upgrade_assistant_frame(
            &upgraded,
            "actual-source",
            &[conflicting]
        )
        .is_err()
    );
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
    let runtime = pl_model::runtime::new_with_account_id(
        "deepseek",
        pl_model::protocol::providers::openai::compatible_endpoint("fixture", "http://127.0.0.1:1"),
        ModelDefinition::compatible("deepseek-v4-pro"),
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
                    tool_data: Default::default(),
                    id: "user".into(),
                    turn_id: None,
                    source: ContextSource::User,
                    content: vec![ContextContent::Text {
                        text: "question".into(),
                    }],
                    tool_calls: vec![],
                },
                ContextRecord {
                    tool_data: Default::default(),
                    id: "source-attempt:output".into(),
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
        members: None,
    };
    assert!(
        model
            .estimate_input(&request(payload.clone()), None)
            .await
            .is_err()
    );
    let upgraded = migrate_payload(&payload).unwrap().unwrap();
    assert!(
        model
            .estimate_input(&request(upgraded.clone()), None)
            .await
            .is_err(),
        "payload-only migration cannot supply the source attempt identity"
    );
    let prepared =
        pl_model::runtime::migration::upgrade_assistant_frame(&upgraded, "source-attempt", &[])
            .unwrap();
    model
        .estimate_input(&request(prepared.payload), None)
        .await
        .expect("contextual producer preparation makes the assistant usable");
}
