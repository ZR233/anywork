//! Dedicated Responses peer for the opt-in Agent assembly observation.
//!
//! This is not a model runtime or a general scenario dispatcher. Its finite
//! phases issue real Studio tools, learn child IDs only from real receipts,
//! and retain the fixture's single canonical request log. Parent/child request
//! order may interleave; duplicates, skipped tool outputs and unknown requests
//! are rejected rather than retried into a successful script.

mod plan;
mod wire;

use super::*;
use anyhow::ensure;
use std::collections::BTreeMap;

pub use plan::{
    AgentPhase, CHILD_MODEL, COMPACT_MODEL, ROOT_MODEL, USER_MODEL_NEW, USER_MODEL_OLD,
};
pub use plan::{DISABLED_PROFILE, UNAVAILABLE_MODEL, UNAVAILABLE_PROFILE, USER_PROFILE};

const MAX_REQUEST_BYTES: usize = 2 * 1024 * 1024;

/// Observer-owned gates and a bounded ledger of the finite observation phases.
/// No runtime identity or Profile configuration is synthesized here.
#[derive(Debug, Clone)]
pub struct AgentDefinitionControl {
    state: Arc<Mutex<ObservationState>>,
    gates: Arc<BTreeMap<AgentPhase, ReplyStage>>,
}

#[derive(Debug, Default)]
struct ObservationState {
    attempts: BTreeMap<AgentPhase, usize>,
    child_ids: BTreeMap<String, String>,
    child_turns: BTreeMap<AgentPhase, (String, String)>,
}

impl Default for AgentDefinitionControl {
    fn default() -> Self {
        Self::new()
    }
}

impl AgentDefinitionControl {
    pub fn new() -> Self {
        let gates = AgentPhase::ALL
            .iter()
            .filter(|phase| phase.is_gated())
            .map(|phase| (*phase, ReplyStage::new()))
            .collect();
        Self {
            state: Arc::new(Mutex::new(ObservationState::default())),
            gates: Arc::new(gates),
        }
    }

    /// Returns only the stage of a phase declared to be gated.
    pub fn stage(&self, phase: AgentPhase) -> Result<ReplyStage> {
        self.gates
            .get(&phase)
            .cloned()
            .with_context(|| format!("Agent observation phase {phase:?} has no gate"))
    }

    /// ID learned from a committed spawn result, never from expected constants.
    pub fn child_id(&self, profile: &str) -> Result<String> {
        self.state
            .lock()
            .map_err(|_| anyhow::anyhow!("Agent observation ledger poisoned"))?
            .child_ids
            .get(profile)
            .cloned()
            .with_context(|| format!("no real spawn receipt for {profile}"))
    }

    /// Bind a held child request to the Turn ID observed on the public Thread
    /// snapshot. This is an expected identity, not a fabricated completion.
    pub fn expect_child_turn(&self, phase: AgentPhase, child: &str, turn: &str) -> Result<()> {
        ensure!(
            !turn.is_empty() && !self.stage(phase)?.is_released(),
            "child identity must be bound before release"
        );
        let mut state = self
            .state
            .lock()
            .map_err(|_| anyhow::anyhow!("Agent observation ledger poisoned"))?;
        let profile = phase.profile().context("not a child observation phase")?;
        ensure!(
            state.attempts.get(&phase) == Some(&1)
                && state.child_ids.get(profile).map(String::as_str) == Some(child),
            "child Turn identity has no real gated request/spawn receipt"
        );
        ensure!(
            !state
                .child_turns
                .values()
                .any(|(old_child, old_turn)| old_child == child && old_turn == turn),
            "same child/Turn reused across observation phases"
        );
        ensure!(
            state
                .child_turns
                .insert(phase, (child.into(), turn.into()))
                .is_none(),
            "child Turn expectation registered twice"
        );
        Ok(())
    }

