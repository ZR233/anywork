use super::{
    CHATGPT_ISSUER, CHATGPT_RESOURCE, ChatGptAuthError, DIRECT_SCOPE, exchange, now, oauth_client,
    session::ChatGptCredentialRecord,
};
use oauth2::TokenResponse as _;
use oauth2::{
    AuthorizationCode, CsrfToken, PkceCodeChallenge, PkceCodeVerifier, RedirectUrl, Scope,
};
use openidconnect::{AccessTokenHash, ClientId, IssuerUrl, Nonce};
use pl_protocol::studio::ChatGptAccountInfo;
use std::collections::BTreeMap;
use tokio::net::TcpListener;
use url::Url;

/// One pending authorization owns its loopback socket and one-use PKCE material.
/// Dropping the future/socket cancels all IO; no worker is detached by this layer.
pub struct ChatGptAuthorization {
    listener: TcpListener,
    url: Url,
    redirect: RedirectUrl,
    state: CsrfToken,
    nonce: Nonce,
    verifier: PkceCodeVerifier,
    host_id: String,
    previous: Option<ChatGptAccountInfo>,
}

impl std::fmt::Debug for ChatGptAuthorization {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("ChatGptAuthorization(<redacted>)")
    }
}

impl ChatGptAuthorization {
    pub async fn prepare(
        host_id: String,
        previous: Option<ChatGptAccountInfo>,
    ) -> Result<Self, ChatGptAuthError> {
        if !host_id.starts_with("urn:uuid:")
            || previous.as_ref().is_some_and(|info| {
                info.issuer != CHATGPT_ISSUER
                    || info.client_id.is_empty()
                    || info.client_id == "dynamic_agent_client"
            })
        {
            return Err(ChatGptAuthError::InvalidIdentity);
        }
        let listener = TcpListener::bind(("127.0.0.1", 0))
            .await
            .map_err(|_| ChatGptAuthError::Network)?;
        let port = listener
            .local_addr()
            .map_err(|_| ChatGptAuthError::Network)?
            .port();
        let redirect = RedirectUrl::new(format!("http://127.0.0.1:{port}/auth/callback"))
            .map_err(|_| ChatGptAuthError::InvalidCallback)?;
        let id = previous
            .as_ref()
            .map_or("dynamic_agent_client", |info| info.client_id.as_str());
        let client = oauth_client(id).set_redirect_uri(redirect.clone());
        let nonce = Nonce::new_random();
        let (challenge, verifier) = PkceCodeChallenge::new_random_sha256();
        let mut authorization = client
            .authorize_url(CsrfToken::new_random)
            .set_pkce_challenge(challenge)
            .add_extra_param("nonce", nonce.secret())
            .add_extra_param("ext_agent_host_id", &host_id)
            .add_extra_param("resource", CHATGPT_RESOURCE);
        for scope in [
            "openid",
            "profile",
            "email",
            "offline_access",
            "resource.invoke",
            DIRECT_SCOPE,
        ] {
            authorization = authorization.add_scope(Scope::new(scope.into()));
        }
        if let Some(previous) = &previous {
            if let Some(email) = &previous.email {
                authorization = authorization.add_extra_param("login_hint", email);
            }
        } else {
            authorization = authorization.add_extra_param("agent_name_hint", "anywork");
        }
        let (url, state) = authorization.url();
        Ok(Self {
            listener,
            url,
            redirect,
            state,
            nonce,
            verifier,
            host_id,
            previous,
        })
    }

    /// Only this explicitly requested projection may expose the browser URL.
    pub fn authorization_url(&self) -> &str {
        self.url.as_str()
    }

    pub async fn finish(self) -> Result<ChatGptCredentialRecord, ChatGptAuthError> {
        self.finish_with_progress(|| {}).await
    }

    pub async fn finish_with_progress(
        self,
        exchanging: impl FnOnce() + Send,
    ) -> Result<ChatGptCredentialRecord, ChatGptAuthError> {
        self.finish_with_http(exchanging, &exchange).await
    }

