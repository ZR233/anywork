//! Scripted external provider for explicit native delegation acceptance.
//! Product tools, routing, evaluation writes and persistence are always real.

mod flow;
mod journeys;
mod lifecycle;
mod recovery;
mod routing;
mod window;
mod wire;

use super::*;
use anyhow::ensure;
use wire::Request;

/// Separate, bounded native journeys. Four preferences require four different
/// roots; this fixture never changes a running root's frozen policy.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum Scenario {
    Routing,
    Lifecycle,
    Window,
    Enablement,
    Recovery,
}

impl Scenario {
    pub fn parse(name: &str) -> Option<Self> {
        match name {
            "delegation-routing" => Some(Self::Routing),
            "delegation-lifecycle" => Some(Self::Lifecycle),
            "delegation-window" => Some(Self::Window),
            "delegation-enablement" => Some(Self::Enablement),
            "delegation-recovery" => Some(Self::Recovery),
            _ => None,
        }
    }

    pub const fn name(self) -> &'static str {
        match self {
            Self::Routing => "delegation-routing",
            Self::Lifecycle => "delegation-lifecycle",
            Self::Window => "delegation-window",
            Self::Enablement => "delegation-enablement",
            Self::Recovery => "delegation-recovery",
        }
    }
}

/// External-only control/observation endpoints. No product write API is exposed.
pub const STATE_PATH: &str = "/delegation/state";
pub const RELEASE_PATH: &str = "/delegation/release";
pub const SHARED_MODEL: &str = "delegation-shared";
pub const OTHER_MODEL: &str = "delegation-other";
/// Observed model-visible activation wrapper; insufficient without the closed
/// target, receipt, invocation and no-new-work checks in the scenario flow.
pub const CLOSED_SEND_ACTIVATION_ERROR: &str = "Agent service failed: Thread activation failed";

#[derive(Debug, Clone, Default)]
pub(super) struct Environment {
    scenario: Option<Scenario>,
    observations: Arc<Mutex<Vec<Observation>>>,
    failures: Arc<Mutex<Vec<String>>>,
    inflight_arrived: CancellationToken,
    inflight_release: CancellationToken,
    repair_arrived: CancellationToken,
    repair_release: CancellationToken,
    // Copies of real committed receipts, solely for the second root's negative
    // authorization attempt. Never used to emulate a product evaluation store.
    foreign: Arc<Mutex<Option<wire::Evaluation>>>,
}

impl Environment {
    pub(super) fn new(scenario: Option<Scenario>) -> Self {
        Self {
            scenario,
            ..Self::default()
        }
    }

    fn snapshot(&self) -> Result<LiveState> {
        Ok(LiveState {
            scenario: self.scenario.context("delegation fixture is not enabled")?,
            observations: self
                .observations
                .lock()
                .map_err(|_| anyhow::anyhow!("delegation observation lock poisoned"))?
                .clone(),
            failures: self
                .failures
                .lock()
                .map_err(|_| anyhow::anyhow!("delegation failure lock poisoned"))?
                .clone(),
            inflight_arrived: self.inflight_arrived.is_cancelled(),
            inflight_released: self.inflight_release.is_cancelled(),
            repair_arrived: self.repair_arrived.is_cancelled(),
            repair_released: self.repair_release.is_cancelled(),
        })
    }

    fn observed_continuation(&self, expected: &ContinuationEvidence) -> Result<bool> {
        Ok(self
            .observations
            .lock()
            .map_err(|_| anyhow::anyhow!("delegation observation lock poisoned"))?
            .iter()
            .any(|row| row.accepted && row.continuation.as_ref() == Some(expected)))
    }

    fn targeted_requests(&self, target: &str) -> Result<usize> {
        Ok(self
            .observations
            .lock()
            .map_err(|_| anyhow::anyhow!("delegation observation lock poisoned"))?
            .iter()
            .filter(|row| row.input_target_agent_id.as_deref() == Some(target))
            .count())
    }
}

/// Evidence from an actual child provider request and its scripted final reply.
/// These are fixture input tags, not fabricated Runtime delivery/Turn identities.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ContinuationEvidence {
    pub target_agent_id: String,
    pub intent: String,
    pub input_sha256: String,
    pub output: String,
}

fn input_digest(text: &str) -> String {
    hex::encode(Sha256::digest(text.as_bytes()))
}

