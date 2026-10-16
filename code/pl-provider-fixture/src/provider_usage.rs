//! Loopback quota and gated MCP surfaces for the `provider-usage` scenario.
//!
//! These routes exist only when that scenario is selected. Quota keys are
//! distinguished by Authorization, because production usage queries reset the
//! URL path to `/user/balance` or `/api/monitor/usage/quota/limit`. MCP
//! initialize hangs on a real gate until the control endpoint releases it.
//! Shutdown cancels the same gates so waiters cannot pin the listener.
//! Bundled DeepSeek catalog discovery uses `GET /v1/models` with the same
//! Bearer keys; that route answers immediately and never touches quota gates
//! or counters.

use super::*;
use axum::http::HeaderMap;
use tokio_util::sync::CancellationToken;

/// Bearer token that hangs DeepSeek `/user/balance` until quota release.
pub const SLOW_QUOTA_KEY: &str = "fixture-usage-slow";
/// Bearer token that returns DeepSeek balance immediately.
pub const FAST_QUOTA_KEY: &str = "fixture-usage-fast";
/// Raw Authorization value that returns Zhipu quota 401.
pub const DENIED_QUOTA_KEY: &str = "fixture-usage-denied";
/// Raw Authorization value that returns a typed Zhipu quota envelope.
pub const PLAN_QUOTA_KEY: &str = "fixture-usage-plan";
/// Bearer token for the scenario MCP server.
pub const MCP_KEY: &str = "fixture-usage-mcp";

pub const MCP_PATH: &str = "/provider-usage/mcp";
pub const STATE_PATH: &str = "/__provider_usage/state";
pub const RELEASE_PATH: &str = "/__provider_usage/release";
pub const MCP_TOOL_NAME: &str = "search";

/// Owned reject category for the scenario's deliberate Zhipu 401.
///
/// Only the raw `DENIED_QUOTA_KEY` branch records this. Unknown or missing
/// quota/MCP credentials stay real failures and must not share web-search
/// category names.
pub const DENIED_QUOTA_CATEGORY: &str = "provider_usage_denied";

#[derive(Debug, Default)]
struct ProviderUsageCounts {
    slow_quota_started: usize,
    fast_quota_started: usize,
    denied_quota_started: usize,
    mcp_started: usize,
}

/// Per-listener gates and counters for quota / MCP handshake control.
#[derive(Clone)]
pub(super) struct ProviderUsageGates {
    counts: Arc<Mutex<ProviderUsageCounts>>,
    quota_release: CancellationToken,
    mcp_release: CancellationToken,
}

impl ProviderUsageGates {
    pub(super) fn new() -> Self {
        Self {
            counts: Arc::new(Mutex::new(ProviderUsageCounts::default())),
            quota_release: CancellationToken::new(),
            mcp_release: CancellationToken::new(),
        }
    }

    fn snapshot(&self) -> ProviderUsageLiveState {
        let counts = self.counts.lock().expect("fixture state poisoned");
        ProviderUsageLiveState {
            slow_quota_started: counts.slow_quota_started,
            fast_quota_started: counts.fast_quota_started,
            denied_quota_started: counts.denied_quota_started,
            mcp_started: counts.mcp_started,
            slow_quota_released: self.quota_release.is_cancelled(),
            mcp_released: self.mcp_release.is_cancelled(),
        }
    }

    fn bump_slow(&self) {
        self.counts
            .lock()
            .expect("fixture state poisoned")
            .slow_quota_started += 1;
    }

    fn bump_fast(&self) {
        self.counts
            .lock()
            .expect("fixture state poisoned")
            .fast_quota_started += 1;
    }

    fn bump_denied(&self) {
        self.counts
            .lock()
            .expect("fixture state poisoned")
            .denied_quota_started += 1;
    }

