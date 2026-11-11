use super::*;

fn target() -> p::AcpSessionTarget {
    p::AcpSessionTarget {
        session_id: "product-session".into(),
        agent_id: "product-agent".into(),
        thread_id: "product-thread".into(),
        instance: 41,
    }
}
fn rpc_failure() -> p::AcpBusinessFailure {
    p::AcpBusinessFailure {
        kind: p::AcpBusinessFailureKind::Rpc,
        rpc_code: Some(-32000),
        message: "authentication required".into(),
        rpc_data: Some(Box::new(
            serde_json::json!({ "nested": [null, true, {"scope":"peer"}], "integer": u64::MAX }),
        )),
        auth_methods: vec![p::AcpAuthMethod {
            id: "actual-login".into(),
            name: "Peer login".into(),
            description: Some("Actual description".into()),
            kind: p::AcpAuthMethodKind::Agent,
        }],
    }
}

#[test]
fn all_business_failure_kinds_preserve_classification_and_original_fields() {
    use BridgeAcpBusinessFailureKind as B;
    use p::AcpBusinessFailureKind as P;

    for (kind, expected) in [
        (P::Busy, B::Busy),
        (P::Stale, B::Stale),
        (P::NotReady, B::NotReady),
        (P::Closed, B::Closed),
        (P::Unsupported, B::Unsupported),
        (P::UnsupportedVersion, B::UnsupportedVersion),
        (P::ServerVersionMismatch, B::ServerVersionMismatch),
        (P::InvalidOption, B::InvalidOption),
        (P::Rpc, B::Rpc),
        (P::InstallRequired, B::InstallRequired),
        (P::InstallationInvalid, B::InstallationInvalid),
        (P::UnsupportedPlatform, B::UnsupportedPlatform),
        (P::MissingExecutable, B::MissingExecutable),
        (P::InvalidWorkingDirectory, B::InvalidWorkingDirectory),
        (P::InvalidDefinition, B::InvalidDefinition),
        (P::Io, B::Io),
        (P::Cancelled, B::Cancelled),
        (P::Preparation, B::Preparation),
        (P::Publication, B::Publication),
    ] {
        let mut original = rpc_failure();
        original.kind = kind;
        let mapped = failure(original.clone()).unwrap();
        assert_eq!(mapped.kind, expected);
        assert_eq!(mapped.message, original.message);
        assert_eq!(mapped.rpc_code, original.rpc_code);
        assert_eq!(
            json::protocol_json(mapped.rpc_data.unwrap()).unwrap(),
            *original.rpc_data.unwrap()
        );
        assert_eq!(mapped.auth_methods.len(), 1);
        assert_eq!(mapped.auth_methods[0].id, original.auth_methods[0].id);
    }
}

#[test]
fn content_variants_use_official_constructors_and_round_trip_all_fields() {
    let meta =
        serde_json::from_value(serde_json::json!({"nested":[null,{"x":true}],"integer":u64::MAX}))
            .unwrap();
    let mut text = s::TextContent::new("literal text");
    text.meta = Some(meta);
    text.annotations = Some(
        s::Annotations::new()
            .audience(vec![s::Role::User, s::Role::Assistant])
            .priority(0.5)
            .last_modified("2026-06-01"),
    );
    let mut image = s::ImageContent::new("base64", "image/png");
    image.uri = Some("https://example.invalid/image".into());
    let mut link = s::ResourceLink::new("name", "file:///source");
    link.description = Some("description".into());
    link.title = Some("title".into());
    link.size = Some(17);
    link.mime_type = Some("text/plain".into());
    let inputs = vec![
        s::ContentBlock::Text(text),
        s::ContentBlock::Image(image),
        s::ContentBlock::Audio(s::AudioContent::new("audio-base64", "audio/wav")),
        s::ContentBlock::ResourceLink(link),
        s::ContentBlock::Resource(s::EmbeddedResource::new(
            s::EmbeddedResourceResource::TextResourceContents(
                s::TextResourceContents::new("source text", "file:///text").mime_type("text/plain"),
            ),
        )),
        s::ContentBlock::Resource(s::EmbeddedResource::new(
            s::EmbeddedResourceResource::BlobResourceContents(
                s::BlobResourceContents::new("blob-base64", "file:///blob")
                    .mime_type("application/octet-stream"),
            ),
        )),
    ];
    for input in inputs {
        let mapped = content(input.clone()).unwrap();
        assert_eq!(protocol_content(mapped).unwrap(), input);
    }
}

