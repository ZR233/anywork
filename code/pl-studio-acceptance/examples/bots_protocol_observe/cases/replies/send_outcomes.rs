//! `reply-send-outcomes-restart`: automatic card replies keep their real
//! outcomes across a same-home restart and are never replayed.
//!
//! Three authorized inbound messages each drive one real model Final through the
//! production runtime:
//!
//! 1. The IM send of the created card entity is applied by the platform and the
//!    response is lost: the reply must stay `unknown` and must not be sent again
//!    (no second entity, no second message identity).
//! 2. The first cumulative body update is explicitly refused with the
//!    documented not-authorized code. That is not recoverable by reopening the
//!    stream, so the reply must stop with a needs-attention outcome and must not
//!    keep accumulating bodies.
//! 3. The first cumulative body update hits the documented stream timeout, which
//!    closes the platform stream. The bounded recovery the design allows is an
//!    official settings reopen; afterwards the reply must continue accumulating
//!    and close successfully with the complete Final.
//!
//! After all three outcomes the server restarts over the same home and peer; no
//! model execution, card operation, send call, or durable send fact may change.

use super::super::Session;
use super::card_stream::{ActionKind, CardStream, Lifecycle, OperationStatus};
use super::{
    CASE_BUDGET, assert_card_uuid_contract, ensure_bound_row, optional_title_step,
    wait_thread_binding,
};
use crate::http;
use crate::report::{self, CaseResult};
use anyhow::{Context, Result, ensure};
use pl_provider_fixture::feishu::{
    CallKind, CardDisposition, CardObservation, CardOperation, ChatType, DIRECT_CHAT_ID,
    SendDisposition, SenderKind, TRUSTED_USER_OPEN_ID, text_event,
};
use pl_provider_fixture::{Protocol, Reply, Step, responses_text};
use std::time::Duration;

pub(super) const CASE: &str = "reply-send-outcomes-restart";

const UNKNOWN_MESSAGE_ID: &str = "om_card_sendout_unknown";
const UNKNOWN_PROMPT: &str = "Bots card send outcome fixture: unknown IM send";
const UNKNOWN_FINAL: &str = "B2U unknown card auto-reply marker.";

const REFUSED_MESSAGE_ID: &str = "om_card_sendout_refused";
const REFUSED_PROMPT: &str = "Bots card send outcome fixture: refused body update";
const REFUSED_FINAL: &str = "B2R refused-update card auto-reply marker.";

const RECOVER_MESSAGE_ID: &str = "om_card_sendout_recover";
const RECOVER_PROMPT: &str = "Bots card send outcome fixture: reopened stream";
const RECOVER_FINAL: &str = "B2C reopened-stream card auto-reply marker.";

