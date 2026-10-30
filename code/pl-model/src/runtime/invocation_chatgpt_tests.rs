use super::*;
use crate::completion::{SystemPrompt, ToolSpec};
use crate::protocol::chatgpt::{
    ChatGptAuthError, ChatGptCredentialRecord, ChatGptCredentialStorage, ChatGptSession,
};
use pl_protocol::{Message, MessageContent, MessageRole, ToolCallKind};
use serde_json::json;

struct NoCredentialIo;
impl ChatGptCredentialStorage for NoCredentialIo {
    fn load(&self) -> std::result::Result<ChatGptCredentialRecord, ChatGptAuthError> {
        panic!("wire preparation must not read credentials")
    }
    fn persist(
        &self,
        _: &str,
        _: &ChatGptCredentialRecord,
    ) -> std::result::Result<(), ChatGptAuthError> {
        panic!("wire preparation must not write credentials")
    }
}

fn fixture() -> (tempfile::TempDir, InvocationRunner) {
    let temp = tempfile::tempdir().unwrap();
    let record = ChatGptCredentialRecord {
        schema_version: 1,
        registration_id: "wire-registration".into(),
        account: pl_protocol::studio::ChatGptAccountInfo {
            issuer: "https://auth.openai.com".into(),
            subject: "wire-subject".into(),
            client_id: "issued-wire-client".into(),
            email: None,
            plan_usage_enabled: true,
        },
        ext_agent_host_id: "urn:uuid:00000000-0000-4000-8000-000000000001".into(),
        access_token: "synthetic-access".into(),
        refresh_token: "synthetic-refresh".into(),
        id_token: "synthetic-id".into(),
        scopes: vec!["chatgpt.tokens.use.direct".into()],
        expires_at: i64::MAX,
        earliest_refresh_at: None,
        refresh_in_flight: false,
    };
    let mut endpoint = ProtocolEndpoint::openai(None);
    endpoint.chatgpt_session = Some(
        ChatGptSession::new(
            &record,
            Arc::new(NoCredentialIo),
            temp.path().join("must-not-lock"),
        )
        .unwrap(),
    );
    let info = crate::config::builtin_account_catalog()
        .unwrap()
        .templates
        .into_iter()
        .find(|t| t.id.as_str() == "openai")
        .unwrap()
        .account
        .effective_models(None)
        .unwrap()
        .into_iter()
        .find(|m| m.model_id == "gpt-5.5")
        .unwrap();
    (
        temp,
        InvocationRunner::new_with_account_id("wire", endpoint, info).unwrap(),
    )
}

fn message(role: MessageRole, text: &str) -> Message {
    Message {
        role,
        content: MessageContent::text(text),
        presentation: Default::default(),
        reasoning_content: None,
        tool_calls: None,
        tool_result: None,
        metadata: Default::default(),
    }
}
fn request() -> CompletionRequest {
    CompletionRequest::builder()
        .system_prompt(SystemPrompt::new("trusted"))
        .messages(vec![message(MessageRole::User, "task")])
        .build()
}
fn body(runner: &InvocationRunner, request: CompletionRequest) -> serde_json::Value {
    serde_json::to_value(runner.prepare_request_body(request, None).unwrap().0).unwrap()
}

