//! `reply-continuation-outcomes`: what a local interaction continuation does to
//! the automatic card reply.
//!
//! Both inbounds stream a real preview and then end by asking the operator a
//! question, so the card is provably open (and `Paused`) while the local
//! interaction is pending. The continuation input is then consumed as a *new*
//! Turn, and the two ways that new Turn can end are observed through the public
//! product surface only:
//!
//! 1. The continuation model attempt fails with an explicit non-retryable error:
//!    the same card closes as `Failed`, the durable stream names the new Turn,
//!    and the confirmed preview is kept.
//! 2. The continuation attempt is held with no Final and the operator stops that
//!    exact execution through `POST /api/v1/threads/{thread_id}/stop`. The route is
//!    no longer addressed by Turn id: the request names the execution observed in
//!    the thread snapshot, so a superseded identity fails instead of stopping
//!    whatever runs next.
//!    Design 14 §14.2 / 27 make an explicit local interrupt a *cancellation*: the
//!    targeted Turn ends `Cancelled{Interrupted}`, the already consumed
//!    continuation input is never replayed, and the card closes as `Cancelled` on
//!    the same card and message over the last confirmed preview.
//!
//! A runtime/observer stop (shutdown) is a different path and is deliberately not
//! modelled here: public DELETE must not stand in for it.

use super::super::Session;
use super::card_stream::{ActionKind, Lifecycle, OperationStatus};
use super::{answers_json, optional_title_step, wait_cancelled_turn};
use crate::http;
use crate::report::{self, CaseResult};
use crate::thread_watch::ThreadWatch;
use anyhow::{Context, Result, ensure};
use pl_protocol::studio::ResolveInteractionRequest;
use pl_protocol::{
    InteractionContent, InteractionRequest, InteractionResolution, InteractionStatus,
    UserInputAnswer, UserInputResolution,
};
use pl_provider_fixture::feishu::{
    CardEntityReport, CardObservation, CardOperation, ChatType, DIRECT_CHAT_ID, SenderKind,
    SyntheticEvent, TRUSTED_USER_OPEN_ID, text_event,
};
use pl_provider_fixture::{
    Protocol, RealtimeToolCall, Reply, ReplyStage, Step, responses_authoritative_final,
    responses_text, responses_text_and_tool_calls_staged,
};
use std::collections::HashMap;
use std::sync::OnceLock;

pub(super) const CASE: &str = "reply-continuation-outcomes";
/// Two inbounds, one public interrupt and one same-home restart.
const CASE_BUDGET_SECONDS: u64 = 240;
/// A restart must be quiet for a couple of recovery sweeps before the cancelled
/// facts are re-asserted.
const RESTART_SETTLE: std::time::Duration = std::time::Duration::from_secs(14);

const MESSAGE_FAIL: &str = "om_cont_fail";
const PROMPT_FAIL: &str = "Bots continuation fixture: continuation fails";
const PREVIEW_FAIL: &str = "CARD_CONT_FAIL_PREVIEW 正在准备最终答复，请稍等。";
const QUESTION_FAIL: &str = "contfail";
const ANSWER_FAIL: &str = "continue";

const MESSAGE_CANCEL: &str = "om_cont_cancel";
const PROMPT_CANCEL: &str = "Bots continuation fixture: continuation interrupted";
const PREVIEW_CANCEL: &str = "CARD_CONT_CANCEL_PREVIEW 正在准备最终答复，请稍等。";
const QUESTION_CANCEL: &str = "contcancel";
const ANSWER_CANCEL: &str = "continue";
const CANCEL_FINAL: &str = "CARD_CONT_CANCEL_FINAL 续接完成，这是最终答复。";

/// Gate that holds a preview answer before its tool call, so the card is
/// provably streamed while the attempt is still open.
static FAIL_PREVIEW_STAGE: OnceLock<ReplyStage> = OnceLock::new();
static CANCEL_PREVIEW_STAGE: OnceLock<ReplyStage> = OnceLock::new();
/// Gate that holds the continuation attempt before any final frame.
static CANCEL_STAGE: OnceLock<ReplyStage> = OnceLock::new();

fn fail_preview_stage() -> &'static ReplyStage {
    FAIL_PREVIEW_STAGE.get_or_init(ReplyStage::new)
}

fn cancel_preview_stage() -> &'static ReplyStage {
    CANCEL_PREVIEW_STAGE.get_or_init(ReplyStage::new)
}

