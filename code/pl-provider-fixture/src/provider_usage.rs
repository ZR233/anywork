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
pub const CONTROL_PATH: &str = "/__provider_usage/control";
pub const MCP_TOOL_NAME: &str = "search";

/// Owned reject category for the scenario's deliberate Zhipu 401.
///
/// Only the raw `DENIED_QUOTA_KEY` branch records this. Unknown or missing
/// quota/MCP credentials stay real failures and must not share web-search
/// category names.
pub const DENIED_QUOTA_CATEGORY: &str = "provider_usage_denied";

const FAST_TRANSIENT_CATEGORY: &str = "provider_usage_fast_transient";

#[derive(Debug, Default)]
struct ProviderUsageCounts {
    slow_quota_started: usize,
    fast_quota_started: usize,
    fast_quota_failure_armed: bool,
    fast_quota_failed: usize,
    denied_quota_started: usize,
    plan_quota_started: usize,
    mcp_started: usize,
}

enum FastQuotaOutcome {
    InitialBalance,
    RecoveredBalance,
    TransientFailure,
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
        self.snapshot_with_counts(&counts)
    }

    fn snapshot_with_counts(&self, counts: &ProviderUsageCounts) -> ProviderUsageLiveState {
        ProviderUsageLiveState {
            slow_quota_started: counts.slow_quota_started,
            fast_quota_started: counts.fast_quota_started,
            fast_quota_failure_armed: counts.fast_quota_failure_armed,
            fast_quota_failed: counts.fast_quota_failed,
            denied_quota_started: counts.denied_quota_started,
            plan_quota_started: counts.plan_quota_started,
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

    fn start_fast_quota(&self) -> Option<FastQuotaOutcome> {
        let mut counts = self.counts.lock().expect("fixture state poisoned");
        let started = counts.fast_quota_started.checked_add(1)?;
        if counts.fast_quota_failure_armed {
            let failed = counts.fast_quota_failed.checked_add(1)?;
            // Admission consumes the fault even if the HTTP caller later cancels.
            // Check both counters before publishing any part of this transition.
            counts.fast_quota_started = started;
            counts.fast_quota_failure_armed = false;
            counts.fast_quota_failed = failed;
            Some(FastQuotaOutcome::TransientFailure)
        } else {
            counts.fast_quota_started = started;
            Some(if counts.fast_quota_failed == 0 {
                FastQuotaOutcome::InitialBalance
            } else {
                FastQuotaOutcome::RecoveredBalance
            })
        }
    }

    fn arm_fast_quota_failure(&self) -> Option<ProviderUsageLiveState> {
        let mut counts = self.counts.lock().expect("fixture state poisoned");
        if counts.fast_quota_failure_armed {
            return None;
        }
        counts.fast_quota_failure_armed = true;
        Some(self.snapshot_with_counts(&counts))
    }

    fn bump_plan(&self) -> Option<()> {
        let mut counts = self.counts.lock().expect("fixture state poisoned");
        counts.plan_quota_started = counts.plan_quota_started.checked_add(1)?;
        Some(())
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
    pub fast_quota_failure_armed: bool,
    pub fast_quota_failed: usize,
    pub denied_quota_started: usize,
    pub plan_quota_started: usize,
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

#[derive(Debug, Deserialize)]
#[serde(tag = "action", rename_all = "camelCase", deny_unknown_fields)]
pub(super) enum ControlRequest {
    FailNextFastQuota {},
}

/// Recognizes only the scenario's deliberate Zhipu 401 and one-shot fast 503.
/// Other credentials, routes, methods and control rejections remain failures.
pub fn is_provider_usage_owned_reject(request: &RecordedRequest) -> bool {
    if request.accepted || request.method != "GET" {
        return false;
    }
    let Some(diagnostic) = &request.diagnostic else {
        return false;
    };
    matches!(
        (
            request.path.as_str(),
            request.body.get("keyAlias").and_then(Value::as_str),
            diagnostic.category.as_str(),
        ),
        (
            "/api/monitor/usage/quota/limit",
            Some("denied"),
            DENIED_QUOTA_CATEGORY
        ) | ("/user/balance", Some("fast"), FAST_TRANSIENT_CATEGORY)
    )
}

pub(super) fn is_unexpected_reject(request: &RecordedRequest) -> bool {
    !request.accepted && !is_provider_usage_owned_reject(request)
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
        actual_prompt: None,
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

fn quota_counter_exhausted(state: &AppState, path: &str, alias: &str) -> Response {
    record(
        state,
        "GET",
        path,
        key_alias_body(alias),
        false,
        Some("provider_usage_counter_exhausted"),
    );
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        Json(json!({ "error": { "code": "quota_counter_exhausted" } })),
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

fn fast_deepseek_balance(total: &str, granted: &str) -> Value {
    json!({
        "is_available": true,
        "balance_infos": [
            {
                "currency": "USD",
                "total_balance": total,
                "granted_balance": granted,
                "topped_up_balance": "80.00",
            },
            {
                "currency": "CNY",
                "total_balance": "0.000000000000000001",
                "granted_balance": "0.000000000000000001",
                "topped_up_balance": "0.000000000000000000",
            },
        ],
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
                    "percentage": 95.0,
                    "currentValue": 95.0,
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
            let Some(outcome) = state.provider_usage.start_fast_quota() else {
                return quota_counter_exhausted(&state, "/user/balance", "fast");
            };
            let failed = matches!(outcome, FastQuotaOutcome::TransientFailure);
            record(
                &state,
                "GET",
                "/user/balance",
                key_alias_body("fast"),
                !failed,
                failed.then_some(FAST_TRANSIENT_CATEGORY),
            );
            match outcome {
                FastQuotaOutcome::InitialBalance => {
                    Json(fast_deepseek_balance("88.00", "8.00")).into_response()
                }
                FastQuotaOutcome::RecoveredBalance => {
                    Json(fast_deepseek_balance("89.00", "9.00")).into_response()
                }
                FastQuotaOutcome::TransientFailure => (
                    StatusCode::SERVICE_UNAVAILABLE,
                    Json(json!({
                        "error": {
                            "code": "quota_temporarily_unavailable",
                            "message": "fixture quota is temporarily unavailable; retry",
                        }
                    })),
                )
                    .into_response(),
            }
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
            if state.provider_usage.bump_plan().is_none() {
                return quota_counter_exhausted(&state, "/api/monitor/usage/quota/limit", "plan");
            }
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

pub(super) async fn control(
    State(state): State<AppState>,
    Json(request): Json<ControlRequest>,
) -> Response {
    let snapshot = match request {
        ControlRequest::FailNextFastQuota {} => state.provider_usage.arm_fast_quota_failure(),
    };
    record(
        &state,
        "POST",
        CONTROL_PATH,
        json!({ "action": "failNextFastQuota", "keyAlias": "control" }),
        snapshot.is_some(),
        snapshot
            .is_none()
            .then_some("provider_usage_fast_failure_already_armed"),
    );
    match snapshot {
        Some(snapshot) => Json(snapshot).into_response(),
        None => (
            StatusCode::CONFLICT,
            Json(json!({
                "error": {
                    "code": "fast_quota_failure_already_armed",
                    "message": "the prepared fast quota failure has not been consumed",
                }
            })),
        )
            .into_response(),
    }
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