#[test]
fn siwc_additional_tools_preserve_declarations_history_and_call_pairing() {
    let (_temp, runner) = fixture();
    let mut request = request();
    let schema = json!({"type":"object","properties":{"q":{"type":"string"}},"required":["q"],"additionalProperties":false});
    request.tools = vec![
        ToolSpec::function("lookup", "lookup", schema.clone()),
        ToolSpec::custom_grammar("edit", "edit", "lark", "start: WORD"),
    ];
    let mut assistant = message(MessageRole::Assistant, "");
    assistant.tool_calls = Some(vec![pl_protocol::ToolCallRecord {
        item_id: "item-edit".into(),
        call_id: "call-edit".into(),
        name: "edit".into(),
        kind: ToolCallKind::Custom,
        arguments: json!("payload"),
        caller: None,
    }]);
    assistant
        .tool_calls
        .as_mut()
        .unwrap()
        .push(pl_protocol::ToolCallRecord {
            item_id: "item-lookup".into(),
            call_id: "call-lookup".into(),
            name: "lookup".into(),
            kind: ToolCallKind::Function,
            arguments: json!({"q":"task"}),
            caller: None,
        });
    let mut output = message(MessageRole::Tool, "edited");
    output.tool_result = Some(pl_protocol::ToolResultRecord {
        item_id: "item-edit".into(),
        call_id: "call-edit".into(),
        name: "edit".into(),
        kind: ToolCallKind::Custom,
    });
    let mut function_output = message(MessageRole::Tool, "found");
    function_output.tool_result = Some(pl_protocol::ToolResultRecord {
        item_id: "item-lookup".into(),
        call_id: "call-lookup".into(),
        name: "lookup".into(),
        kind: ToolCallKind::Function,
    });
    request
        .input
        .extend([assistant.into(), output.into(), function_output.into()]);
    let original = format!("{:?}", request.input);
    let encoded = body(&runner, request.clone());
    assert_eq!(encoded, body(&runner, request.clone()));
    assert_eq!(format!("{:?}", request.input), original);
    assert!(encoded.get("tools").is_none());
    assert_eq!(encoded["input"][0]["role"], "developer");
    let declarations = &encoded["input"][1];
    assert_eq!(declarations["type"], "additional_tools");
    assert_eq!(declarations["role"], "developer");
    // Retain the existing canonical tool-schema ordering, not a new SIWC registry.
    assert_eq!(declarations["tools"][1]["name"], "lookup");
    assert_eq!(declarations["tools"][1]["parameters"], schema);
    assert_eq!(declarations["tools"][0]["name"], "edit");
    assert_eq!(
        declarations["tools"][0]["format"],
        json!({"type":"grammar","syntax":"lark","definition":"start: WORD"})
    );
    assert_eq!(encoded["input"][2]["role"], "user");
    assert_eq!(encoded["input"][3]["type"], "custom_tool_call");
    assert_eq!(encoded["input"][3]["call_id"], "call-edit");
    assert_eq!(encoded["input"][4]["type"], "function_call");
    assert_eq!(encoded["input"][4]["call_id"], "call-lookup");
    assert_eq!(encoded["input"][4]["name"], "lookup");
    assert_eq!(encoded["input"][5]["type"], "custom_tool_call_output");
    assert_eq!(encoded["input"][5]["call_id"], "call-edit");
    assert_eq!(encoded["input"][6]["type"], "function_call_output");
    assert_eq!(encoded["input"][6]["call_id"], "call-lookup");
    assert_eq!(encoded["store"], false);
    assert_eq!(encoded["stream"], true);
    assert!(
        body(
            &runner,
            CompletionRequest::builder()
                .messages(vec![message(MessageRole::User, "task")])
                .build()
        )["input"]
            .as_array()
            .unwrap()
            .iter()
            .all(|item| item["type"] != "additional_tools")
    );
}

