use super::{
    CHATGPT_ISSUER, CHATGPT_RESOURCE, ChatGptAuthError, DIRECT_SCOPE, TokenResponse, exchange, now,
    oauth_client,
};
use oauth2::TokenResponse as _;
use pl_protocol::studio::ChatGptAccountInfo;
use std::path::PathBuf;
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

/// A complete protected keyring payload, never a settings/document/wire value.
#[derive(Clone, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatGptCredentialRecord {
    pub schema_version: u32,
    pub registration_id: String,
    pub account: ChatGptAccountInfo,
    pub ext_agent_host_id: String,
    pub access_token: String,
    pub refresh_token: String,
    pub id_token: String,
    pub scopes: Vec<String>,
    pub expires_at: i64,
    pub earliest_refresh_at: Option<i64>,
    /// Persisted *before* sending a rotating refresh. Any ambiguous failure requires login,
    /// including across process restart; the old one-use refresh is never replayed.
    pub refresh_in_flight: bool,
}

impl std::fmt::Debug for ChatGptCredentialRecord {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("ChatGptCredentialRecord(<redacted>)")
    }
}

impl ChatGptCredentialRecord {
    pub(super) fn from_response(
        account: ChatGptAccountInfo,
        host_id: String,
        id_token: String,
        response: TokenResponse,
        saved_at: i64,
    ) -> Result<Self, ChatGptAuthError> {
        if response.token_type() != &oauth2::basic::BasicTokenType::Bearer {
            return Err(ChatGptAuthError::InvalidIdentity);
        }
        let scopes: Vec<_> = response
            .scopes()
            .ok_or(ChatGptAuthError::MissingPlanPermission)?
            .iter()
            .map(|scope| scope.as_str().to_owned())
            .collect();
        if !scopes.iter().any(|scope| scope == DIRECT_SCOPE) {
            return Err(ChatGptAuthError::MissingPlanPermission);
        }
        let expires = response
            .expires_in()
            .filter(|expiry| expiry.as_secs() > 0)
            .ok_or(ChatGptAuthError::InvalidIdentity)?
            .as_secs();
        let refresh_token = response
            .refresh_token()
            .filter(|token| !token.secret().is_empty())
            .ok_or(ChatGptAuthError::InvalidIdentity)?
            .secret()
            .clone();
        let record = Self {
            schema_version: 1,
            // Cryptographically random, opaque local ownership generation; not the OAuth client ID.
            registration_id: oauth2::CsrfToken::new_random().secret().clone(),
            account,
            ext_agent_host_id: host_id,
            access_token: response.access_token().secret().clone(),
            refresh_token,
            id_token,
            scopes,
            expires_at: saved_at
                .checked_add(i64::try_from(expires).map_err(|_| ChatGptAuthError::InvalidIdentity)?)
                .ok_or(ChatGptAuthError::InvalidIdentity)?,
            earliest_refresh_at: response.extra_fields().earliest_refresh_at,
            refresh_in_flight: false,
        };
        record.validate()?;
        Ok(record)
    }

    pub fn validate(&self) -> Result<(), ChatGptAuthError> {
        if self.schema_version != 1
            || self.registration_id.is_empty()
            || self.account.issuer != CHATGPT_ISSUER
            || self.account.subject.is_empty()
            || self.account.client_id.is_empty()
            || self.account.client_id == "dynamic_agent_client"
            || self.access_token.is_empty()
            || self.refresh_token.is_empty()
            || self.id_token.is_empty()
        {
            return Err(ChatGptAuthError::InvalidIdentity);
        }
        if !self.account.plan_usage_enabled
            || !self.scopes.iter().any(|scope| scope == DIRECT_SCOPE)
        {
            return Err(ChatGptAuthError::MissingPlanPermission);
        }
        Ok(())
    }
}

/// Injected by the host. All IO is strict durable read/write, never a process lease.
/// `persist` must compare the current protected registration ID before replacing it, and
/// read back the complete record from the durable store before returning success.
/// Host replacement/delete and this capability must hold the same `lock_path` file lock.
pub trait ChatGptCredentialStorage: Send + Sync {
    fn load(&self) -> Result<ChatGptCredentialRecord, ChatGptAuthError>;
    fn persist(
        &self,
        expected_registration: &str,
        record: &ChatGptCredentialRecord,
    ) -> Result<(), ChatGptAuthError>;
}