    /// Every required phase must run its exact number of provider attempts.
    /// The caller must separately audit `FixtureServer::recorded`, including
    /// rejected requests; this ledger is not a replacement for wire evidence.
    pub fn verify_complete(&self) -> Result<()> {
        let state = self
            .state
            .lock()
            .map_err(|_| anyhow::anyhow!("Agent observation ledger poisoned"))?;
        for phase in AgentPhase::ALL {
            let actual = state.attempts.get(phase).copied().unwrap_or(0);
            ensure!(
                actual == phase.expected_attempts(),
                "Agent phase {phase:?}: {actual}/{} attempts",
                phase.expected_attempts()
            );
            if phase.is_gated() {
                ensure!(
                    self.stage(*phase)?.is_released(),
                    "Agent phase {phase:?} was never released"
                );
            }
        }
        ensure!(
            state.child_ids.len() == 2,
            "expected two real child identities"
        );
        Ok(())
    }

    fn reply(&self, body: &Value) -> Result<Reply> {
        let phase = wire::phase(body)?;
        let mut state = self
            .state
            .lock()
            .map_err(|_| anyhow::anyhow!("Agent observation ledger poisoned"))?;
        let ordinal = state.attempts.get(&phase).copied().unwrap_or(0);
        ensure!(
            ordinal < phase.expected_attempts(),
            "extra provider attempt for Agent phase {phase:?}"
        );
        let ObservationState {
            child_ids,
            child_turns,
            ..
        } = &mut *state;
        let reply = plan::reply(phase, ordinal, body, child_ids, child_turns)?;
        state.attempts.insert(phase, ordinal + 1);
        drop(state);
        if ordinal == 0 && phase.is_gated() {
            let Reply::Sse(mut events) = reply else {
                bail!("gated Agent phase did not produce SSE events");
            };
            ensure!(!events.is_empty(), "gated Agent reply is empty");
            let after = events.split_off(1);
            return Ok(self.stage(phase)?.gated(events, after));
        }
        Ok(reply)
    }
}

/// Wire adapter selected only by `FixtureOptions.agent_definitions`.
/// All SSE writing and listener cancellation reuse the existing fixture owner.
pub(super) async fn responses(
    State(state): State<AppState>,
    request: axum::extract::Request,
) -> Response {
    let method = request.method().to_string();
    let path = request.uri().path().to_owned();
    let parsed = async {
        let bytes = axum::body::to_bytes(request.into_body(), MAX_REQUEST_BYTES).await?;
        Ok::<Value, anyhow::Error>(serde_json::from_slice(&bytes)?)
    }
    .await;
    let (body, reply) = match parsed {
        Ok(body) => {
            let result = state
                .agent_definitions
                .as_ref()
                .context("Agent observation handler has no control owner")
                .and_then(|control| control.reply(&body));
            (body, result)
        }
        Err(error) => (
            Value::Null,
            Err(error.context("Agent observation request JSON")),
        ),
    };
    let diagnostic = reply.as_ref().err().map(|error| RejectDiagnostic {
        category: format!("agent_observation: {error:#}"),
        expected_method: Some("POST".into()),
        expected_path: Some("/v1/responses".into()),
        expected_kind: "agent_definitions".into(),
        expected_prompt: None,
        actual_prompt: None,
        expected_step: None,
        actual_prompt_present: body.get("input").is_some(),
        prompt_matches_expected: false,
        delivery_seen: false,
        tool_output_seen: false,
    });
    state
        .script
        .lock()
        .expect("fixture request log poisoned")
        .requests
        .push(RecordedRequest {
            method,
            path,
            body,
            accepted: reply.is_ok(),
            diagnostic,
        });
    match reply {
        Ok(Reply::Sse(events)) => sse_reply(events, false, state.stopping.clone()),
        Ok(Reply::GatedSse {
            before,
            reached,
            release,
            after,
        }) => gated_sse_reply(before, after, reached, release, state.stopping.clone()),
        Ok(_) | Err(_) => (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": {"code": "agent_observation_mismatch", "message": "unexpected Agent observation request"}})),
        )
            .into_response(),
    }
}