    async fn finish_with_http<F, Fut>(
        self,
        exchanging: impl FnOnce() + Send,
        http: &F,
    ) -> Result<ChatGptCredentialRecord, ChatGptAuthError>
    where
        F: Fn(oauth2::HttpRequest) -> Fut + Sync,
        Fut: std::future::Future<Output = Result<oauth2::HttpResponse, ChatGptAuthError>>
            + Send
            + 'static,
    {
        let callback =
            tokio::time::timeout(std::time::Duration::from_secs(15 * 60), self.callback())
                .await
                .map_err(|_| ChatGptAuthError::Expired)??;
        let (code, client_id) = callback;
        exchanging();
        super::within_operation_limit(async {
            // Resolve/validate discovery before consuming the one-use code.
            let metadata = openidconnect::core::CoreProviderMetadata::discover_async(
                IssuerUrl::new(CHATGPT_ISSUER.into())
                    .map_err(|_| ChatGptAuthError::InvalidIdentity)?,
                http,
            )
            .await
            .map_err(|_| ChatGptAuthError::InvalidIdentity)?;
            let verifier = openidconnect::core::CoreClient::from_provider_metadata(
                metadata,
                ClientId::new(client_id.clone()),
                None,
            );
            // oauth2 performs the grant construction and typed token-response parsing.
            let client = oauth_client(&client_id).set_redirect_uri(self.redirect);
            let response = client
                .exchange_code(AuthorizationCode::new(code))
                .set_pkce_verifier(self.verifier)
                .add_extra_param("resource", CHATGPT_RESOURCE)
                .request_async(http)
                .await
                .map_err(|_| ChatGptAuthError::Network)?;
            let id_token = response
                .extra_fields()
                .id_token
                .as_ref()
                .ok_or(ChatGptAuthError::InvalidIdentity)?;
            let id_verifier = verifier.id_token_verifier();
            let claims = id_token
                .claims(&id_verifier, &self.nonce)
                .map_err(|_| ChatGptAuthError::InvalidIdentity)?;
            if let Some(expected) = claims.access_token_hash() {
                let actual = AccessTokenHash::from_token(
                    response.access_token(),
                    id_token
                        .signing_alg()
                        .map_err(|_| ChatGptAuthError::InvalidIdentity)?,
                    id_token
                        .signing_key(&id_verifier)
                        .map_err(|_| ChatGptAuthError::InvalidIdentity)?,
                )
                .map_err(|_| ChatGptAuthError::InvalidIdentity)?;
                if &actual != expected {
                    return Err(ChatGptAuthError::InvalidIdentity);
                }
            }
            let info = ChatGptAccountInfo {
                issuer: CHATGPT_ISSUER.into(),
                subject: claims.subject().as_str().into(),
                client_id,
                email: claims.email().map(|email| email.as_str().into()),
                plan_usage_enabled: true,
            };
            if self.previous.as_ref().is_some_and(|previous| {
                previous.subject != info.subject || previous.issuer != info.issuer
            }) {
                return Err(ChatGptAuthError::InvalidIdentity);
            }
            ChatGptCredentialRecord::from_response(
                info,
                self.host_id,
                id_token.to_string(),
                response,
                now(),
            )
        })
        .await
    }

