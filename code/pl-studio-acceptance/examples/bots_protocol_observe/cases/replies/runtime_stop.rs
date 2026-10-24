//! `reply-runtime-stop`: a real runtime stop while an automatic reply is live.
//!
//! The stop path here is the product's own shutdown: the acceptance sends SIGINT
//! and waits for the real process exit (`StudioServer::stop`), then relaunches the
//! same binary on the same home. It never uses the public Turn interrupt, which is
//! a different contract (an explicit local cancellation).
//!
//! The oracle is a strict composition of process facts and canonical state:
//!
//! 1. the target Turn is canonically running and its card operation is confirmed,
//!    so nothing is in flight when the signal arrives;
//! 2. exactly one SIGINT reaches the managed server child and the launcher is
//!    observed to exit zero (a non-zero exit, a killed group, or a second signal is
//!    a failed graceful stop, not this case's success);
//! 3. the same home is restarted and the named Turn stays `Cancelled` with exactly
//!    the cause this shutdown path projects (`Unspecified`; see the assertion
//!    note). `Recovery` belongs to the force-exit-then-recover path and must not be
//!    accepted as graceful-stop evidence;
//! 4. the original input stays consumed by that same Turn, and the reply keeps one
//!    card, one platform message, the confirmed preview, no final content, one
//!    terminal inbound row, no extra model attempt, and no interaction hint.
//!
//! The product keeps the durable intent instead of fabricating a finished reply;
//! replaying the consumed input would be a separate defect this case still forbids.

use super::super::Session;
use super::CASE_BUDGET;
use super::card_stream::OperationStatus;
use crate::http;
use crate::report::{self, CaseResult};
use anyhow::{Context, Result, ensure};
use pl_provider_fixture::feishu::{
    CardObservation, CardOperation, ChatType, DIRECT_CHAT_ID, SenderKind, SyntheticEvent,
    TRUSTED_USER_OPEN_ID, text_event,
};
use pl_provider_fixture::{Protocol, ReplyStage, Step, responses_authoritative_final};
use std::sync::OnceLock;

pub(super) const CASE: &str = "reply-runtime-stop";

const MESSAGE_ID: &str = "om_runtime_stop";
const PROMPT: &str = "Bots runtime stop fixture: live card reply";
const PREVIEW: &str = "# 停机样例 CARD_RUNTIME_STOP_HEAD\n\n";
const FINAL: &str = "# 停机样例 CARD_RUNTIME_STOP_HEAD\n\nCARD_RUNTIME_STOP_BODY\n";
const RESTART_SETTLE: std::time::Duration = std::time::Duration::from_secs(14);
/// A stop leaves the work item claimed by the old worker until its lease expires,
/// so the settle window must cover the production inbound lease (60s) plus one
/// recovery sweep.
const SETTLE_BUDGET: std::time::Duration = std::time::Duration::from_secs(120);

/// Gate held after the streamed preview, so the Turn is provably running.
static STOP_STAGE: OnceLock<ReplyStage> = OnceLock::new();

fn stop_stage() -> &'static ReplyStage {
    STOP_STAGE.get_or_init(ReplyStage::new)
}

pub(crate) async fn runtime_stop(session: &mut Session) -> Result<CaseResult> {
    let mut evidence = Vec::new();
    let outcome =
        tokio::time::timeout(CASE_BUDGET, runtime_stop_inner(session, &mut evidence)).await;
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
                "reply-runtime-stop exceeded its absolute observe budget",
            );
            result.evidence = evidence;
            Ok(result)
        }
    }
}

