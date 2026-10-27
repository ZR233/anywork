//! Controlled product-chain observation; the loopback model supplies conclusions,
//! while all admission, forwarding, completion and history facts come from tools.
use super::{
    Environment, SHARED_MODEL, flow::*, journeys::Decision, review_child, review_wire::*, wire::*,
};
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::json;
use std::collections::BTreeMap;

const INITIAL: &str = "controlled executor initial delivery";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct Identity {
    pub child_id: String,
    pub turn_id: String,
    pub input_id: Option<String>,
    pub commit_sequence: u64,
}

impl Identity {
    pub fn new(report: &Report) -> Self {
        Self {
            child_id: report.child_id.clone(),
            turn_id: report.turn_id.clone(),
            input_id: report.input_id.clone(),
            commit_sequence: report.commit_sequence,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct FirstEvidence {
    pub root: String,
    pub executor: Identity,
    pub reviewer: Identity,
    pub approval: Identity,
    pub compact: String,
    pub arrival: review_child::Arrival,
    pub child_requests: BTreeMap<String, usize>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReviewerCheckpoint {
    target: String,
    target_marker: String,
    provider_requests: usize,
}

pub(super) fn run(flow: &Flow<'_>, prompt: &str, environment: &Environment) -> Progress<Decision> {
    let marker = prompt
        .lines()
        .next()
        .context("missing feedback root marker")?;
    match marker {
        "[[delegation:review-feedback:normal-full]]" => full(flow, environment),
        "[[delegation:review-feedback:reopen]]" => reopen(flow, environment),
        "[[delegation:review-feedback:illegal]]" => illegal(flow, environment),
        "[[delegation:review-feedback:normal]]" => normal(flow, environment),
        "[[delegation:review-feedback:approved]]" => no_wake(flow, environment, "approved"),
        "[[delegation:review-feedback:inconclusive]]" => no_wake(flow, environment, "inconclusive"),
        "[[delegation:review-feedback:natural]]" => no_wake(flow, environment, "natural"),
        "[[delegation:review-feedback:omitted]]" => no_wake(flow, environment, "omitted"),
        "[[delegation:review-feedback:busy]]" => {
            super::review_interleaving::run(flow, environment, "busy")
        }
        "[[delegation:review-feedback:changed]]" => {
            super::review_interleaving::run(flow, environment, "changed")
        }
        "[[delegation:review-feedback:closed]]" => {
            super::review_interleaving::run(flow, environment, "closed")
        }
        _ => Err(anyhow::anyhow!("unknown review-feedback root marker").into()),
    }
}

pub(super) fn routes(flow: &Flow<'_>) -> Progress<(Route, Route)> {
    let models = flow.models()?;
    Ok((
        select(&models, "-a", SHARED_MODEL)?,
        select(&models, "-b", SHARED_MODEL)?,
    ))
}

pub(super) fn executor(flow: &Flow<'_>, route: &Route, case: &str) -> Progress<(Spawn, Report)> {
    let child = flow.spawn(
        "rf-executor",
        "executor",
        Some(route),
        &format!("[[delegation:child:rf-executor:{case}]]"),
        None,
    )?;
    let report = flow.report("rf-initial", &child, INITIAL, 0)?;
    idle(flow, "rf-initial-idle", &child, &report)?;
    Ok((child, report))
}

pub(super) fn reviewer(
    flow: &Flow<'_>,
    environment: &Environment,
    label: &str,
    route: &Route,
    target: &Spawn,
    case: &str,
    feedback: bool,
) -> Progress<Spawn> {
    let expected =
        serde_json::to_string(&completion_expectation(route)?).context("encode reviewer route")?;
    let mut arguments = json!({"profileId":"reviewer","taskSummary":format!("Controlled review {case}"),"reviewTargetAgentId":target.agent_id,"modelSelection":route,"message":format!("[[delegation:child:rf-review:{case}]]\nDELEGATION_EXPECT_COMPLETION:{expected}\nApproved scope: inspect work/review-surface.txt through the real read_file tool, report synthetic findings with the assigned structured disposition. The supplier is scripted, not a real business-code review. Do not alter files or send messages. Stop on any conflict; feedback does not grant architecture authority.")});
    if feedback {
        arguments["reviewFeedback"] = "toExecutor".into();
    }
    let receipt: Spawn = match flow.read(label, "spawn_agent", arguments) {
        Err(Stop::Call(mut decision)) => {
            let target_marker = format!(
                "[[delegation:child:rf-executor:{}]]",
                if case == "approved-normal" {
                    "normal"
                } else {
                    case
                }
            );
            let checkpoint = ReviewerCheckpoint {
                target: target.agent_id.clone(),
                provider_requests: marker_count(environment, &target_marker)?,
                target_marker,
            };
            decision.receipt =
                Some(serde_json::to_value(checkpoint).context("encode pre-review request count")?);
            return Err(Stop::Call(decision));
        }
        result => result?,
    };
    require(
        receipt.message_accepted
            && receipt
                .message_sequence
                .is_some_and(|sequence| sequence > 0)
            && receipt.profile_id == "reviewer"
            && receipt.agent_id != target.agent_id
            && receipt.model == *route,
        "review spawn did not bind a fresh real review child and selected route",
    )?;
    Ok(receipt)
}

pub(super) fn review_report(
    flow: &Flow<'_>,
    label: &str,
    child: &Spawn,
    target: &Spawn,
) -> Progress<Report> {
    for index in 0..8 {
        if let Some(report) = flow
            .request
            .reports()?
            .into_iter()
            .find(|report| report.child_id == child.agent_id)
        {
            report.completed()?;
            let review = report
                .review
                .as_ref()
                .context("review terminal lacks structured projection")?;
            review.require_binding(&report, target)?;
            require(
                report.last_tool.is_none(),
                "review last_tool leaked into compact projection",
            )?;
            return Ok(report);
        }
        flow.raw(
            &format!("{label}-wait-{index}"),
            "wait",
            json!({"taskIds":[],"timeoutMs":300000}),
        )?;
    }
    Err(anyhow::anyhow!("controlled reviewer has no completed report after bounded waits").into())
}

pub(super) fn idle(
    flow: &Flow<'_>,
    label: &str,
    child: &Spawn,
    report: &Report,
) -> Progress<String> {
    let rows: Vec<AgentRow> = flow.read(label, "list_agents", json!({}))?;
    let row = rows
        .iter()
        .find(|row| row.id == child.agent_id)
        .context("target missing from real directory")?;
    require(
        row.lifecycle == Lifecycle::Open
            && row.pending_inputs == 0
            && row.running_tasks == 0
            && row.frozen_model.as_ref() == Some(&child.model),
        "target is not idle on its frozen route",
    )?;
    flow.latest_completed_turn(
        &format!("{label}-latest"),
        LatestTurnCheck {
            row,
            child,
            turn_id: &report.turn_id,
            history: TurnHistory::Always,
        },
    )?;
    Ok(row
        .parent_id
        .clone()
        .context("target lost its direct parent")?)
}

pub(super) fn child_counts(environment: &Environment) -> Result<BTreeMap<String, usize>> {
    let observations = environment
        .observations
        .lock()
        .map_err(|_| anyhow::anyhow!("observation lock poisoned"))?;
    let mut counts = BTreeMap::new();
    for row in observations
        .iter()
        .filter(|row| row.marker.starts_with("[[delegation:child:"))
    {
        *counts.entry(row.marker.clone()).or_default() += 1;
    }
    Ok(counts)
}

pub(super) fn marker_count(environment: &Environment, marker: &str) -> Result<usize> {
    Ok(child_counts(environment)?.get(marker).copied().unwrap_or(0))
}

fn unchanged_provider_count(
    flow: &Flow<'_>,
    environment: &Environment,
    label: &str,
    target: &Spawn,
) -> Result<usize> {
    let (_, prompt) = flow.request.prompt()?;
    let marker = prompt.lines().next().context("root marker absent")?;
    let observations = environment
        .observations
        .lock()
        .map_err(|_| anyhow::anyhow!("observation lock poisoned"))?;
    let rows = observations
        .iter()
        .filter(|row| row.marker == marker && row.note == label)
        .collect::<Vec<_>>();
    require(
        rows.len() == 1,
        "review lost its single original provider-count checkpoint",
    )?;
    let checkpoint: ReviewerCheckpoint = serde_json::from_value(
        rows[0]
            .receipt
            .clone()
            .context("pre-review checkpoint missing")?,
    )
    .context("decode original request count")?;
    drop(observations);
    let after = marker_count(environment, &checkpoint.target_marker)?;
    require(
        checkpoint.target == target.agent_id
            && checkpoint.provider_requests > 0
            && after == checkpoint.provider_requests,
        "non-forwarding review added target provider requests",
    )?;
    Ok(after)
}

fn normal(flow: &Flow<'_>, environment: &Environment) -> Progress<Decision> {
    review_child::require_no_leak(flow.request)?;
    let (execution, review_route) = routes(flow)?;
    let (executor, initial) = executor(flow, &execution, "normal")?;
    let reviewer = reviewer(
        flow,
        environment,
        "rf-reviewer",
        &review_route,
        &executor,
        "normal",
        true,
    )?;
    let report = review_report(flow, "rf-review", &reviewer, &executor)?;
    let review = report.review.as_ref().context("missing normal review")?;
    let baseline = review.require_binding(&report, &executor)?;
    require(
        baseline.turn_id == initial.turn_id
            && baseline.input_id == initial.input_id
            && review.disposition == Disposition::NeedsChanges
            && review.reason.is_none()
            && review.summary == review_child::summary("normal"),
        "normal review lost its original target delivery or typed conclusion",
    )?;
    let (message_id, sequence) = match &review.forward {
        Forward::Accepted {
            message_id,
            sequence,
        } if !message_id.is_empty() && *sequence > baseline.message_sequence => {
            (message_id, sequence)
        }
        _ => {
            return Err(anyhow::anyhow!(
                "normal feedback was not really accepted: {:?}",
                review.forward
            )
            .into());
        }
    };
    let repaired = processed(flow, &executor, &initial)?;
    let arrival: review_child::Arrival = decode(&repaired.message)?;
    let version = review
        .reviewed_version
        .as_deref()
        .context("normal review has no actual read version")?;
    require(
        version
            == format!(
                "{} {}",
                review_child::SURFACE,
                review_child::digest(review_child::SURFACE_TEXT)
            ),
        "review version is not the actual file identity",
    )?;
    let expected_wrapper = review_child::wrapper(
        &reviewer.agent_id,
        &executor.agent_id,
        &report.turn_id,
        version,
        "normal",
    );
    {
        let wrappers = environment
            .review_wrappers
            .lock()
            .map_err(|_| anyhow::anyhow!("wrapper lock poisoned"))?;
        let actual = wrappers
            .iter()
            .find(|row| row.arrival.target == executor.agent_id)
            .context("no actual target provider wrapper")?;
        require(
            actual.text == expected_wrapper
                && actual.arrival == arrival
                && arrival.reviewer == reviewer.agent_id
                && arrival.review_turn == report.turn_id
                && arrival.body_sha256 == review_child::digest(&review_child::body("normal")),
            "target provider request did not contain the exact complete bound wrapper",
        )?;
    }
    let root = idle(flow, "rf-repaired-idle", &executor, &repaired)?;
    flow.close("rf-close-first-reviewer", &reviewer)?;
    let approval_child = self::reviewer(
        flow,
        environment,
        "rf-approval",
        &review_route,
        &executor,
        "approved-normal",
        true,
    )?;
    require(
        approval_child.agent_id != reviewer.agent_id,
        "approval reused reviewer context",
    )?;
    let approval = review_report(flow, "rf-approved", &approval_child, &executor)?;
    let approved = approval.review.as_ref().context("approval missing")?;
    require(
        approved.disposition == Disposition::Approved
            && approved.reason.is_none()
            && approved
                .target
                .as_ref()
                .and_then(|target| target.baseline.as_ref())
                .is_some_and(|baseline| baseline.turn_id == repaired.turn_id)
            && matches!(approved.forward, Forward::NotRequired),
        "fresh approved review forwarded or lost repaired target",
    )?;
    idle(flow, "rf-after-approval-idle", &executor, &repaired)?;
    unchanged_provider_count(flow, environment, "rf-approval", &executor)?;
    flow.close("rf-close-approved-reviewer", &approval_child)?;
    let first = FirstEvidence {
        root,
        executor: Identity::new(&repaired),
        reviewer: Identity::new(&report),
        approval: Identity::new(&approval),
        compact: serde_json::to_string(review).context("encode original compact review")?,
        arrival,
        child_requests: normal_counts(environment)?,
    };
    let mut saved = environment
        .review_first
        .lock()
        .map_err(|_| anyhow::anyhow!("first evidence lock poisoned"))?;
    if let Some(previous) = saved.as_ref() {
        require(*previous == first, "normal evidence changed on replay")?;
    } else {
        *saved = Some(first.clone());
    }
    let mut decision = Decision::answer(
        "rf-normal-compact-complete",
        "review feedback normal compact complete; explicitly request [[delegation:review-feedback:normal-full]] next",
    );
    decision.receipt = Some(
        json!({"first":first,"accepted":{"messageId":message_id,"sequence":sequence},"executorMessagesExposed":repaired.messages.len(),"executorInputId":repaired.input_id,"compactLeakCount":0,"targetInputHistory":"not a public inbox ledger"}),
    );
    Ok(decision)
}

fn processed(flow: &Flow<'_>, child: &Spawn, initial: &Report) -> Progress<Report> {
    for index in 0..8 {
        if let Some(report) = flow.request.reports()?.into_iter().find(|report| {
            report.child_id == child.agent_id && report.commit_sequence > initial.commit_sequence
        }) {
            report.completed()?;
            require(
                report.turn_id != initial.turn_id && report.review.is_none(),
                "feedback processing did not produce a new ordinary executor Turn",
            )?;
            let _: review_child::Arrival = decode(&report.message)?;
            return Ok(report);
        }
        flow.raw(
            &format!("rf-process-wait-{index}"),
            "wait",
            json!({"taskIds":[],"timeoutMs":300000}),
        )?;
    }
    Err(anyhow::anyhow!("feedback did not finish a new executor Turn").into())
}

fn no_wake(flow: &Flow<'_>, environment: &Environment, case: &str) -> Progress<Decision> {
    review_child::require_no_leak(flow.request)?;
    let (execution, review_route) = routes(flow)?;
    let (executor, initial) = executor(flow, &execution, case)?;
    let reviewer = reviewer(
        flow,
        environment,
        "rf-reviewer",
        &review_route,
        &executor,
        case,
        case != "omitted",
    )?;
    let report = review_report(flow, "rf-review", &reviewer, &executor)?;
    let review = report.review.as_ref().context("no-wake review missing")?;
    let baseline = review.require_binding(&report, &executor)?;
    require(
        baseline.turn_id == initial.turn_id && baseline.input_id == initial.input_id,
        "no-wake reviewer lost its original target delivery",
    )?;
    require(
        review.target.as_ref().is_some_and(|target| {
            if case == "omitted" {
                target.feedback.is_none()
            } else {
                target.feedback == Some(Feedback::ToExecutor)
            }
        }),
        "review feedback authorization changed",
    )?;
    let expected = match case {
        "approved" => Disposition::Approved,
        "omitted" => Disposition::NeedsChanges,
        _ => Disposition::Inconclusive,
    };
    require(
        review.disposition == expected
            && if case == "natural" {
                review.reason == Some(ConclusionReason::MissingConclusion)
                    && review.reviewed_version.is_none()
            } else {
                review.reason.is_none() && review.summary == review_child::summary(case)
            },
        "no-wake conclusion was not projected conservatively",
    )?;
    if case != "natural" {
        require(
            review.reviewed_version.as_deref()
                == Some(&format!(
                    "{} {}",
                    review_child::SURFACE,
                    review_child::digest(review_child::SURFACE_TEXT)
                )),
            "no-wake typed review did not retain the actual read version",
        )?;
    }
    require(
        if case == "omitted" {
            matches!(review.forward, Forward::NotRequested)
        } else {
            matches!(review.forward, Forward::NotRequired)
        },
        "no-wake review attempted automatic feedback",
    )?;
    idle(flow, "rf-no-wake-idle", &executor, &initial)?;
    let target_requests = unchanged_provider_count(flow, environment, "rf-reviewer", &executor)?;
    let reports = flow.request.reports()?;
    require(
        reports
            .iter()
            .filter(|report| report.child_id == executor.agent_id)
            .count()
            == 1,
        "no-wake review created another executor Turn",
    )?;
    require(
        !environment
            .review_wrappers
            .lock()
            .map_err(|_| anyhow::anyhow!("wrapper lock poisoned"))?
            .iter()
            .any(|row| row.arrival.target == executor.agent_id),
        "no-wake review reached executor provider",
    )?;
    flow.close("rf-close-reviewer", &reviewer)?;
    flow.close("rf-close-executor", &executor)?;
    let mut decision = Decision::answer(
        &format!("rf-{case}-complete"),
        &format!("review feedback {case} complete"),
    );
    decision.receipt = Some(
        json!({"executor":Identity::new(&initial),"reviewer":Identity::new(&report),"review":review,"targetProviderRequestsBeforeAndAfter":target_requests,"childRequests":child_counts(environment)?}),
    );
    Ok(decision)
}

fn illegal(flow: &Flow<'_>, environment: &Environment) -> Progress<Decision> {
    let (execution, _) = routes(flow)?;
    let before: Vec<AgentRow> = flow.read("rf-illegal-before", "list_agents", json!({}))?;
    let arguments = json!({"profileId":"executor","taskSummary":"Illegal non-review feedback","modelSelection":execution,"writablePaths":["work"],"reviewFeedback":"toExecutor","message":"[[delegation:child:rf-executor:illegal-spawn]]"});
    flow.rejected(
        "rf-illegal-spawn",
        "spawn_agent",
        arguments,
        "Profile executor does not accept a review target",
    )?;
    let after: Vec<AgentRow> = flow.read("rf-illegal-after", "list_agents", json!({}))?;
    let ids = |rows: &[AgentRow]| {
        rows.iter()
            .map(|row| (row.id.clone(), row.parent_id.clone()))
            .collect::<BTreeMap<_, _>>()
    };
    require(
        ids(&before) == ids(&after),
        "illegal spawn left a new child",
    )?;
    require(
        !child_counts(environment)?.contains_key("[[delegation:child:rf-executor:illegal-spawn]]"),
        "illegal spawn started provider work",
    )?;
    let child = flow.spawn(
        "rf-illegal-executor",
        "executor",
        Some(&execution),
        "[[delegation:child:rf-executor:illegal]]",
        None,
    )?;
    let report = flow.report(
        "rf-illegal-finish",
        &child,
        "ordinary review parameter rejected",
        0,
    )?;
    require(
        report.review.is_none(),
        "ordinary executor acquired a valid review",
    )?;
    idle(flow, "rf-illegal-idle", &child, &report)?;
    flow.close("rf-illegal-close", &child)?;
    Ok(Decision::answer(
        "rf-illegal-complete",
        "review feedback illegal calls really rejected",
    ))
}

pub(super) fn original<T: DeserializeOwned>(flow: &Flow<'_>, label: &str, tool: &str) -> Result<T> {
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
        .context("original public tool history is missing")?;
    decode(
        &flow
            .request
            .output(call.call_id.as_deref().context("original callId missing")?)?
            .context("original receipt missing")?,
    )
}

fn first(environment: &Environment) -> Result<FirstEvidence> {
    environment
        .review_first
        .lock()
        .map_err(|_| anyhow::anyhow!("first evidence lock poisoned"))?
        .clone()
        .context("complete normal compact phase first")
}

fn full(flow: &Flow<'_>, environment: &Environment) -> Progress<Decision> {
    let first = first(environment)?;
    let reviewer: Spawn = original(flow, "rf-reviewer", "spawn_agent")?;
    let report = flow
        .request
        .reports()?
        .into_iter()
        .find(|report| Identity::new(report) == first.reviewer)
        .context("original reviewer report missing")?;
    let expected = review_child::body("normal");
    // The first request issuing this public full read must still be leak-free.
    let first_id = format!("{}-rf-full-0", flow.prefix);
    if flow.request.output(&first_id)?.is_none() {
        review_child::require_no_leak(flow.request)?;
    }
    let mut cursor = None;
    let mut through = None;
    let mut ordinal = None;
    let mut found_body = false;
    let mut found_commentary = false;
    for index in 0..4 {
        let page: SavedPage = flow.read(&format!("rf-full-{index}"), "read_agent_session", json!({"target":reviewer.agent_id,"order":"descending","detail":"full","limit":50,"cursor":cursor}))?;
        require(
            page.agent_id == reviewer.agent_id
                && page.path == [first.root.clone(), reviewer.agent_id.clone()]
                && page.through_sequence > 0
                && through.is_none_or(|value| value == page.through_sequence)
                && matches!(page.order, SavedOrder::Descending)
                && matches!(page.detail, SavedDetail::Full)
                && page.items.len() <= 50
                && page.has_more == page.next_cursor.is_some(),
            "public full history lost target/path/watermark/pagination",
        )?;
        through = Some(page.through_sequence);
        for item in page.items {
            require(
                item.thread_id == reviewer.agent_id
                    && ordinal.is_none_or(|value| item.ordinal < value),
                "full history page is unordered or foreign",
            )?;
            ordinal = Some(item.ordinal);
            if item.turn_id == report.turn_id
                && let SavedItemState::Text { data } = item.state
            {
                match data.channel {
                    SavedTextChannel::Final if data.text == expected => found_body = true,
                    SavedTextChannel::Commentary
                        if data.text == review_child::commentary("normal") =>
                    {
                        found_commentary = true
                    }
                    _ => {}
                }
            }
        }
        if found_body && found_commentary {
            let mut decision = Decision::answer(
                "rf-full-history-complete",
                "review feedback full history complete; explicit full read authorized",
            );
            decision.receipt = Some(
                json!({"location":first.reviewer,"bodySha256":review_child::digest(&expected),"fullBodyFound":true,"commentaryFound":true,"compactLeakCountBeforeRead":0}),
            );
            return Ok(decision);
        }
        cursor = page.next_cursor;
        require(
            cursor.is_some(),
            "reviewer public history lacks exact full body or commentary",
        )?;
    }
    Err(anyhow::anyhow!("reviewer full history exceeded four bounded pages").into())
}

fn reopen(flow: &Flow<'_>, environment: &Environment) -> Progress<Decision> {
    let first = first(environment)?;
    let child: Spawn = original(flow, "rf-executor", "spawn_agent")?;
    let reports = flow.request.reports()?;
    let review = reports
        .iter()
        .find(|report| Identity::new(report) == first.reviewer)
        .context("reopened root lost original parent review report identity")?;
    let executor = reports
        .iter()
        .find(|report| Identity::new(report) == first.executor)
        .context("reopened root lost processed executor Turn")?;
    require(
        serde_json::to_string(review.review.as_ref().context("reopened review missing")?)
            .context("encode reopened review")?
            == first.compact,
        "reopened compact report or accepted feedback receipt changed",
    )?;
    let rows: Vec<AgentRow> = flow.read("rf-reopen-directory", "list_agents", json!({}))?;
    let row = rows
        .iter()
        .find(|row| row.id == child.agent_id)
        .context("reopened target absent")?;
    require(
        row.frozen_model.as_ref() == Some(&child.model)
            && row.pending_inputs == 0
            && row.running_tasks == 0,
        "reopened target changed route or has pending work",
    )?;
    flow.latest_completed_turn(
        "rf-reopen-latest",
        LatestTurnCheck {
            row,
            child: &child,
            turn_id: &executor.turn_id,
            history: TurnHistory::Always,
        },
    )?;
    require(
        normal_counts(environment)? == first.child_requests,
        "reconciliation/history/reopen invoked another child provider request",
    )?;
    require(
        reports
            .iter()
            .filter(|report| {
                report.child_id == child.agent_id
                    && report.commit_sequence > executor.commit_sequence
            })
            .count()
            == 0,
        "normal reopen added another target Turn",
    )?;
    let mut decision = Decision::answer(
        "rf-reopen-complete",
        "review feedback reopen complete; no duplicate accepted feedback or child work",
    );
    decision.receipt = Some(
        json!({"first":first,"childRequestsAfter":normal_counts(environment)?,"inboxLedger":"not publicly exposed","observerCrash":"not injected or proved"}),
    );
    Ok(decision)
}

fn normal_counts(environment: &Environment) -> Result<BTreeMap<String, usize>> {
    Ok(child_counts(environment)?
        .into_iter()
        .filter(|(marker, _)| {
            [
                "[[delegation:child:rf-executor:normal]]",
                "[[delegation:child:rf-review:normal]]",
                "[[delegation:child:rf-review:approved-normal]]",
            ]
            .contains(&marker.as_str())
        })
        .collect())
}