/// Safe, synthetic wire evidence. It contains no VM URL, Authorization header,
/// full system prompt or copied user home. Model IDs are provider *completion*
/// request IDs, never `/models` inventory hits.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Observation {
    pub ordinal: usize,
    pub endpoint_alias: String,
    pub model: String,
    pub marker: String,
    pub note: String,
    pub accepted: bool,
    pub tools: Vec<String>,
    pub preference_templates: Vec<String>,
    pub expected_account_id: Option<String>,
    pub actual_effort: Option<String>,
    /// Fixture-owned target tag on an actual send-input provider request,
    /// including discovery steps. It never authorizes Runtime execution.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_target_agent_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation: Option<ContinuationEvidence>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub receipt: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LiveState {
    pub scenario: Scenario,
    pub observations: Vec<Observation>,
    pub failures: Vec<String>,
    pub inflight_arrived: bool,
    pub inflight_released: bool,
    pub repair_arrived: bool,
    pub repair_released: bool,
}

pub(super) fn routes(app: Router<AppState>) -> Router<AppState> {
    app.route(
        "/v1/delegation-a/responses",
        post(responses).fallback(unexpected_route),
    )
    .route(
        "/v1/delegation-b/responses",
        post(responses).fallback(unexpected_route),
    )
    .route(STATE_PATH, get(live_state).fallback(unexpected_route))
    .route(RELEASE_PATH, post(release).fallback(unexpected_route))
}

