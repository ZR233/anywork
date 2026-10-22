//! `reply-send-outcomes-restart`: automatic formal replies stay accounted as
//! Unknown/Partial across a same-home restart and are never replayed.
//!
//! Two authorized inbound messages each drive one real model Final. The first
//! reply hits a real HTTP uncertainty (accepted then dropped) and must land in
//! the durable ledger as `unknown`; the second is a complete multi-segment
//! Final whose first segment succeeds and second is rejected, landing as
//! `partial` with the remaining segment never sent. After both outcomes are
//! determined the server restarts over the same home and peer; no model
//! execution, no send call, and no durable send fact may change or replay.

use super::super::Session;
use super::{CASE_BUDGET, ensure_bound_row, optional_title_step};
use crate::http;
use crate::report::{self, CaseResult};
use anyhow::{Context, Result, ensure};
use pl_provider_fixture::feishu::{
    CallKind, ChatType, DIRECT_CHAT_ID, SendDisposition, SenderKind, TRUSTED_USER_OPEN_ID,
    text_event,
};
use pl_provider_fixture::{Protocol, Reply, Step, responses_text};
use serde::Deserialize;
use std::time::Duration;

pub(super) const CASE: &str = "reply-send-outcomes-restart";

const UNKNOWN_MESSAGE_ID: &str = "om_sendout_unknown";
const UNKNOWN_PROMPT: &str = "Bots send outcome fixture: unknown after accepted drop";
const UNKNOWN_FINAL: &str = "B2U single-segment unknown auto-reply marker.";
const UNKNOWN_MARKER: &str = "B2U single-segment unknown auto-reply marker";
const PARTIAL_MESSAGE_ID: &str = "om_sendout_partial";
const PARTIAL_PROMPT: &str = "Bots send outcome fixture: partial multi-segment final";
const PARTIAL_HEAD: &str = "B2P partial auto-reply header marker. ";
const PARTIAL_UNIT: &str = "b2p segment payload unit ";
const PARTIAL_TAIL: &str = " b2p partial tail marker.";
const PARTIAL_UNIT_REPEATS: usize = 2_440;
/// Recovery sweep observations after the restart. There is no public
/// "sweep ran" marker, so the case holds a bounded quiet window that covers
/// at least two full sweep periods of the frozen-source 5s scheduler and then
/// re-asserts the durable facts; this cannot prove claim-takeover races.
const RESTART_QUIET: Duration = Duration::from_secs(14);

pub(crate) async fn send_outcomes(session: &mut Session) -> Result<CaseResult> {
    let mut evidence = Vec::new();
    let outcome =
        tokio::time::timeout(CASE_BUDGET, send_outcomes_inner(session, &mut evidence)).await;
    match outcome {
        Ok(Ok(result)) => Ok(result),
        Ok(Err(error)) => {
            let mut result = report::failed(CASE, format!("{error:#}"));
            result.evidence = evidence;
            Ok(result)
        }
        Err(_) => {
            let mut result = report::failed(
                CASE,
                "reply-send-outcomes-restart exceeded its absolute observe budget",
            );
            result.evidence = evidence;
            Ok(result)
        }
    }
}