async fn runtime_stop_inner(
    session: &mut Session,
    evidence: &mut Vec<String>,
) -> Result<CaseResult> {
    let (bot_id, _) = session.ensure_trusted_direct().await?;
    session.wait_connected(&bot_id).await?;
    session.control()?.set_card_script(Vec::new()).await;

    let delivery_baseline = session.control()?.snapshot_report().await.calls.len();
    session
        .control()?
        .send_event(inbound(MESSAGE_ID, PROMPT))
        .await?;
    // The reply is live: its gate is reached, the platform already holds a
    // confirmed preview body, and the Turn is still running.
    tokio::time::timeout(http::PREDICATE_TIMEOUT, stop_stage().wait_reached())
        .await
        .context("the stopped reply never streamed its preview")?;
    let preview = wait_preview(session).await?;
    let card_id = preview.card_id.clone();
    let preview_body = preview.content.clone().unwrap_or_default();
    ensure!(
        preview_body == PREVIEW,
        "the confirmed preview must be the streamed head, got {:?}",
        preview_body
    );
    // The durable intent is written before HTTP, so wait until the same operation
    // is confirmed: the stop must happen with no card operation in flight.
    let running = {
        let deadline = std::time::Instant::now() + http::PREDICATE_TIMEOUT;
        loop {
            let stream =
                super::card_stream::card_stream(&session.home, &bot_id, MESSAGE_ID).await?;
            let confirmed = stream
                .state
                .last_operation
                .as_ref()
                .is_some_and(|operation| operation.status == OperationStatus::Confirmed);
            if confirmed {
                break stream;
            }
            if std::time::Instant::now() >= deadline {
                anyhow::bail!(
                    "the live reply never confirmed its card operation, last={:?}",
                    stream
                        .state
                        .last_operation
                        .as_ref()
                        .map(|operation| operation.status)
                );
            }
            tokio::time::sleep(http::POLL).await;
        }
    };
    let confirmed_op = running
        .state
        .last_operation
        .as_ref()
        .context("the live reply must already own a card operation")?;
    ensure!(
        running.state.confirmed_text == preview_body,
        "the durable confirmed body must match the platform preview"
    );
    let thread_id = super::wait_thread_binding(&session.home, &bot_id, DIRECT_CHAT_ID).await?;
    let original_input_id = format!("bot:{bot_id}:{DIRECT_CHAT_ID}:{MESSAGE_ID}");
    let stopped_turn = {
        let inputs = crate::sqlite::thread_inputs(&session.home, &thread_id).await?;
        let input = inputs
            .iter()
            .find(|row| row.id == original_input_id)
            .context("the live reply must own one canonical input")?;
        match &input.state {
            crate::sqlite::ThreadInputState::Consumed { turn_id } => turn_id.clone(),
            other => {
                anyhow::bail!("the live reply's input must already be consumed, got {other:?}")
            }
        }
    };
    let message_id = session
        .control()?
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == card_id)
        .and_then(|entity| entity.sent_message_id)
        .context("the live reply must already have sent its card message")?;
    let messages_before = messages(session).await?;
    let entities_before = entities(session).await?;
    let attempts_before = session.model_attempts();
    // The stop target must still be canonically running, so the later cancellation
    // is attributable to the stop itself instead of to a Turn that had already
    // finished or failed before the signal.
    let running_turn = super::wait_running_turn(session, &thread_id, &stopped_turn).await?;
    evidence.push(format!(
        "before stop: turn={stopped_turn} phase={:?} card={card_id} preview={} bytes last_operation={:?}/{:?} messages={} entities={} attempts={attempts_before}",
        running_turn.phase(),
        preview_body.len(),
        confirmed_op.action.kind,
        confirmed_op.status,
        messages_before,
        entities_before
    ));

    // Real runtime stop: exactly one SIGINT to the managed server child, an observed
    // zero exit, then a relaunch on the same home. `Recovery`, a non-zero exit, or a
    // killed group must not be presented as this case's graceful stop.
    let restart = session.restart_studio_server().await?;
    ensure!(
        restart.stopped_sigints == 1,
        "the graceful stop must deliver exactly one SIGINT to the managed server, got {}",
        restart.stopped_sigints
    );
    ensure!(
        restart.stopped_graceful && restart.stopped_exit_code == Some(0),
        "a graceful SIGINT stop must be observed as a zero launcher exit, got graceful={} exitCode={:?}",
        restart.stopped_graceful,
        restart.stopped_exit_code
    );
    evidence.push(restart.to_string());
    session.wait_connected(&bot_id).await?;
    http::hold_for(RESTART_SETTLE).await;

    // The stop must not fabricate a finished reply, introduce an unknown card
    // operation, duplicate the entity/message it delivered, or replay the consumed
    // input. Every fact below is asserted from canonical product state.
    // The stop must settle the reply as Cancelled; wait bounded so a slow but
    // correct shutdown is not reported as a failure, and a replay stays visible.
    let after = {
        let deadline = std::time::Instant::now() + SETTLE_BUDGET;
        loop {
            let stream =
                super::card_stream::card_stream(&session.home, &bot_id, MESSAGE_ID).await?;
            if stream.state.lifecycle == super::card_stream::Lifecycle::Cancelled {
                break stream;
            }
            if std::time::Instant::now() >= deadline {
                anyhow::bail!(
                    "the stopped reply did not settle as Cancelled within the observe budget: lifecycle={:?} confirmed={} bytes attempts={}->{} inbound={:?}",
                    stream.state.lifecycle,
                    stream.state.confirmed_text.len(),
                    attempts_before,
                    session.model_attempts(),
                    crate::sqlite::inbound(&session.home, &bot_id)
                        .await?
                        .iter()
                        .filter(|row| row.message_id == MESSAGE_ID)
                        .map(|row| row.status.clone())
                        .collect::<Vec<_>>()
                );
            }
            tokio::time::sleep(http::POLL).await;
        }
    };
    ensure!(
        after.state.card_id.as_deref() == Some(card_id.as_str()),
        "the stopped reply must keep its card {card_id}"
    );
    ensure!(
        after.state.platform_message_id.as_deref() == Some(message_id.as_str()),
        "the stopped reply must keep its platform message id, got {:?}",
        after.state.platform_message_id
    );
    ensure!(
        after.state.lifecycle == super::card_stream::Lifecycle::Cancelled,
        "a stopped live reply must settle as Cancelled, got {:?}",
        after.state.lifecycle
    );
    ensure!(
        after.state.confirmed_text == preview_body,
        "the confirmed preview must survive the stop unchanged, got {} bytes",
        after.state.confirmed_text.len()
    );
    ensure!(
        after.state.final_content_hash.is_none(),
        "a stopped reply must not claim a final content hash"
    );
    let close = after
        .state
        .last_operation
        .as_ref()
        .context("the cancelled reply must keep its last card operation")?;
    ensure!(
        close.action.kind == super::card_stream::ActionKind::Settings
            && close.action.streaming == Some(false)
            && close.status == OperationStatus::Confirmed,
        "a stopped reply must end with a confirmed stream close, got {:?}/{:?}/{:?}",
        close.action.kind,
        close.action.streaming,
        close.status
    );
    let entity = card_entity(session, &card_id).await?;
    ensure!(
        entity.streaming_closed && entity.content == preview_body,
        "the platform card must be closed over exactly the confirmed preview"
    );
    ensure!(
        entity.sent_message_id.as_deref() == Some(message_id.as_str()),
        "the platform message identity must not change across the stop"
    );
    ensure!(
        entities(session).await? == entities_before,
        "a runtime stop must not create another card entity"
    );
    let delivery = super::reply_delivery_from(
        session,
        delivery_baseline,
        DIRECT_CHAT_ID,
        &card_id,
        entity.sent_message_id.as_deref(),
    )
    .await?;
    ensure!(
        delivery.unexpected.is_empty(),
        "the stopped reply delivered something unexpected: {:?}",
        delivery.unexpected
    );
    ensure!(
        delivery.formal_messages == 1
            && delivery.formal_message_id.as_deref() == Some(message_id.as_str()),
        "the stopped reply must keep exactly one formal interactive message, got {}",
        delivery.formal_messages
    );
    ensure!(
        delivery.hints == 0,
        "a stopped reply must not send any interaction hint, got {}",
        delivery.hints
    );
    let attempts_after = session.model_attempts();
    ensure!(
        attempts_after == attempts_before,
        "a runtime stop must not replay the consumed input ({attempts_before} -> {attempts_after})"
    );

    // Canonical input/Turn facts: the message owns exactly one input, it stayed
    // consumed by the Turn that was running, and that Turn is now cancelled.
    let inputs = crate::sqlite::thread_inputs(&session.home, &thread_id).await?;
    let mut owned = inputs
        .iter()
        .filter(|row| row.id == original_input_id)
        .peekable();
    let input = owned
        .next()
        .with_context(|| format!("the stopped message must own the input {original_input_id}"))?;
    ensure!(
        owned.next().is_none(),
        "the stopped message must own exactly one canonical input"
    );
    ensure!(
        input.revision != 0
            && input
                .digest
                .as_deref()
                .is_some_and(|digest| !digest.is_empty()),
        "the stopped input's terminal identity must keep its revision and digest"
    );
    ensure!(
        matches!(
            &input.state,
            crate::sqlite::ThreadInputState::Consumed { turn_id } if turn_id == &stopped_turn
        ),
        "the original input must stay consumed by the stopped Turn, got {:?}",
        input.state
    );
    let cancelled = super::wait_cancelled_turn(session, &thread_id, &stopped_turn).await?;
    let cause = cancelled.cause().clone();
    // The graceful SIGINT close is the product's `Cancelled` path, and that path has
    // exactly one projection: design/16-core-contracts.md:373 keeps an explicit
    // interrupt/direct new input on `Interrupted` and a close/cancel token on
    // `Cancelled`, and thread_projection/turns.rs projects a cancelled shutdown as
    // `Unspecified` (only `CoreTurnState::Interrupted` maps to `Interrupted` /
    // `Recovery`). Accepting another cause here would let a force-exit or a
    // different cancellation path pass as this case's graceful stop, so the expected
    // cause is exact rather than a whitelist.
    ensure!(
        cause == pl_protocol::TurnCancellationCause::Unspecified,
        "the graceful SIGINT close must project the stopped Turn as Cancelled/Unspecified, got {cause:?}"
    );

    // The durable inbound fact: exactly one row, terminal, completed.
    let inbound = crate::sqlite::inbound(&session.home, &bot_id).await?;
    let mut rows = inbound
        .iter()
        .filter(|row| row.message_id == MESSAGE_ID)
        .peekable();
    let row = rows
        .next()
        .context("the stopped message must keep one inbound work row")?;
    ensure!(
        rows.next().is_none(),
        "the stopped message must keep exactly one inbound work row"
    );
    ensure!(
        super::inbound_is_terminal(&row.status)?,
        "the stopped message's inbound fact must be terminal, got {:?}",
        row.status
    );
    ensure!(
        row.status == "completed",
        "a closed cancelled card must settle its work item as completed, got {:?}",
        row.status
    );
    evidence.push(format!(
        "after stop: lifecycle={:?} close={:?}/{:?} cause={cause:?} inbound={:?} attempts {attempts_before}->{attempts_after} formal={} hints={} entity_closed={} messages={} entities={}",
        after.state.lifecycle,
        close.action.kind,
        close.status,
        row.status,
        delivery.formal_messages,
        delivery.hints,
        entity.streaming_closed,
        messages(session).await?,
        entities(session).await?
    ));

    let mut result = report::passed(
        CASE,
        format!(
            "a real runtime stop during a live automatic reply kept one card and one formal interactive message with its confirmed preview, settled the Turn as Cancelled{{cause={cause:?}}} with a confirmed stream close and no final hash, settled the single inbound work item as completed, and replayed no consumed input ({attempts_before}->{attempts_after} model attempts)"
        ),
    );
    result.evidence = evidence.clone();
    Ok(result)
}