#[test]
fn structured_extension_json_keeps_integer_limits_and_rejects_nonfinite_input() {
    let input = serde_json::json!({"a":[null,true,false,-9,1.5],"large":u64::MAX,"small":i64::MIN,"text":" literal "});
    let mapped = json::json(input.clone()).unwrap();
    assert_eq!(json::protocol_json(mapped).unwrap(), input);
    assert!(matches!(
        json::protocol_json(BridgeAcpJsonValue::Number {
            value: BridgeAcpJsonNumber::Float { value: f64::NAN },
        }),
        Err(BridgeAcpBusinessError::Runtime(_))
    ));
}

#[test]
fn config_keeps_group_order_metadata_boolean_type_and_absent_vs_empty() {
    let first = s::SessionConfigSelectOption::new("one", "One");
    let mut second = s::SessionConfigSelectOption::new("two", "Two");
    second.description = Some("Second description".into());
    let group = s::SessionConfigSelectGroup::new("group-id", "Group name", vec![first, second]);
    let mut select = s::SessionConfigOption::new(
        "config-id",
        "Model",
        s::SessionConfigKind::Select(s::SessionConfigSelect::new(
            "two",
            s::SessionConfigSelectOptions::Grouped(vec![group]),
        )),
    );
    select.description = Some("Config description".into());
    select.category = Some(s::SessionConfigOptionCategory::Model);
    select.meta = Some(
        serde_json::from_value(serde_json::json!({"order":7,"custom":{"allowed":true}})).unwrap(),
    );
    let boolean = s::SessionConfigOption::new(
        "boolean-id",
        "Review",
        s::SessionConfigKind::Boolean(s::SessionConfigBoolean::new(false)),
    );
    let mut source = p::AcpBusinessSnapshot {
        target: target(),
        acp_session_id: Some("peer-session".into()),
        ready: true,
        closing: false,
        config_pending: true,
        config_options: Some(vec![select, boolean]),
        modes: None,
        active_run: Some(p::AcpRunId {
            instance: 9,
            sequence: 2,
        }),
        last_completed: None,
        observation_gap: None,
        auth_methods: vec![],
    };
    let mapped = snapshot(source.clone()).unwrap();
    assert_eq!(mapped.target.instance, 41);
    assert_eq!(mapped.active_run.unwrap().instance, 9);
    let configs = mapped.config_options.unwrap();
    assert_eq!(configs[0].id.value, "config-id");
    assert_eq!(
        configs[0].description.as_deref(),
        Some("Config description")
    );
    assert_eq!(configs[0].category, Some(BridgeAcpConfigCategory::Model));
    assert_eq!(
        json::protocol_meta(configs[0].meta.clone().unwrap()).unwrap(),
        source.config_options.as_ref().unwrap()[0]
            .meta
            .clone()
            .unwrap()
    );
    let BridgeAcpConfigKind::Select {
        current_value,
        options: BridgeAcpSelectOptions::Grouped { groups },
    } = &configs[0].kind
    else {
        panic!("lost grouped select");
    };
    assert_eq!(current_value.value, "two");
    assert_eq!(groups[0].group, "group-id");
    assert_eq!(groups[0].options[0].value.value, "one");
    assert_eq!(
        groups[0].options[1].description.as_deref(),
        Some("Second description")
    );
    assert_eq!(
        configs[1].kind,
        BridgeAcpConfigKind::Boolean {
            current_value: false
        }
    );
    assert_eq!(
        serde_json::to_value(protocol_config_value(BridgeAcpConfigValue::Boolean {
            value: false
        }))
        .unwrap(),
        serde_json::json!({"type":"boolean","value":false})
    );
    assert_eq!(
        protocol_config_value(BridgeAcpConfigValue::ValueId {
            value: BridgeAcpConfigValueId {
                value: "two".into()
            }
        }),
        s::SessionConfigOptionValue::value_id("two")
    );
    source.config_options = Some(vec![]);
    assert_eq!(
        snapshot(source.clone()).unwrap().config_options,
        Some(vec![])
    );
    source.config_options = None;
    assert_eq!(snapshot(source).unwrap().config_options, None);
}