async fn send_outcomes_inner(
    session: &mut Session,
    evidence: &mut Vec<String>,
) -> Result<CaseResult> {
    let (bot_id, _) = session.ensure_trusted_direct().await?;
    session.wait_connected(&bot_id).await?;
    session
        .control()?
        .set_send_script(vec![
            SendDisposition::AcceptThenDrop,
            SendDisposition::Succeed,
            SendDisposition::Reject {
                code: 230_020,
                msg: "rate limited".into(),
            },
        ])
        .await;

    // Outcome 1: a real HTTP uncertainty for a single-segment Final.
    session
        .control()?
        .send_event(text_event(
            UNKNOWN_MESSAGE_ID,
            DIRECT_CHAT_ID,
            ChatType::P2p,
            SenderKind::User,
            TRUSTED_USER_OPEN_ID,
            UNKNOWN_PROMPT,
            Vec::new(),
        ))
        .await?;
    wait_send_status(session, &bot_id, "unknown").await?;
    wait_inbound_status(session, &bot_id, UNKNOWN_MESSAGE_ID, "needs_attention").await?;
    evidence.push("single-segment Final landed as unknown with needs_attention inbound".into());

    // Outcome 2: a complete multi-segment Final with a real mid-send rejection.
    session
        .control()?
        .send_event(text_event(
            PARTIAL_MESSAGE_ID,
            DIRECT_CHAT_ID,
            ChatType::P2p,
            SenderKind::User,
            TRUSTED_USER_OPEN_ID,
            PARTIAL_PROMPT,
            Vec::new(),
        ))
        .await?;
    wait_send_status(session, &bot_id, "partial").await?;
    wait_inbound_status(session, &bot_id, PARTIAL_MESSAGE_ID, "needs_attention").await?;
    evidence.push("multi-segment Final landed as partial with needs_attention inbound".into());

    let before = restart_baseline(session, &bot_id).await?;
    ensure!(
        before.model_executions == 2,
        "the two inbound messages must consume exactly two model executions, got {}",
        before.model_executions
    );
    ensure!(
        before.unknown_calls == 1 && before.partial_calls == 2 && before.total_calls == 3,
        "send calls before restart must be one unknown plus two partial segments, got {}",
        before.summary()
    );
    let unknown_detail = before
        .send_details
        .iter()
        .find(|row| row.status == "unknown")
        .context("no durable unknown send row")?;
    let partial_detail = before
        .send_details
        .iter()
        .find(|row| row.status == "partial")
        .context("no durable partial send row")?;
    assert_unknown_ledger(unknown_detail, &before.send_uuids)?;
    assert_partial_ledger(partial_detail, &before.send_uuids)?;
    ensure!(
        before.send_details.len() == 2,
        "the durable send ledger must hold exactly the two automatic replies, got {}",
        before.send_details.len()
    );
    evidence.push(format!(
        "ledger before restart: {}",
        before
            .send_details
            .iter()
            .map(|row| format!("{}={}", row.operation_id, row.status))
            .collect::<Vec<_>>()
            .join(", ")
    ));

    let thread_id = super::wait_thread_binding(&session.home, &bot_id, DIRECT_CHAT_ID).await?;

    // Same-home restart over the same peer; wait out at least two recovery
    // sweep periods, then require every durable fact to be unchanged.
    let restart = session.restart_studio_server().await?;
    evidence.push(restart);
    session.wait_connected(&bot_id).await?;
    http::hold_for(RESTART_QUIET).await;

    let after = restart_baseline(session, &bot_id).await?;
    ensure!(
        after.model_executions == before.model_executions,
        "restart must not re-execute either model Final ({} -> {})",
        before.model_executions,
        after.model_executions
    );
    ensure!(
        after.total_calls == before.total_calls
            && after.unknown_calls == before.unknown_calls
            && after.partial_calls == before.partial_calls,
        "restart must not add any Feishu send call: {} -> {}",
        before.summary(),
        after.summary()
    );
    ensure!(
        after.send_uuids == before.send_uuids,
        "the send-call uuid multiset must be unchanged across the restart"
    );
    ensure!(
        after.send_details == before.send_details,
        "the durable send ledger must keep the unknown/partial facts unchanged"
    );
    let unknown_after = after
        .send_details
        .iter()
        .find(|row| row.status == "unknown")
        .context("the unknown send row vanished after the restart")?;
    let partial_after = after
        .send_details
        .iter()
        .find(|row| row.status == "partial")
        .context("the partial send row vanished after the restart")?;
    assert_unknown_ledger(unknown_after, &after.send_uuids)?;
    assert_partial_ledger(partial_after, &after.send_uuids)?;
    let bindings = crate::sqlite::thread_bindings(&session.home, &bot_id).await?;
    let dm = bindings
        .iter()
        .filter(|row| row.chat_id == DIRECT_CHAT_ID)
        .collect::<Vec<_>>();
    ensure!(
        dm.len() == 1 && dm[0].thread_id == thread_id,
        "the DM must stay bound to the original Thread {thread_id}"
    );
    ensure_bound_row(dm[0])?;
    wait_inbound_status(session, &bot_id, UNKNOWN_MESSAGE_ID, "needs_attention").await?;
    wait_inbound_status(session, &bot_id, PARTIAL_MESSAGE_ID, "needs_attention").await?;

    let mut result = report::passed(
        CASE,
        format!(
            "automatic formal replies landed as unknown and partial before the restart and neither replayed afterwards: model executions stayed {}, send calls stayed {} with identical uuids, the ledger kept both outcomes, and the DM stayed bound to {thread_id}",
            after.model_executions, after.total_calls
        ),
    );
    result.evidence = evidence.clone();
    result.evidence.push(
        "quiet window covers >=2 sweep periods of the frozen-source 5s recovery scheduler; \
         no public sweep marker exists, so precise claim-takeover races stay uncovered"
            .into(),
    );
    result.evidence.push(format!(
        "third planned segment keeps its initial planned-fact state and its stable uuid stays \
         absent from the peer send-call set ({} uuids observed after the restart)",
        after.send_uuids.len()
    ));
    Ok(result)
}