#[test]
fn siwc_rejects_explicit_parameters_and_all_override_sources_before_io() {
    let (_temp, runner) = fixture();
    let mut temperature = request();
    temperature.temperature = Some(0.1);
    let mut limit = request();
    limit.max_tokens = Some(10);
    for request in [temperature, limit] {
        assert!(runner.prepare_request_body(request, None).is_err());
    }
    let mut overrides = vec![
        json!({"store":true}),
        json!({"stream":false}),
        json!({"input":"not-array"}),
        json!({"input":[]}),
        json!({"tools":[{"type":"tool_search"}]}),
        json!({"instructions":"secret-value"}),
    ];
    for field in [
        "background",
        "conversation",
        "max_output_tokens",
        "max_tool_calls",
        "metadata",
        "moderation",
        "multi_agent",
        "prompt",
        "prompt_cache_retention",
        "safety_identifier",
        "temperature",
        "top_logprobs",
        "top_p",
        "truncation",
        "user",
        "previous_response_id",
    ] {
        overrides.push(json!({field:null}));
    }
    for value in overrides {
        let overlay = value.as_object().unwrap().clone();
        let mut fixed = runner.clone();
        fixed.model.binding.request.body = overlay.clone();
        assert!(
            fixed.prepare_request_body(request(), None).is_err(),
            "{value}"
        );
        assert!(
            runner
                .with_native_body(overlay.clone())
                .prepare_request_body(request(), None)
                .is_err(),
            "{value}"
        );
        let mut parameter = runner.clone();
        let wire = crate::model::ParameterWire {
            set: overlay
                .into_iter()
                .map(|(path, value)| crate::model::WireAssignment { path, value })
                .collect(),
            remove: vec![],
        };
        parameter.model.parameters = vec![crate::model::ModelParameter {
            name: "effort".into(),
            label: None,
            default: Some("low".into()),
            candidates: vec!["low".into()],
            wire: std::collections::BTreeMap::from([("low".into(), wire)]),
        }];
        let mut selected = request();
        selected.reasoning = Some(crate::completion::ReasoningConfig {
            effort: Some("low".into()),
            summary: None,
        });
        assert!(
            parameter.prepare_request_body(selected, None).is_err(),
            "{value}"
        );
    }
    let mut supported = runner.clone();
    supported.model.parameters = vec![crate::model::ModelParameter {
        name: "effort".into(),
        label: None,
        default: Some("low".into()),
        candidates: vec!["low".into()],
        wire: std::collections::BTreeMap::from([(
            "low".into(),
            crate::model::ParameterWire {
                set: vec![
                    crate::model::WireAssignment {
                        path: "reasoning.effort".into(),
                        value: json!("low"),
                    },
                    crate::model::WireAssignment {
                        path: "store".into(),
                        value: json!(false),
                    },
                    crate::model::WireAssignment {
                        path: "stream".into(),
                        value: json!(true),
                    },
                ],
                remove: vec![],
            },
        )]),
    }];
    let mut selected = request();
    selected.reasoning = Some(crate::completion::ReasoningConfig {
        effort: Some("low".into()),
        summary: None,
    });
    assert_eq!(body(&supported, selected)["reasoning"]["effort"], "low");
}

