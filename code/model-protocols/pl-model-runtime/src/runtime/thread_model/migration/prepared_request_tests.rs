use super::*;
use serde_json::json;

const FORMAT: &str = "pl.model.prepared-request";

fn account_request() -> serde_json::Value {
    json!({
        "binding": {
            "accountId": "saved-account",
            "modelId": "saved-model",
            "protocol": "open_ai",
            "wireApi": "responses",
            "isolation": "saved-isolation",
            "purpose": "conversation",
            "contextWindow": 65536
        },
        "tools": [{"kind": "programmaticToolCalling"}],
        "toolChoice": "auto",
        "parallelToolCalls": false,
        "prompt": {
            "scope": "conversation",
            "generation": 4,
            "accountId": "saved-account",
            "accountHash": "account-fingerprint",
            "modelId": "saved-model",
            "fixedPrefixHash": "prefix-fingerprint",
            "toolSchemaHash": "tools-fingerprint",
            "contextHash": "context-fingerprint",
            "prefixChangedReason": "accountChanged",
            "updatedAt": 42
        },
        "futureEvidence": {"precision": 9007199254740993_u64}
    })
}

#[test]
fn account_bound_prepared_request_retains_all_saved_fields() -> Result<(), ModelError> {
    let input = account_request();
    let saved = OpaquePayload::new(FORMAT, 2, input.to_string()).unwrap();
    let upgraded = migrate_payload(&saved)?.expect("upgrade account-bound revision 2");
    assert_eq!(upgraded.version(), REQUEST_RECEIPT_VERSION);
    assert_eq!(parse::<serde_json::Value>(upgraded.content())?, input);
    assert!(migrate_payload(&upgraded)?.is_none());
    Ok(())
}

#[test]
fn provider_bound_prepared_request_converts_old_binding_and_prompt_diagnostics()
-> Result<(), ModelError> {
    let current = account_request();
    let mut input = current.clone();
    input["binding"] = json!({
        "providerInstanceId": "saved-account",
        "requestedModel": "saved-model",
        "adapter": "openAi",
        "protocol": "responses",
        "isolation": "saved-isolation",
        "purpose": "conversation",
        "contextWindow": 65536
    });
    input["prompt"] = json!({
        "scope": "conversation",
        "generation": 4,
        "provider": "old display name",
        "providerHash": "account-fingerprint",
        "model": "saved-model",
        "fixedPrefixHash": "prefix-fingerprint",
        "toolSchemaHash": "tools-fingerprint",
        "contextHash": "context-fingerprint",
        "prefixChangedReason": "providerChanged",
        "updatedAt": 42
    });
    let saved = OpaquePayload::new(FORMAT, 1, input.to_string()).unwrap();
    let upgraded = migrate_payload(&saved)?.expect("upgrade provider-bound revision 1");
    assert_eq!(upgraded.version(), REQUEST_RECEIPT_VERSION);
    assert_eq!(parse::<serde_json::Value>(upgraded.content())?, current);
    Ok(())
}

#[test]
fn prepared_request_rejects_bad_current_data_and_unknown_revision() {
    for (revision, content, diagnostic) in [
        (REQUEST_RECEIPT_VERSION, "{", "EOF"),
        (
            REQUEST_RECEIPT_VERSION + 1,
            "{}",
            "unsupported prepared model request record",
        ),
    ] {
        let payload = OpaquePayload::new(FORMAT, revision, content).unwrap();
        let error = migrate_payload(&payload).unwrap_err();
        assert_eq!(error.kind, ModelFailureKind::UnsupportedContent);
        assert!(error.source.unwrap().to_string().contains(diagnostic));
    }
}