#[derive(Debug)]
struct RestartBaseline {
    model_executions: usize,
    total_calls: usize,
    unknown_calls: usize,
    partial_calls: usize,
    send_uuids: Vec<String>,
    send_details: Vec<crate::sqlite::SendDetailRow>,
}

impl RestartBaseline {
    fn summary(&self) -> String {
        format!(
            "calls total={} unknown={} partial={}",
            self.total_calls, self.unknown_calls, self.partial_calls
        )
    }
}

async fn restart_baseline(session: &Session, bot_id: &str) -> Result<RestartBaseline> {
    let report = session.control()?.snapshot_report().await;
    let mut unknown_calls = 0usize;
    let mut partial_calls = 0usize;
    let mut send_uuids = Vec::new();
    for call in report
        .calls
        .iter()
        .filter(|call| call.kind == Some(CallKind::MessageSend) && call.accepted)
    {
        let body = call
            .send_body
            .as_ref()
            .map(|body| body.to_string())
            .unwrap_or_default();
        if body.contains(UNKNOWN_MARKER) {
            unknown_calls += 1;
        } else if body.contains(PARTIAL_UNIT) {
            partial_calls += 1;
        }
        if let Some(uuid) = &call.uuid
            && !uuid.is_empty()
        {
            send_uuids.push(uuid.clone());
        }
    }
    send_uuids.sort();
    Ok(RestartBaseline {
        model_executions: session.model_executions(),
        total_calls: unknown_calls + partial_calls,
        unknown_calls,
        partial_calls,
        send_uuids,
        send_details: crate::sqlite::send_details(&session.home, bot_id).await?,
    })
}

fn assert_unknown_ledger(row: &crate::sqlite::SendDetailRow, peer_uuids: &[String]) -> Result<()> {
    let facts = decode_segment_facts(row)?;
    ensure!(
        facts.len() == 1 && facts[0].index == 0 && facts[0].status == "unknown",
        "the unknown reply must keep exactly one planned segment at index 0 in the unknown \
         planned-fact status, got {}",
        facts.len()
    );
    ensure!(
        peer_uuids.contains(&facts[0].uuid),
        "the uncertain segment's stable uuid must appear in the peer send-call set; without it \
         the real HTTP attempt is unproven"
    );
    ensure!(
        row.platform_message_ids.trim().is_empty(),
        "an unknown outcome must not record a platform message id"
    );
    Ok(())
}