fn cancel_stage() -> &'static ReplyStage {
    CANCEL_STAGE.get_or_init(ReplyStage::new)
}

pub(crate) async fn continuation_outcomes(session: &mut Session) -> Result<CaseResult> {
    let mut evidence = Vec::new();
    let budget = std::time::Duration::from_secs(CASE_BUDGET_SECONDS);
    let outcome =
        tokio::time::timeout(budget, continuation_outcomes_inner(session, &mut evidence)).await;
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
                "reply-continuation-outcomes exceeded its absolute observe budget",
            );
            result.evidence = evidence;
            Ok(result)
        }
    }
}

async fn continuation_outcomes_inner(
    session: &mut Session,
    evidence: &mut Vec<String>,
) -> Result<CaseResult> {
    let (bot_id, _) = session.ensure_trusted_direct().await?;
    session.wait_connected(&bot_id).await?;

    // ---- Phase 1: the continuation Turn fails explicitly --------------------
    let fail_baseline = session.control()?.snapshot_report().await.calls.len();
    session
        .control()?
        .send_event(inbound(MESSAGE_FAIL, PROMPT_FAIL))
        .await?;
    let thread_id = super::wait_thread_binding(&session.home, &bot_id, DIRECT_CHAT_ID).await?;
    let mut watch = ThreadWatch::connect(session.http()?.origin(), &thread_id).await?;
    watch.wait_snapshot(http::PREDICATE_TIMEOUT).await?;
    wait_gate(fail_preview_stage(), "failing continuation preview").await?;
    let preview = wait_preview(session, "CARD_CONT_FAIL_PREVIEW").await?;
    fail_preview_stage().release();
    let question = watch
        .wait_interaction(
            http::PREDICATE_TIMEOUT,
            |item| is_question(item, QUESTION_FAIL) && item.status() == InteractionStatus::Pending,
            "the question that starts the failing continuation",
        )
        .await?;
    let first_turn = question.scope.turn_id.clone();
    ensure!(
        !first_turn.is_empty(),
        "the question must name the Turn that consumed the input"
    );
    let fail_card_id = preview.card_id.clone();
    ensure!(
        preview.content.as_deref() == Some(PREVIEW_FAIL),
        "the previewed body must be the streamed answer before the question"
    );
    let paused = wait_card_lifecycle(session, &bot_id, MESSAGE_FAIL, Lifecycle::Paused).await?;
    ensure!(
        paused.state.turn_id.as_deref() == Some(first_turn.as_str()),
        "a consumed input must name the Turn that consumed it, got {:?}",
        paused.state.turn_id
    );
    resolve_question(session, &question, QUESTION_FAIL, ANSWER_FAIL).await?;

    let failed = wait_card_lifecycle(session, &bot_id, MESSAGE_FAIL, Lifecycle::Failed).await?;
    // A closed card is a settled work item: the reply outcome lives on the card
    // (`Failed`), while the inbound fact finishes and is never retried. Let the
    // owner settle it, then require that settling added no model attempt.
    let attempts_before_settle = session.model_attempts();
    http::hold_for(std::time::Duration::from_secs(3)).await;
    let fail_statuses = inbound_statuses(session, &bot_id, MESSAGE_FAIL).await?;
    ensure!(
        session.model_attempts() == attempts_before_settle,
        "a failed continuation must not be re-run by the owner ({} -> {})",
        attempts_before_settle,
        session.model_attempts()
    );
    ensure!(
        fail_statuses.iter().all(|status| status == "completed"),
        "a failed continuation settles its work item while the card keeps Failed, got {fail_statuses:?}"
    );
    let fail_status = fail_statuses.join(",");
    ensure!(
        failed.state.lifecycle == Lifecycle::Failed,
        "a failed continuation must close the card as Failed, got {:?}",
        failed.state.lifecycle
    );
    let failed_turn = failed
        .state
        .turn_id
        .clone()
        .context("the failed continuation must name its Turn")?;
    ensure!(
        failed_turn != first_turn,
        "the continuation input must be consumed by a new Turn, still {first_turn}"
    );
    ensure!(
        failed.state.card_id.as_deref() == Some(fail_card_id.as_str()),
        "the failed continuation must keep the original card {}",
        fail_card_id
    );
    ensure!(
        failed.state.confirmed_text == PREVIEW_FAIL,
        "the failed continuation must keep the last confirmed preview"
    );
    let failed_op = failed
        .state
        .last_operation
        .as_ref()
        .context("the failed continuation must keep its last card operation")?;
    ensure!(
        failed_op.action.kind == ActionKind::Settings
            && failed_op.status == OperationStatus::Confirmed,
        "the failed continuation must end with a confirmed stream close, got {:?}/{:?}",
        failed_op.action.kind,
        failed_op.status
    );
    let failed_entity = card_entity(session, &fail_card_id).await?;
    ensure!(
        failed_entity.streaming_closed && failed_entity.content == PREVIEW_FAIL,
        "the same card must be closed over the confirmed preview"
    );
    // Formal delivery is a typed platform fact: one accepted interactive send that
    // references this card and carries the card entity's own message identity.
    let failed_delivery = super::reply_delivery_from(
        session,
        fail_baseline,
        DIRECT_CHAT_ID,
        &fail_card_id,
        failed_entity.sent_message_id.as_deref(),
    )
    .await?;
    ensure!(
        failed_delivery.unexpected.is_empty(),
        "the failed continuation sent something that is neither its formal reply nor the documented hint: {:?}",
        failed_delivery.unexpected
    );
    ensure!(
        failed_delivery.formal_messages == 1
            && failed_delivery.formal_message_id == failed_entity.sent_message_id,
        "the failed continuation must deliver exactly one formal interactive card message, got {} (id {:?} vs entity {:?})",
        failed_delivery.formal_messages,
        failed_delivery.formal_message_id,
        failed_entity.sent_message_id
    );
    ensure!(
        failed_delivery.hints <= 1,
        "at most the documented local interaction hint may accompany the reply, got {}",
        failed_delivery.hints
    );
    evidence.push(format!(
        "continuation-failed: question turn={first_turn}, preview {} bytes on card {fail_card_id}, continuation turn={failed_turn} closed the same card as Failed, status={fail_status}",
        PREVIEW_FAIL.len()
    ));

    // ---- Phase 2: a public Turn interrupt is a terminal local cancellation --
    //
    // Design 14 §14.2 / 27: an explicit local interrupt is a *cancellation*, not a
    // runtime stop. The already-consumed continuation input must never be replayed,
    // so the card closes as `Cancelled` on the same card and message, the inbound
    // work item settles, and a same-home restart only re-asserts those facts.
    let cancel_baseline = session.control()?.snapshot_report().await.calls.len();
    session
        .control()?
        .send_event(inbound(MESSAGE_CANCEL, PROMPT_CANCEL))
        .await?;
    wait_gate(cancel_preview_stage(), "interrupted continuation preview").await?;
    let cancel_preview = wait_preview(session, "CARD_CONT_CANCEL_PREVIEW").await?;
    cancel_preview_stage().release();
    let cancel_question = watch
        .wait_interaction(
            http::PREDICATE_TIMEOUT,
            |item| {
                is_question(item, QUESTION_CANCEL) && item.status() == InteractionStatus::Pending
            },
            "the question that starts the interrupted continuation",
        )
        .await?;
    let cancel_first_turn = cancel_question.scope.turn_id.clone();
    let cancel_card_id = cancel_preview.card_id.clone();
    wait_card_lifecycle(session, &bot_id, MESSAGE_CANCEL, Lifecycle::Paused).await?;
    let cancel_message_at_pause = card_entity(session, &cancel_card_id).await?.sent_message_id;
    // Fix the delivered set at the exact paused phase: one formal card message for
    // this reply, plus the local hint the interaction sends separately.
    let paused_entity = card_entity(session, &cancel_card_id).await?;
    let paused_delivery = super::reply_delivery_from(
        session,
        cancel_baseline,
        DIRECT_CHAT_ID,
        &cancel_card_id,
        paused_entity.sent_message_id.as_deref(),
    )
    .await?;
    ensure!(
        paused_delivery.unexpected.is_empty(),
        "the paused continuation sent something unexpected: {:?}",
        paused_delivery.unexpected
    );
    ensure!(
        paused_delivery.formal_messages == 1
            && paused_delivery.formal_message_id == paused_entity.sent_message_id,
        "the paused continuation must own exactly one formal interactive card message, got {}",
        paused_delivery.formal_messages
    );
    ensure!(
        paused_delivery.hints <= 1,
        "at most one documented hint may accompany the paused reply, got {}",
        paused_delivery.hints
    );
    resolve_question(session, &cancel_question, QUESTION_CANCEL, ANSWER_CANCEL).await?;

    // The held continuation attempt must really start: its gate is reached, the
    // Turn is a new identity, and it is the canonical continuation of the answer.
    wait_gate(cancel_stage(), "held continuation attempt").await?;
    let continuation_turn = wait_active_turn(session, &thread_id).await?;
    ensure!(
        continuation_turn != cancel_first_turn,
        "the continuation must run as a new Turn, not {cancel_first_turn}"
    );
    // The contract is that a consumed continuation immediately owns the watched
    // identity, even when it is cancelled at once. Wait bounded for that binding so
    // a slow persist is not reported as a wrong identity, then require it.
    let bind_deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    let mut bound_turn = None;
    while std::time::Instant::now() < bind_deadline {
        let stream =
            super::card_stream::card_stream(&session.home, &bot_id, MESSAGE_CANCEL).await?;
        if stream.state.turn_id.as_deref() == Some(continuation_turn.as_str()) {
            bound_turn = Some(stream);
            break;
        }
        tokio::time::sleep(http::POLL).await;
    }
    bound_turn.with_context(|| {
        format!(
            "the consumed continuation {continuation_turn} must own the watched card identity before it is cancelled"
        )
    })?;
    let attempts_before_interrupt = session.model_attempts();
    // The stop names the execution the caller really observed for that Turn; the Turn id itself is
    // never the target identity.
    let execution_id = wait_execution_of_turn(session, &thread_id, &continuation_turn).await?;
    let reply = session
        .http()?
        .stop_thread(&thread_id, &execution_id, "op-bots-cont-stop")
        .await?;
    ensure!(
        reply.stopped && reply.execution_id == execution_id && reply.thread_id == thread_id,
        "the public stop must acknowledge exactly the observed execution {execution_id}"
    );
    ensure!(
        !reply.receipt.effective && reply.receipt.requires_identity_observation,
        "a stop acknowledgement is accepted but not effective; it still needs the identity observation: {:?}",
        reply.receipt
    );
    // The acknowledgement is the owner's, not a locally fabricated success: it names this operation,
    // reports a real disposition and targets the execution resource it accepted.
    ensure!(
        reply.receipt.operation_id == "op-bots-cont-stop"
            && reply.receipt.effect == "immediate"
            && !reply.receipt.durable
            && matches!(reply.receipt.disposition.as_str(), "applied" | "noChange")
            && reply
                .receipt
                .targets
                .iter()
                .any(|target| target["resourceKey"]
                    == serde_json::json!(format!("thread-execution:{thread_id}"))),
        "the stop receipt must describe this operation and its target execution: {:?}",
        reply.receipt
    );

    // Canonical Turn fact: the targeted Turn ends Cancelled with cause Interrupted.
    let cancelled_turn = wait_cancelled_turn(session, &thread_id, &continuation_turn).await?;
    ensure!(
        *cancelled_turn.cause() == pl_protocol::TurnCancellationCause::Interrupted,
        "an explicit local interrupt must be recorded as Interrupted, got {:?}",
        cancelled_turn.cause()
    );

    // Card fact: same card, same message, last confirmed preview kept, no final
    // hash, and a confirmed close — a real terminal cancellation, not a preview
    // left dangling and not a completion.
    let cancelled =
        wait_card_lifecycle(session, &bot_id, MESSAGE_CANCEL, Lifecycle::Cancelled).await?;
    ensure!(
        cancelled.state.card_id.as_deref() == Some(cancel_card_id.as_str()),
        "a cancelled continuation must keep its card {cancel_card_id}"
    );
    ensure!(
        cancelled.state.confirmed_text == PREVIEW_CANCEL,
        "a cancelled continuation must keep the last confirmed preview"
    );
    ensure!(
        cancelled.state.final_content_hash.is_none(),
        "a cancelled continuation must not claim a final content hash"
    );
    let cancelled_op = cancelled
        .state
        .last_operation
        .as_ref()
        .context("the cancelled continuation must keep its last card operation")?;
    ensure!(
        cancelled_op.action.kind == ActionKind::Settings
            && cancelled_op.action.streaming == Some(false)
            && cancelled_op.status == OperationStatus::Confirmed,
        "a cancelled continuation must end with a confirmed stream close, got {:?}/{:?}/{:?}",
        cancelled_op.action.kind,
        cancelled_op.action.streaming,
        cancelled_op.status
    );
    let cancelled_entity = card_entity(session, &cancel_card_id).await?;
    ensure!(
        cancelled_entity.streaming_closed && cancelled_entity.content == PREVIEW_CANCEL,
        "the cancelled card must be closed over its preview"
    );
    ensure!(
        cancelled_entity.sent_message_id == cancel_message_at_pause
            && cancel_message_at_pause.is_some(),
        "the cancelled continuation must keep its one formal message identity"
    );
    let interrupted_delivery = super::reply_delivery_from(
        session,
        cancel_baseline,
        DIRECT_CHAT_ID,
        &cancel_card_id,
        cancelled_entity.sent_message_id.as_deref(),
    )
    .await?;
    ensure!(
        interrupted_delivery.unexpected.is_empty(),
        "the cancelled continuation sent something unexpected: {:?}",
        interrupted_delivery.unexpected
    );
    ensure!(
        interrupted_delivery.formal_messages == 1
            && interrupted_delivery.formal_message_id == paused_delivery.formal_message_id,
        "a cancelled continuation must keep exactly its one formal interactive message, got {} (id {:?} vs {:?})",
        interrupted_delivery.formal_messages,
        interrupted_delivery.formal_message_id,
        paused_delivery.formal_message_id
    );
    // Hints are ordinary posts; only the documented interaction hint may appear and
    // its count must not grow beyond the paused phase.
    ensure!(
        interrupted_delivery.hints <= paused_delivery.hints + 1,
        "at most one additional documented hint may be sent, got {} -> {}",
        paused_delivery.hints,
        interrupted_delivery.hints
    );

    // The work item settles (a closed card is a finished item) and the stopped
    // input is never replayed: no further model attempt, no new card operation.
    wait_inbound_contains(session, &bot_id, MESSAGE_CANCEL, "completed").await?;
    ensure!(
        session.model_attempts() == attempts_before_interrupt,
        "an interrupted continuation must not be replayed ({} -> {})",
        attempts_before_interrupt,
        session.model_attempts()
    );
    let operations_after_interrupt = session.control()?.card_observations().await.len();
    evidence.push(format!(
        "continuation-interrupted: continuation turn={continuation_turn} cancelled as Interrupted, card {cancel_card_id} closed as Cancelled with its preview and one message, inbound settled, attempts={attempts_before_interrupt}"
    ));

    // ---- Same-home restart only re-asserts the cancelled facts --------------
    let restart = session.restart_studio_server().await?;
    evidence.push(restart.to_string());
    session.wait_connected(&bot_id).await?;
    http::hold_for(RESTART_SETTLE).await;
    ensure!(
        session.model_attempts() == attempts_before_interrupt,
        "a restart must not run the interrupted input again ({} -> {})",
        attempts_before_interrupt,
        session.model_attempts()
    );
    ensure!(
        session.control()?.card_observations().await.len() == operations_after_interrupt,
        "a restart must not add any card operation for a cancelled continuation"
    );
    let after_restart =
        super::card_stream::card_stream(&session.home, &bot_id, MESSAGE_CANCEL).await?;
    ensure!(
        after_restart.state == cancelled.state,
        "the restart rewrote the cancelled reply: {:?} -> {:?}",
        cancelled.state,
        after_restart.state
    );
    ensure!(
        card_entity(session, &cancel_card_id).await?.sent_message_id == cancel_message_at_pause,
        "a restart must not send another formal message for a cancelled reply"
    );
    let restart_delivery = super::reply_delivery_from(
        session,
        cancel_baseline,
        DIRECT_CHAT_ID,
        &cancel_card_id,
        cancelled_entity.sent_message_id.as_deref(),
    )
    .await?;
    ensure!(
        restart_delivery.unexpected.is_empty()
            && restart_delivery.formal_messages == 1
            && restart_delivery.formal_message_id == interrupted_delivery.formal_message_id
            && restart_delivery.hints == interrupted_delivery.hints,
        "the restart changed the cancelled reply's delivered set: formal {} -> {} (id {:?} -> {:?}), hints {} -> {}",
        interrupted_delivery.formal_messages,
        restart_delivery.formal_messages,
        interrupted_delivery.formal_message_id,
        restart_delivery.formal_message_id,
        interrupted_delivery.hints,
        restart_delivery.hints
    );
    evidence.push(format!(
        "continuation-cancelled-after-restart: card {cancel_card_id} still Cancelled with turn {continuation_turn}, no model replay, no card operation, one message"
    ));

    let mut result = report::passed(
        CASE,
        "a local interaction continuation ran as a new Turn: its explicit model failure closed the same card as Failed, and a public Turn interrupt on the held continuation ended that Turn as Cancelled{Interrupted}, closed the same card and message as Cancelled over its last confirmed preview with no final hash and no model replay, while a same-home restart only re-asserted those facts",
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

fn is_question(item: &InteractionRequest, question_id: &str) -> bool {
    matches!(&item.content, InteractionContent::UserInput(value)
        if value.questions().iter().any(|question| question.id == question_id))
}

async fn resolve_question(
    session: &Session,
    interaction: &InteractionRequest,
    question_id: &str,
    answer: &str,
) -> Result<()> {
    session
        .http()?
        .resolve_interaction(
            &interaction.interaction_id,
            &ResolveInteractionRequest {
                operation_id: format!("op-bots-cont-{question_id}"),
                // 该机器人会话就是这条交互所属的主会话，宿主身份与版本都来自刚观察到的权威记录。
                host_thread_id: interaction.scope.thread_id.clone(),
                expected_revision: interaction.revision,
                resolution: InteractionResolution::UserInput(UserInputResolution {
                    answers: HashMap::from([(
                        question_id.to_string(),
                        UserInputAnswer {
                            answers: vec![answer.to_string()],
                        },
                    )]),
                }),
            },
        )
        .await
        .with_context(|| format!("resolving {question_id} over public HTTP failed"))
}

/// Waits until the durable card stream reports `expected`.
async fn wait_card_lifecycle(
    session: &Session,
    bot_id: &str,
    message_id: &str,
    expected: Lifecycle,
) -> Result<super::card_stream::CardStream> {
    let deadline = std::time::Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        let stream = super::card_stream::card_stream(&session.home, bot_id, message_id).await?;
        if stream.state.lifecycle == expected {
            return Ok(stream);
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!(
                "card stream {message_id} stayed {:?}, expected {expected:?}",
                stream.state.lifecycle
            );
        }
        tokio::time::sleep(http::POLL).await;
    }
}

/// Waits until one ordered model gate is really reached by the fixture.
async fn wait_gate(stage: &'static ReplyStage, what: &str) -> Result<()> {
    tokio::time::timeout(http::PREDICATE_TIMEOUT, stage.wait_reached())
        .await
        .with_context(|| format!("the {what} gate was never reached"))?;
    Ok(())
}

/// Waits for one accepted cumulative body carrying `marker`.
async fn wait_preview(session: &Session, marker: &str) -> Result<CardObservation> {
    let deadline = std::time::Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        let observations = session.control()?.card_observations().await;
        if let Some(found) = observations.into_iter().find(|item| {
            item.operation == CardOperation::Update
                && item.accepted
                && item
                    .content
                    .as_deref()
                    .is_some_and(|content| content.contains(marker))
        }) {
            return Ok(found);
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!("no accepted card body carried {marker} in time");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

async fn card_entity(session: &Session, card_id: &str) -> Result<CardEntityReport> {
    session
        .control()?
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == card_id)
        .with_context(|| format!("card entity {card_id} vanished"))
}

/// Waits for the active Turn identity of the bound Thread.
/// Waits until the observed Thread publishes the execution of `turn_id`.
///
/// The execution identity is what a precise stop names; a Turn id or `activeTurn` cannot
/// substitute for it.
async fn wait_execution_of_turn(
    session: &Session,
    thread_id: &str,
    turn_id: &str,
) -> Result<String> {
    let deadline = std::time::Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        let snapshot = session.http()?.read_thread(thread_id).await?;
        if let Some(execution) = snapshot
            .runtime
            .as_ref()
            .and_then(|runtime| runtime.execution.as_ref())
            && execution.turn_id() == Some(turn_id)
        {
            return Ok(execution.id().to_owned());
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!("the Thread never published an execution for Turn {turn_id}");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

async fn wait_active_turn(session: &Session, thread_id: &str) -> Result<String> {
    let deadline = std::time::Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        let snapshot = session.http()?.read_thread(thread_id).await?;
        if let Some(turn) = snapshot.active_turn.as_ref()
            && !turn.id.is_empty()
        {
            return Ok(turn.id.clone());
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!("the Thread never reported an active Turn");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

/// Every durable inbound status recorded for one Feishu message identity.
///
/// One message can own more than one work item: the first attempt ends when the
/// Turn requests an interaction, and the continuation is a separate consumption
/// of the same conversation identity. Every status is classified, so an unknown
/// status still fails instead of being ignored.
async fn inbound_statuses(
    session: &Session,
    bot_id: &str,
    message_id: &str,
) -> Result<Vec<String>> {
    let inbound = crate::sqlite::inbound(&session.home, bot_id).await?;
    let mut statuses = Vec::new();
    for row in inbound.iter().filter(|row| row.message_id == message_id) {
        super::inbound_is_terminal(&row.status)?;
        statuses.push(row.status.clone());
    }
    Ok(statuses)
}

/// Waits until one inbound work item of `message_id` reports `expected`.
async fn wait_inbound_contains(
    session: &Session,
    bot_id: &str,
    message_id: &str,
    expected: &str,
) -> Result<()> {
    let deadline = std::time::Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        if inbound_statuses(session, bot_id, message_id)
            .await?
            .iter()
            .any(|status| status == expected)
        {
            return Ok(());
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!("inbound {message_id} never reported {expected}");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

fn question_arguments(question_id: &str) -> String {
    serde_json::json!({
        "questions": [{
            "id": question_id,
            "header": "Continuation",
            "question": "Should the reply continue now?",
            "isOther": false,
            "isSecret": false,
            "options": [{"label": "continue", "description": "Continue the reply."}]
        }]
    })
    .to_string()
}

pub(crate) fn continuation_outcomes_model_steps() -> Vec<Step> {
    let fail_continuation = answers_json(
        &format!("op-bots-cont-{QUESTION_FAIL}"),
        &[(QUESTION_FAIL, ANSWER_FAIL)],
    );
    let cancel_continuation = answers_json(
        &format!("op-bots-cont-{QUESTION_CANCEL}"),
        &[(QUESTION_CANCEL, ANSWER_CANCEL)],
    );
    let (cancel_before, cancel_after) = responses_authoritative_final(
        "",
        CANCEL_FINAL,
        "bots-cont-cancel-attempt",
        "fixture-model",
    );
    let (fail_before, fail_after) = responses_text_and_tool_calls_staged(
        PREVIEW_FAIL,
        "bots-cont-fail-preview",
        "fixture-model",
        &[RealtimeToolCall {
            item_id: "bots-cont-fail-question",
            call_id: "bots-cont-fail-question-call",
            name: "request_user_input",
            arguments: question_arguments(QUESTION_FAIL),
        }],
    );
    let (cancel_preview_before, cancel_preview_after) = responses_text_and_tool_calls_staged(
        PREVIEW_CANCEL,
        "bots-cont-cancel-preview",
        "fixture-model",
        &[RealtimeToolCall {
            item_id: "bots-cont-cancel-question",
            call_id: "bots-cont-cancel-question-call",
            name: "request_user_input",
            arguments: question_arguments(QUESTION_CANCEL),
        }],
    );
    vec![
        optional_title_step(0, PROMPT_FAIL),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_FAIL,
            1,
            fail_preview_stage().gated(fail_before, fail_after),
        ),
        optional_title_step(2, &fail_continuation),
        Step::prompt(
            Protocol::ResponsesHttp,
            fail_continuation,
            3,
            Reply::HttpError {
                status: 401,
                code: "invalid_api_key".into(),
                message: "invalid api key".into(),
            },
        ),
        optional_title_step(4, PROMPT_CANCEL),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_CANCEL,
            5,
            cancel_preview_stage().gated(cancel_preview_before, cancel_preview_after),
        ),
        optional_title_step(6, &cancel_continuation),
        Step::prompt(
            Protocol::ResponsesHttp,
            cancel_continuation.clone(),
            7,
            cancel_stage().gated(cancel_before, cancel_after),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            cancel_continuation,
            8,
            Reply::Sse(responses_text(
                CANCEL_FINAL,
                "bots-cont-cancel-recovered",
                "fixture-model",
            )),
        )
        .optional(),
        optional_title_step(9, CANCEL_FINAL),
    ]
}