    fn bump_mcp(&self) {
        self.counts
            .lock()
            .expect("fixture state poisoned")
            .mcp_started += 1;
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderUsageLiveState {
    pub slow_quota_started: usize,
    pub fast_quota_started: usize,
    pub denied_quota_started: usize,
    pub mcp_started: usize,
    pub slow_quota_released: bool,
    pub mcp_released: bool,
}

#[derive(Debug, Deserialize)]
pub(super) struct ReleaseRequest {
    #[serde(default)]
    quota: bool,
    #[serde(default)]
    mcp: bool,
}

pub(super) fn is_owned_reject(request: &RecordedRequest) -> bool {
    !request.accepted
        && request.method == "GET"
        && request.path == "/api/monitor/usage/quota/limit"
        && request.body.get("keyAlias").and_then(Value::as_str) == Some("denied")
        && request
            .diagnostic
            .as_ref()
            .is_some_and(|diagnostic| diagnostic.category == DENIED_QUOTA_CATEGORY)
}

pub(super) fn is_unexpected_reject(request: &RecordedRequest) -> bool {
    !request.accepted && !is_owned_reject(request)
}

fn record(
    state: &AppState,
    method: &str,
    path: &str,
    body: Value,
    accepted: bool,
    category: Option<&str>,
) {
    let diagnostic = category.map(|category| RejectDiagnostic {
        category: category.to_owned(),
        expected_method: Some(method.to_owned()),
        expected_path: Some(path.to_owned()),
        expected_kind: "provider_usage".to_owned(),
        expected_prompt: None,
        expected_step: None,
        actual_prompt_present: true,
        prompt_matches_expected: accepted,
        delivery_seen: false,
        tool_output_seen: false,
    });
    state
        .script
        .lock()
        .expect("fixture state poisoned")
        .requests
        .push(RecordedRequest {
            method: method.to_owned(),
            path: path.to_owned(),
            body,
            accepted,
            diagnostic,
        });
}

fn bearer_token(headers: &HeaderMap) -> Option<&str> {
    headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .map(str::trim)
        .filter(|token| !token.is_empty())
}

fn raw_authorization(headers: &HeaderMap) -> Option<&str> {
    headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .filter(|token| !token.is_empty())
}

fn key_alias_body(alias: &str) -> Value {
    json!({ "keyAlias": alias })
}

fn unauthorized() -> Response {
    (
        StatusCode::UNAUTHORIZED,
        Json(json!({
            "error": {
                "code": "invalid_api_key",
                "message": "fixture rejected the credential",
            }
        })),
    )
        .into_response()
}

fn openai_model_list() -> Value {
    json!({
        "object": "list",
        "data": [{
            "id": "fixture-deepseek",
            "object": "model",
            "owned_by": "fixture",
        }],
    })
}

fn deepseek_balance(total: &str, granted: &str, topped_up: &str) -> Value {
    json!({
        "is_available": true,
        "balance_infos": [{
            "currency": "USD",
            "total_balance": total,
            "granted_balance": granted,
            "topped_up_balance": topped_up,
        }],
    })
}

fn zhipu_quota_envelope() -> Value {
    json!({
        "success": true,
        "code": 200,
        "msg": "ok",
        "data": {
            "level": "fixture-plan",
            "limits": [
                {
                    "type": "TOKENS_LIMIT",
                    "unit": 3,
                    "number": 5,
                    "percentage": 40.0,
                    "currentValue": 40.0,
                    "usage": 100.0,
                    "nextResetTime": 1_700_000_000_000_i64,
                },
                {
                    "type": "TOKENS_LIMIT",
                    "unit": 6,
                    "number": 1,
                    "percentage": 10.0,
                    "currentValue": 10.0,
                    "usage": 100.0,
                    "nextResetTime": 1_700_086_400_000_i64,
                },
            ],
        },
    })
}

async fn wait_gate(release: &CancellationToken, stopping: &CancellationToken) {
    tokio::select! {
        () = release.cancelled() => {}
        () = stopping.cancelled() => {}
    }
}

async fn json_body(request: axum::extract::Request) -> Option<Value> {
    let bytes = axum::body::to_bytes(request.into_body(), 1024 * 1024)
        .await
        .ok()?;
    serde_json::from_slice(&bytes).ok()
}

/// Immediate OpenAI-compatible catalog for Bundled DeepSeek discovery.
///
/// Only the slow/fast Bearer keys succeed. The response never waits on the
/// quota gate and never increments quota counters.
pub(super) async fn models_get(State(state): State<AppState>, headers: HeaderMap) -> Response {
    match bearer_token(&headers) {
        Some(SLOW_QUOTA_KEY) => {
            record(
                &state,
                "GET",
                "/v1/models",
                key_alias_body("slow"),
                true,
                None,
            );
            Json(openai_model_list()).into_response()
        }
        Some(FAST_QUOTA_KEY) => {
            record(
                &state,
                "GET",
                "/v1/models",
                key_alias_body("fast"),
                true,
                None,
            );
            Json(openai_model_list()).into_response()
        }
        Some(_) => {
            record(
                &state,
                "GET",
                "/v1/models",
                key_alias_body("unknown"),
                false,
                Some("quota_credential_rejected"),
            );
            unauthorized()
        }
        None => {
            record(
                &state,
                "GET",
                "/v1/models",
                key_alias_body("missing"),
                false,
                Some("quota_credential_rejected"),
            );
            unauthorized()
        }
    }
}

pub(super) async fn deepseek_balance_get(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Response {
    match bearer_token(&headers) {
        Some(SLOW_QUOTA_KEY) => {
            state.provider_usage.bump_slow();
            record(
                &state,
                "GET",
                "/user/balance",
                key_alias_body("slow"),
                true,
                None,
            );
            wait_gate(&state.provider_usage.quota_release, &state.stopping).await;
            Json(deepseek_balance("1.00", "1.00", "0.00")).into_response()
        }
        Some(FAST_QUOTA_KEY) => {
            state.provider_usage.bump_fast();
            record(
                &state,
                "GET",
                "/user/balance",
                key_alias_body("fast"),
                true,
                None,
            );
            Json(deepseek_balance("88.00", "8.00", "80.00")).into_response()
        }
        Some(_) => {
            record(
                &state,
                "GET",
                "/user/balance",
                key_alias_body("unknown"),
                false,
                Some("quota_credential_rejected"),
            );
            unauthorized()
        }
        None => {
            record(
                &state,
                "GET",
                "/user/balance",
                key_alias_body("missing"),
                false,
                Some("quota_credential_rejected"),
            );
            unauthorized()
        }
    }
}

pub(super) async fn zhipu_quota_get(State(state): State<AppState>, headers: HeaderMap) -> Response {
    match raw_authorization(&headers) {
        Some(DENIED_QUOTA_KEY) => {
            state.provider_usage.bump_denied();
            record(
                &state,
                "GET",
                "/api/monitor/usage/quota/limit",
                key_alias_body("denied"),
                false,
                Some(DENIED_QUOTA_CATEGORY),
            );
            unauthorized()
        }
        Some(PLAN_QUOTA_KEY) => {
            record(
                &state,
                "GET",
                "/api/monitor/usage/quota/limit",
                key_alias_body("plan"),
                true,
                None,
            );
            Json(zhipu_quota_envelope()).into_response()
        }
        Some(_) => {
            record(
                &state,
                "GET",
                "/api/monitor/usage/quota/limit",
                key_alias_body("unknown"),
                false,
                Some("quota_credential_rejected"),
            );
            unauthorized()
        }
        None => {
            record(
                &state,
                "GET",
                "/api/monitor/usage/quota/limit",
                key_alias_body("missing"),
                false,
                Some("quota_credential_rejected"),
            );
            unauthorized()
        }
    }
}

pub(super) async fn live_state(State(state): State<AppState>) -> Response {
    let snapshot = state.provider_usage.snapshot();
    record(
        &state,
        "GET",
        STATE_PATH,
        json!({ "keyAlias": "control" }),
        true,
        None,
    );
    Json(snapshot).into_response()
}

pub(super) async fn release(
    State(state): State<AppState>,
    Json(request): Json<ReleaseRequest>,
) -> Response {
    if request.quota {
        state.provider_usage.quota_release.cancel();
    }
    if request.mcp {
        state.provider_usage.mcp_release.cancel();
    }
    record(
        &state,
        "POST",
        RELEASE_PATH,
        json!({ "quota": request.quota, "mcp": request.mcp, "keyAlias": "control" }),
        true,
        None,
    );
    Json(state.provider_usage.snapshot()).into_response()
}

pub(super) async fn mcp_get() -> Response {
    StatusCode::METHOD_NOT_ALLOWED.into_response()
}

pub(super) async fn mcp_post(
    State(state): State<AppState>,
    headers: HeaderMap,
    request: axum::extract::Request,
) -> Response {
    let Some(body) = json_body(request).await else {
        record(
            &state,
            "POST",
            MCP_PATH,
            Value::Null,
            false,
            Some("mcp_invalid_json"),
        );
        return StatusCode::BAD_REQUEST.into_response();
    };
    if bearer_token(&headers) != Some(MCP_KEY) {
        record(
            &state,
            "POST",
            MCP_PATH,
            json!({ "keyAlias": "unknown", "method": body.get("method") }),
            false,
            Some("mcp_credential_rejected"),
        );
        return unauthorized();
    }
    let method = body
        .get("method")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned();
    let id = body.get("id").cloned().unwrap_or(Value::Null);
    match method.as_str() {
        "server/discover" => {
            record(
                &state,
                "POST",
                MCP_PATH,
                body,
                true,
                Some("mcp_legacy_fallback"),
            );
            jsonrpc_error(id, -32601, "server/discover is not supported")
        }
        "initialize" => {
            let version = body
                .pointer("/params/protocolVersion")
                .and_then(Value::as_str)
                .unwrap_or("2025-11-25")
                .to_owned();
            state.provider_usage.bump_mcp();
            record(
                &state,
                "POST",
                MCP_PATH,
                json!({ "keyAlias": "mcp", "method": "initialize" }),
                true,
                None,
            );
            wait_gate(&state.provider_usage.mcp_release, &state.stopping).await;
            jsonrpc_ok(
                id,
                json!({
                    "protocolVersion": version,
                    "capabilities": { "tools": { "listChanged": false } },
                    "serverInfo": { "name": "fixture-provider-usage", "version": "0.1.0" },
                }),
            )
        }
        "notifications/initialized" => {
            record(&state, "POST", MCP_PATH, body, true, None);
            StatusCode::ACCEPTED.into_response()
        }
        "tools/list" => {
            record(&state, "POST", MCP_PATH, body, true, None);
            jsonrpc_ok(id, json!({ "tools": [mcp_tool_spec()] }))
        }
        "tools/call" => {
            let name = body
                .pointer("/params/name")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            let query = body
                .pointer("/params/arguments/query")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .trim()
                .to_owned();
            if name != MCP_TOOL_NAME || query.is_empty() {
                record(
                    &state,
                    "POST",
                    MCP_PATH,
                    body,
                    false,
                    Some("mcp_tool_call_invalid"),
                );
                return jsonrpc_error(id, -32602, "unsupported tools/call");
            }
            record(&state, "POST", MCP_PATH, body, true, None);
            jsonrpc_ok(
                id,
                json!({
                    "content": [{
                        "type": "text",
                        "text": format!("fixture provider-usage search result for {query}"),
                    }],
                    "isError": false,
                }),
            )
        }
        _ => {
            record(
                &state,
                "POST",
                MCP_PATH,
                body,
                false,
                Some("mcp_unknown_method"),
            );
            jsonrpc_error(id, -32601, "method not found")
        }
    }
}

fn jsonrpc_ok(id: Value, result: Value) -> Response {
    Json(json!({ "jsonrpc": "2.0", "id": id, "result": result })).into_response()
}

fn jsonrpc_error(id: Value, code: i64, message: &str) -> Response {
    Json(json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": { "code": code, "message": message },
    }))
    .into_response()
}

fn mcp_tool_spec() -> Value {
    json!({
        "name": MCP_TOOL_NAME,
        "description": "Read-only fixture search tool for provider-usage MCP isolation.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": { "type": "string", "description": "Search query" }
            },
            "required": ["query"],
            "additionalProperties": false
        }
    })
}