/// Recovery observations after the restart. There is no public "sweep ran"
/// marker, so the case holds a bounded quiet window that covers at least two
/// full sweep periods of the frozen-source 5s scheduler and then re-asserts the
/// durable facts; this cannot prove claim-takeover races.
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

    // Outcome 1: the platform applies the interactive card send, then the
    // response is never written.
    session
        .control()?
        .set_send_script(vec![SendDisposition::AcceptThenDrop])
        .await;
    session
        .control()?
        .send_event(inbound(UNKNOWN_MESSAGE_ID, UNKNOWN_PROMPT))
        .await?;
    wait_inbound_status(session, &bot_id, UNKNOWN_MESSAGE_ID, "needs_attention").await?;
    evidence.push("unknown card send landed as needs_attention inbound".into());

    // Outcome 2: an unrecoverable explicit refusal on the first body update.
    session
        .control()?
        .set_send_script(vec![SendDisposition::Succeed])
        .await;
    session
        .control()?
        .set_card_script(vec![
            CardDisposition::Succeed,
            CardDisposition::Reject {
                code: 300_311,
                msg: "no card permission".into(),
            },
        ])
        .await;
    session
        .control()?
        .send_event(inbound(REFUSED_MESSAGE_ID, REFUSED_PROMPT))
        .await?;
    wait_inbound_status(session, &bot_id, REFUSED_MESSAGE_ID, "needs_attention").await?;
    let refused = wait_card_rejection(session, 300_311, CardOperation::Update).await?;
    evidence.push(format!(
        "refused body update observed on the peer: code={} card={} sequence={:?}",
        refused.code, refused.card_id, refused.sequence
    ));

    // Outcome 3: a documented stream timeout closes the platform stream; the
    // product may reopen it through official settings and continue.
    let recover_script = {
        let mut steps = vec![
            CardDisposition::Succeed,
            CardDisposition::Reject {
                code: 200_850,
                msg: "stream update timed out".into(),
            },
        ];
        // Reopen plus the remaining cumulative updates and the close.
        steps.extend(std::iter::repeat_n(CardDisposition::Succeed, 8));
        steps
    };
    session.control()?.set_card_script(recover_script).await;
    session
        .control()?
        .send_event(inbound(RECOVER_MESSAGE_ID, RECOVER_PROMPT))
        .await?;
    let recover_completed =
        wait_inbound_status_result(session, &bot_id, RECOVER_MESSAGE_ID).await?;
    ensure!(
        recover_completed == "completed",
        "the reopened stream must finish as a completed reply, got {recover_completed}"
    );
    let timeout = wait_card_rejection(session, 200_850, CardOperation::Update).await?;
    let observations = session.control()?.card_observations().await;
    let recover_ops: Vec<&CardObservation> = observations
        .iter()
        .filter(|item| item.card_id == timeout.card_id)
        .collect();
    let reopen_index = recover_ops
        .iter()
        .position(|item| item.operation == CardOperation::Reopen && item.accepted)
        .context("the product must reopen the timed-out stream through official settings")?;
    let accepted_after_reopen: Vec<&CardObservation> = recover_ops
        .iter()
        .enumerate()
        .filter(|(index, item)| {
            *index > reopen_index && item.operation == CardOperation::Update && item.accepted
        })
        .map(|(_, item)| *item)
        .collect();
    // Contract facts, not an algorithm count: at least one accepted body after
    // the reopen, the last accepted body is the complete Final, and a bounded
    // action budget keeps a runaway retry loop visible.
    ensure!(
        !accepted_after_reopen.is_empty(),
        "after the reopen the reply must submit at least one accepted body"
    );
    ensure!(
        accepted_after_reopen.len() <= 8,
        "the reopened stream must stay inside a bounded body budget, got {}",
        accepted_after_reopen.len()
    );
    ensure!(
        accepted_after_reopen
            .last()
            .and_then(|item| item.content.as_deref())
            == Some(RECOVER_FINAL),
        "the last accepted body after the reopen must be the complete Final"
    );
    let recover_close = recover_ops
        .iter()
        .find(|item| item.operation == CardOperation::Close && item.accepted)
        .context("the reopened reply must close its stream")?;
    let recover_entity = session
        .control()?
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == timeout.card_id)
        .context("the reopened card entity vanished")?;
    ensure!(
        recover_entity.streaming_closed && recover_entity.content == RECOVER_FINAL,
        "the reopened card must end closed with the complete Final"
    );
    ensure!(
        recover_close.sequence == Some(recover_entity.last_sequence),
        "the accepted close must be the last operation on the same sequence counter"
    );
    evidence.push(format!(
        "reopened stream: timeout code 200850, reopen accepted, {} bodies after reopen, close accepted, entity closed with the exact Final",
        accepted_after_reopen.len()
    ));

    // The refused phase must not have kept accumulating after the refusal.
    let refused_updates = {
        let observations = session.control()?.card_observations().await;
        let refused_index = observations
            .iter()
            .position(|item| item.operation == CardOperation::Update && item.code == 300_311)
            .context("the refused update observation vanished")?;
        observations
            .iter()
            .enumerate()
            .filter(|(index, item)| {
                *index > refused_index
                    && item.card_id == refused.card_id
                    && item.operation == CardOperation::Update
                    && item.accepted
            })
            .count()
    };
    ensure!(
        refused_updates == 0,
        "an unrecoverable refusal must not continue accumulating bodies, got {refused_updates}"
    );
    assert_card_uuid_contract(session, &session.control()?.card_observations().await)?;

    let before = restart_baseline(session, &bot_id).await?;
    ensure!(
        before.model_executions == 3,
        "the three inbound messages must consume exactly three model executions, got {}",
        before.model_executions
    );
    ensure!(
        before.streams.len() == 3,
        "the durable card ledger must hold exactly the three automatic replies, got {}",
        before.streams.len()
    );
    // Outcome 1: the applied-but-unanswered interactive send is a real unknown,
    // never a completion and never a fabricated platform message id.
    let unknown_stream = stream_of(&before.streams, UNKNOWN_MESSAGE_ID)?;
    ensure!(
        unknown_stream.state.lifecycle == Lifecycle::NeedsAttention,
        "an unknown interactive send must end as needsAttention, got {:?}",
        unknown_stream.state.lifecycle
    );
    let unknown_op = unknown_stream
        .state
        .last_operation
        .as_ref()
        .context("the unknown send must keep its last card operation")?;
    ensure!(
        unknown_op.action.kind == ActionKind::Send,
        "the unknown outcome belongs to the interactive send, got {:?}",
        unknown_op.action.kind
    );
    ensure!(
        matches!(
            unknown_op.status,
            OperationStatus::Unknown | OperationStatus::Intent
        ),
        "an unanswered interactive send must stay unknown or intent, got {:?}",
        unknown_op.status
    );
    ensure!(
        unknown_stream.state.platform_message_id.is_none(),
        "an unknown send must not record a platform message id, got {:?}",
        unknown_stream.state.platform_message_id
    );
    ensure!(
        unknown_stream.state.confirmed_sequence == 0
            && unknown_stream.state.final_content_hash.is_none(),
        "an unknown send must not claim a confirmed body or a final hash"
    );
    // Outcome 2: the explicit refusal is typed as a rejected content operation.
    let refused_stream = stream_of(&before.streams, REFUSED_MESSAGE_ID)?;
    ensure!(
        refused_stream.state.lifecycle == Lifecycle::NeedsAttention,
        "an unrecoverable refusal must end as needsAttention, got {:?}",
        refused_stream.state.lifecycle
    );
    let refused_op = refused_stream
        .state
        .last_operation
        .as_ref()
        .context("the refused update must keep its last card operation")?;
    ensure!(
        refused_op.action.kind == ActionKind::Content
            && refused_op.status == OperationStatus::Rejected,
        "the refused body update must be a rejected content operation, got {:?}/{:?}",
        refused_op.action.kind,
        refused_op.status
    );
    ensure!(
        refused_stream
            .state
            .platform_message_id
            .as_deref()
            .is_some_and(|id| !id.is_empty()),
        "the refused update happens after exactly one delivered preview message"
    );
    ensure!(
        refused_stream.state.confirmed_text.is_empty()
            || REFUSED_FINAL.starts_with(&refused_stream.state.confirmed_text),
        "the refused stream must keep a real confirmed prefix, got {:?}",
        refused_stream.state.confirmed_text
    );
    // Outcome 3: the reopened stream is completed with the exact Final.
    let recovered_stream = stream_of(&before.streams, RECOVER_MESSAGE_ID)?;
    ensure!(
        recovered_stream.state.lifecycle == Lifecycle::Completed,
        "a stream reopened through official settings must complete, got {:?}",
        recovered_stream.state.lifecycle
    );
    ensure!(
        recovered_stream.state.confirmed_text == RECOVER_FINAL,
        "the completed stream must keep the exact Final as confirmed text"
    );
    ensure!(
        recovered_stream.state.sequence == recovered_stream.state.confirmed_sequence
            && recovered_stream.state.final_content_hash.is_some(),
        "a completed stream must have no unconfirmed sequence left and must hold its final hash"
    );
    let recovered_op = recovered_stream
        .state
        .last_operation
        .as_ref()
        .context("the reopened reply must keep its last card operation")?;
    ensure!(
        recovered_op.action.kind == ActionKind::Settings
            && recovered_op.action.streaming == Some(false)
            && recovered_op.status == OperationStatus::Confirmed,
        "the reopened reply must end with a confirmed stream close, got {:?}/{:?}/{:?}",
        recovered_op.action.kind,
        recovered_op.action.streaming,
        recovered_op.status
    );
    ensure!(
        recovered_stream.state.recovery_used,
        "the reopened stream must record that it spent its bounded recovery"
    );
    ensure!(
        before.interactive_sends == 3,
        "each automatic reply must attempt exactly one interactive send, got {}",
        before.interactive_sends
    );
    ensure!(
        before.dropped_send_observations == 1,
        "the platform must have applied exactly one unanswered interactive send, got {}",
        before.dropped_send_observations
    );
    ensure!(
        before.creates == 3,
        "each reply must create exactly one card entity, got {}",
        before.creates
    );
    evidence.push(format!(
        "durable card ledger before restart: streams={} unknown=send/{:?} refused=content/{:?} recovered=settings/{:?} creates={} updates={} interactive-sends={}",
        before.streams.len(),
        unknown_op.status,
        refused_op.status,
        recovered_op.status,
        before.creates,
        before.updates,
        before.interactive_sends
    ));

    let thread_id = wait_thread_binding(&session.home, &bot_id, DIRECT_CHAT_ID).await?;

    // Same-home restart over the same peer; wait out at least two recovery
    // sweep periods, then require every durable fact to be unchanged.
    let restart = session.restart_studio_server().await?;
    evidence.push(restart.to_string());
    session.wait_connected(&bot_id).await?;
    http::hold_for(RESTART_QUIET).await;

    let after = restart_baseline(session, &bot_id).await?;
    ensure!(
        after.model_executions == before.model_executions,
        "restart must not re-execute any model Final ({} -> {})",
        before.model_executions,
        after.model_executions
    );
    ensure!(
        after.creates == before.creates,
        "restart must not create another card entity ({} -> {})",
        before.creates,
        after.creates
    );
    ensure!(
        after.updates == before.updates && after.card_operations == before.card_operations,
        "restart must not add any card operation (ops {} -> {}, updates {} -> {})",
        before.card_operations,
        after.card_operations,
        before.updates,
        after.updates
    );
    ensure!(
        after.interactive_sends == before.interactive_sends
            && after.dropped_send_observations == before.dropped_send_observations,
        "restart must not send any reply again (sends {} -> {}, unknown {} -> {})",
        before.interactive_sends,
        after.interactive_sends,
        before.dropped_send_observations,
        after.dropped_send_observations
    );
    ensure!(
        after.send_uuids == before.send_uuids,
        "the send-call uuid multiset must be unchanged across the restart"
    );
    assert_streams_unchanged(&before.streams, &after.streams)?;
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
    wait_inbound_status(session, &bot_id, REFUSED_MESSAGE_ID, "needs_attention").await?;
    ensure!(
        wait_inbound_status_result(session, &bot_id, RECOVER_MESSAGE_ID).await? == "completed",
        "the reopened reply must stay completed after the restart"
    );

    let mut result = report::passed(
        CASE,
        format!(
            "automatic card replies kept real unknown, refused-update and reopened-stream outcomes: model executions stayed {}, card operations stayed {} with {} cumulative updates, interactive sends stayed {}, and nothing replayed across the same-home restart (thread={thread_id})",
            after.model_executions, after.card_operations, after.updates, after.interactive_sends
        ),
    );
    result.evidence = evidence.clone();
    result.evidence.push(
        "quiet window covers >=2 sweep periods of the frozen-source 5s recovery scheduler; \
         no public sweep marker exists, so precise claim-takeover races stay uncovered"
            .into(),
    );
    Ok(result)
}

