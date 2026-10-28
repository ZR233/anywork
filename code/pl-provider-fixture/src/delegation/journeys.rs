//! Scenario dispatch belongs only to the external scripted provider.

use super::flow::{Flow, Progress, Stop, completion_expectation, require, select};
use super::{Environment, Scenario, wire::*};
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::{Value, json};
use std::collections::BTreeMap;

const ROOT_ONLY_TOOLS: [&str; 4] = [
    "spawn_agent",
    "list_delegation_models",
    "get_delegation_model",
    "evaluate_agent",
];

pub(super) struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: Value,
}

pub(super) struct Decision {
    pub note: String,
    pub text: String,
    pub call: Option<ToolCall>,
    pub wait_for_repair: bool,
    pub receipt: Option<Value>,
}

impl Decision {
    pub fn answer(note: &str, text: &str) -> Self {
        Self {
            note: note.into(),
            text: text.into(),
            call: None,
            wait_for_repair: false,
            receipt: None,
        }
    }

    pub fn call(note: &str, id: &str, tool: &str, arguments: Value) -> Self {
        Self {
            note: note.into(),
            text: String::new(),
            call: Some(ToolCall {
                id: id.into(),
                name: tool.into(),
                arguments,
            }),
            wait_for_repair: note == "running-old-terminal",
            receipt: None,
        }
    }
}

pub(super) fn decide(request: &Request, environment: &Environment) -> Result<Decision> {
    let (_, prompt) = request.prompt()?;
    let flow = Flow::new(request, environment)?;
    let scenario = environment.scenario.context("delegation scenario absent")?;
    let result = if prompt.starts_with("[[delegation:child:") {
        child(request, &prompt, environment)
    } else {
        match scenario {
            Scenario::Routing => super::routing::run(&flow, &prompt),
            Scenario::Lifecycle => super::lifecycle::run(&flow, &prompt, environment),
            Scenario::Window => super::window::run(&flow, &prompt),
            Scenario::Enablement => enablement(&flow, &prompt, environment),
            Scenario::Recovery => super::recovery::run(&flow, &prompt, environment),
            Scenario::ReviewFeedback => super::review_feedback::run(&flow, &prompt, environment),
            Scenario::Worktree => super::worktree::run(&flow, &prompt, environment),
        }
    };
    match result {
        Ok(decision) => Ok(decision),
        Err(Stop::Call(mut decision)) => {
            if decision
                .call
                .as_ref()
                .is_some_and(|call| call.name == "read_file")
            {
                for case in ["busy", "changed", "closed"] {
                    if prompt.starts_with(&format!("[[delegation:child:rf-review:{case}]]")) {
                        decision.note = format!("rf-review-{case}-arrived");
                    }
                }
            }
            Ok(*decision)
        }
        Err(Stop::Failed(error)) => Err(error),
    }
}

fn child(request: &Request, prompt: &str, environment: &Environment) -> Progress<Decision> {
    require(
        ROOT_ONLY_TOOLS.iter().all(|tool| !request.declared(tool)),
        "child received a root-only delegation tool",
    )?;
    let flow = Flow::new(request, environment)?;
    for (index, tool) in ROOT_ONLY_TOOLS.iter().enumerate() {
        let discovery = flow.discovered(&format!("child-root-surface-{index}"), tool)?;
        // A valid per-name query with zero matches cannot hide a forbidden
        // member behind the producer's twenty-result cap. Nonempty is not proof.
        require(
            discovery.tool_ids.is_empty(),
            "child discovery returned matching root-only tools",
        )?;
        require(
            ROOT_ONLY_TOOLS.iter().all(|tool| !request.declared(tool)),
            "child discovery revealed a deferred root-only tool",
        )?;
    }
    if let Some(decision) = super::review_child::child(&flow, prompt, environment)? {
        return Ok(decision);
    }
    if let Some(decision) = super::worktree::child_reply(&flow, prompt)? {
        return Ok(decision);
    }
    let (note, text) = if let Some(reply) = super::recovery::child_reply(request, prompt)? {
        reply
    } else if prompt.starts_with("[[delegation:child:initial]]") {
        ("child_initial", "delegation initial delivery")
    } else if prompt.starts_with("[[delegation:child:review]]") {
        (
            "child_review",
            "delegation independent review: changes requested",
        )
    } else if prompt.starts_with("[[delegation:child:repair]]") {
        ("child_repair", "delegation repaired delivery")
    } else if prompt.starts_with("[[delegation:child:review-pass]]") {
        (
            "child_review_pass",
            "delegation independent review: approved",
        )
    } else if prompt.starts_with("[[delegation:child:late-repair]]") {
        ("repair_arrived", "delegation late repaired delivery")
    } else if prompt.starts_with("[[delegation:child:sample]]") {
        ("child_sample", "delegation sample delivery")
    } else {
        return Err(anyhow::anyhow!("unknown child marker").into());
    };
    if prompt.starts_with("[[delegation:child:review]]")
        || prompt.starts_with("[[delegation:child:review-pass]]")
        || prompt.starts_with("[[delegation:child:recovery-review-")
    {
        return super::review_child::finish_review(
            &flow,
            note,
            text,
            if prompt.starts_with("[[delegation:child:review]]") {
                super::review_wire::Disposition::NeedsChanges
            } else {
                super::review_wire::Disposition::Approved
            },
            note,
        );
    }
    Ok(Decision::answer(note, text))
}