#[derive(Clone)]
pub struct ChatGptSession {
    inner: Arc<SessionInner>,
}

struct SessionInner {
    registration: String,
    identity: ChatGptAccountInfo,
    storage: Arc<dyn ChatGptCredentialStorage>,
    lock_path: PathBuf,
    serial: tokio::sync::Mutex<()>,
    revoked: AtomicBool,
    failed: AtomicBool,
}

impl std::fmt::Debug for ChatGptSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("ChatGptSession(<redacted>)")
    }
}
impl PartialEq for ChatGptSession {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.inner, &other.inner)
    }
}
impl Eq for ChatGptSession {}

impl ChatGptSession {
    /// Opaque local connection generation, safe only as an input to isolation fingerprints.
    pub fn registration_id(&self) -> &str {
        &self.inner.registration
    }
    pub fn new(
        record: &ChatGptCredentialRecord,
        storage: Arc<dyn ChatGptCredentialStorage>,
        lock_path: PathBuf,
    ) -> Result<Self, ChatGptAuthError> {
        record.validate()?;
        Ok(Self {
            inner: Arc::new(SessionInner {
                registration: record.registration_id.clone(),
                identity: record.account.clone(),
                storage,
                lock_path,
                serial: tokio::sync::Mutex::new(()),
                revoked: AtomicBool::new(false),
                failed: AtomicBool::new(false),
            }),
        })
    }

    pub fn revoke(&self) {
        self.inner.revoked.store(true, Ordering::Release);
    }

    pub fn validate_resource(base_url: &str) -> Result<(), ChatGptAuthError> {
        if base_url != CHATGPT_RESOURCE {
            return Err(ChatGptAuthError::UnsupportedResource);
        }
        Ok(())
    }

    /// Route clones share this owner. Interprocess locking precedes strict re-read, so no
    /// process may reuse its cached refresh token after another process rotates it.
    pub async fn access_token(&self) -> Result<String, ChatGptAuthError> {
        self.access_token_with_http(&exchange).await
    }

    async fn access_token_with_http<F, Fut>(&self, http: &F) -> Result<String, ChatGptAuthError>
    where
        F: Fn(oauth2::HttpRequest) -> Fut + Sync,
        Fut: std::future::Future<Output = Result<oauth2::HttpResponse, ChatGptAuthError>>
            + Send
            + 'static,
    {
        let _serial = self.inner.serial.lock().await;
        if self.inner.revoked.load(Ordering::Acquire) {
            return Err(ChatGptAuthError::Revoked);
        }
        if self.inner.failed.load(Ordering::Acquire) {
            return Err(ChatGptAuthError::ReauthorizationRequired);
        }
        let path = self.inner.lock_path.clone();
        let lock = {
            let mut options = std::fs::OpenOptions::new();
            options.read(true).write(true).create(true).truncate(false);
            #[cfg(unix)]
            {
                use std::os::unix::fs::OpenOptionsExt;
                options.mode(0o600);
            }
            let file = options.open(path).map_err(|_| ChatGptAuthError::Storage)?;
            let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(30);
            loop {
                match fs4::FileExt::try_lock(&file) {
                    Ok(()) => break,
                    Err(fs4::TryLockError::WouldBlock) => {
                        if tokio::time::Instant::now() >= deadline {
                            return Err(ChatGptAuthError::Storage);
                        }
                        tokio::time::sleep(std::time::Duration::from_millis(25)).await;
                    }
                    Err(_) => return Err(ChatGptAuthError::Storage),
                }
            }
            file
        };
        let result = self.access_token_locked(http).await;
        drop(lock);
        result
    }

