use pl_model_auth::chatgpt::{
    ChatGptAuthError, ChatGptCredentialRecord, ChatGptCredentialStorage, ChatGptSession,
};
use std::sync::Arc;

fn record() -> ChatGptCredentialRecord {
    serde_json::from_value(serde_json::json!({
            "schemaVersion": 1, "registrationId": "endpoint-fixture",
            "account": {"issuer": "https://auth.openai.com", "subject": "fixture-sub", "clientId": "fixture-client", "email": null, "planUsageEnabled": true},
            "extAgentHostId": "urn:uuid:00000000-0000-4000-8000-000000000001",
            "accessToken": "access", "refreshToken": "refresh", "idToken": "verified",
            "scopes": ["chatgpt.tokens.use.direct"], "expiresAt": 1,
            "earliestRefreshAt": null, "refreshInFlight": false
        })).unwrap()
}
struct Storage;
impl ChatGptCredentialStorage for Storage {
    fn load(&self) -> Result<ChatGptCredentialRecord, ChatGptAuthError> {
        Ok(record())
    }
    fn persist(&self, _: &str, _: &ChatGptCredentialRecord) -> Result<(), ChatGptAuthError> {
        panic!("endpoint policy must not refresh credentials")
    }
}
#[test]
fn chatgpt_endpoint_restricts_resource_transport_capabilities_and_authorization_owner() {
    let directory = tempfile::tempdir().unwrap();
    let session = ChatGptSession::new(
        &record(),
        Arc::new(Storage),
        directory.path().join("account.lock"),
    )
    .unwrap();
    let mut account = pl_model::config::builtin_account_catalog()
        .unwrap()
        .templates
        .into_iter()
        .find(|template| template.id.as_str() == "openai")
        .unwrap()
        .account;
    account.authentication = pl_model::config::AccountAuthenticationMethod::ChatGpt;
    account.chatgpt_account = Some(record().account);
    account.chatgpt_session = Some(session);
    account.bearer_token_env = None;
    account.http_headers = Some(
        [("authorization".into(), "Bearer legacy-api-key".into())]
            .into_iter()
            .collect(),
    );
    let endpoint = account.to_endpoint().unwrap();
    let headers = endpoint
        .request_headers(
            Some("selected-oauth-token"),
            &[("Authorization".into(), "Bearer model-override".into())]
                .into_iter()
                .collect(),
        )
        .unwrap();
    assert_eq!(
        headers[reqwest::header::AUTHORIZATION],
        "Bearer selected-oauth-token"
    );
    let capabilities = account.service_capabilities().unwrap();
    assert!(capabilities.image_generation.is_none());
    assert!(capabilities.web_search.standalone.is_none());
    assert!(!capabilities.remote_compaction);
    assert_eq!(capabilities.files, Default::default());
    let models = account.effective_catalog(None).unwrap();
    assert!(!models.is_empty());
    for entry in models {
        assert_eq!(
            entry.model.extra.binding.transport.protocol,
            pl_model::protocol::WireApi::Responses
        );
        assert_eq!(
            entry
                .model
                .extra
                .binding
                .transport
                .supported_connection_modes,
            [pl_model::protocol::ConnectionMode::Http]
        );
        assert_eq!(
            entry.model.extra.binding.transport.default_connection_mode,
            pl_model::protocol::ConnectionMode::Http
        );
    }
    account.base_url = "https://custom.example/v1".into();
    assert!(account.to_endpoint().is_err());
}