fn assert_partial_ledger(row: &crate::sqlite::SendDetailRow, peer_uuids: &[String]) -> Result<()> {
    let facts = decode_segment_facts(row)?;
    ensure!(
        facts.len() == 3,
        "the partial reply must keep its full planned segment set, got {}",
        facts.len()
    );
    for (position, fact) in facts.iter().enumerate() {
        ensure!(
            fact.index == position as u32,
            "planned segments must keep their ledger index (found {} at position {position})",
            fact.index
        );
    }
    ensure!(
        facts[0].status == "succeeded" && facts[0].platform_message_id.is_some(),
        "the first segment must stay succeeded with its platform message id"
    );
    ensure!(
        peer_uuids.contains(&facts[0].uuid),
        "the first segment's stable uuid must appear in the peer send-call set"
    );
    ensure!(
        facts[1].status == "rejected",
        "the second segment must stay rejected"
    );
    ensure!(
        peer_uuids.contains(&facts[1].uuid),
        "the second segment's stable uuid must appear in the peer send-call set"
    );
    // The durable ledger has no "unattempted" status: a planned segment that
    // never ran keeps its initial planned-fact state (unknown, no platform
    // message id). Its never-attempted proof is the stable uuid staying absent
    // from the peer send-call set, not an invented status string.
    ensure!(
        facts[2].status == "unknown" && facts[2].platform_message_id.is_none(),
        "the third planned segment must keep its initial planned-fact state (unknown, no \
         platform message id), got status={} platform_message_id={:?}",
        facts[2].status,
        facts[2].platform_message_id
    );
    ensure!(
        !peer_uuids.contains(&facts[2].uuid),
        "the third segment's stable uuid must stay absent from the peer send-call set; a \
         replay or late attempt would add it"
    );
    let delivered = row
        .platform_message_ids
        .split(',')
        .filter(|value| !value.trim().is_empty())
        .count();
    ensure!(
        delivered == 1,
        "the partial reply must keep exactly one delivered platform message id, got {delivered}"
    );
    Ok(())
}

#[derive(Debug, Deserialize)]
struct SegmentFact {
    index: u32,
    uuid: String,
    status: String,
    platform_message_id: Option<String>,
}

fn decode_segment_facts(row: &crate::sqlite::SendDetailRow) -> Result<Vec<SegmentFact>> {
    serde_json::from_str(&row.segment_facts).with_context(|| {
        format!(
            "durable segment facts for {} failed to decode; refusing to guess the outcome",
            row.operation_id
        )
    })
}

async fn wait_send_status(session: &Session, bot_id: &str, status: &'static str) -> Result<()> {
    http::wait_until(http::PREDICATE_TIMEOUT, || async {
        Ok(crate::sqlite::send_details(&session.home, bot_id)
            .await?
            .iter()
            .any(|row| row.status == status))
    })
    .await
    .with_context(|| format!("no durable send row reached status {status}"))
}

async fn wait_inbound_status(
    session: &Session,
    bot_id: &str,
    message_id: &'static str,
    status: &'static str,
) -> Result<()> {
    http::wait_until(http::PREDICATE_TIMEOUT, || async {
        Ok(crate::sqlite::inbound(&session.home, bot_id)
            .await?
            .iter()
            .any(|row| row.message_id == message_id && row.status == status))
    })
    .await
    .with_context(|| format!("inbound {message_id} did not reach status {status}"))
}

pub(crate) fn send_outcomes_model_steps() -> Vec<Step> {
    vec![
        optional_title_step(0, UNKNOWN_PROMPT),
        Step::prompt(
            Protocol::ResponsesHttp,
            UNKNOWN_PROMPT,
            1,
            Reply::Sse(responses_text(
                UNKNOWN_FINAL,
                "bots-sendout-unknown",
                "fixture-model",
            )),
        ),
        optional_title_step(2, PARTIAL_PROMPT),
        Step::prompt(
            Protocol::ResponsesHttp,
            PARTIAL_PROMPT,
            3,
            Reply::Sse(responses_text(
                &partial_final_text(),
                "bots-sendout-partial",
                "fixture-model",
            )),
        ),
    ]
}

/// A complete Final that needs three send segments under the production
/// 30 KiB segment budget, with a stable unit marker inside every segment and
/// distinct head/tail markers; synthetic payload only, no private text.
fn partial_final_text() -> String {
    let mut text = String::with_capacity(
        PARTIAL_HEAD.len() + PARTIAL_UNIT.len() * PARTIAL_UNIT_REPEATS + PARTIAL_TAIL.len(),
    );
    text.push_str(PARTIAL_HEAD);
    for _ in 0..PARTIAL_UNIT_REPEATS {
        text.push_str(PARTIAL_UNIT);
    }
    text.push_str(PARTIAL_TAIL);
    text
}