    async fn access_token_locked<F, Fut>(&self, http: &F) -> Result<String, ChatGptAuthError>
    where
        F: Fn(oauth2::HttpRequest) -> Fut + Sync,
        Fut: std::future::Future<Output = Result<oauth2::HttpResponse, ChatGptAuthError>>
            + Send
            + 'static,
    {
        let mut record = self.inner.storage.load()?;
        record.validate()?;
        if record.registration_id != self.inner.registration
            || record.account != self.inner.identity
            || self.inner.revoked.load(Ordering::Acquire)
        {
            return Err(ChatGptAuthError::Revoked);
        }
        if record.refresh_in_flight {
            return Err(ChatGptAuthError::ReauthorizationRequired);
        }
        let time = now();
        if record.expires_at > time + 60
            || record
                .earliest_refresh_at
                .is_some_and(|earliest| time < earliest && record.expires_at > time)
        {
            return Ok(record.access_token);
        }
        if record
            .earliest_refresh_at
            .is_some_and(|earliest| time < earliest)
        {
            return Err(ChatGptAuthError::Expired);
        }
        record.refresh_in_flight = true;
        self.inner
            .storage
            .persist(&self.inner.registration, &record)?;
        // Cancellation after this point also leaves the durable one-use marker intact.
        self.inner.failed.store(true, Ordering::Release);
        let mut next = super::within_operation_limit(async {
            let client = oauth_client(&record.account.client_id);
            let response = client
                .exchange_refresh_token(&oauth2::RefreshToken::new(record.refresh_token.clone()))
                .add_extra_param("resource", CHATGPT_RESOURCE)
                .request_async(http)
                .await
                .map_err(|_| ChatGptAuthError::ReauthorizationRequired)?;
            // A refresh ID token, if present, must still validate against the selected registration.
            // Ordinary refreshes may omit it. Never replace a retained token with unverified bytes.
            let retained_id_token = if let Some(id_token) = &response.extra_fields().id_token {
                let metadata = openidconnect::core::CoreProviderMetadata::discover_async(
                    openidconnect::IssuerUrl::new(CHATGPT_ISSUER.into())
                        .map_err(|_| ChatGptAuthError::InvalidIdentity)?,
                    http,
                )
                .await
                .map_err(|_| ChatGptAuthError::InvalidIdentity)?;
                let client = openidconnect::core::CoreClient::from_provider_metadata(
                    metadata,
                    openidconnect::ClientId::new(record.account.client_id.clone()),
                    None,
                );
                // OIDC refresh responses need not repeat the original authorization nonce.
                let verifier = client.id_token_verifier();
                let claims = id_token
                    .claims(&verifier, |_: Option<&openidconnect::Nonce>| Ok(()))
                    .map_err(|_| ChatGptAuthError::InvalidIdentity)?;
                if claims.subject().as_str() != record.account.subject {
                    return Err(ChatGptAuthError::InvalidIdentity);
                }
                if let Some(expected) = claims.access_token_hash() {
                    let actual = openidconnect::AccessTokenHash::from_token(
                        response.access_token(),
                        id_token
                            .signing_alg()
                            .map_err(|_| ChatGptAuthError::InvalidIdentity)?,
                        id_token
                            .signing_key(&verifier)
                            .map_err(|_| ChatGptAuthError::InvalidIdentity)?,
                    )
                    .map_err(|_| ChatGptAuthError::InvalidIdentity)?;
                    if &actual != expected {
                        return Err(ChatGptAuthError::InvalidIdentity);
                    }
                }
                id_token.to_string()
            } else {
                record.id_token.clone()
            };
            ChatGptCredentialRecord::from_response(
                record.account,
                record.ext_agent_host_id,
                retained_id_token,
                response,
                now(),
            )
        })
        .await?;
        next.registration_id = self.inner.registration.clone();
        if self.inner.revoked.load(Ordering::Acquire) {
            return Err(ChatGptAuthError::Revoked);
        }
        self.inner
            .storage
            .persist(&self.inner.registration, &next)?;
        self.inner.failed.store(false, Ordering::Release);
        Ok(next.access_token)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::sync::{Mutex, atomic::AtomicUsize};

    struct Storage {
        record: Mutex<ChatGptCredentialRecord>,
        reads: AtomicUsize,
        writes: AtomicUsize,
        fail_write: usize,
    }
    impl ChatGptCredentialStorage for Storage {
        fn load(&self) -> Result<ChatGptCredentialRecord, ChatGptAuthError> {
            self.reads.fetch_add(1, Ordering::SeqCst);
            Ok(self.record.lock().unwrap().clone())
        }
        fn persist(
            &self,
            expected: &str,
            record: &ChatGptCredentialRecord,
        ) -> Result<(), ChatGptAuthError> {
            let write = self.writes.fetch_add(1, Ordering::SeqCst) + 1;
            if write == self.fail_write {
                return Err(ChatGptAuthError::Storage);
            }
            let mut current = self.record.lock().unwrap();
            if current.registration_id != expected {
                return Err(ChatGptAuthError::Revoked);
            }
            *current = record.clone();
            Ok(())
        }
    }
    fn record() -> ChatGptCredentialRecord {
        ChatGptCredentialRecord {
            schema_version: 1,
            registration_id: "fixture-generation".into(),
            account: ChatGptAccountInfo {
                issuer: CHATGPT_ISSUER.into(),
                subject: "fixture-sub".into(),
                client_id: "fixture-client".into(),
                email: None,
                plan_usage_enabled: true,
            },
            ext_agent_host_id: "urn:uuid:00000000-0000-4000-8000-000000000001".into(),
            access_token: "old-access".into(),
            refresh_token: "one-use-refresh".into(),
            id_token: "retained-verified-id-token".into(),
            scopes: vec![DIRECT_SCOPE.into()],
            expires_at: now() - 1,
            earliest_refresh_at: None,
            refresh_in_flight: false,
        }
    }
    fn storage(fail_write: usize) -> Arc<Storage> {
        Arc::new(Storage {
            record: Mutex::new(record()),
            reads: AtomicUsize::new(0),
            writes: AtomicUsize::new(0),
            fail_write,
        })
    }

    #[test]
    fn chatgpt_endpoint_restricts_resource_transport_capabilities_and_authorization_owner() {
        let directory = tempfile::tempdir().unwrap();
        let session =
            ChatGptSession::new(&record(), storage(0), directory.path().join("account.lock"))
                .unwrap();
        let mut account = crate::config::builtin_account_catalog()
            .unwrap()
            .templates
            .into_iter()
            .find(|template| template.id.as_str() == "openai")
            .unwrap()
            .account;
        account.authentication = pl_protocol::studio::AccountAuthenticationMethod::ChatGpt;
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
                entry.model.binding.transport.protocol,
                crate::protocol::WireApi::Responses
            );
            assert_eq!(
                entry.model.binding.transport.supported_connection_modes,
                [crate::protocol::ConnectionMode::Http]
            );
            assert_eq!(
                entry.model.binding.transport.default_connection_mode,
                crate::protocol::ConnectionMode::Http
            );
        }
        account.base_url = "https://custom.example/v1".into();
        assert!(account.to_endpoint().is_err());
    }
    fn refresh_http(calls: &AtomicUsize, request: oauth2::HttpRequest) -> oauth2::HttpResponse {
        calls.fetch_add(1, Ordering::SeqCst);
        assert_eq!(request.uri().to_string(), super::super::TOKEN);
        let form: std::collections::BTreeMap<_, _> = url::form_urlencoded::parse(request.body())
            .into_owned()
            .collect();
        assert_eq!(form["grant_type"], "refresh_token");
        assert_eq!(form["refresh_token"], "one-use-refresh");
        assert_eq!(form["client_id"], "fixture-client");
        assert_eq!(form["resource"], CHATGPT_RESOURCE);
        assert!(!form.contains_key("scope"));
        oauth2::http::Response::builder().status(200).header("content-type", "application/json")
            .body(serde_json::to_vec(&json!({
                "access_token": "new-access", "refresh_token": "rotated-refresh", "token_type": "Bearer",
                "scope": DIRECT_SCOPE, "expires_in": 3600, "earliest_refresh_at": now() + 1200
            })).unwrap()).unwrap()
    }

    #[tokio::test]
    async fn refresh_rotates_once_across_route_clones_and_independent_owners() {
        let directory = tempfile::tempdir().unwrap();
        let storage = storage(0);
        let first = ChatGptSession::new(
            &record(),
            storage.clone(),
            directory.path().join("account.lock"),
        )
        .unwrap();
        let second = ChatGptSession::new(
            &record(),
            storage.clone(),
            directory.path().join("account.lock"),
        )
        .unwrap();
        let cloned = first.clone();
        let calls = AtomicUsize::new(0);
        let http = |request| {
            let response = refresh_http(&calls, request);
            async { Ok(response) }
        };
        let (one, two, three) = tokio::join!(
            first.access_token_with_http(&http),
            second.access_token_with_http(&http),
            cloned.access_token_with_http(&http)
        );
        assert_eq!(
            [one.unwrap(), two.unwrap(), three.unwrap()],
            ["new-access", "new-access", "new-access"]
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        let stored = storage.record.lock().unwrap();
        assert_eq!(stored.refresh_token, "rotated-refresh");
        assert!(stored.earliest_refresh_at.unwrap() > now());
        assert!(!stored.refresh_in_flight);
        assert_eq!(storage.writes.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn ambiguous_refresh_and_durable_write_failure_never_replay_after_restart() {
        for network_failure in [false, true] {
            let directory = tempfile::tempdir().unwrap();
            let storage = storage(if network_failure { 0 } else { 2 });
            let session = ChatGptSession::new(
                &record(),
                storage.clone(),
                directory.path().join("account.lock"),
            )
            .unwrap();
            let calls = AtomicUsize::new(0);
            let http = |request| {
                let response = refresh_http(&calls, request);
                async move {
                    if network_failure {
                        Err(ChatGptAuthError::Network)
                    } else {
                        Ok(response)
                    }
                }
            };
            assert!(session.access_token_with_http(&http).await.is_err());
            assert_eq!(
                session.access_token_with_http(&http).await,
                Err(ChatGptAuthError::ReauthorizationRequired)
            );
            let restarted = ChatGptSession::new(
                &record(),
                storage.clone(),
                directory.path().join("account.lock"),
            )
            .unwrap();
            assert_eq!(
                restarted.access_token_with_http(&http).await,
                Err(ChatGptAuthError::ReauthorizationRequired)
            );
            assert_eq!(calls.load(Ordering::SeqCst), 1);
            assert!(storage.record.lock().unwrap().refresh_in_flight);
        }
    }

    #[tokio::test(start_paused = true)]
    async fn refresh_operation_deadline_keeps_the_one_use_marker_and_never_replays() {
        let directory = tempfile::tempdir().unwrap();
        let storage = storage(0);
        let path = directory.path().join("account.lock");
        let session = ChatGptSession::new(&record(), storage.clone(), path.clone()).unwrap();
        let calls = AtomicUsize::new(0);
        let http = |request| {
            let response = refresh_http(&calls, request);
            async move {
                tokio::time::sleep(std::time::Duration::from_secs(31)).await;
                Ok(response)
            }
        };
        assert_eq!(
            session.access_token_with_http(&http).await,
            Err(ChatGptAuthError::Network)
        );
        assert!(storage.record.lock().unwrap().refresh_in_flight);
        let restarted = ChatGptSession::new(&record(), storage, path).unwrap();
        assert_eq!(
            restarted.access_token_with_http(&http).await,
            Err(ChatGptAuthError::ReauthorizationRequired)
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn cancelling_lock_wait_leaves_no_worker_or_lock_and_earliest_refresh_is_honored() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("account.lock");
        let holder = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(&path)
            .unwrap();
        fs4::FileExt::try_lock(&holder).unwrap();
        let storage = storage(0);
        storage.record.lock().unwrap().expires_at = now() + 20;
        storage.record.lock().unwrap().earliest_refresh_at = Some(now() + 10);
        let session = ChatGptSession::new(&record(), storage.clone(), path.clone()).unwrap();
        let calls = AtomicUsize::new(0);
        let http = |request| {
            let response = refresh_http(&calls, request);
            async { Ok(response) }
        };
        assert!(
            tokio::time::timeout(
                std::time::Duration::from_millis(30),
                session.access_token_with_http(&http)
            )
            .await
            .is_err()
        );
        assert_eq!(storage.reads.load(Ordering::SeqCst), 0);
        drop(holder);
        let after_cancel = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(&path)
            .unwrap();
        fs4::FileExt::try_lock(&after_cancel).unwrap();
        drop(after_cancel);
        assert_eq!(
            session.access_token_with_http(&http).await.unwrap(),
            "old-access"
        );
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        session.revoke();
        assert_eq!(
            session.access_token_with_http(&http).await,
            Err(ChatGptAuthError::Revoked)
        );
    }
}
