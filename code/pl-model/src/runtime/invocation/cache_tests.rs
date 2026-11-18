use super::*;
use crate::model::ModelInfo;
use crate::model::{ModelParameter, ModelTransportProfile, ParameterWire, WireAssignment};
use crate::protocol::PromptCacheDialect;
use crate::protocol::ProtocolEndpoint;
use crate::runtime::invocation_context::InvocationPurpose;
use serde_json::json;

fn runner(enabled: bool) -> ModelRuntime {
    let mut endpoint = ProtocolEndpoint::compatible("cache", "http://127.0.0.1:1");
    if enabled {
        endpoint.service_capabilities.prompt_cache.dialect =
            PromptCacheDialect::OpenAiPromptCacheKey;
    }
    let mut model = ModelInfo::compatible("cache-model");
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    ModelRuntime::new_with_account_id("cache-account", endpoint, model).unwrap()
}

#[test]
fn cache_policy_applies_at_request_preparation() {
    let (body, _) = runner(false)
        .prepare_request_body(
            CompletionRequest::builder().build(),
            Some("caller-key"),
            &InvocationPurpose::Completion,
        )
        .unwrap();
    assert!(
        serde_json::to_value(body)
            .unwrap()
            .get("prompt_cache_key")
            .is_none()
    );
}

#[test]
fn cache_key_overrides_are_rejected_before_io() {
    for expected in [None, Some("thread-key")] {
        for value in [json!("shared-key"), json!(null)] {
            let mut fixed = runner(true);
            fixed
                .model
                .binding
                .request
                .body
                .insert("prompt_cache_key".into(), value.clone());
            assert!(
                fixed
                    .prepare_request_body(
                        CompletionRequest::builder().build(),
                        expected,
                        &InvocationPurpose::Completion
                    )
                    .is_err(),
                "fixed body: {value}"
            );

            let mut parameter = runner(true);
            parameter.model.parameters = vec![ModelParameter {
                name: "effort".into(),
                label: None,
                default: None,
                candidates: vec!["low".into()],
                wire: std::collections::BTreeMap::from([(
                    "low".into(),
                    ParameterWire {
                        set: vec![WireAssignment {
                            path: "prompt_cache_key".into(),
                            value,
                        }],
                        remove: vec![],
                    },
                )]),
            }];
            let request = CompletionRequest::builder()
                .reasoning(Some(crate::completion::ReasoningConfig {
                    effort: Some("low".into()),
                    summary: None,
                }))
                .build();
            assert!(
                parameter
                    .prepare_request_body(request, expected, &InvocationPurpose::Completion)
                    .is_err(),
                "parameter wire"
            );
        }
    }
    let mut removed = runner(true);
    removed.model.parameters = vec![ModelParameter {
        name: "effort".into(),
        label: None,
        default: None,
        candidates: vec!["low".into()],
        wire: std::collections::BTreeMap::from([(
            "low".into(),
            ParameterWire {
                set: vec![],
                remove: vec!["prompt_cache_key".into()],
            },
        )]),
    }];
    let request = CompletionRequest::builder()
        .reasoning(Some(crate::completion::ReasoningConfig {
            effort: Some("low".into()),
            summary: None,
        }))
        .build();
    assert!(
        removed
            .prepare_request_body(request, Some("thread-key"), &InvocationPurpose::Completion)
            .is_err()
    );
}
