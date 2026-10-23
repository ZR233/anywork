//! One scripted model step at a time, derived from committed wire history.

use super::{ContinuationEvidence, Environment, input_digest, journeys::Decision, wire::*};
use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::{Value, json};

pub(super) enum Stop {
    Call(Box<Decision>),
    Failed(anyhow::Error),
}

impl From<anyhow::Error> for Stop {
    fn from(error: anyhow::Error) -> Self {
        Self::Failed(error)
    }
}

pub(super) type Progress<T> = std::result::Result<T, Stop>;

pub(super) struct Flow<'a> {
    pub request: &'a Request,
    pub prefix: String,
    environment: &'a Environment,
}

pub(super) struct Continuation {
    pub receipt: Sent,
    intent: String,
    input_sha256: String,
}

pub(super) struct ContinuationReport<'a> {
    pub child: &'a Spawn,
    pub previous: &'a Report,
    pub input: &'a Continuation,
    pub previous_sequence: u64,
    pub output: &'a str,
}

pub(super) enum TurnHistory {
    WhenMissing,
    Always,
}

pub(super) struct LatestTurnCheck<'a> {
    pub row: &'a AgentRow,
    pub child: &'a Spawn,
    pub turn_id: &'a str,
    pub history: TurnHistory,
}

pub(super) struct ClosedSendCheck<'a> {
    pub label: &'a str,
    pub child: &'a Spawn,
    pub close: &'a Closed,
    pub root: &'a str,
    pub turn_id: &'a str,
    pub marker: &'a str,
}

