use super::*;
use axum::body::{Body, to_bytes};
use axum::http::Request;
use pl_protocol::studio::{AcpProvider, StudioErrorCode};

async fn extract<T: serde::de::DeserializeOwned>(body: serde_json::Value) -> Result<T, ApiError> {
    let request = Request::builder()
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(body.to_string()))
        .unwrap();
    ApiJson::<T>::from_request(request, &())
        .await
        .map(|ApiJson(value)| value)
}

#[tokio::test]
async fn acp_account_http_input_preserves_sources_launch_literals_and_document_cas() {
    let request = extract::<UpdateAcpAccountRequest>(serde_json::json!({
        "operationId": "save-op",
        "expectedRevision": 6,
        "expectedDocumentRevision": 19,
        "account": {
            "accountId": "custom-agent",
            "name": "Custom",
            "template": null,
            "command": "/a path/agent",
            "args": ["two words", "$(literal)", ""],
            "env": {"KEY": " raw value "},
            "enabled": false
        }
    }))
    .await
    .unwrap_or_else(|_| panic!("valid generic account rejected"));
    assert_eq!(request.operation_id, "save-op");
    assert_eq!(request.expected_revision, 6);
    assert_eq!(request.expected_document_revision, Some(19));
    assert_eq!(request.account.template, None);
    assert_eq!(request.account.command.as_deref(), Some("/a path/agent"));
    assert_eq!(
        request.account.args,
        Some(vec!["two words".into(), "$(literal)".into(), "".into()])
    );
    assert_eq!(request.account.env["KEY"], " raw value ");
    assert!(!request.account.enabled);

    let managed = extract::<UpdateAcpAccountRequest>(serde_json::json!({
        "operationId": "create-op",
        "expectedRevision": 7,
        "expectedDocumentRevision": null,
        "account": {
            "accountId": "managed",
            "name": "Managed",
            "template": "antigravity"
        }
    }))
    .await
    .unwrap_or_else(|_| panic!("valid managed account rejected"));
    assert_eq!(managed.expected_document_revision, None);
    assert_eq!(managed.account.template, Some(AcpProvider::Antigravity));
    assert_eq!(managed.account.command, None);
    assert_eq!(managed.account.args, None);

    let remove = extract::<RemoveAcpAccountRequest>(serde_json::json!({
        "operationId": "remove-op",
        "expectedRevision": 8,
        "accountId": "custom-agent",
        "expectedDocumentRevision": 19
    }))
    .await
    .unwrap_or_else(|_| panic!("valid removal rejected"));
    assert_eq!(remove.account_id, "custom-agent");
    assert_eq!(remove.expected_document_revision, 19);
}

#[tokio::test]
async fn acp_detection_http_input_keeps_cancel_target_and_safe_error_envelope() {
    let target = extract::<AccountObservationTarget>(serde_json::json!({
        "kind": "acpLocalDetection"
    }))
    .await
    .unwrap_or_else(|_| panic!("valid detection observation rejected"));
    assert_eq!(target, AccountObservationTarget::AcpLocalDetection);

    let cancel = extract::<CancelAcpLocalDetectionRequest>(serde_json::json!({
        "operationId": "cancel-op",
        "targetOperationId": "target-op"
    }))
    .await
    .unwrap_or_else(|_| panic!("valid cancel rejected"));
    assert_eq!(cancel.operation_id, "cancel-op");
    assert_eq!(cancel.target_operation_id, "target-op");

    let error = match extract::<CancelAcpLocalDetectionRequest>(serde_json::json!({
        "operationId": "cancel-op",
        "targetOperationId": "target-op",
        "rawPayload": "not-for-error-output"
    }))
    .await
    {
        Err(error) => error,
        Ok(_) => panic!("unknown request field accepted"),
    };
    let response = error.into_response();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let correlation_id = response.headers()["x-correlation-id"].clone();
    let body = to_bytes(response.into_body(), 4096).await.unwrap();
    let error: StudioError = serde_json::from_slice(&body).unwrap();
    assert_eq!(error.code, StudioErrorCode::InvalidArgument);
    assert_eq!(error.message, "invalid JSON request body");
    assert_eq!(error.correlation_id, correlation_id.to_str().unwrap());
    assert!(!String::from_utf8_lossy(&body).contains("not-for-error-output"));
}