#[test]
fn permission_and_tool_updates_keep_identity_and_optional_fields() {
    let mut fields = s::ToolCallUpdateFields::new();
    fields.content = Some(vec![]);
    fields.raw_input = Some(serde_json::Value::Null);
    let request = s::RequestPermissionRequest::new(
        "peer-session",
        s::ToolCallUpdate::new("tool-id", fields),
        vec![s::PermissionOption::new(
            "permission-option",
            "Allow once",
            s::PermissionOptionKind::AllowOnce,
        )],
    );
    let mapped = frame(p::AcpSessionFrame::Event {
        event: Box::new(p::AcpSessionEvent::Permission {
            id: p::AcpPermissionId {
                instance: 9,
                sequence: 12,
            },
            request,
        }),
    })
    .unwrap();
    let BridgeAcpSessionFrame::Event { event } = mapped else {
        panic!("wrong frame");
    };
    let BridgeAcpSessionEvent::Permission { id, request } = *event else {
        panic!("wrong frame");
    };
    assert_eq!(id.instance, 9);
    assert_eq!(id.sequence, 12);
    assert_eq!(request.session_id.value, "peer-session");
    assert_eq!(request.options[0].option_id.value, "permission-option");
    assert_eq!(request.options[0].kind, BridgeAcpPermissionKind::AllowOnce);
    assert_eq!(request.tool_call.content, Some(vec![]));
    assert_eq!(request.tool_call.locations, None);
    assert_eq!(request.tool_call.raw_input, Some(BridgeAcpJsonValue::Null));
    assert_eq!(request.tool_call.raw_output, None);
}

#[test]
fn official_update_three_state_fields_are_not_collapsed() {
    let input: s::SessionNotification = serde_json::from_value(serde_json::json!({
        "sessionId":"peer-session","update":{"sessionUpdate":"session_info_update","title":null}
    }))
    .unwrap();
    let mapped = notification::notification(input).unwrap();
    let BridgeAcpSessionUpdate::SessionInfo {
        title, updated_at, ..
    } = mapped.update
    else {
        panic!("wrong update");
    };
    assert_eq!(title, BridgeAcpStringField::Null);
    assert_eq!(updated_at, BridgeAcpStringField::Undefined);
    let input: s::SessionNotification = serde_json::from_value(serde_json::json!({
        "sessionId":"peer-session","update":{"sessionUpdate":"session_info_update","title":"New title","updatedAt":null}
    })).unwrap();
    let BridgeAcpSessionUpdate::SessionInfo {
        title, updated_at, ..
    } = notification::notification(input).unwrap().update
    else {
        panic!("wrong update");
    };
    assert_eq!(
        title,
        BridgeAcpStringField::Value {
            value: "New title".into()
        }
    );
    assert_eq!(updated_at, BridgeAcpStringField::Null);
}

#[test]
fn available_command_unstructured_payload_keeps_hint_metadata_and_absence() {
    let input_meta: s::Meta = serde_json::from_value(serde_json::json!({
        "nested": [null, true, {"order": 7}]
    }))
    .unwrap();
    let mut input = s::UnstructuredCommandInput::new(" literal argument hint ");
    input.meta = Some(input_meta.clone());
    let mut with_input = s::AvailableCommand::new("actual-command", "Actual description");
    with_input.input = Some(s::AvailableCommandInput::Unstructured(input));
    let without_input = s::AvailableCommand::new("no-input", "No arguments");
    let source = s::SessionNotification::new(
        "peer-session",
        s::SessionUpdate::AvailableCommandsUpdate(s::AvailableCommandsUpdate::new(vec![
            with_input,
            without_input,
        ])),
    );
    let mapped = notification::notification(source).unwrap();
    let BridgeAcpSessionUpdate::AvailableCommands { commands, .. } = mapped.update else {
        panic!("wrong update");
    };
    assert_eq!(commands[0].name, "actual-command");
    assert_eq!(commands[0].description, "Actual description");
    let input = commands[0].input.as_ref().unwrap();
    assert_eq!(input.hint, " literal argument hint ");
    assert_eq!(
        json::protocol_meta(input.meta.clone().unwrap()).unwrap(),
        input_meta
    );
    assert_eq!(commands[1].name, "no-input");
    assert!(commands[1].input.is_none());
}