#[test]
fn siwc_rejects_unsupported_tools_without_downgrading_callers_or_native_history() {
    let (_temp, runner) = fixture();
    let mut unsupported_custom = runner.clone();
    unsupported_custom.model.capabilities.tools.custom_tools = false;
    unsupported_custom.model.capabilities.tools.freeform_tools = false;
    let mut selected = request();
    selected.tools = vec![ToolSpec::custom_grammar(
        "edit",
        "edit",
        "lark",
        "start: WORD",
    )];
    assert!(
        unsupported_custom
            .prepare_request_body(selected, None)
            .is_err()
    );
    let mut search_request = request();
    search_request.tools = vec![ToolSpec::WebSearch {
        options: pl_protocol::HostedWebSearchOptions::OpenAi {
            external_web_access: false,
            indexed_web_access: None,
            filters: None,
            user_location: None,
            search_context_size: None,
            search_content_types: None,
        },
    }];
    let mut search = runner.clone();
    search.model.capabilities.web_search = true;
    search
        .endpoint
        .service_capabilities
        .web_search
        .hosted_responses = true;
    assert_eq!(
        body(&search, search_request.clone())["tools"][0]["type"],
        "web_search"
    );
    search
        .endpoint
        .service_capabilities
        .web_search
        .hosted_responses = false;
    assert!(search.prepare_request_body(search_request, None).is_err());
    let mut function_patch = request();
    function_patch.tools = vec![ToolSpec::function(
        "apply_patch",
        "frozen",
        json!({"type":"object"}),
    )];
    let encoded = body(&runner, function_patch);
    assert_eq!(encoded["input"][1]["tools"][0]["type"], "function");
    assert_eq!(
        encoded["input"][1]["tools"][0]["parameters"],
        json!({"type":"object"})
    );
    let mut only_programmatic = ToolSpec::function("p", "p", json!({"type":"object"}));
    if let ToolSpec::Function {
        allowed_callers, ..
    } = &mut only_programmatic
    {
        *allowed_callers = vec![pl_protocol::ToolCallerMode::Programmatic];
    }
    for tool in [ToolSpec::ProgrammaticToolCalling, only_programmatic] {
        let mut selected = request();
        selected.tools = vec![tool];
        assert!(runner.prepare_request_body(selected, None).is_err());
    }
    let mut mixed = ToolSpec::function("mixed", "mixed", json!({"type":"object"}));
    if let ToolSpec::Function {
        allowed_callers, ..
    } = &mut mixed
    {
        *allowed_callers = vec![
            pl_protocol::ToolCallerMode::Direct,
            pl_protocol::ToolCallerMode::Programmatic,
        ];
    }
    let mut selected = request();
    selected.tools = vec![mixed];
    assert_eq!(
        body(&runner, selected)["input"][1]["tools"][0]["allowed_callers"],
        json!(["direct", "programmatic"])
    );
    for value in [
        json!({"type":"program","id":"p"}),
        json!({"type":"tool_search_call","id":"s"}),
        json!({"type":"message","role":"system","content":[]}),
        json!({"type":"additional_tools","role":"developer","tools":[]}),
    ] {
        let mut selected = request();
        // Test the opaque input path without introducing a second codec or network bypass.
        selected
            .input
            .push(pl_protocol::ModelContextItem::Responses {
                item: pl_protocol::ResponsesContextItem {
                    kind: pl_protocol::ResponsesContextItemKind::Unknown,
                    value,
                },
            });
        assert!(runner.prepare_request_body(selected, None).is_err());
    }
    let mut selected = request();
    let reasoning =
        json!({"type":"reasoning","id":"r","encrypted_content":"opaque","status":"completed"});
    selected
        .input
        .push(pl_protocol::ModelContextItem::Responses {
            item: pl_protocol::ResponsesContextItem {
                kind: pl_protocol::ResponsesContextItemKind::Reasoning,
                value: reasoning.clone(),
            },
        });
    assert_eq!(body(&runner, selected)["input"][2], reasoning);
}

#[tokio::test]
async fn siwc_thread_keeps_capacity_metadata_but_does_not_invent_an_output_limit() {
    use pl_core::{
        context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource},
        model::{Model, ModelRequest, ToolCallMode},
    };
    let (_temp, mut runner) = fixture();
    runner.model.max_output_tokens = Some(4096);
    if let crate::model::ModelProtocolOptions::Responses(options) =
        &mut runner.model.binding.request.protocol
    {
        options.max_tokens_field = crate::model::ResponsesMaxTokensField::MaxOutputTokens;
    }
    let runtime = crate::runtime::ModelRuntime::new_with_account_id(
        "wire",
        runner.endpoint.clone(),
        runner.model.clone(),
    )
    .unwrap();
    assert_eq!(runtime.model().max_output_tokens, Some(4096));
    let model = crate::runtime::ThreadModel::new(runtime, None);
    let mut session = model.open_session().await.unwrap();
    let prepared = session
        .prepare(ModelRequest {
            thread_id: "t".into(),
            turn_id: "turn".into(),
            attempt_id: "a".into(),
            context: ContextSnapshot {
                revision: 1,
                records: vec![ContextRecord {
                    id: "u".into(),
                    turn_id: None,
                    source: ContextSource::User,
                    content: vec![ContextContent::Text {
                        text: "task".into(),
                    }],
                    tool_calls: vec![],
                }]
                .into(),
            },
            tools: vec![].into(),
            tool_call_mode: ToolCallMode::Parallel,
            solo_tool_ids: Default::default(),
            committed_private_context: None,
            resources: None,
            cancellation: Default::default(),
            progress: None,
        })
        .await
        .unwrap();
    let metadata: serde_json::Value =
        serde_json::from_str(prepared.request_metadata().unwrap().content()).unwrap();
    assert_eq!(metadata["maxTokens"], serde_json::Value::Null);
    // Preparing must not poll the operation or access the protected storage.
    drop(prepared);
    session.close().await.unwrap();
}