    async fn callback(&self) -> Result<(String, String), ChatGptAuthError> {
        loop {
            let (socket, _) = self
                .listener
                .accept()
                .await
                .map_err(|_| ChatGptAuthError::Network)?;
            let accepted = std::sync::Mutex::new(None);
            let service =
                hyper::service::service_fn(|request: hyper::Request<hyper::body::Incoming>| {
                    let result = self.parse_callback(&request);
                    let valid = result.is_some();
                    if valid {
                        *accepted.lock().unwrap_or_else(|error| error.into_inner()) = result;
                    }
                    async move {
                        Ok::<_, std::convert::Infallible>(
                            hyper::Response::builder()
                                .status(if valid { 200 } else { 400 })
                                .header("content-type", "text/plain; charset=utf-8")
                                .header("cache-control", "no-store")
                                .header("connection", "close")
                                .body(axum::body::Body::from(if valid {
                                    "Authorization received. You may close this window."
                                } else {
                                    "Invalid authorization callback."
                                }))
                                .expect("static callback response"),
                        )
                    }
                });
            // Hyper owns HTTP framing/limits. This connection future owns the only accepted
            // socket and is never spawned; cancellation/drop closes it synchronously.
            let mut builder = hyper::server::conn::http1::Builder::new();
            builder.keep_alive(false).max_buf_size(8192);
            let _ = tokio::time::timeout(
                std::time::Duration::from_secs(3),
                builder.serve_connection(hyper_util::rt::TokioIo::new(socket), service),
            )
            .await;
            if let Some(result) = accepted
                .into_inner()
                .unwrap_or_else(|error| error.into_inner())
            {
                return result;
            }
        }
    }

    fn parse_callback<B>(
        &self,
        request: &hyper::Request<B>,
    ) -> Option<Result<(String, String), ChatGptAuthError>> {
        if request.method() != hyper::Method::GET
            || request.uri().path() != "/auth/callback"
            || request.uri().scheme().is_some()
            || request.uri().authority().is_some()
        {
            return None;
        }
        let axum::extract::Query(pairs) =
            axum::extract::Query::<Vec<(String, String)>>::try_from_uri(request.uri()).ok()?;
        let mut params = BTreeMap::new();
        for (key, value) in pairs {
            if params.insert(key, value).is_some() {
                return None;
            }
        }
        // Hash comparison follows openidconnect's nonce verifier, avoiding an early-exit
        // character-by-character comparison of the random authorization binding.
        use sha2::{Digest, Sha256};
        if Sha256::digest(params.get("state")?.as_bytes())
            != Sha256::digest(self.state.secret().as_bytes())
        {
            return None;
        }
        Some(self.valid_callback(params))
    }

    fn valid_callback(
        &self,
        mut params: BTreeMap<String, String>,
    ) -> Result<(String, String), ChatGptAuthError> {
        if let Some(error) = params.remove("error") {
            return Err(if error == "access_denied" {
                ChatGptAuthError::AuthorizationDenied
            } else {
                ChatGptAuthError::InvalidCallback
            });
        }
        let client_id = match (&self.previous, params.remove("client_id")) {
            (Some(previous), Some(id)) if id != previous.client_id => {
                return Err(ChatGptAuthError::InvalidIdentity);
            }
            (Some(previous), _) => previous.client_id.clone(),
            (None, Some(id)) if !id.is_empty() && id != "dynamic_agent_client" => id,
            _ => return Err(ChatGptAuthError::InvalidCallback),
        };
        let code = params
            .remove("code")
            .filter(|code| !code.is_empty())
            .ok_or(ChatGptAuthError::InvalidCallback)?;
        Ok((code, client_id))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use openidconnect::{
        PrivateSigningKey,
        core::{
            CoreEdDsaPrivateSigningKey, CoreIdToken, CoreIdTokenClaims, CoreJwsSigningAlgorithm,
        },
    };
    use serde_json::json;
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };

    // Generated exclusively for this synthetic OIDC issuer; never a user credential.
    const TEST_KEY: &str = "-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIP7pMOiwZ7NV0btLR8wY2WhnPmxnJ0SIQie/6DbmIE7A\n-----END PRIVATE KEY-----";