#[test]
fn tool_notification_keeps_all_content_locations_and_raw_extension_values() {
    let source: s::SessionNotification = serde_json::from_value(serde_json::json!({
        "sessionId":"peer-session",
        "_meta":{"notification":"meta"},
        "update":{
            "sessionUpdate":"tool_call","toolCallId":"tool-id","title":"Execute",
            "name":"actual-tool","kind":"execute","status":"in_progress",
            "content":[
                {"type":"content","content":{"type":"text","text":"actual output"},"_meta":{"order":1}},
                {"type":"diff","path":"/file path","oldText":null,"newText":"new text"},
                {"type":"terminal","terminalId":"terminal-id"}
            ],
            "locations":[{"path":"/file path","line":7,"_meta":{"location":true}}],
            "rawInput":{"nested":[null,true,3]},
            "rawOutput":{"result":"actual-result"},
            "_meta":{"tool":"meta"}
        }
    })).unwrap();
    let mapped = notification::notification(source.clone()).unwrap();
    assert_eq!(mapped.session_id.value, "peer-session");
    assert_eq!(
        json::protocol_meta(mapped.meta.unwrap()).unwrap(),
        source.meta.unwrap()
    );
    let BridgeAcpSessionUpdate::ToolCall { call } = mapped.update else {
        panic!("wrong update");
    };
    assert_eq!(call.tool_call_id, "tool-id");
    assert_eq!(call.title, "Execute");
    assert_eq!(call.name.as_deref(), Some("actual-tool"));
    assert_eq!(call.kind, BridgeAcpToolKind::Execute);
    assert_eq!(call.status, BridgeAcpToolStatus::InProgress);
    let BridgeAcpToolContent::Content { content, meta } = &call.content[0] else {
        panic!("lost content");
    };
    assert!(
        matches!(&**content, BridgeAcpContentBlock::Text { text, .. } if text == "actual output")
    );
    assert!(meta.is_some());
    assert!(
        matches!(&call.content[1], BridgeAcpToolContent::Diff { path, old_text: None, new_text, .. } if path == "/file path" && new_text == "new text")
    );
    assert!(
        matches!(&call.content[2], BridgeAcpToolContent::Terminal { terminal_id, .. } if terminal_id == "terminal-id")
    );
    assert_eq!(call.locations[0].line, Some(7));
    assert_eq!(call.locations[0].path, "/file path");
    assert!(call.locations[0].meta.is_some());
    assert_eq!(
        json::protocol_json(call.raw_input.unwrap()).unwrap(),
        serde_json::json!({"nested":[null,true,3]})
    );
    assert_eq!(
        json::protocol_json(call.raw_output.unwrap()).unwrap(),
        serde_json::json!({"result":"actual-result"})
    );
    assert!(call.meta.is_some());
}

#[test]
fn ready_modes_and_list_preserve_peer_identity_metadata_and_order() {
    let response: s::NewSessionResponse = serde_json::from_value(serde_json::json!({
        "sessionId":"remote-id","configOptions":[],
        "modes":{
            "currentModeId":"second",
            "availableModes":[
                {"id":"first","name":"First"},
                {"id":"second","name":"Second","description":"actual description","_meta":{"rank":2}}
            ],"_meta":{"source":"peer"}
        },"_meta":{"ready":"meta"}
    })).unwrap();
    let mapped = frame(p::AcpSessionFrame::Event {
        event: Box::new(p::AcpSessionEvent::Ready { response }),
    })
    .unwrap();
    let BridgeAcpSessionFrame::Event { event } = mapped else {
        panic!("wrong frame");
    };
    let BridgeAcpSessionEvent::Ready { response } = *event else {
        panic!("wrong event");
    };
    assert_eq!(response.session_id.value, "remote-id");
    assert_eq!(response.config_options, Some(vec![]));
    assert!(response.meta.is_some());
    let modes = response.modes.unwrap();
    assert_eq!(modes.current_mode_id.value, "second");
    assert_eq!(modes.available_modes[0].id.value, "first");
    assert_eq!(
        modes.available_modes[1].description.as_deref(),
        Some("actual description")
    );
    assert!(modes.available_modes[1].meta.is_some());
    assert!(modes.meta.is_some());
    let response: s::ListSessionsResponse = serde_json::from_value(serde_json::json!({
        "sessions":[{"sessionId":"remote-id","cwd":"/peer path","additionalDirectories":["/second path","/third"],
            "title":"actual title","updatedAt":"2026-06-01T00:00:00Z","_meta":{"item":true}}],
        "nextCursor":"actual-cursor","_meta":{"list":true}
    })).unwrap();
    let mapped = list(response).unwrap();
    assert_eq!(mapped.next_cursor.as_deref(), Some("actual-cursor"));
    assert!(mapped.meta.is_some());
    assert_eq!(mapped.sessions[0].session_id.value, "remote-id");
    assert_eq!(mapped.sessions[0].cwd, "/peer path");
    assert_eq!(
        mapped.sessions[0].additional_directories,
        vec!["/second path", "/third"]
    );
    assert_eq!(mapped.sessions[0].title.as_deref(), Some("actual title"));
    assert_eq!(
        mapped.sessions[0].updated_at.as_deref(),
        Some("2026-06-01T00:00:00Z")
    );
    assert!(mapped.sessions[0].meta.is_some());
}