#[derive(Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct ClosedChildState {
    target: String,
    parent_agent_id: String,
    model: Route,
    turn_id: String,
    lifecycle: Lifecycle,
    pending_inputs: usize,
    running_tasks: usize,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClosedSendAttempt {
    call_id: String,
    tool: String,
    target: String,
    provider_requests_before: usize,
    before: ClosedChildState,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ClosedSendEvidence {
    call_id: String,
    tool: String,
    target: String,
    tool_error: String,
    pub provider_requests_before: usize,
    pub provider_requests_after: usize,
    before: ClosedChildState,
    after: ClosedChildState,
}

pub(super) fn require(condition: bool, message: &str) -> Result<()> {
    ensure!(condition, "{message}");
    Ok(())
}

impl<'a> Flow<'a> {
    pub fn new(request: &'a Request, environment: &'a Environment) -> Result<Self> {
        let (start, _) = request.prompt()?;
        let generation = request.input[..=start]
            .iter()
            .filter(|item| item.role.as_deref() == Some("user"))
            .filter_map(|item| item.content.as_ref())
            .filter(|content| content.joined().trim_start().starts_with("[[delegation:"))
            .count();
        Ok(Self {
            request,
            prefix: format!("dg-{generation}"),
            environment,
        })
    }

    pub fn raw(&self, label: &str, tool: &str, arguments: Value) -> Progress<String> {
        let id = format!("{}-{label}", self.prefix);
        if let Some(output) = self.request.output(&id)? {
            let declaration = self
                .request
                .input
                .iter()
                .find(|item| item.kind == "function_call" && item.call_id.as_deref() == Some(&id))
                .context("missing tool call declaration")?;
            require(
                declaration.name.as_deref() == Some(tool),
                "tool result belongs to the wrong tool",
            )?;
            return Ok(output);
        }
        require(
            self.request.declared(tool),
            &format!("required tool {tool} was not declared after discovery"),
        )?;
        Err(Stop::Call(Box::new(Decision::call(
            label, &id, tool, arguments,
        ))))
    }

    pub fn read<T: DeserializeOwned>(
        &self,
        label: &str,
        tool: &str,
        arguments: Value,
    ) -> Progress<T> {
        Ok(decode(&self.raw(label, tool, arguments)?)?)
    }

    pub fn rejected(
        &self,
        label: &str,
        tool: &str,
        arguments: Value,
        reason: &str,
    ) -> Progress<()> {
        let text = self.raw(label, tool, arguments)?;
        require(
            text.contains(reason),
            &format!("expected real {tool} rejection containing {reason:?}; got {text}"),
        )?;
        // A response carrying successful evaluation/agent state is never an
        // authorization or validation rejection, even if its comment echoes it.
        require(
            serde_json::from_str::<Value>(&text).is_err(),
            "negative tool call returned structured success instead of a failure",
        )?;
        Ok(())
    }

    pub fn discover(&self) -> Progress<()> {
        let discovered = self.discovered("discover", "delegation_model")?;
        require(
            ["list_delegation_models", "get_delegation_model"]
                .iter()
                .all(|tool| discovered.tool_ids.iter().any(|id| id == tool)),
            "automatic model queries were absent from the real discovery result",
        )?;
        require(
            self.request.declared("list_delegation_models")
                && self.request.declared("get_delegation_model"),
            "automatic model queries were not revealed by discovery",
        )?;
        Ok(())
    }

    pub fn discovered(&self, label: &str, query: &str) -> Progress<DiscoveredTools> {
        let result: DiscoveredTools = self.read(label, "discover_tools", json!({"query":query}))?;
        let id = format!("{}-{label}", self.prefix);
        let declaration = self
            .request
            .input
            .iter()
            .find(|item| item.kind == "function_call" && item.call_id.as_deref() == Some(&id))
            .context("discovery result lost its call declaration")?;
        let arguments: Value = serde_json::from_str(
            declaration
                .arguments
                .as_deref()
                .context("discovery call lacks query arguments")?,
        )
        .context("decode discovery query arguments")?;
        require(
            arguments == json!({"query":query}),
            "discovery call used a different query",
        )?;
        let mut identities = std::collections::BTreeSet::new();
        require(
            result.tool_ids.len() <= 20
                && result
                    .tool_ids
                    .iter()
                    .all(|id| !id.trim().is_empty() && identities.insert(id)),
            "discovery result exceeded its bound or has invalid/duplicate tool identities",
        )?;
        Ok(result)
    }

    /// Walk production cursor pages, never reconstruct the qualification chain.
    /// Page limits and stable identities are checked as observable contracts.
    pub fn models(&self) -> Progress<Vec<Model>> {
        self.discover()?;
        let mut cursor: Option<String> = None;
        let mut models = Vec::new();
        let mut revision = None;
        for index in 0..8 {
            let mut arguments = json!({});
            if let Some(value) = cursor.as_ref() {
                arguments["cursor"] = value.clone().into();
            }
            let page: ModelList = self.read(
                &format!("models-{index}"),
                "list_delegation_models",
                arguments,
            )?;
            require(page.models.len() <= 5, "default query exceeded five models")?;
            if index == 0 && page.next_cursor.is_some() {
                require(
                    page.models.len() == 5,
                    "default first page with further candidates must contain exactly five models",
                )?;
            }
            require(
                revision.is_none_or(|revision| revision == page.catalog_revision),
                "cursor pages changed canonical catalog revision",
            )?;
            revision = Some(page.catalog_revision);
            models.extend(page.models);
            cursor = page.next_cursor;
            if cursor.is_none() {
                let keys: Vec<_> = models
                    .iter()
                    .map(|model| (&model.account_id, &model.model_id))
                    .collect();
                require(
                    keys.windows(2).all(|keys| keys[0] < keys[1]),
                    "model query did not use unique stable account/model order",
                )?;
                require(
                    !models.is_empty(),
                    "no eligible models; fixture must not fall back to a fixed route",
                )?;
                return Ok(models);
            }
        }
        Err(
            anyhow::anyhow!("delegation model query exceeded the bounded eight-page journey")
                .into(),
        )
    }

    pub fn spawn(
        &self,
        label: &str,
        profile: &str,
        route: Option<&Route>,
        marker: &str,
        review: Option<&str>,
    ) -> Progress<Spawn> {
        let expectation = if let Some(route) = route {
            completion_expectation(route)?
        } else {
            CompletionExpectation {
                model_id: if profile == "reviewer" {
                    super::SHARED_MODEL
                } else {
                    super::OTHER_MODEL
                }
                .into(),
                endpoint_alias: if profile == "reviewer" { "b" } else { "a" }.into(),
                account_id: None,
                effort: (profile != "reviewer").then(|| "high".into()),
                continuation: None,
            }
        };
        let expectation =
            serde_json::to_string(&expectation).context("encode completion expectation")?;
        let mut arguments = json!({"profileId": profile, "taskSummary":format!("Delegation {label}"), "message":format!("{marker}\nDELEGATION_EXPECT_COMPLETION:{expectation}\nIsolated manual acceptance. Complete only the assigned synthetic delivery, with no external network or user data changes. Return the exact scenario delivery text; never spawn children or submit evaluations." )});
        if let Some(route) = route {
            arguments["modelSelection"] = json!(route);
        }
        if profile == "executor" {
            arguments["writablePaths"] = json!(["work"]);
        }
        if let Some(target) = review {
            arguments["reviewTargetAgentId"] = target.into();
        }
        let receipt: Spawn = self.read(label, "spawn_agent", arguments)?;
        require(
            receipt.message_accepted
                && receipt
                    .message_sequence
                    .is_some_and(|sequence| sequence > 0)
                && !receipt.agent_id.is_empty(),
            "spawn receipt did not accept the real child input",
        )?;
        require(
            receipt.profile_id == profile,
            "spawn changed the selected role",
        )?;
        if let Some(route) = route {
            require(
                receipt.model == *route,
                "spawn receipt changed the selected account/model/effort",
            )?;
        }
        Ok(receipt)
    }

    pub fn report(
        &self,
        label: &str,
        child: &Spawn,
        message: &str,
        after: u64,
    ) -> Progress<Report> {
        // A report can arrive with the spawn/send receipt. Do not wait for a
        // *second* delivery after already consuming its immutable terminal fact.
        // ACKs and list directory rows never satisfy this check.
        for retry in 0..8 {
            let reports = self.request.reports()?;
            let matches: Vec<_> = reports
                .into_iter()
                .filter(|report| {
                    report.child_id == child.agent_id
                        && report.commit_sequence > after
                        && report.message == message
                })
                .collect();
            if let Some(report) = matches
                .into_iter()
                .max_by_key(|report| report.commit_sequence)
            {
                report.completed()?;
                return Ok(report);
            }
            let _ = self.raw(
                &format!("wait-{label}-{retry}"),
                "wait",
                json!({"taskIds":[],"timeoutMs":300000}),
            )?;
        }
        Err(anyhow::anyhow!(
            "no matching completed report for child {} after bounded waits",
            child.agent_id
        )
        .into())
    }

    pub fn evaluate(
        &self,
        label: &str,
        child: &Spawn,
        report: &Report,
        revision: u64,
        comment: &str,
        outcome: &str,
    ) -> Progress<EvaluationReceipt> {
        require(
            report.child_id == child.agent_id,
            "evaluation report belongs to another child",
        )?;
        report.completed()?;
        let rows: Vec<AgentRow> =
            self.read(&format!("{label}-preflight"), "list_agents", json!({}))?;
        let row = rows
            .iter()
            .find(|row| row.id == child.agent_id)
            .context("evaluation target missing from real agent directory")?;
        require(
            row.lifecycle == Lifecycle::Open
                && row.pending_inputs == 0
                && row.running_tasks == 0
                && row.frozen_model.as_ref() == Some(&child.model),
            "evaluation target still has pending input/work or lost its frozen route",
        )?;
        self.latest_completed_turn(
            &format!("{label}-latest"),
            LatestTurnCheck {
                row,
                child,
                turn_id: &report.turn.turn_id,
                history: TurnHistory::WhenMissing,
            },
        )?;
        let mut arguments = evaluation_arguments(child, report, revision, comment);
        arguments["outcome"] = outcome.into();
        if outcome == "notRated" {
            arguments
                .as_object_mut()
                .context("evaluation arguments must be an object")?
                .remove("quality");
            arguments
                .as_object_mut()
                .context("evaluation arguments must be an object")?
                .remove("instructionFollowing");
        }
        let receipt: EvaluationReceipt = self.read(label, "evaluate_agent", arguments)?;
        require(
            receipt.target == child.agent_id
                && receipt.evaluation.agent_id == child.agent_id
                && receipt.evaluation.model == child.model
                && receipt.evaluation.profile_id == child.profile_id
                && receipt.evaluation.turn_id == report.turn.turn_id,
            "evaluation did not bind the exact child frozen identity and final Turn",
        )?;
        require(
            receipt.evaluation.comment == comment && receipt.evaluation.outcome == outcome,
            "evaluation changed the original Unicode comment or outcome",
        )?;
        require(
            row.parent_id.as_deref() == Some(&receipt.evaluation.parent_agent_id),
            "evaluation does not bind the real direct parent identity",
        )?;
        Ok(receipt)
    }

    pub fn continued_report(&self, label: &str, check: ContinuationReport<'_>) -> Progress<Report> {
        require(
            check.previous.child_id == check.child.agent_id
                && check.input.receipt.target == check.child.agent_id
                && check.previous_sequence > 0
                && check.input.receipt.sequence > check.previous_sequence,
            "continuation did not advance the real target's delivery sequence",
        )?;
        let report = self.report(
            label,
            check.child,
            check.output,
            check.previous.commit_sequence,
        )?;
        require(
            report.turn.turn_id != check.previous.turn.turn_id,
            "continuation reused the previous terminal Turn",
        )?;
        require(
            self.environment
                .observed_continuation(&ContinuationEvidence {
                    target_agent_id: check.child.agent_id.clone(),
                    intent: check.input.intent.clone(),
                    input_sha256: check.input.input_sha256.clone(),
                    output: check.output.to_owned(),
                })?,
            "new terminal has no matching child provider request for the accepted continuation input",
        )?;
        let rows: Vec<AgentRow> = self.read(
            &format!("{label}-continuation-state"),
            "list_agents",
            json!({}),
        )?;
        let row = rows
            .iter()
            .find(|row| row.id == check.child.agent_id)
            .context("continuation child missing from real directory")?;
        require(
            row.lifecycle == Lifecycle::Open
                && row.pending_inputs == 0
                && row.running_tasks == 0
                && row.frozen_model.as_ref() == Some(&check.child.model),
            "continuation report is not the current completed frozen child with no pending work",
        )?;
        self.latest_completed_turn(
            &format!("{label}-continuation-latest"),
            LatestTurnCheck {
                row,
                child: check.child,
                turn_id: &report.turn.turn_id,
                history: TurnHistory::WhenMissing,
            },
        )?;
        Ok(report)
    }

    pub fn close(&self, label: &str, child: &Spawn) -> Progress<Closed> {
        let receipt: Closed = self.read(
            label,
            "close_agent",
            json!({"target":child.agent_id,"workspaceDisposition":"preserve"}),
        )?;
        require(
            receipt.target == child.agent_id
                && receipt.lifecycle == Lifecycle::Closed
                && receipt.workspace_disposition == "preserve",
            "close did not return the real Closed/preserve receipt",
        )?;
        Ok(receipt)
    }

    /// The public activation wrapper is not a typed closed cause. Accept it
    /// only for a successfully closed, unchanged direct child and exact call.
    pub fn refused_closed_send(&self, check: ClosedSendCheck<'_>) -> Progress<ClosedSendEvidence> {
        require(
            check.close.target == check.child.agent_id
                && check.close.lifecycle == Lifecycle::Closed
                && check.close.workspace_disposition == "preserve",
            "closed-send probe lacks the real explicit close receipt",
        )?;
        let route: Detail = self.read(
            &format!("{}-route", check.label),
            "get_delegation_model",
            json!({"accountId":check.child.model.account_id,"modelId":check.child.model.model_id}),
        )?;
        require(
            route.account_id == check.child.model.account_id && route.available,
            "closed-send probe route is unavailable; a configuration/admission failure is not closed evidence",
        )?;
        let rows: Vec<AgentRow> =
            self.read(&format!("{}-before", check.label), "list_agents", json!({}))?;
        let before = closed_child_state(&rows, &check)?;
        self.latest_completed_turn(
            &format!("{}-before-session", check.label),
            LatestTurnCheck {
                row: rows
                    .iter()
                    .find(|row| row.id == check.child.agent_id)
                    .context("closed-send target disappeared before latest Turn check")?,
                child: check.child,
                turn_id: check.turn_id,
                history: TurnHistory::Always,
            },
        )?;
        let mut expectation = completion_expectation(&check.child.model)?;
        expectation.continuation = Some(ContinuationTag {
            target_agent_id: check.child.agent_id.clone(),
            intent: format!("{}-{}", self.prefix, check.label),
        });
        let message = format!(
            "{}\nDELEGATION_EXPECT_COMPLETION:{}",
            check.marker,
            serde_json::to_string(&expectation).context("encode closed-send probe input")?
        );
        let arguments = json!({"target":check.child.agent_id,"message":message});
        let call_id = format!("{}-{}", self.prefix, check.label);
        let error = match self.raw(check.label, "send_message", arguments.clone()) {
            Err(Stop::Call(mut decision)) => {
                // Capture the external counter before dispatch, not when a
                // later model step replays this immutable tool result.
                decision.receipt = Some(json!(ClosedSendAttempt {
                    call_id,
                    tool: "send_message".into(),
                    target: check.child.agent_id.clone(),
                    provider_requests_before: self
                        .environment
                        .targeted_requests(&check.child.agent_id)?,
                    before,
                }));
                return Err(Stop::Call(decision));
            }
            result => result?,
        };
        let declaration = self
            .request
            .input
            .iter()
            .find(|item| item.kind == "function_call" && item.call_id.as_deref() == Some(&call_id))
            .context("closed-send result lost its exact call declaration")?;
        let declared_arguments: Value = serde_json::from_str(
            declaration
                .arguments
                .as_deref()
                .context("closed-send declaration has no arguments")?,
        )
        .context("decode closed-send arguments")?;
        require(
            declaration.name.as_deref() == Some("send_message") && declared_arguments == arguments,
            "closed-send callId/name/target/message association changed",
        )?;
        require(
            serde_json::from_str::<Sent>(&error).is_err()
                && serde_json::from_str::<Value>(&error).is_err()
                && error == super::CLOSED_SEND_ACTIVATION_ERROR,
            "closed-send did not return the exact observed activation failure (ACK/other errors are not proof)",
        )?;
        let attempt = {
            let observations = self
                .environment
                .observations
                .lock()
                .map_err(|_| anyhow::anyhow!("delegation observation lock poisoned"))?;
            let mut attempts = observations
                .iter()
                .filter(|row| row.note == check.label)
                .map(|row| {
                    serde_json::from_value::<ClosedSendAttempt>(
                        row.receipt
                            .clone()
                            .context("closed-send dispatch lost its pre-call evidence")?,
                    )
                    .context("decode closed-send dispatch evidence")
                })
                .collect::<Result<Vec<_>>>()?;
            require(
                attempts.len() == 1,
                "closed-send dispatch evidence is missing or duplicated",
            )?;
            attempts
                .pop()
                .context("closed-send has no original dispatch")?
        };
        require(
            attempt.call_id == call_id
                && attempt.tool == "send_message"
                && attempt.target == check.child.agent_id
                && attempt.before == before,
            "closed-send pre-call identity/state differs from its actual dispatch",
        )?;
        let rows: Vec<AgentRow> =
            self.read(&format!("{}-after", check.label), "list_agents", json!({}))?;
        let after = closed_child_state(&rows, &check)?;
        self.latest_completed_turn(
            &format!("{}-after-session", check.label),
            LatestTurnCheck {
                row: rows
                    .iter()
                    .find(|row| row.id == check.child.agent_id)
                    .context("closed-send target disappeared after latest Turn check")?,
                child: check.child,
                turn_id: check.turn_id,
                history: TurnHistory::Always,
            },
        )?;
        let provider_requests_after = self.environment.targeted_requests(&check.child.agent_id)?;
        require(
            after == before && provider_requests_after == attempt.provider_requests_before,
            "closed child acquired a new Turn, changed state or reached the provider",
        )?;
        Ok(ClosedSendEvidence {
            call_id,
            tool: "send_message".into(),
            target: check.child.agent_id.clone(),
            tool_error: error,
            provider_requests_before: attempt.provider_requests_before,
            provider_requests_after,
            before,
            after,
        })
    }

    /// A missing list projection needs durable public history. A conflicting
    /// projection is a failure, never a reason to replace it with history.
    pub fn latest_completed_turn(&self, label: &str, check: LatestTurnCheck<'_>) -> Progress<()> {
        require(
            check.row.id == check.child.agent_id && !check.turn_id.trim().is_empty(),
            "latest Turn evidence belongs to a different or invalid child/Turn",
        )?;
        let root = check
            .row
            .parent_id
            .as_deref()
            .context("latest Turn target has no direct parent")?;
        let missing = match check.row.last_turn.as_ref() {
            Some(turn) => {
                require(
                    turn.turn_id == check.turn_id
                        && matches!(&turn.state, TurnState::Finished(outcome) if outcome == "completed"),
                    "listed latest Turn conflicts with the expected completed report",
                )?;
                false
            }
            None => true,
        };
        if missing || matches!(check.history, TurnHistory::Always) {
            self.saved_completed_turn(label, check.child, root, check.turn_id)?;
        }
        Ok(())
    }

    fn saved_completed_turn(
        &self,
        label: &str,
        child: &Spawn,
        root: &str,
        turn_id: &str,
    ) -> Progress<()> {
        let mut cursor = None;
        let mut through = None;
        let mut previous_ordinal = None;
        for index in 0..4 {
            let page: SavedPage = self.read(&format!("{label}-{index}"), "read_agent_session",
                json!({"target":child.agent_id,"order":"descending","detail":"full","limit":50,"cursor":cursor}))?;
            require(
                page.agent_id == child.agent_id
                    && page.path == [root, child.agent_id.as_str()]
                    && matches!(page.order, SavedOrder::Descending)
                    && matches!(page.detail, SavedDetail::Full)
                    && page.through_sequence > 0
                    && through.is_none_or(|value| value == page.through_sequence)
                    && page.items.len() <= 50
                    && page.has_more == page.next_cursor.is_some(),
                "saved child Turn query lost its target/parent/order/watermark contract",
            )?;
            through = Some(page.through_sequence);
            for item in page.items {
                require(
                    !item.id.trim().is_empty()
                        && item.thread_id == child.agent_id
                        && previous_ordinal.is_none_or(|ordinal| item.ordinal < ordinal),
                    "saved child Turn page is unordered or belongs to another target",
                )?;
                previous_ordinal = Some(item.ordinal);
                if let SavedItemState::Turn { data: turn } = item.state {
                    require(
                        item.turn_id == turn_id
                            && matches!(turn.state, SavedTurnState::Completed {data: SavedCompleted {completed_at, completion: SavedCompletion::Normal}} if completed_at > 0),
                        "child history has a different or non-completed latest Turn",
                    )?;
                    return Ok(());
                }
            }
            cursor = page.next_cursor;
            require(
                cursor.is_some(),
                "saved child history has no completed Turn evidence",
            )?;
        }
        Err(anyhow::anyhow!("saved child latest Turn exceeded four bounded history pages").into())
    }

    pub fn send(&self, label: &str, child: &Spawn, marker: &str) -> Progress<Continuation> {
        let intent = format!("{}-{label}", self.prefix);
        let mut expectation = completion_expectation(&child.model)?;
        expectation.continuation = Some(ContinuationTag {
            target_agent_id: child.agent_id.clone(),
            intent: intent.clone(),
        });
        let expectation =
            serde_json::to_string(&expectation).context("encode continuation expectation")?;
        let message = format!("{marker}\nDELEGATION_EXPECT_COMPLETION:{expectation}");
        let receipt: Sent = self.read(
            label,
            "send_message",
            json!({"target":child.agent_id,"message":message}),
        )?;
        require(
            receipt.target == child.agent_id
                && receipt.sequence > 0
                && !receipt.message_id.trim().is_empty(),
            "continuation did not return a real target/input delivery identity",
        )?;
        Ok(Continuation {
            receipt,
            intent,
            input_sha256: input_digest(&message),
        })
    }
}

fn closed_child_state(rows: &[AgentRow], check: &ClosedSendCheck<'_>) -> Result<ClosedChildState> {
    require(
        rows.iter().any(|row| {
            row.id == check.root && row.parent_id.is_none() && row.lifecycle == Lifecycle::Open
        }),
        "closed-send caller is not the live original root",
    )?;
    let row = rows
        .iter()
        .find(|row| row.id == check.child.agent_id)
        .context("closed-send target is missing from the real directory")?;
    require(
        row.parent_id.as_deref() == Some(check.root)
            && row.lifecycle == Lifecycle::Closed
            && row.frozen_model.as_ref() == Some(&check.child.model)
            && row.pending_inputs == 0
            && row.running_tasks == 0,
        "closed-send target is not the unchanged closed direct child/frozen route/final Turn",
    )?;
    Ok(ClosedChildState {
        target: check.child.agent_id.clone(),
        parent_agent_id: check.root.into(),
        model: check.child.model.clone(),
        turn_id: check.turn_id.into(),
        lifecycle: Lifecycle::Closed,
        pending_inputs: row.pending_inputs,
        running_tasks: row.running_tasks,
    })
}

pub(super) fn completion_expectation(route: &Route) -> Result<CompletionExpectation> {
    let alias = if route.account_id.ends_with("-a") {
        "a"
    } else if route.account_id.ends_with("-b") {
        "b"
    } else {
        anyhow::bail!("production query selected an unexpected synthetic account")
    };
    Ok(CompletionExpectation {
        model_id: route.model_id.clone(),
        endpoint_alias: alias.into(),
        account_id: Some(route.account_id.clone()),
        effort: route.effort.clone(),
        continuation: None,
    })
}

pub(super) fn evaluation_arguments(
    child: &Spawn,
    report: &Report,
    revision: u64,
    comment: &str,
) -> Value {
    json!({"target":child.agent_id,"expectedTurnId":report.turn.turn_id,"expectedRevision":revision,"taskCategory":"general","outcome":"passed","quality":4,"instructionFollowing":5,"comment":comment})
}

pub(super) fn select(models: &[Model], suffix: &str, model_id: &str) -> Result<Route> {
    models.iter().find(|model| model.account_id.ends_with(suffix) && model.model_id == model_id)
        .map(Model::route).context("requested synthetic identity was not returned by the production model query; no fallback")
}