fn inbound(message_id: &str, prompt: &str) -> pl_provider_fixture::feishu::SyntheticEvent {
    text_event(
        message_id,
        DIRECT_CHAT_ID,
        ChatType::P2p,
        SenderKind::User,
        TRUSTED_USER_OPEN_ID,
        prompt,
        Vec::new(),
    )
}

/// Waits for one specific explicit platform refusal on the peer.
async fn wait_card_rejection(
    session: &Session,
    code: i32,
    operation: CardOperation,
) -> Result<CardObservation> {
    let deadline = std::time::Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        let observations = session.control()?.card_observations().await;
        if let Some(found) = observations
            .into_iter()
            .find(|item| !item.accepted && item.code == code && item.operation == operation)
        {
            return Ok(found);
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!(
                "the peer never answered the expected {operation:?} rejection with code {code}"
            );
        }
        tokio::time::sleep(http::POLL).await;
    }
}

#[derive(Debug)]
struct RestartBaseline {
    model_executions: usize,
    creates: usize,
    updates: usize,
    card_operations: usize,
    interactive_sends: usize,
    dropped_send_observations: usize,
    send_uuids: Vec<String>,
    /// Durable automatic-card facts, sorted by inbound message identity.
    streams: Vec<CardStream>,
}

async fn restart_baseline(session: &Session, bot_id: &str) -> Result<RestartBaseline> {
    let report = session.control()?.snapshot_report().await;
    let creates = report
        .cards
        .iter()
        .filter(|item| item.operation == CardOperation::Create && item.accepted)
        .count();
    let updates = report
        .cards
        .iter()
        .filter(|item| item.operation == CardOperation::Update && item.accepted)
        .count();
    let sends: Vec<_> = report
        .calls
        .iter()
        .filter(|call| call.kind == Some(CallKind::MessageSend) && call.accepted)
        .cloned()
        .collect();
    let interactive_sends = sends
        .iter()
        .filter(|call| call.msg_type.as_deref() == Some("interactive"))
        .count();
    let dropped_send_observations = report
        .cards
        .iter()
        .filter(|item| item.operation == CardOperation::Send && item.response_dropped)
        .count();
    let mut send_uuids = sends
        .iter()
        .filter_map(|call| call.uuid.clone())
        .filter(|uuid| !uuid.is_empty())
        .collect::<Vec<_>>();
    send_uuids.sort();
    let mut streams = super::card_stream::card_streams(&session.home, bot_id).await?;
    streams.sort_by(|left, right| left.message_id.cmp(&right.message_id));
    Ok(RestartBaseline {
        model_executions: session.model_executions(),
        creates,
        updates,
        card_operations: report.cards.len(),
        interactive_sends,
        dropped_send_observations,
        send_uuids,
        streams,
    })
}