#[test]
fn failure_completion_and_partial_close_keep_original_business_facts() {
    let failure = rpc_failure();
    let mapped = super::failure(failure.clone()).unwrap();
    assert_eq!(mapped.rpc_code, Some(-32000));
    assert_eq!(mapped.auth_methods[0].id, "actual-login");
    assert_eq!(
        json::protocol_json(mapped.rpc_data.unwrap()).unwrap(),
        *failure.rpc_data.clone().unwrap()
    );
    let error = runtime_error(anyhow::Error::new(failure.clone()).context("original open"));
    assert!(matches!(error, BridgeAcpBusinessError::Business(v) if v.rpc_code == Some(-32000)));
    let source = p::AcpBusinessClose {
        local_complete: false,
        sdk_finished: true,
        cleanup_timed_out: true,
        remote_close_error: Some(failure.clone()),
        sdk_error: None,
        worker_error: Some("pending".into()),
        driver_error: None,
        unfinished_prompt: Some(p::AcpRunId {
            instance: 9,
            sequence: 12,
        }),
        unfinished_controls: true,
        last_completed: Some(p::AcpCompletedRun {
            run: p::AcpRunId {
                instance: 9,
                sequence: 11,
            },
            completion_sequence: 3,
            result: Err(failure),
            summary: "summary".into(),
            truncated: true,
        }),
        owner_failures: vec![p::AcpMemberCloseFailure {
            thread_id: "child-id".into(),
            message: "cleanup pending".into(),
        }],
    };
    let mapped = close(source).unwrap();
    assert!(!mapped.local_complete);
    assert!(mapped.sdk_finished);
    assert!(mapped.cleanup_timed_out);
    assert_eq!(mapped.unfinished_prompt.unwrap().instance, 9);
    assert!(mapped.unfinished_controls);
    assert_eq!(mapped.owner_failures[0].thread_id, "child-id");
    let completed = mapped.last_completed.unwrap();
    assert_eq!(completed.run.sequence, 11);
    assert_eq!(completed.completion_sequence, 3);
    assert!(completed.truncated);
    assert!(
        matches!(completed.result, BridgeAcpPromptResult::Failed { failure } if failure.rpc_code == Some(-32000))
    );
}

#[test]
fn list_and_open_inputs_preserve_literal_paths_remote_ids_and_extension_values() {
    let request: p::OpenAcpSessionRequest = BridgeOpenAcpSessionRequest {
        account_id: "account".into(),
        expected_connection_revision: 4,
        workspace_id: "workspace".into(),
        thread_id: Some("product-thread".into()),
        intent: BridgeAcpOpenIntent::Load {
            session_id: BridgeAcpRemoteSessionId {
                value: "remote-id".into(),
            },
        },
    }
    .into();
    assert_eq!(request.thread_id.as_deref(), Some("product-thread"));
    assert_eq!(request.intent, p::AcpOpenIntent::Load("remote-id".into()));
    let (mapped_target, request) = protocol_list(BridgeAcpListRequest {
        target: target().into(),
        cwd: Some("/a literal path".into()),
        cursor: Some("literal-cursor".into()),
        meta: None,
    })
    .unwrap();
    assert_eq!(mapped_target.instance, 41);
    assert_eq!(
        request.cwd.unwrap(),
        std::path::PathBuf::from("/a literal path")
    );
    assert_eq!(request.cursor.as_deref(), Some("literal-cursor"));
}