    async fn signed_flow(
        case: &str,
        previous: Option<ChatGptAccountInfo>,
    ) -> Result<ChatGptCredentialRecord, ChatGptAuthError> {
        let authorization = ChatGptAuthorization::prepare(
            "urn:uuid:00000000-0000-4000-8000-000000000001".into(),
            previous,
        )
        .await
        .unwrap();
        let params: BTreeMap<_, _> = authorization
            .url
            .query_pairs()
            .map(|(key, value)| (key.into_owned(), value.into_owned()))
            .collect();
        assert_eq!(
            params["scope"],
            "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
        );
        assert_eq!(params["resource"], CHATGPT_RESOURCE);
        assert!(!params.contains_key("id_token_hint"));
        let redirect = authorization.redirect.as_str().to_owned();
        let mut callback = Url::parse(&redirect).unwrap();
        callback
            .query_pairs_mut()
            .append_pair("state", &params["state"])
            .append_pair("code", "one-use-code")
            .append_pair("client_id", "issued-client");
        if case == "client" {
            callback.set_query(None);
            callback
                .query_pairs_mut()
                .append_pair("state", &params["state"])
                .append_pair("code", "one-use-code")
                .append_pair("client_id", "changed-client");
        } else if case == "missing-client" {
            callback.set_query(None);
            callback
                .query_pairs_mut()
                .append_pair("state", &params["state"])
                .append_pair("code", "one-use-code");
        } else if case == "denied" {
            callback.set_query(None);
            callback
                .query_pairs_mut()
                .append_pair("state", &params["state"])
                .append_pair("error", "access_denied");
        }
        let key = CoreEdDsaPrivateSigningKey::from_ed25519_pem(TEST_KEY, None).unwrap();
        let mut claims = json!({
            "iss": CHATGPT_ISSUER, "sub": "signed-subject", "aud": ["issued-client"],
            "iat": now(), "exp": now() + 3600, "nonce": params["nonce"], "email": "fixture@example.test"
        });
        match case {
            "issuer" => claims["iss"] = json!("https://wrong.example"),
            "audience" => claims["aud"] = json!(["wrong-client"]),
            "expiry" => claims["exp"] = json!(now() - 3600),
            "nonce" => claims["nonce"] = json!("wrong-nonce"),
            _ => {}
        }
        let claims: CoreIdTokenClaims = serde_json::from_value(claims).unwrap();
        let signed =
            CoreIdToken::new(claims, &key, CoreJwsSigningAlgorithm::EdDsa, None, None).unwrap();
        let mut jwks = json!({"keys": [key.as_verification_key()]});
        if case == "signature" {
            jwks["keys"][0]["x"] = json!("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
        }
        let token = json!({
            "access_token": if case == "empty-access" { "" } else { "fixture-access" }, "refresh_token": "fixture-refresh", "id_token": signed.to_string(),
            "token_type": "Bearer", "expires_in": 3600, "earliest_refresh_at": now() + 1800,
            "scope": if case == "scope" { "openid profile email offline_access" } else { DIRECT_SCOPE }
        });
        let exchanges = Arc::new(AtomicUsize::new(0));
        let count = exchanges.clone();
        let http = move |request: oauth2::HttpRequest| {
            let uri = request.uri().to_string();
            let body = if uri.ends_with("/.well-known/openid-configuration") {
                json!({
                    "issuer": CHATGPT_ISSUER, "authorization_endpoint": super::super::AUTHORIZE,
                    "token_endpoint": super::super::TOKEN, "jwks_uri": "https://auth.openai.com/fixture-jwks",
                    "response_types_supported": ["code"], "subject_types_supported": ["public"],
                    "id_token_signing_alg_values_supported": ["EdDSA"]
                })
            } else if uri.ends_with("/fixture-jwks") {
                jwks.clone()
            } else {
                assert_eq!(uri, super::super::TOKEN);
                assert_eq!(request.method(), hyper::Method::POST);
                let form: BTreeMap<_, _> = url::form_urlencoded::parse(request.body())
                    .map(|(key, value)| (key.into_owned(), value.into_owned()))
                    .collect();
                assert_eq!(form["grant_type"], "authorization_code");
                assert_eq!(form["client_id"], "issued-client");
                assert_eq!(form["redirect_uri"], redirect);
                assert_eq!(form["code"], "one-use-code");
                assert_eq!(form["resource"], CHATGPT_RESOURCE);
                let challenge = PkceCodeChallenge::from_code_verifier_sha256(
                    &PkceCodeVerifier::new(form["code_verifier"].clone()),
                );
                assert_eq!(challenge.as_str(), params["code_challenge"]);
                count.fetch_add(1, Ordering::SeqCst);
                token.clone()
            };
            async move {
                Ok(oauth2::http::Response::builder()
                    .status(200)
                    .header("content-type", "application/json")
                    .body(serde_json::to_vec(&body).unwrap())
                    .unwrap())
            }
        };
        let progress = AtomicUsize::new(0);
        let finish = authorization.finish_with_http(
            || {
                progress.fetch_add(1, Ordering::SeqCst);
            },
            &http,
        );
        let browser = async {
            let client = reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(5))
                .build()
                .unwrap();
            let mut invalid = callback.clone();
            invalid
                .query_pairs_mut()
                .append_pair("state", "duplicate-state");
            assert_eq!(client.get(invalid).send().await.unwrap().status(), 400);
            let mut wrong = callback.clone();
            wrong.set_query(Some(
                "state=wrong&code=must-not-exchange&client_id=issued-client",
            ));
            assert_eq!(client.get(wrong).send().await.unwrap().status(), 400);
            assert_eq!(exchanges.load(Ordering::SeqCst), 0);
            assert_eq!(client.get(callback).send().await.unwrap().status(), 200);
        };
        let (result, ()) = tokio::join!(finish, browser);
        let expected = usize::from(!matches!(case, "client" | "missing-client" | "denied"));
        assert_eq!(progress.load(Ordering::SeqCst), expected);
        assert_eq!(exchanges.load(Ordering::SeqCst), expected);
        result
    }