async fn live_state(State(state): State<AppState>) -> Response {
    match state.delegation.snapshot() {
        Ok(snapshot) => Json(snapshot).into_response(),
        Err(error) => failure(error),
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Release {
    gate: String,
}

async fn release(State(state): State<AppState>, Json(request): Json<Release>) -> Response {
    // Release is allowed only after the actual request reached the handler;
    // pre-releasing a gate would invalidate the in-flight proof.
    if request.gate != "inflight" || !state.delegation.inflight_arrived.is_cancelled() {
        return (
            StatusCode::CONFLICT,
            "gate has no arrived completion request",
        )
            .into_response();
    }
    state.delegation.inflight_release.cancel();
    Json(json!({"released":"inflight"})).into_response()
}

fn failure(error: anyhow::Error) -> Response {
    (
        StatusCode::BAD_REQUEST,
        Json(
            json!({"error":{"code":"delegation_fixture_rejected", "message":format!("{error:#}")}}),
        ),
    )
        .into_response()
}

#[derive(Clone, Copy)]
struct Recorded {
    request_index: usize,
    observation_index: usize,
}

fn reject(
    state: &AppState,
    path: String,
    body: Value,
    error: anyhow::Error,
    recorded: Option<Recorded>,
) -> Response {
    // Persist every 4xx, including malformed/oversized wire requests. A later
    // successful journey must not erase an earlier supplier protocol failure.
    state
        .delegation
        .failures
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .push(format!("{error:#}"));
    let mut script = state
        .script
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let diagnostic = Some(RejectDiagnostic {
        category: format!("delegation_failure: {error:#}"),
        expected_method: None,
        expected_path: None,
        expected_kind: "delegation".into(),
        expected_prompt: None,
        expected_step: None,
        actual_prompt_present: false,
        prompt_matches_expected: false,
        delivery_seen: false,
        tool_output_seen: false,
    });
    if let Some(row) = recorded.and_then(|recorded| script.requests.get_mut(recorded.request_index))
    {
        // Arrival and a later gate failure are one HTTP request, not two
        // completions. Keep the original request identity and replace its result.
        row.accepted = false;
        row.diagnostic = diagnostic;
    } else {
        script.requests.push(RecordedRequest {
            method: "POST".into(),
            path,
            body,
            accepted: false,
            diagnostic,
        });
    }
    drop(script);
    if let Some(recorded) = recorded
        && let Some(row) = state
            .delegation
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get_mut(recorded.observation_index)
    {
        row.accepted = false;
    }
    failure(error)
}

pub(super) async fn responses(
    State(state): State<AppState>,
    request: axum::extract::Request,
) -> Response {
    let path = request.uri().path().to_owned();
    let credential_present = request.headers().contains_key(header::AUTHORIZATION);
    let bytes = match axum::body::to_bytes(request.into_body(), 8 * 1024 * 1024).await {
        Ok(bytes) => bytes,
        Err(error) => return reject(&state, path, Value::Null, error.into(), None),
    };
    let body: Value = match serde_json::from_slice(&bytes) {
        Ok(body) => body,
        Err(error) => return reject(&state, path, Value::Null, error.into(), None),
    };
    let parsed =
        serde_json::from_value::<Request>(body.clone()).context("decode Responses request");
    let mut recorded = None;
    let result = async {
        ensure!(!credential_present, "synthetic credential-free endpoints must not receive Authorization");
        ensure!(path == "/v1/delegation-a/responses" || path == "/v1/delegation-b/responses", "account endpoint identity was lost");
        let request = parsed?;
        if let Some(expected) = request.expected_completion()? {
            ensure!(request.model == expected.model_id && path == format!("/v1/delegation-{}/responses", expected.endpoint_alias), "actual child completion endpoint/model differs from selected frozen route");
            ensure!(request.reasoning.as_ref().and_then(|reasoning| reasoning.effort.as_ref()) == expected.effort.as_ref(), "actual child completion effort differs from the frozen route");
        }
        let decision = if request.is_title() {
            journeys::Decision::answer("title", "Delegation acceptance")
        } else {
            journeys::decide(&request, &state.delegation)?
        };
        if decision.wait_for_repair {
            tokio::select! {
                () = state.stopping.cancelled() => bail!("fixture stopped before repair request arrived"),
                () = state.delegation.repair_arrived.cancelled() => {},
                () = tokio::time::sleep(Duration::from_secs(60)) => bail!("repair completion request did not reach its external gate"),
            }
        }
        if decision.note == "repair_rejected_old_terminal" {
            state.delegation.repair_release.cancel();
        }
        if decision.note == "inflight_arrived" {
            state.delegation.inflight_arrived.cancel();
        }
        if decision.note == "repair_arrived" {
            state.delegation.repair_arrived.cancel();
        }
        recorded = Some(record(&state, &path, body.clone(), &request, &decision, true)?);
        if matches!(decision.note.as_str(), "inflight_arrived" | "repair_arrived") {
            let release = if decision.note == "inflight_arrived" { &state.delegation.inflight_release } else { &state.delegation.repair_release };
            tokio::select! {
                () = state.stopping.cancelled() => bail!("fixture stopped with unreleased provider response"),
                () = release.cancelled() => {},
                () = tokio::time::sleep(Duration::from_secs(180)) => bail!("external provider response gate timed out"),
            }
        }
        let id = format!("delegation-{}", Sha256::digest(&bytes).iter().take(8).map(|byte| format!("{byte:02x}")).collect::<String>());
        let events = if let Some(call) = decision.call {
            responses_tool_calls(&id, &request.model, &[RealtimeToolCall {
                item_id: &format!("{}-item", call.id), call_id: &call.id, name: &call.name, arguments: call.arguments.to_string(),
            }])
        } else {
            responses_text(&decision.text, &id, &request.model)
        };
        Ok(sse_reply(events, false, state.stopping.clone()))
    }.await;
    match result {
        Ok(response) => response,
        Err(error) => reject(&state, path, body, error, recorded),
    }
}

fn record(
    state: &AppState,
    path: &str,
    body: Value,
    request: &Request,
    decision: &journeys::Decision,
    accepted: bool,
) -> Result<Recorded> {
    let expected = request.expected_completion()?;
    let continuation = if decision.call.is_none() {
        expected
            .as_ref()
            .and_then(|expected| expected.continuation.as_ref())
            .map(|tag| {
                let (_, prompt) = request.prompt()?;
                ensure!(
                    prompt.trim_start().starts_with("[[delegation:child:")
                        && !tag.target_agent_id.trim().is_empty()
                        && !tag.intent.trim().is_empty()
                        && !decision.text.is_empty(),
                    "invalid child continuation evidence"
                );
                Ok::<_, anyhow::Error>(ContinuationEvidence {
                    target_agent_id: tag.target_agent_id.clone(),
                    intent: tag.intent.clone(),
                    input_sha256: input_digest(&prompt),
                    output: decision.text.clone(),
                })
            })
            .transpose()?
    } else {
        None
    };
    let mut observations = state
        .delegation
        .observations
        .lock()
        .map_err(|_| anyhow::anyhow!("delegation observation lock poisoned"))?;
    let ordinal = observations.len();
    if matches!(
        decision.note.as_str(),
        "inflight_arrived" | "repair_arrived"
    ) {
        ensure!(
            !observations
                .iter()
                .any(|observation| observation.note == decision.note),
            "a single-use provider gate received a duplicate request"
        );
    }
    observations.push(Observation {
        ordinal,
        endpoint_alias: if path.contains("delegation-b") {
            "b"
        } else {
            "a"
        }
        .into(),
        model: request.model.clone(),
        marker: request
            .prompt()
            .map(|(_, text)| {
                format!(
                    "{}]]",
                    text.split_once("]]")
                        .map_or("[[delegation:invalid", |(marker, _)| marker)
                        .chars()
                        .take(96)
                        .collect::<String>()
                )
            })
            .unwrap_or_else(|_| "title".into()),
        note: decision.note.clone(),
        accepted,
        tools: request
            .tools
            .iter()
            .filter_map(|tool| tool.name().map(str::to_owned))
            .collect(),
        preference_templates: ["经济", "平衡", "快速"]
            .into_iter()
            .filter(|label| {
                request
                    .instructions
                    .contains(&format!("自动分发偏好：{label}。"))
            })
            .map(str::to_owned)
            .collect(),
        input_target_agent_id: expected
            .as_ref()
            .and_then(|expected| expected.continuation.as_ref())
            .map(|tag| tag.target_agent_id.clone()),
        expected_account_id: expected.and_then(|expected| expected.account_id),
        actual_effort: request
            .reasoning
            .as_ref()
            .and_then(|reasoning| reasoning.effort.clone()),
        continuation,
        receipt: decision.receipt.clone(),
    });
    drop(observations);
    let mut script = state
        .script
        .lock()
        .map_err(|_| anyhow::anyhow!("fixture request lock poisoned"))?;
    let request_index = script.requests.len();
    script.requests.push(RecordedRequest {
        method: "POST".into(),
        path: path.into(),
        body,
        accepted,
        diagnostic: Some(RejectDiagnostic {
            category: decision.note.clone(),
            expected_method: None,
            expected_path: None,
            expected_kind: "delegation".into(),
            expected_prompt: None,
            expected_step: None,
            actual_prompt_present: true,
            prompt_matches_expected: accepted,
            delivery_seen: false,
            tool_output_seen: false,
        }),
    });
    Ok(Recorded {
        request_index,
        observation_index: ordinal,
    })
}

/// Required scene checkpoints, checked by the *outer fixture process*. A main
/// flow that was never exercised is an error, not a successful empty script.
///
/// # Errors
/// Any rejected request or missing completed journey is returned to the CLI.
pub fn verify_requests(scenario: Scenario, requests: &[RecordedRequest]) -> Result<()> {
    ensure!(
        requests.iter().all(|request| request.accepted),
        "delegation fixture has rejected requests"
    );
    let required: &[&str] = match scenario {
        Scenario::Routing => &[
            "routing_fixed_complete",
            "routing_economy_complete",
            "routing_balanced_complete",
            "routing_fast_complete",
        ],
        Scenario::Lifecycle => &[
            "lifecycle_complete",
            "foreign_parent_rejected",
            "cold_close_complete",
            "repair_rejected_old_terminal",
        ],
        Scenario::Window => &["window_complete", "window_reopened_complete"],
        Scenario::Enablement => &[
            "enabled_query_before_disable",
            "inflight_arrived",
            "disabled_query_excluded",
            "no_candidates_rejected",
            "enablement_complete",
        ],
        Scenario::Recovery => &[
            "recovery_first_complete",
            "recovery_explicit_close_rejected",
            "recovery_complete",
            "recovery_child_initial",
            "recovery_child_review_initial",
            "recovery_child_repair",
            "recovery_child_review_resumed",
        ],
    };
    for note in required {
        ensure!(
            requests.iter().any(|request| request
                .diagnostic
                .as_ref()
                .is_some_and(|diagnostic| diagnostic.category == *note)),
            "{} main flow incomplete: missing {note}",
            scenario.name()
        );
    }
    if scenario == Scenario::Recovery {
        for note in recovery::CHILD_FINAL_NOTES {
            ensure!(
                requests
                    .iter()
                    .filter(|request| request
                        .diagnostic
                        .as_ref()
                        .is_some_and(|diagnostic| diagnostic.category == note))
                    .count()
                    == 1,
                "recovery requires exactly one actual final completion for {note}"
            );
        }
    }
    Ok(())
}
