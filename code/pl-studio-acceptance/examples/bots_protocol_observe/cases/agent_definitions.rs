//! Opt-in product journey for Agent identity/Mode/compaction and dispatch schema.
//! Session remains the sole environment/resource owner. This module only drives
//! public HTTP, the real Feishu peer and the model peer, with read-only durable
//! corroboration; it never assembles production instructions itself.

mod config;
mod delegation;
mod journey;
mod saved;
mod schema;
mod wire;

use super::{Session, http, report, sqlite};
use anyhow::{Context, Result, ensure};
use pl_provider_fixture::{
    RecordedRequest,
    agent_definitions::{AgentDefinitionControl, AgentPhase},
};
use serde::Serialize;
use std::{fs, path::Path};

pub(crate) const CASE: &str = "agent-definitions-mode-recovery";

/// Shared Session startup calls this only for this exclusive case, after the
/// existing model listener is ready and before the production server starts.
pub(crate) fn prepare_config(home: &Path, model_base_url: &str) -> Result<()> {
    config::prepare(home, model_base_url)
}

struct Observation<'a> {
    session: &'a mut Session,
    control: AgentDefinitionControl,
    evidence: Vec<String>,
}

pub(crate) async fn run(session: &mut Session) -> Result<report::CaseResult> {
    let control = session
        .agent_definitions
        .as_ref()
        .context("exclusive Agent fixture control missing")?
        .clone();
    let mut observation = Observation {
        session,
        control,
        evidence: Vec::new(),
    };
    let journey = observation.observe().await;
    // Preserve actual requests even on a partial journey. A later missing phase
    // cannot be converted to Passed by an empty dynamic-script cursor.
    let requests = observation.requests()?;
    let artifact = observation
        .session
        .output
        .join("agent-definition-requests.json");
    fs::write(
        &artifact,
        crate::env::redact(&serde_json::to_string_pretty(&requests)?),
    )?;
    let outcome = serde_json::json!({
        "case": CASE,
        "completedEvidence": &observation.evidence,
        "allModelAttemptsIncludingRejected": requests.len(),
        "error": journey.as_ref().err().map(|error| format!("{error:#}")),
    });
    observation.write("agent-definition-journey.json", &outcome)?;
    journey?;
    observation.control.verify_complete()?;
    wire::audit_attempts(&requests)?;
    let mut result = report::passed(
        CASE,
        "real roots, independent Agent/Mode sources, automatic TextSummary compaction, same-home cold child recovery and actual dynamic spawn oneOf/catalog generations",
    );
    result.evidence = observation.evidence;
    result.evidence.push(format!(
        "{} exact model attempts including rejected; requests={}",
        requests.len(),
        artifact.display()
    ));
    Ok(result)
}

impl Observation<'_> {
    fn requests(&self) -> Result<Vec<RecordedRequest>> {
        Ok(self
            .session
            .model
            .as_ref()
            .context("model fixture missing")?
            .recorded())
    }

    fn write<T: Serialize>(&self, name: &str, value: &T) -> Result<()> {
        fs::write(
            self.session.output.join(name),
            serde_json::to_vec_pretty(value)?,
        )
        .with_context(|| format!("write Agent observation evidence {name}"))
    }

    async fn gate(&self, phase: AgentPhase) -> Result<pl_provider_fixture::ReplyStage> {
        let stage = self.control.stage(phase)?;
        tokio::time::timeout(http::PREDICATE_TIMEOUT, stage.wait_reached())
            .await
            .with_context(|| format!("Agent gate {phase:?} not reached"))?;
        ensure!(
            !stage.is_released(),
            "Agent gate {phase:?} released before observation"
        );
        Ok(stage)
    }

    fn phase_requests(&self, phase: AgentPhase) -> Result<Vec<serde_json::Value>> {
        Ok(wire::requests(&self.requests()?, phase)?
            .into_iter()
            .cloned()
            .collect())
    }
}
