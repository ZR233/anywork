//! Official Sign in with ChatGPT. Secrets remain in this Rust-only boundary.
mod authorization;
mod http;
mod session;

pub use authorization::ChatGptAuthorization;
pub use session::{ChatGptCredentialRecord, ChatGptCredentialStorage, ChatGptSession};

pub const CHATGPT_RESOURCE: &str = "https://api.openai.com/v1";
pub const CHATGPT_ISSUER: &str = "https://auth.openai.com";
const AUTHORIZE: &str = "https://auth.openai.com/api/accounts/authorize";
const TOKEN: &str = "https://auth.openai.com/api/accounts/oauth/token";
const DIRECT_SCOPE: &str = "chatgpt.tokens.use.direct";

/// Intentionally does not retain transport errors, callback URLs, bodies or tokens.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum ChatGptAuthError {
    #[error(
        "RecoveryRequired: ChatGPT credential transaction requires recovery in its owning home"
    )]
    RecoveryRequired,
    #[error("ChatGPT authentication network operation failed")]
    Network,
    #[error("ChatGPT authorization was denied")]
    AuthorizationDenied,
    #[error("ChatGPT authorization callback is invalid")]
    InvalidCallback,
    #[error("ChatGPT signed identity is invalid or changed")]
    InvalidIdentity,
    #[error("ChatGPT plan usage permission was not granted")]
    MissingPlanPermission,
    #[error("ChatGPT authorization expired")]
    Expired,
    #[error("ChatGPT protected credential storage failed")]
    Storage,
    #[error("ChatGPT credentials require a new sign-in; refresh will not be replayed")]
    ReauthorizationRequired,
    #[error("ChatGPT credential owner was replaced or revoked")]
    Revoked,
    #[error("ChatGPT credentials may only be used with official Responses HTTP and models")]
    UnsupportedResource,
}

pub(crate) fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or_default()
}

fn oauth_client(
    client_id: &str,
) -> oauth2::Client<
    oauth2::basic::BasicErrorResponse,
    TokenResponse,
    oauth2::basic::BasicTokenIntrospectionResponse,
    oauth2::StandardRevocableToken,
    oauth2::basic::BasicRevocationErrorResponse,
    oauth2::EndpointSet,
    oauth2::EndpointNotSet,
    oauth2::EndpointNotSet,
    oauth2::EndpointNotSet,
    oauth2::EndpointSet,
> {
    oauth2::Client::new(oauth2::ClientId::new(client_id.to_owned()))
        .set_auth_uri(oauth2::AuthUrl::new(AUTHORIZE.into()).expect("static authorization URL"))
        .set_token_uri(oauth2::TokenUrl::new(TOKEN.into()).expect("static token URL"))
}

#[derive(Clone, serde::Deserialize, serde::Serialize)]
struct TokenExtras {
    id_token: Option<openidconnect::core::CoreIdToken>,
    earliest_refresh_at: Option<i64>,
}

// oauth2 requires Debug for ExtraTokenFields. Never derive it for a token-bearing value.
impl std::fmt::Debug for TokenExtras {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("TokenExtras(<redacted>)")
    }
}
impl oauth2::ExtraTokenFields for TokenExtras {}

type TokenResponse = oauth2::StandardTokenResponse<TokenExtras, oauth2::basic::BasicTokenType>;

async fn exchange(request: oauth2::HttpRequest) -> Result<oauth2::HttpResponse, ChatGptAuthError> {
    http::request(request).await
}

/// Discovery, grant exchange and signed-identity validation share one operation budget,
/// rather than each sequential HTTP request extending the deadline by another 30 seconds.
async fn within_operation_limit<T: Send>(
    operation: impl std::future::Future<Output = Result<T, ChatGptAuthError>> + Send,
) -> Result<T, ChatGptAuthError> {
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(30);
    let result = tokio::time::timeout_at(deadline, operation)
        .await
        .map_err(|_| ChatGptAuthError::Network)?;
    // Synchronous signature/JSON work cannot yield to the Tokio timer.
    if tokio::time::Instant::now() >= deadline {
        return Err(ChatGptAuthError::Network);
    }
    result
}