fn inbound(message_id: &str, prompt: &str) -> SyntheticEvent {
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

/// Accepted cumulative body carrying the preview marker.
async fn wait_preview(session: &Session) -> Result<CardObservation> {
    let deadline = std::time::Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        let observations = session.control()?.card_observations().await;
        if let Some(found) = observations.into_iter().find(|item| {
            item.operation == CardOperation::Update
                && item.accepted
                && item
                    .content
                    .as_deref()
                    .is_some_and(|content| content.contains("CARD_RUNTIME_STOP_HEAD"))
        }) {
            return Ok(found);
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!("the stopped reply never confirmed a preview body");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

async fn card_entity(
    session: &Session,
    card_id: &str,
) -> Result<pl_provider_fixture::feishu::CardEntityReport> {
    session
        .control()?
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == card_id)
        .with_context(|| format!("card entity {card_id} vanished"))
}

/// Distinct delivered platform message identities.
async fn messages(session: &Session) -> Result<usize> {
    let report = session.control()?.snapshot_report().await;
    let ids: std::collections::BTreeSet<&str> = report
        .calls
        .iter()
        .filter(|call| {
            call.kind == Some(pl_provider_fixture::feishu::CallKind::MessageSend) && call.accepted
        })
        .filter_map(|call| call.assigned_message_id.as_deref())
        .filter(|message_id| !message_id.is_empty())
        .collect();
    Ok(ids.len())
}

async fn entities(session: &Session) -> Result<usize> {
    Ok(session.control()?.card_entities().await.len())
}

pub(crate) fn runtime_stop_model_steps() -> Vec<Step> {
    let (before, after) =
        responses_authoritative_final(PREVIEW, FINAL, "bots-runtime-stop", "fixture-model");
    vec![
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT,
            0,
            stop_stage().gated(before, after),
        ),
        super::optional_title_step(1, PROMPT),
        super::optional_title_step(2, PROMPT),
    ]
}