/// Finds the durable stream of one inbound message; ambiguity is an error.
fn stream_of<'a>(streams: &'a [CardStream], message_id: &str) -> Result<&'a CardStream> {
    let mut matches = streams
        .iter()
        .filter(|stream| stream.message_id == message_id);
    let found = matches
        .next()
        .with_context(|| format!("no durable card stream for inbound {message_id}"))?;
    ensure!(
        matches.next().is_none(),
        "inbound {message_id} owns more than one durable card stream"
    );
    Ok(found)
}

/// Compares two consecutive baselines of the durable card streams.
///
/// The fencing `version` counter is allowed to move forward (`>=`), because a
/// lease handoff may rewrite the same facts; every reply fact acceptance cares
/// about must be identical, so a retry, a new sequence, a new card, a new uuid,
/// or a lifecycle change across a restart stays visible.
fn assert_streams_unchanged(before: &[CardStream], after: &[CardStream]) -> Result<()> {
    ensure!(
        before.len() == after.len(),
        "the restart changed the number of durable card streams ({} -> {})",
        before.len(),
        after.len()
    );
    for (old, new) in before.iter().zip(after) {
        ensure!(
            old.message_id == new.message_id
                && old.identity == new.identity
                && old.thread_id == new.thread_id
                && old.turn_id == new.turn_id,
            "the restart rebound card stream {} to another identity",
            old.message_id
        );
        ensure!(
            new.version >= old.version,
            "the fencing version of {} went backwards ({} -> {})",
            old.message_id,
            old.version,
            new.version
        );
        ensure!(
            old.state == new.state,
            "the restart rewrote the durable reply facts of {}: {:?} -> {:?}",
            old.message_id,
            old.state,
            new.state
        );
    }
    Ok(())
}