fn enablement(flow: &Flow<'_>, prompt: &str, environment: &Environment) -> Progress<Decision> {
    if prompt.starts_with("[[delegation:before-disable]]") {
        let models = flow.models()?;
        require(
            models.iter().any(|model| {
                model.account_id.ends_with("-a") && model.model_id == super::SHARED_MODEL
            }),
            "before-disable query did not include the enabled target",
        )?;
        let b = select(&models, "-b", super::SHARED_MODEL)?;
        let candidates: ModelList = flow.read(
            "enabled-b-candidates",
            "list_delegation_models",
            json!({"accountId":b.account_id}),
        )?;
        require(
            select(&candidates.models, "-b", super::SHARED_MODEL)? == b,
            "enabled B route did not come from its actual candidate query",
        )?;
        let available: EnablementAvailability = flow.read(
            "enabled-b-detail",
            "get_delegation_model",
            json!({"accountId":b.account_id,"modelId":b.model_id}),
        )?;
        available.require_enabled(&b)?;
        return Ok(Decision::answer(
            "enabled_query_before_disable",
            "query captured before disable; start the other root inflight gate now",
        ));
    }
    if prompt.starts_with("[[delegation:inflight]]") {
        return Ok(Decision::answer(
            "inflight_arrived",
            "delegation inflight completed after disable",
        ));
    }
    // A disabled next Turn must fail before another completion request. Seeing
    // this marker at the supplier is itself a hard harness failure.
    require(
        !prompt.starts_with("[[delegation:disabled-next]]"),
        "disabled route admitted a new completion request",
    )?;
    if prompt.starts_with("[[delegation:inspect-disabled]]") {
        flow.discover()?;
        let (start, _) = flow.request.prompt()?;
        let old_call = flow.request.input[..start]
            .iter()
            .rfind(|item| {
                item.kind == "function_call"
                    && item.name.as_deref() == Some("list_delegation_models")
                    && item
                        .call_id
                        .as_ref()
                        .is_some_and(|id| id.ends_with("-models-0"))
            })
            .context("capture [[delegation:before-disable]] in this observer root first")?;
        let old_call_id = old_call
            .call_id
            .as_deref()
            .context("old query missing call id")?;
        let old_arguments: Value = serde_json::from_str(
            old_call
                .arguments
                .as_deref()
                .context("old query missing arguments")?,
        )
        .context("decode old query arguments")?;
        let old_page: ModelList = flow.read_call(
            old_call_id,
            "list_delegation_models",
            old_arguments,
            "disabled-old-query",
        )?;
        flow.rejected("stale-after-disable", "list_delegation_models", json!({"cursor":old_page.next_cursor.context("before-disable query did not return a cursor")?}), "stale or belongs to another query")?;
        let models = flow.models()?;
        let surviving = super::flow::select(&models, "-a", super::OTHER_MODEL)?;
        require(
            !models.iter().any(|model| {
                model.account_id == surviving.account_id && model.model_id == super::SHARED_MODEL
            }),
            "disabled model remained in a new delegation query",
        )?;
        let detail: Detail = flow.read(
            "disabled-detail",
            "get_delegation_model",
            json!({"accountId":surviving.account_id,"modelId":super::SHARED_MODEL}),
        )?;
        require(
            !detail.available
                && detail
                    .unavailable_reason
                    .as_ref()
                    .is_some_and(|reason| !reason.is_empty()),
            "disabled route detail lost its explicit unavailable reason",
        )?;
        let rows: Vec<AgentRow> = flow.read("disabled-directory", "list_agents", json!({}))?;
        require(
            !rows.is_empty(),
            "disabled inspect root lost its production directory",
        )?;
        return Ok(Decision::answer(
            "disabled_query_excluded",
            "disabled route query excluded; keep the inflight response held until the UI canonical disabled state is recorded",
        ));
    }
    if prompt.starts_with("[[delegation:no-candidates]]") {
        let models = flow.models()?;
        let _ = select(&models, "-a", super::OTHER_MODEL)?;
        return disabled_spawn(flow, environment);
    }
    if prompt.starts_with("[[delegation:enabled-again]]") {
        let mut result = Decision::answer("enablement_complete", "delegation enabled again");
        let rows: Vec<AgentRow> = flow.read("enabled-list", "list_agents", json!({}))?;
        require(
            !rows.is_empty(),
            "enabled root has no real directory identity",
        )?;
        result.receipt = Some(
            json!({"rootAgentId":rows.iter().find(|row| row.parent_id.is_none()).context("missing real root directory row")?.id}),
        );
        return Ok(result);
    }
    Err(anyhow::anyhow!("unknown enablement marker").into())
}