    #[tokio::test]
    async fn signed_oidc_exchange_rejects_bad_callbacks_claims_and_missing_direct_scope() {
        let connected = signed_flow("valid", None).await.unwrap();
        assert_eq!(connected.account.client_id, "issued-client");
        assert_eq!(connected.account.subject, "signed-subject");
        assert!(connected.account.plan_usage_enabled);
        for case in [
            "signature",
            "issuer",
            "audience",
            "expiry",
            "nonce",
            "empty-access",
        ] {
            assert_eq!(
                signed_flow(case, None).await,
                Err(ChatGptAuthError::InvalidIdentity),
                "{case}"
            );
        }
        assert_eq!(
            signed_flow("scope", None).await,
            Err(ChatGptAuthError::MissingPlanPermission)
        );
        assert_eq!(
            signed_flow("missing-client", None).await,
            Err(ChatGptAuthError::InvalidCallback)
        );
        assert_eq!(
            signed_flow("denied", None).await,
            Err(ChatGptAuthError::AuthorizationDenied)
        );
        assert_eq!(
            signed_flow("client", Some(connected.account.clone())).await,
            Err(ChatGptAuthError::InvalidIdentity)
        );
        let mut old = connected.account.clone();
        old.subject = "different-saved-subject".into();
        assert_eq!(
            signed_flow("valid", Some(old)).await,
            Err(ChatGptAuthError::InvalidIdentity)
        );
    }

    #[tokio::test]
    async fn callback_cancellation_releases_listener_and_partial_http_socket() {
        let authorization = ChatGptAuthorization::prepare(
            "urn:uuid:00000000-0000-4000-8000-000000000001".into(),
            None,
        )
        .await
        .unwrap();
        let address = authorization.listener.local_addr().unwrap();
        let mut socket = tokio::net::TcpStream::connect(address).await.unwrap();
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        socket
            .write_all(b"GET /auth/callback HTTP/1.1\r\n")
            .await
            .unwrap();
        let finish = authorization.finish();
        assert!(
            tokio::time::timeout(std::time::Duration::from_millis(30), finish)
                .await
                .is_err()
        );
        let mut byte = [0_u8; 1];
        assert_eq!(
            tokio::time::timeout(std::time::Duration::from_secs(1), socket.read(&mut byte))
                .await
                .unwrap()
                .unwrap(),
            0
        );
        assert!(tokio::net::TcpStream::connect(address).await.is_err());
        let _rebound = TcpListener::bind(address).await.unwrap();
    }
}