async fn wait_inbound_status(
    session: &Session,
    bot_id: &str,
    message_id: &'static str,
    status: &'static str,
) -> Result<()> {
    let observed = wait_inbound_status_result(session, bot_id, message_id).await?;
    ensure!(
        observed == status,
        "inbound {message_id} reached {observed}, expected {status}"
    );
    Ok(())
}

async fn wait_inbound_status_result(
    session: &Session,
    bot_id: &str,
    message_id: &'static str,
) -> Result<String> {
    let deadline = std::time::Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        let inbound = crate::sqlite::inbound(&session.home, bot_id).await?;
        for row in inbound.iter().filter(|row| row.message_id == message_id) {
            if super::inbound_is_terminal(&row.status)? {
                return Ok(row.status.clone());
            }
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!("inbound {message_id} never reached a terminal status");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

pub(crate) fn send_outcomes_model_steps() -> Vec<Step> {
    vec![
        Step::prompt(
            Protocol::ResponsesHttp,
            UNKNOWN_PROMPT,
            0,
            Reply::Sse(responses_text(
                UNKNOWN_FINAL,
                "bots-card-sendout-unknown",
                "fixture-model",
            )),
        ),
        optional_title_step(1, UNKNOWN_PROMPT),
        Step::prompt(
            Protocol::ResponsesHttp,
            REFUSED_PROMPT,
            2,
            Reply::Sse(responses_text(
                REFUSED_FINAL,
                "bots-card-sendout-refused",
                "fixture-model",
            )),
        ),
        optional_title_step(3, REFUSED_PROMPT),
        Step::prompt(
            Protocol::ResponsesHttp,
            RECOVER_PROMPT,
            4,
            Reply::Sse(responses_text(
                RECOVER_FINAL,
                "bots-card-sendout-recover",
                "fixture-model",
            )),
        ),
        optional_title_step(5, RECOVER_PROMPT),
    ]
}