/// Only the canonical detail fields needed to explain this admission failure.
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct EnablementAvailability {
    account_id: String,
    descriptor: EnablementDescriptor,
    available: bool,
    unavailable_reason: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct EnablementDescriptor {
    model_id: String,
    enabled: bool,
}

impl EnablementAvailability {
    fn require_enabled(&self, route: &Route) -> Result<()> {
        require(
            self.account_id == route.account_id
                && self.descriptor.model_id == route.model_id
                && self.descriptor.enabled
                && self.available
                && self.unavailable_reason.is_none(),
            "B/shared was not an available enabled canonical candidate before disable",
        )
    }

    fn require_disabled(&self, route: &Route) -> Result<()> {
        let reason = format!(
            "configuration error: role executor uses disabled model {}.{}",
            route.account_id, route.model_id,
        );
        require(
            self.account_id == route.account_id
                && self.descriptor.model_id == route.model_id
                && !self.descriptor.enabled
                && !self.available
                && self.unavailable_reason.as_deref() == Some(reason.as_str()),
            "B/shared detail did not prove the same existing model is now disabled",
        )
    }
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct EnablementProviderCounts {
    route_requests: usize,
    child_requests: usize,
}

fn provider_counts(environment: &Environment, route: &Route) -> Result<EnablementProviderCounts> {
    let expected = completion_expectation(route)?;
    let rows = environment
        .observations
        .lock()
        .map_err(|_| anyhow::anyhow!("delegation observation lock poisoned"))?;
    Ok(EnablementProviderCounts {
        route_requests: rows
            .iter()
            .filter(|row| {
                row.endpoint_alias == expected.endpoint_alias && row.model == route.model_id
            })
            .count(),
        child_requests: rows
            .iter()
            .filter(|row| row.marker.starts_with("[[delegation:child:"))
            .count(),
    })
}

type EnablementDirectory = BTreeMap<String, Option<String>>;

fn enablement_directory(rows: Vec<AgentRow>) -> Result<EnablementDirectory> {
    let mut directory = BTreeMap::new();
    require(!rows.is_empty(), "enablement lost its real agent directory")?;
    for row in rows {
        require(
            !row.id.trim().is_empty()
                && row.parent_id.is_none()
                && !directory.contains_key(&row.id),
            "enablement spawned or retained an unexpected child/directory identity",
        )?;
        directory.insert(row.id, row.parent_id);
    }
    Ok(directory)
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DisabledSpawnAttempt {
    call_id: String,
    tool: String,
    arguments: Value,
    model: Route,
    before: EnablementDirectory,
    provider_requests_before: EnablementProviderCounts,
}

fn original_enablement<T: DeserializeOwned>(
    flow: &Flow<'_>,
    label: &str,
    tool: &str,
) -> Progress<(T, Value)> {
    let (start, _) = flow.request.prompt()?;
    let suffix = format!("-{label}");
    let call = flow.request.input[..start]
        .iter()
        .rfind(|item| {
            item.kind == "function_call"
                && item.name.as_deref() == Some(tool)
                && item
                    .call_id
                    .as_ref()
                    .is_some_and(|id| id.ends_with(&suffix))
        })
        .context("enablement observer lost its real before-disable tool history")?;
    let arguments: Value = serde_json::from_str(
        call.arguments
            .as_deref()
            .context("original query has no arguments")?,
    )
    .context("decode original before-disable arguments")?;
    let call_id = call
        .call_id
        .as_deref()
        .context("original query has no callId")?;
    let result = flow.read_call(
        call_id,
        tool,
        arguments.clone(),
        &format!("enablement-history-{label}"),
    )?;
    Ok((result, arguments))
}

fn disabled_spawn(flow: &Flow<'_>, environment: &Environment) -> Progress<Decision> {
    let (candidates, query): (ModelList, _) =
        original_enablement(flow, "enabled-b-candidates", "list_delegation_models")?;
    let b = select(&candidates.models, "-b", super::SHARED_MODEL)?;
    let (enabled, detail_query): (EnablementAvailability, _) =
        original_enablement(flow, "enabled-b-detail", "get_delegation_model")?;
    require(
        query == json!({"accountId":b.account_id})
            && detail_query == json!({"accountId":b.account_id,"modelId":b.model_id}),
        "before-disable evidence belongs to a different account/model query",
    )?;
    enabled.require_enabled(&b)?;
    let empty: ModelList = flow.read(
        "empty-account",
        "list_delegation_models",
        json!({"accountId":b.account_id}),
    )?;
    require(
        empty.models.is_empty() && empty.next_cursor.is_none(),
        "no-candidate account did not remain explicitly empty",
    )?;
    let disabled: EnablementAvailability = flow.read(
        "disabled-b-detail",
        "get_delegation_model",
        json!({"accountId":b.account_id,"modelId":b.model_id}),
    )?;
    disabled.require_disabled(&b)?;
    require(
        environment.inflight_arrived.is_cancelled() && !environment.inflight_release.is_cancelled(),
        "disabled spawn must run while the actual inflight response remains held",
    )?;
    let before =
        enablement_directory(flow.read("disabled-spawn-before", "list_agents", json!({}))?)?;
    // This remains a valid child request even if production wrongly admits it.
    // The supplier answers normally; it never implements the disabled policy.
    let message = format!(
        "[[delegation:child:sample]]\nDELEGATION_EXPECT_COMPLETION:{}",
        serde_json::to_string(&completion_expectation(&b)?)
            .context("encode disabled-spawn completion expectation")?
    );
    let arguments = json!({"profileId":"explorer","taskSummary":"Reject disabled route","message":message,"modelSelection":b});
    let call_id = format!("{}-disabled-spawn", flow.prefix);
    let error = match flow.raw("disabled-spawn", "spawn_agent", arguments.clone()) {
        Err(Stop::Call(mut decision)) => {
            decision.receipt = Some(json!(DisabledSpawnAttempt {
                call_id,
                tool: "spawn_agent".into(),
                arguments,
                model: b.clone(),
                before,
                provider_requests_before: provider_counts(environment, &b)?,
            }));
            return Err(Stop::Call(decision));
        }
        result => result?,
    };
    let declaration = flow
        .request
        .input
        .iter()
        .find(|item| item.kind == "function_call" && item.call_id.as_deref() == Some(&call_id))
        .context("disabled-spawn lost its exact call declaration")?;
    let declared_arguments: Value = serde_json::from_str(
        declaration
            .arguments
            .as_deref()
            .context("disabled-spawn call lacks arguments")?,
    )
    .context("decode disabled-spawn arguments")?;
    require(
        declaration.name.as_deref() == Some("spawn_agent") && declared_arguments == arguments,
        "disabled-spawn callId/name/arguments changed",
    )?;
    require(
        serde_json::from_str::<Spawn>(&error).is_err()
            && serde_json::from_str::<Sent>(&error).is_err()
            && serde_json::from_str::<Value>(&error).is_err()
            && error == "child configuration resolution failed",
        "disabled-spawn did not return the exact configuration failure; other errors/ACKs are not evidence",
    )?;
    let attempt = {
        let observations = environment
            .observations
            .lock()
            .map_err(|_| anyhow::anyhow!("delegation observation lock poisoned"))?;
        let mut attempts = observations
            .iter()
            .filter(|row| row.note == "disabled-spawn")
            .map(|row| {
                serde_json::from_value::<DisabledSpawnAttempt>(
                    row.receipt
                        .clone()
                        .context("disabled-spawn dispatch lost its baseline")?,
                )
                .context("decode disabled-spawn dispatch baseline")
            })
            .collect::<Result<Vec<_>>>()?;
        require(
            attempts.len() == 1,
            "disabled-spawn original dispatch is missing or duplicated",
        )?;
        attempts
            .pop()
            .context("disabled-spawn has no original dispatch")?
    };
    require(
        attempt.call_id == call_id
            && attempt.tool == "spawn_agent"
            && attempt.arguments == arguments
            && attempt.model == b
            && attempt.before == before,
        "disabled-spawn pre-call evidence does not match its actual dispatch",
    )?;
    let after =
        enablement_directory(flow.read("disabled-spawn-after", "list_agents", json!({}))?)?;
    let provider_requests_after = provider_counts(environment, &b)?;
    require(
        after == before && provider_requests_after == attempt.provider_requests_before,
        "disabled-spawn created a directory member or a provider request/fallback",
    )?;
    let mut result = Decision::answer(
        "no_candidates_rejected",
        "no candidates; disabled spawn refused without a supplier request or fallback",
    );
    result.receipt = Some(
        json!({"callId":call_id,"tool":"spawn_agent","arguments":arguments,"toolError":error,"model":b,"enabledBefore":enabled,"disabledAfter":disabled,"before":before,"after":after,"providerRequestsBefore":attempt.provider_requests_before,"providerRequestsAfter":provider_requests_after}),
    );
    Ok(result)
}
