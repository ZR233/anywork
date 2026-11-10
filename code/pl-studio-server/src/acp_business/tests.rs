use super::*;
use axum::body::to_bytes;

#[cfg(target_os = "linux")]
mod real_transport;

#[tokio::test]
async fn business_error_keeps_status_kind_rpc_data_and_authentication_methods() {
    use AcpBusinessFailureKind as K;
    use StatusCode as S;

    for (kind, status) in [
        (K::Busy, S::CONFLICT),
        (K::Stale, S::CONFLICT),
        (K::NotReady, S::CONFLICT),
        (K::Closed, S::GONE),
        (K::Unsupported, S::NOT_IMPLEMENTED),
        (K::UnsupportedVersion, S::BAD_REQUEST),
        (K::ServerVersionMismatch, S::BAD_REQUEST),
        (K::InvalidOption, S::BAD_REQUEST),
        (K::Rpc, S::BAD_GATEWAY),
        (K::InstallRequired, S::SERVICE_UNAVAILABLE),
        (K::InstallationInvalid, S::SERVICE_UNAVAILABLE),
        (K::UnsupportedPlatform, S::SERVICE_UNAVAILABLE),
        (K::MissingExecutable, S::SERVICE_UNAVAILABLE),
        (K::InvalidWorkingDirectory, S::SERVICE_UNAVAILABLE),
        (K::InvalidDefinition, S::SERVICE_UNAVAILABLE),
        (K::Io, S::SERVICE_UNAVAILABLE),
        (K::Cancelled, S::SERVICE_UNAVAILABLE),
        (K::Preparation, S::SERVICE_UNAVAILABLE),
        (K::Publication, S::SERVICE_UNAVAILABLE),
    ] {
        let failure = AcpBusinessFailure {
            kind: kind.clone(),
            rpc_code: Some(-32000),
            message: "original safe runtime message".into(),
            rpc_data: Some(Box::new(serde_json::json!({
                "retry": false, "nested": [null, {"scope": "actual-peer"}]
            }))),
            auth_methods: vec![AcpAuthMethod {
                id: "actual-login".into(),
                name: "Peer login".into(),
                description: Some("Actual initialize description".into()),
                kind: AcpAuthMethodKind::Agent,
            }],
        };
        let expected = serde_json::to_value(&failure).unwrap();
        let error = AcpApiError::from(anyhow::Error::new(failure).context("open failed"));
        let response = error.into_response();
        assert_eq!(response.status(), status, "{kind:?}");
        assert!(
            !response
                .headers()
                .contains_key(axum::http::header::RETRY_AFTER)
        );
        let body = to_bytes(response.into_body(), 8192).await.unwrap();
        let decoded: AcpBusinessFailure = serde_json::from_slice(&body).unwrap();
        assert_eq!(decoded.kind, kind);
        assert_eq!(serde_json::to_value(decoded).unwrap(), expected);
    }
}

#[tokio::test]
async fn nonbusiness_anyhow_failure_keeps_runtime_typed_envelope() {
    let failure = StudioError::new(StudioErrorCode::StaleRevision, "stale document", false);
    let correlation_id = failure.correlation_id.clone();
    let response = AcpApiError::from(anyhow::Error::new(failure)).into_response();
    assert_eq!(response.status(), StatusCode::CONFLICT);
    assert_eq!(response.headers()["x-correlation-id"], correlation_id);
    let body = to_bytes(response.into_body(), 8192).await.unwrap();
    let failure: StudioError = serde_json::from_slice(&body).unwrap();
    assert_eq!(failure.code, StudioErrorCode::StaleRevision);
    assert_eq!(failure.message, "stale document");
}

#[test]
fn request_qualification_does_not_substitute_product_instance_for_sdk_run() {
    let request: AcpReplaceRequest = serde_json::from_value(serde_json::json!({
        "target": {
            "sessionId": "product-session", "agentId": "product-agent",
            "threadId": "product-thread", "instance": 41
        },
        "run": { "instance": 9, "sequence": 12 },
        "content": [{ "type": "text", "text": " replacement " }]
    }))
    .unwrap();
    assert_eq!(request.target.instance, 41);
    assert_eq!(request.run.instance, 9);
    assert_eq!(request.run.sequence, 12);
    let value = serde_json::to_value(request).unwrap();
    assert_eq!(value["content"][0]["text"], " replacement ");
}

#[test]
fn partial_close_preserves_all_cleanup_facts() {
    let close = AcpBusinessClose {
        local_complete: false,
        sdk_finished: true,
        cleanup_timed_out: true,
        remote_close_error: None,
        sdk_error: None,
        worker_error: Some("worker still closing".into()),
        driver_error: None,
        unfinished_prompt: Some(AcpRunId {
            instance: 9,
            sequence: 12,
        }),
        unfinished_controls: true,
        last_completed: None,
        owner_failures: vec![AcpMemberCloseFailure {
            thread_id: "actual-child".into(),
            message: "cleanup pending".into(),
        }],
    };
    let encoded = serde_json::to_value(&close).unwrap();
    let decoded: AcpBusinessClose = serde_json::from_value(encoded.clone()).unwrap();
    assert_eq!(serde_json::to_value(decoded).unwrap(), encoded);
    assert_eq!(encoded["localComplete"], false);
    assert_eq!(encoded["unfinishedPrompt"]["instance"], 9);
    assert_eq!(encoded["ownerFailures"][0]["threadId"], "actual-child");
}

#[test]
fn snapshot_keeps_distinct_config_types_grouping_metadata_and_absent_vs_empty() {
    let configs = serde_json::json!([
        {
            "id": "select-config", "name": "Model", "description": "Choose model",
            "category": "model", "type": "select", "currentValue": "second",
            "options": [{
                "group": "peer-group", "name": "Peer models",
                "options": [
                    {"value": "first", "name": "First", "description": "First model"},
                    {"value": "second", "name": "Second", "_meta": {"weight": 2}}
                ],
                "_meta": {"groupOrder": 3}
            }],
            "_meta": {"order": 7, "nested": {"peer": true}}
        },
        {
            "id": "boolean-config", "name": "Review", "description": "Require review",
            "type": "boolean", "currentValue": false,
            "_meta": {"order": 2}
        }
    ]);
    let mut snapshot = AcpBusinessSnapshot {
        target: AcpSessionTarget {
            session_id: "product-session".into(),
            agent_id: "product-agent".into(),
            thread_id: "product-thread".into(),
            instance: 41,
        },
        acp_session_id: Some("remote-session".into()),
        ready: true,
        closing: false,
        config_pending: false,
        config_options: Some(serde_json::from_value(configs.clone()).unwrap()),
        modes: None,
        active_run: None,
        last_completed: None,
        observation_gap: None,
        auth_methods: vec![],
    };
    let value = serde_json::to_value(&snapshot).unwrap();
    assert_eq!(value["configOptions"], configs);
    let decoded: AcpBusinessSnapshot = serde_json::from_value(value).unwrap();
    assert_eq!(decoded.config_options, snapshot.config_options);
    snapshot.config_options = Some(vec![]);
    assert_eq!(
        serde_json::to_value(&snapshot).unwrap()["configOptions"],
        serde_json::json!([])
    );
    snapshot.config_options = None;
    assert_eq!(
        serde_json::to_value(snapshot).unwrap()["configOptions"],
        serde_json::Value::Null
    );
}
