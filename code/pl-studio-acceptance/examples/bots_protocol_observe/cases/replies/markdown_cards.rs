//! `markdown-streaming-cards`: official `post.md` and CardKit streaming cards
//! through the real Studio server, runtime, model fixture and Feishu peer.
//!
//! Five phases in one session-exclusive case, each driven by one authorized
//! inbound platform event and one real model attempt:
//!
//! A. Markdown Final with a real `commentary`-phase message in the same attempt:
//!    the model stream is held by an explicit stage handshake, so a card body
//!    update is observed while the Turn is still open; the final body and the
//!    closed stream must match the canonical Final exactly, while the
//!    commentary channel stays local.
//! B. A Final whose card entity would exceed 30 KB must be refused locally: no
//!    card side effect reaches the platform and the full local history stays.
//! C. A synthetic application without `cardkit:card:write` must surface the
//!    documented permission answer and must not fall back to a plain message.
//! D. An unknown card creation (request applied, response lost) must keep its
//!    real outcome and must not be retried or replaced after a server restart.
//! E. A card that already shows a preview must not grow past the limit: the
//!    platform keeps the last real preview and the reply is not a false success.
//!
//! Nothing here writes product state, calls private bot APIs, or imports
//! production encoding constants. Verdicts come from public HTTP, read-only
//! SQLite facts and the independent peer's ordered platform observations.

use super::super::Session;
use super::card_stream::{ActionKind, Lifecycle, OperationStatus};
use super::{
    CASE_BUDGET, assert_card_uuid_contract, assert_no_hidden_markers, ensure_bound_row,
    optional_title_step, wait_thread_binding,
};
use crate::http;
use crate::report::{self, CaseResult};
use anyhow::{Context, Result, bail, ensure};
use pl_protocol::{
    ThreadContentField, ThreadTextChannel, TimelineDescriptor, TimelineItem, TimelinePage,
};
use pl_provider_fixture::feishu::{
    CallKind, CardDisposition, CardEntityReport, CardObservation, CardOperation, ChatType,
    DIRECT_CHAT_ID, RecordedCall, SenderKind, SyntheticEvent, TRUSTED_USER_OPEN_ID, text_event,
};
use pl_provider_fixture::{
    Protocol, Reply, ReplyStage, Step, responses_authoritative_final,
    responses_reasoning_commentary_text_segments, responses_text,
};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

pub(super) const CASE: &str = "markdown-streaming-cards";
const CASE_BUDGET_SECONDS: u64 = 480;
/// One server restart needs at least two recovery sweeps of the frozen 5s
/// scheduler before durable facts are re-asserted.
const RESTART_QUIET: Duration = Duration::from_secs(14);

// ---------------------------------------------------------------------------
// Synthetic texts and markers. All of them are invented for this observation.
// ---------------------------------------------------------------------------

const PROMPT_STREAM: &str = "Bots card fixture: streamed markdown final";
const PROMPT_OVER_LIMIT: &str = "Bots card fixture: over-limit markdown final";
const PROMPT_NO_SCOPE: &str = "Bots card fixture: missing card scope";
const PROMPT_UNKNOWN_CREATE: &str = "Bots card fixture: unknown card create";
const PROMPT_GROWING: &str = "Bots card fixture: preview grows past the card limit";
const PROMPT_BLANK_FINAL: &str = "Bots card fixture: empty canonical final after a preview";
const PROMPT_UNKNOWN_UPDATE: &str = "Bots card fixture: unknown cumulative update";
const PROMPT_UNKNOWN_CLOSE: &str = "Bots card fixture: unknown stream close";

const MESSAGE_STREAM: &str = "om_card_stream";
const MESSAGE_OVER_LIMIT: &str = "om_card_over_limit";
const MESSAGE_NO_SCOPE: &str = "om_card_no_scope";
const MESSAGE_UNKNOWN_CREATE: &str = "om_card_unknown_create";
const MESSAGE_GROWING: &str = "om_card_growing";
const MESSAGE_BLANK_FINAL: &str = "om_card_blank_final";
const MESSAGE_UNKNOWN_UPDATE: &str = "om_card_unknown_update";
const MESSAGE_UNKNOWN_CLOSE: &str = "om_card_unknown_close";

/// Hidden reasoning lines; none of them may reach the peer.
const REASONING_LINES: [&str; 3] = [
    "CARD_REASONING_ONLY_MARKER internal plan line one",
    "commentary: tool planning stays internal",
    "hidden payload CARD_REASONING_ONLY_MARKER end",
];
const REASONING_MARKER: &str = "CARD_REASONING_ONLY_MARKER";
/// Real `commentary`-phase message text. It must stay local, and the thread must
/// show it in its own channel, so this proves channel filtering rather than
/// filtering of a reasoning string.
const COMMENTARY_TEXT: &str =
    "CARD_COMMENTARY_ONLY_MARKER 这是一段只应出现在本地 commentary 通道的说明。";
const COMMENTARY_MARKER: &str = "CARD_COMMENTARY_ONLY_MARKER";

/// First stage of the normal Final: a strict prefix streamed before the stage
/// handshake blocks the attempt.
const HEAD: &str =
    "# 卡片样例\n\n这是**加粗**、`inline code` 与 [文档链接](https://open.feishu.cn) 的组合。\n\n";
/// Second stage of the normal Final.
const TAIL: &str = "- 第一项\n- 第二项\n\n```rust\nlet stream = true;\n```\n\n| 列 A | 列 B |\n| --- | --- |\n| 1 | 2 |\n\n完成标记：CARD_FINAL_MARKER\n";
const HEAD_MARKER: &str = "卡片样例";
const FINAL_MARKER: &str = "CARD_FINAL_MARKER";

const SHORT_FINAL_NO_SCOPE: &str = "NSCOPE short final that must not be sent as a plain message.";
const SHORT_FINAL_UNKNOWN_CREATE: &str =
    "NUNKNOWN short final that must not become a second card entity.";

/// Phase E: a small preview that must stay the last real platform state.
const GROW_HEAD: &str = "# 增长样例\n\nCARD_GROW_HEAD\n\n";
const GROW_MARKER: &str = "CARD_GROW_HEAD";

/// Phase H: a real preview, then an authoritative final message that is blank.
const BLANK_HEAD: &str = "# 空Final样例\n\nCARD_BLANK_FINAL_HEAD\n\n";
const BLANK_HEAD_MARKER: &str = "CARD_BLANK_FINAL_HEAD";
/// Whitespace only, exactly what the authoritative final message carries.
const BLANK_FINAL_TEXT: &str = "  \n\t ";
/// The product's exact localized summary for "preview kept, no final answer".
const NO_FINAL_SUMMARY: &str = "未生成最终答复，所示内容仅为未完成预览";

/// Phase F: the head is confirmed as a preview, the tail update is applied by
/// the platform and its answer is lost.
const UPDATE_HEAD: &str = "# 更新未知样例\n\nCARD_UNKNOWN_UPDATE_HEAD\n\n";
const UPDATE_TAIL: &str = "- 未知更新第二段 CARD_UNKNOWN_UPDATE_BODY\n";
const UPDATE_HEAD_MARKER: &str = "CARD_UNKNOWN_UPDATE_HEAD";
/// Phase G: the complete Final is confirmed before the stream close is lost.
const CLOSE_HEAD: &str = "# 关闭未知样例\n\nCARD_UNKNOWN_CLOSE_HEAD\n\n";
const CLOSE_TAIL: &str = "- 关闭未知正文 CARD_UNKNOWN_CLOSE_BODY\n";
const CLOSE_MARKER: &str = "CARD_UNKNOWN_CLOSE_BODY";

fn expected_final() -> String {
    format!("{HEAD}{TAIL}")
}

fn commentary_lines() -> [&'static str; 1] {
    [COMMENTARY_TEXT]
}

/// Over-limit Final: repeated synthetic lines whose card entity exceeds 30 KB.
fn over_limit_final() -> String {
    let mut text = String::from("# 超限样例\n\nCARD_OVER_LIMIT_HEAD\n\n");
    for index in 0..900 {
        text.push_str(&format!(
            "- 第 {index:04} 行：这是用于 30KB 边界观察的合成正文，不含任何真实内容。\n"
        ));
    }
    text.push_str("\nCARD_OVER_LIMIT_TAIL\n");
    text
}

/// Phase E Final: a small preview followed by a body that no longer fits.
fn growing_tail() -> String {
    let mut text = String::from("\n");
    for index in 0..700 {
        text.push_str(&format!(
            "- 增长第 {index:04} 行：预览之后继续累积，使整卡超过 30KB 的合成正文。\n"
        ));
    }
    text.push_str("\nCARD_GROW_TAIL\n");
    text
}

// ---------------------------------------------------------------------------
// Model script
// ---------------------------------------------------------------------------

/// Gate 1: after the streamed head (`reached` before any body/terminal event).
static STAGE: OnceLock<ReplyStage> = OnceLock::new();
/// Gate 2: after the complete body but before the item/response completion.
static BODY_STAGE: OnceLock<ReplyStage> = OnceLock::new();
/// Gate 3: after `output_item.done` but before `response.completed`.
static TERMINAL_STAGE: OnceLock<ReplyStage> = OnceLock::new();
static GROW_STAGE: OnceLock<ReplyStage> = OnceLock::new();
/// Gate inside the unknown-update reply, held after the streamed head.
static UPDATE_STAGE: OnceLock<ReplyStage> = OnceLock::new();
/// Gate inside the unknown-close reply, held after the complete body and before
/// the terminal frames.
static CLOSE_STAGE: OnceLock<ReplyStage> = OnceLock::new();
/// Gate inside the blank-final reply, held after the streamed prefix and before
/// the authoritative final message.
static BLANK_STAGE: OnceLock<ReplyStage> = OnceLock::new();

fn stage() -> &'static ReplyStage {
    STAGE.get_or_init(ReplyStage::new)
}

fn body_stage() -> &'static ReplyStage {
    BODY_STAGE.get_or_init(ReplyStage::new)
}

fn terminal_stage() -> &'static ReplyStage {
    TERMINAL_STAGE.get_or_init(ReplyStage::new)
}

fn grow_stage() -> &'static ReplyStage {
    GROW_STAGE.get_or_init(ReplyStage::new)
}

fn update_stage() -> &'static ReplyStage {
    UPDATE_STAGE.get_or_init(ReplyStage::new)
}

fn close_stage() -> &'static ReplyStage {
    CLOSE_STAGE.get_or_init(ReplyStage::new)
}

fn blank_stage() -> &'static ReplyStage {
    BLANK_STAGE.get_or_init(ReplyStage::new)
}

pub(crate) fn model_steps() -> Vec<Step> {
    let commentary = commentary_lines();
    let segments = responses_reasoning_commentary_text_segments(
        &REASONING_LINES,
        &commentary,
        HEAD,
        TAIL,
        "bots-card-stream",
        "fixture-model",
    );
    let grow_segments = responses_reasoning_commentary_text_segments(
        &REASONING_LINES,
        &commentary,
        GROW_HEAD,
        &growing_tail(),
        "bots-card-growing",
        "fixture-model",
    );
    let grow_before = grow_segments[0].clone();
    let mut grow_after = Vec::new();
    for segment in grow_segments.iter().skip(1) {
        grow_after.extend(segment.clone());
    }
    // Unknown update: one gate after the streamed head, so the case can confirm
    // one accepted preview body before arming the unanswered update.
    let update_segments = responses_reasoning_commentary_text_segments(
        &REASONING_LINES,
        &commentary,
        UPDATE_HEAD,
        UPDATE_TAIL,
        "bots-card-unknown-update",
        "fixture-model",
    );
    let update_before = update_segments[0].clone();
    let mut update_after = Vec::new();
    for segment in update_segments.iter().skip(1) {
        update_after.extend(segment.clone());
    }
    // Unknown close: one gate after the complete body and before the terminal
    // frames, so every body is already confirmed when the close is lost.
    let close_segments = responses_reasoning_commentary_text_segments(
        &REASONING_LINES,
        &commentary,
        CLOSE_HEAD,
        CLOSE_TAIL,
        "bots-card-unknown-close",
        "fixture-model",
    );
    let mut close_before = Vec::new();
    for segment in close_segments.iter().take(2) {
        close_before.extend(segment.clone());
    }
    // Every remaining frame, including the terminal `response.completed`, must be
    // served: holding only `output_item.done` would end the stream early and turn
    // this phase into a transport retry instead of a normal Turn completion.
    let mut close_after = Vec::new();
    for segment in close_segments.iter().skip(2) {
        close_after.extend(segment.clone());
    }
    // Blank final: the streamed prefix is a real preview, and the authoritative
    // final message carries whitespace only.
    let (blank_before, blank_after) = responses_authoritative_final(
        BLANK_HEAD,
        BLANK_FINAL_TEXT,
        "bots-card-blank-final",
        "fixture-model",
    );
    vec![
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_STREAM,
            0,
            ReplyStage::staged(segments, &[stage(), body_stage(), terminal_stage()]),
        ),
        optional_title_step(1, PROMPT_STREAM),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_OVER_LIMIT,
            2,
            Reply::Sse(responses_text(
                &over_limit_final(),
                "bots-card-over-limit",
                "fixture-model",
            )),
        ),
        optional_title_step(3, PROMPT_OVER_LIMIT),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_NO_SCOPE,
            4,
            Reply::Sse(responses_text(
                SHORT_FINAL_NO_SCOPE,
                "bots-card-no-scope",
                "fixture-model",
            )),
        ),
        optional_title_step(5, PROMPT_NO_SCOPE),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_UNKNOWN_CREATE,
            6,
            Reply::Sse(responses_text(
                SHORT_FINAL_UNKNOWN_CREATE,
                "bots-card-unknown-create",
                "fixture-model",
            )),
        ),
        optional_title_step(7, PROMPT_UNKNOWN_CREATE),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_GROWING,
            8,
            grow_stage().gated(grow_before, grow_after),
        ),
        optional_title_step(9, PROMPT_GROWING),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_BLANK_FINAL,
            10,
            blank_stage().gated(blank_before, blank_after),
        ),
        optional_title_step(11, PROMPT_BLANK_FINAL),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_UNKNOWN_UPDATE,
            12,
            update_stage().gated(update_before, update_after),
        ),
        optional_title_step(13, PROMPT_UNKNOWN_UPDATE),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_UNKNOWN_CLOSE,
            14,
            close_stage().gated(close_before, close_after),
        ),
        optional_title_step(15, PROMPT_UNKNOWN_CLOSE),
    ]
}

// ---------------------------------------------------------------------------
// Case entry
// ---------------------------------------------------------------------------

pub(crate) async fn markdown_streaming_cards(session: &mut Session) -> Result<CaseResult> {
    let mut evidence = Vec::new();
    let budget = Duration::from_secs(CASE_BUDGET_SECONDS).max(CASE_BUDGET);
    let outcome = tokio::time::timeout(budget, inner(session, &mut evidence)).await;
    match outcome {
        Ok(Ok(result)) => Ok(result),
        Ok(Err(error)) => {
            let mut result = report::failed(CASE, format!("{error:#}"));
            result.evidence = evidence;
            Ok(result)
        }
        Err(_) => {
            let mut result =
                report::failed(CASE, format!("{CASE} exceeded its absolute observe budget"));
            result.evidence = evidence;
            Ok(result)
        }
    }
}

async fn inner(session: &mut Session, evidence: &mut Vec<String>) -> Result<CaseResult> {
    let (bot_id, _) = session.ensure_trusted_direct().await?;
    session.wait_connected(&bot_id).await?;
    let baseline = Baseline::capture(session).await?;
    evidence.push(format!(
        "baseline: entities={} cardOps={} sends={} model={}",
        baseline.entities, baseline.card_operations, baseline.sends, baseline.model
    ));

    // ---- Phase A: streamed Markdown inside one open Turn -------------------
    session
        .control()?
        .send_event(inbound(MESSAGE_STREAM, PROMPT_STREAM))
        .await?;
    wait_stage_reached().await?;
    ensure!(
        session.model_executions() == baseline.model + 1,
        "the stage handshake must happen inside the first model attempt"
    );
    ensure!(
        !stage().is_released(),
        "the reply suffix must still be held while the preview is observed"
    );
    let open_status = inbound_status(session, &bot_id, MESSAGE_STREAM).await?;
    ensure!(
        open_status != "completed",
        "the Turn must still be open when the preview is observed, ledger says {open_status}"
    );
    let preview = wait_preview_observation(session, HEAD_MARKER).await?;
    let preview_content = preview
        .content
        .as_deref()
        .context("the preview observation must carry its submitted content")?;
    let final_text = expected_final();
    ensure!(
        preview_content.len() < final_text.len() && final_text.starts_with(preview_content),
        "the observed preview must be a strict prefix of the canonical Final"
    );
    ensure!(
        preview_content.len() >= 8,
        "the observed preview must carry real streamed Markdown, got {} bytes",
        preview_content.len()
    );
    let opened = session.control()?.card_entities().await;
    let new_entities: Vec<CardEntityReport> = opened.into_iter().skip(baseline.entities).collect();
    ensure!(
        new_entities.len() == 1,
        "the normal phase must own exactly one card entity, got {}",
        new_entities.len()
    );
    let card = new_entities[0].clone();
    ensure!(
        card.sent_message_id.is_some(),
        "the card entity must be sent before body updates"
    );
    // Release only the prefix gate: the body streams, the item/response
    // completion stays withheld, so the platform must not close the card yet.
    stage().release();
    wait_gate(body_stage(), "body stage gate").await?;
    let body_seen = wait_full_body_update(session, &final_text).await?;
    let open_entity = session
        .control()?
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == card.card_id)
        .context("the card entity vanished before the terminal gate")?;
    ensure!(
        !body_stage().is_released(),
        "the accumulated body stage gate must still be held after the prefix"
    );
    ensure!(
        !open_entity.streaming_closed,
        "the card must not be closed before the model terminal events"
    );
    let mid_status = inbound_status(session, &bot_id, MESSAGE_STREAM).await?;
    ensure!(
        mid_status != "completed",
        "the Turn cannot be complete before the model terminal events (status={mid_status})"
    );
    if let Some(body) = &body_seen {
        ensure!(
            body.content.as_deref() == Some(final_text.as_str()),
            "the platform must already hold the complete current body before the terminal events"
        );
        evidence.push(format!(
            "mid-stage: complete body ({} bytes) observed while the model terminal is withheld; card open, inbound={mid_status}",
            final_text.len()
        ));
    } else {
        evidence.push(format!(
            "mid-stage: no complete-body preview was submitted before the terminal; the explicit fact is the withheld model terminal with card open and inbound={mid_status}"
        ));
    }
    // Release the body gate: `output_item.done` now exists, `response.completed`
    // is still withheld. The project's completeness is the Turn terminal, so the
    // target Turn must not be terminal yet.
    body_stage().release();
    wait_gate(terminal_stage(), "terminal stage gate").await?;
    let turn_state = active_turn_state(session, &bot_id).await?;
    ensure!(
        !terminal_stage().is_released(),
        "response.completed must still be withheld while the item is already done"
    );
    ensure!(
        matches!(turn_state, Some(pl_protocol::TurnState::Running(_))),
        "after output_item.done the target Turn must still be running, got {turn_state:?}"
    );
    let item_done_status = inbound_status(session, &bot_id, MESSAGE_STREAM).await?;
    ensure!(
        item_done_status != "completed",
        "the Turn cannot be complete while response.completed is withheld (status={item_done_status})"
    );
    let item_done_entity = session
        .control()?
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == card.card_id)
        .context("the card entity vanished after the item-done stage")?;
    ensure!(
        !item_done_entity.streaming_closed,
        "the card must not close after output_item.done but before response.completed"
    );
    evidence.push(format!(
        "item-done stage: item text done, target Turn running, inbound={item_done_status}, card open, response.completed withheld"
    ));
    // Peer-side ordering fact: no close may exist before the Turn terminal.
    let closes_before_terminal = session
        .control()?
        .card_observations()
        .await
        .iter()
        .filter(|item| item.operation == CardOperation::Close)
        .count();
    ensure!(
        closes_before_terminal == 0,
        "no card close may be submitted before the target Turn terminal, got {closes_before_terminal}"
    );
    terminal_stage().release();
    evidence.push(format!(
        "preview: {} of {} bytes submitted while inbound={open_status}; card={} sent={:?}; terminal released after the open-stage checks",
        preview_content.len(),
        final_text.len(),
        card.card_id,
        card.sent_message_id
    ));

    // ---- Phase A completion ------------------------------------------------
    let completed = wait_card_completed(session, &card.card_id, &final_text).await?;
    let completed_status = wait_inbound_terminal(session, &bot_id, MESSAGE_STREAM).await?;
    ensure!(
        completed_status == "completed",
        "after the model terminal the Turn must complete, got {completed_status}"
    );
    let canonical = canonical_final(session, &bot_id, MESSAGE_STREAM).await?;
    ensure!(
        canonical == final_text,
        "the canonical Final-channel text must be exactly the model's Markdown answer"
    );
    assert_commentary_channel_local(session, &bot_id, MESSAGE_STREAM).await?;
    let cards = session.control()?.card_observations().await;
    let updates: Vec<&CardObservation> = cards
        .iter()
        .filter(|item| item.card_id == card.card_id && item.operation == CardOperation::Update)
        .collect();
    ensure!(
        updates.len() >= 2,
        "the normal phase must submit at least two cumulative body updates, got {}",
        updates.len()
    );
    // Approved cumulative-body oracle: sequence strictly increases, every body
    // is a prefix of the canonical Final, adjacent bodies never shrink (an equal
    // repeat at a higher sequence is a legitimate finalization step), and at
    // least two *distinct* bodies exist. Byte growth per submission is not
    // required.
    let mut previous = 0usize;
    let mut previous_sequence = 0i64;
    let mut distinct: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
    for update in &updates {
        let content = update
            .content
            .as_deref()
            .context("a body update observation must carry its full content")?;
        ensure!(
            content.len() >= previous,
            "a body update must never shrink the cumulative body ({} -> {})",
            previous,
            content.len()
        );
        ensure!(
            final_text.starts_with(content),
            "every body update must be a prefix of the canonical Final"
        );
        let sequence = update.sequence.context("body update needs a sequence")?;
        ensure!(
            sequence > previous_sequence,
            "card operations must use strictly increasing sequences ({previous_sequence} -> {sequence})"
        );
        distinct.insert(content.to_owned());
        previous = content.len();
        previous_sequence = sequence;
    }
    ensure!(
        distinct.len() >= 2,
        "the normal phase needs at least two distinct cumulative bodies, got {}",
        distinct.len()
    );
    // One of them must be a real preview: observed before the body gate was
    // released and strictly shorter than the Final.
    ensure!(
        preview_content.len() < final_text.len()
            && updates.iter().any(|item| item.ordinal == preview.ordinal),
        "the preview body must be a shorter cumulative body observed inside the open Turn"
    );
    ensure!(
        updates.last().and_then(|item| item.content.as_deref()) == Some(final_text.as_str()),
        "the last body update must carry the complete Final"
    );
    let closes: Vec<&CardObservation> = cards
        .iter()
        .filter(|item| item.card_id == card.card_id && item.operation == CardOperation::Close)
        .collect();
    ensure!(
        closes.len() == 1 && closes[0].accepted && closes[0].streaming_mode == Some(false),
        "the card stream must be closed exactly once with streaming_mode=false"
    );
    let close_sequence = closes[0].sequence.context("close needs a sequence")?;
    ensure!(
        close_sequence > previous_sequence,
        "the close must share the card sequence counter ({previous_sequence} -> {close_sequence})"
    );
    ensure!(
        updates.iter().all(|item| item.ordinal < closes[0].ordinal),
        "no body update may follow the close"
    );
    ensure!(
        preview.ordinal < closes[0].ordinal,
        "the preview must precede the close on the same card"
    );
    ensure!(
        completed.streaming_closed && completed.content == final_text,
        "the platform entity must end closed with the complete Final"
    );
    let after_a = Baseline::capture(session).await?;
    ensure!(
        after_a.sends == baseline.sends + 1,
        "the normal phase must send exactly one IM message, got {}",
        after_a.sends.saturating_sub(baseline.sends)
    );
    ensure!(
        after_a.entities == baseline.entities + 1,
        "the normal phase must create exactly one card entity"
    );
    let stream_sends = peer_sends(session, |call| {
        call.card_id.as_deref() == Some(card.card_id.as_str())
    })
    .await?;
    ensure!(
        stream_sends.len() == 1,
        "the card entity must be sent exactly once, got {}",
        stream_sends.len()
    );
    ensure!(
        stream_sends[0].msg_type.as_deref() == Some("interactive"),
        "automatic replies must use an interactive card message"
    );
    assert_no_markdown_post(session, "the normal card phase").await?;
    // Identity contract: every content/settings operation carries its own stable
    // non-empty uuid, so a future retry can be deduplicated by the platform.
    assert_card_uuid_contract(session, &cards)?;
    assert_no_hidden_markers(
        session,
        "the normal card phase",
        &[REASONING_MARKER, COMMENTARY_MARKER],
    )
    .await?;
    evidence.push(format!(
        "normal: {} cumulative body updates, close at seq {close_sequence}, one entity, one send, canonical Final matched ({} bytes incl. {FINAL_MARKER}); commentary channel stayed local",
        updates.len(),
        final_text.len()
    ));

    // ---- Phase B: over-limit entity must be refused locally ---------------
    session
        .control()?
        .send_event(inbound(MESSAGE_OVER_LIMIT, PROMPT_OVER_LIMIT))
        .await?;
    let huge = over_limit_final();
    let over_limit_status = wait_inbound_terminal(session, &bot_id, MESSAGE_OVER_LIMIT).await?;
    ensure!(
        over_limit_status != "completed",
        "an over-limit card must not be reported as a completed reply (status={over_limit_status})"
    );
    let after_b = Baseline::capture(session).await?;
    ensure!(
        after_b.sends == after_a.sends,
        "an over-limit card must not deliver any IM message"
    );
    ensure!(
        after_b.entities == after_a.entities,
        "an over-limit card must not create any entity"
    );
    ensure!(
        after_b.card_operations == after_a.card_operations,
        "root decision: an over-limit card must be refused before the first network side effect \
         (card operations {} -> {})",
        after_a.card_operations,
        after_b.card_operations
    );
    ensure!(
        !inbound_diagnostic(session, &bot_id, MESSAGE_OVER_LIMIT)
            .await?
            .is_empty(),
        "an over-limit card must leave a local diagnostic on the inbound fact"
    );
    let (page, turn_id) = inbound_target_timeline(session, &bot_id, MESSAGE_OVER_LIMIT).await?;
    let huge_canonical = final_total_bytes(&page, &turn_id)?;
    ensure!(
        huge_canonical == huge.len() as u64,
        "the over-limit Final must stay complete in local history ({} != {} bytes)",
        huge_canonical,
        huge.len()
    );
    evidence.push(format!(
        "over-limit: status={over_limit_status}, no card operation/send/entity, local history={} bytes",
        huge.len()
    ));

    // ---- Phase C: missing card scope --------------------------------------
    session.control()?.set_card_scope_allowed(false).await;
    let before_c = Baseline::capture(session).await?;
    session
        .control()?
        .send_event(inbound(MESSAGE_NO_SCOPE, PROMPT_NO_SCOPE))
        .await?;
    let no_scope_status = wait_inbound_terminal(session, &bot_id, MESSAGE_NO_SCOPE).await?;
    ensure!(
        no_scope_status != "completed",
        "a card permission failure must not be reported as a completed reply (status={no_scope_status})"
    );
    let denied = session
        .control()?
        .card_observations()
        .await
        .into_iter()
        .filter(|item| item.code == 300_311)
        .count();
    ensure!(
        denied >= 1,
        "the synthetic application must receive the documented not-authorized answer"
    );
    let after_c = Baseline::capture(session).await?;
    ensure!(
        after_c.sends == before_c.sends,
        "a card permission failure must not be masked by a plain Markdown message"
    );
    assert_no_markdown_post(session, "the missing-scope phase").await?;
    session.control()?.set_card_scope_allowed(true).await;
    evidence.push(format!(
        "missing-scope: status={no_scope_status}, documented 300311 answers={denied}, no fallback send"
    ));

    // ---- Phase D: unknown card creation, then a same-home restart ---------
    session
        .control()?
        .set_card_script(vec![CardDisposition::AcceptThenDrop])
        .await;
    let before_d = Baseline::capture(session).await?;
    session
        .control()?
        .send_event(inbound(MESSAGE_UNKNOWN_CREATE, PROMPT_UNKNOWN_CREATE))
        .await?;
    let unknown: CardObservation = wait_unknown_creation(session).await?;
    let unknown_status = wait_inbound_terminal(session, &bot_id, MESSAGE_UNKNOWN_CREATE).await?;
    ensure!(
        unknown_status != "completed",
        "an unknown card creation must not be reported as completed (status={unknown_status})"
    );
    let after_unknown = Baseline::capture(session).await?;
    ensure!(
        after_unknown.sends == before_d.sends,
        "an unknown card creation must not send any IM message"
    );
    ensure!(
        after_unknown.entities == before_d.entities + 1,
        "the platform must hold exactly the unconfirmed entity once"
    );
    let thread_id = wait_thread_binding(&session.home, &bot_id, DIRECT_CHAT_ID).await?;
    let binding = crate::sqlite::thread_bindings(&session.home, &bot_id)
        .await?
        .into_iter()
        .find(|row| row.chat_id == DIRECT_CHAT_ID)
        .context("DM binding vanished")?;
    ensure_bound_row(&binding)?;

    let restart = session.restart_studio_server().await?;
    evidence.push(restart.to_string());
    session.wait_connected(&bot_id).await?;
    http::hold_for(RESTART_QUIET).await;
    let after_restart = Baseline::capture(session).await?;
    ensure!(
        after_restart.model == after_unknown.model,
        "a restart must not re-execute the unknown Turn ({} -> {})",
        after_unknown.model,
        after_restart.model
    );
    ensure!(
        after_restart.card_operations == after_unknown.card_operations,
        "a restart must not add any card operation ({} -> {})",
        after_unknown.card_operations,
        after_restart.card_operations
    );
    ensure!(
        after_restart.sends == after_unknown.sends,
        "a restart must not send the unconfirmed entity"
    );
    ensure!(
        after_restart.entities == after_unknown.entities,
        "a restart must not create a replacement card entity"
    );
    let status_after = inbound_status(session, &bot_id, MESSAGE_UNKNOWN_CREATE).await?;
    ensure!(
        status_after != "completed",
        "a restart must not turn an unknown card creation into a completed reply"
    );
    let local_final = canonical_total_bytes(session, &bot_id, MESSAGE_UNKNOWN_CREATE).await?;
    ensure!(
        local_final == SHORT_FINAL_UNKNOWN_CREATE.len() as u64,
        "the unknown phase must keep its complete local Final history"
    );
    evidence.push(format!(
        "unknown-create: card={} response_dropped=true, no send, restart kept ops={} sends={} status={status_after} thread={thread_id}",
        unknown.card_id, after_restart.card_operations, after_restart.sends
    ));

    // ---- Phase E: a delivered preview must not grow into a false success --
    let before_e = Baseline::capture(session).await?;
    session
        .control()?
        .send_event(inbound(MESSAGE_GROWING, PROMPT_GROWING))
        .await?;
    tokio::time::timeout(http::PREDICATE_TIMEOUT, grow_stage().wait_reached())
        .await
        .context("the growing reply never streamed its first stage")?;
    let grow_preview = wait_preview_observation(session, GROW_MARKER).await?;
    let grow_card_id = grow_preview.card_id.clone();
    let grow_preview_content = grow_preview
        .content
        .as_deref()
        .context("the growing preview must carry its submitted content")?
        .to_owned();
    grow_stage().release();
    let growing_status = wait_inbound_terminal(session, &bot_id, MESSAGE_GROWING).await?;
    ensure!(
        growing_status != "completed",
        "a preview that cannot be completed must not be reported as a completed reply (status={growing_status})"
    );
    let grow_final = format!("{GROW_HEAD}{}", growing_tail());
    let after_e = Baseline::capture(session).await?;
    ensure!(
        after_e.sends == before_e.sends + 1,
        "the growing phase delivers exactly its preview message, got {}",
        after_e.sends.saturating_sub(before_e.sends)
    );
    let grow_entity = session
        .control()?
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == grow_card_id)
        .context("the growing card entity vanished")?;
    ensure!(
        grow_entity.content == grow_preview_content,
        "the platform must keep exactly the last accepted cumulative body"
    );
    ensure!(
        grow_final.starts_with(&grow_entity.content)
            && grow_entity.content.len() < grow_final.len(),
        "the kept body must be a real prefix of the Final, not a truncated full body"
    );
    // Root decision: the product refuses the over-limit body locally, so this
    // card must show exactly the one preview update and no platform size answer.
    let grow_operations: Vec<CardObservation> = session
        .control()?
        .card_observations()
        .await
        .into_iter()
        .filter(|item| item.card_id == grow_card_id)
        .collect();
    ensure!(
        !grow_operations.iter().any(|item| item.code == 200_860),
        "the product must refuse the over-limit body locally, not by asking the platform"
    );
    ensure!(
        grow_operations
            .iter()
            .filter(|item| item.operation == CardOperation::Update && item.accepted)
            .count()
            == 1,
        "only the observed preview body may be submitted for a growing card"
    );
    ensure!(
        !inbound_diagnostic(session, &bot_id, MESSAGE_GROWING)
            .await?
            .is_empty(),
        "the refused growth must leave a local diagnostic on the inbound fact"
    );
    assert_no_hidden_markers(
        session,
        "the growing card phase",
        &[REASONING_MARKER, COMMENTARY_MARKER],
    )
    .await?;
    let grow_local = canonical_total_bytes(session, &bot_id, MESSAGE_GROWING).await?;
    ensure!(
        grow_local == grow_final.len() as u64,
        "the growing Final must stay complete in local history"
    );
    evidence.push(format!(
        "growing: preview={} of {} bytes kept on card {grow_card_id}, no false success, local history complete",
        grow_entity.content.len(),
        grow_final.len()
    ));

    // ---- Phase H: a real preview, then an empty canonical Final ------------
    //
    // The gate holds the streamed prefix, so the platform provably received a
    // real cumulative body first. Releasing it lets the authoritative final
    // message replace that text with whitespace, which is the only shape that
    // yields an empty canonical Final after a visible preview.
    session.control()?.set_card_script(Vec::new()).await;
    let before_blank = Baseline::capture(session).await?;
    session
        .control()?
        .send_event(inbound(MESSAGE_BLANK_FINAL, PROMPT_BLANK_FINAL))
        .await?;
    wait_gate(blank_stage(), "blank-final stage").await?;
    let blank_preview = wait_preview_observation(session, BLANK_HEAD_MARKER).await?;
    let blank_card_id = blank_preview.card_id.clone();
    let blank_prefix = blank_preview.content.clone().unwrap_or_default();
    ensure!(
        !blank_prefix.trim().is_empty(),
        "the blank-final preview must carry real streamed Markdown"
    );
    ensure!(
        inbound_status(session, &bot_id, MESSAGE_BLANK_FINAL).await? != "completed",
        "the Turn must still be open while the preview is confirmed"
    );
    blank_stage().release();
    let blank_status = wait_inbound_terminal(session, &bot_id, MESSAGE_BLANK_FINAL).await?;
    ensure!(
        blank_status == "needs_attention",
        "an empty canonical Final must end as needs_attention, got {blank_status}"
    );
    let after_blank = Baseline::capture(session).await?;
    ensure!(
        after_blank.entities == before_blank.entities + 1,
        "an empty canonical Final must keep exactly the one card entity it created"
    );
    ensure!(
        after_blank.sends == before_blank.sends + 1,
        "an empty canonical Final must deliver exactly its one preview message"
    );
    let blank_stream =
        super::card_stream::card_stream(&session.home, &bot_id, MESSAGE_BLANK_FINAL).await?;
    ensure!(
        blank_stream.state.lifecycle == Lifecycle::NoFinalReply,
        "an empty canonical Final with a preview must be typed noFinalReply, got {:?}",
        blank_stream.state.lifecycle
    );
    ensure!(
        blank_stream.state.card_id.as_deref() == Some(blank_card_id.as_str()),
        "the blank-final reply must stay on its original card"
    );
    ensure!(
        blank_stream.state.final_content_hash.is_none(),
        "a noFinalReply stream must not claim a final content hash"
    );
    ensure!(
        blank_stream.state.confirmed_text == blank_prefix,
        "the last confirmed preview must stay the confirmed body"
    );
    let blank_entity = session
        .control()?
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == blank_card_id)
        .context("the blank-final card entity vanished")?;
    ensure!(
        blank_entity.streaming_closed && blank_entity.content == blank_prefix,
        "the same card must be closed over the delivered preview, never replaced or truncated"
    );
    let blank_ops: Vec<CardObservation> = session
        .control()?
        .card_observations()
        .await
        .into_iter()
        .filter(|item| item.card_id == blank_card_id)
        .collect();
    let blank_closes: Vec<&CardObservation> = blank_ops
        .iter()
        .filter(|item| item.operation == CardOperation::Close && item.accepted)
        .collect();
    ensure!(
        blank_closes.len() == 1,
        "the blank-final card must be closed exactly once, got {}",
        blank_closes.len()
    );
    ensure!(
        blank_closes[0].summary.as_deref() == Some(NO_FINAL_SUMMARY),
        "the blank-final close must carry the exact localized summary, got {:?}; card operations were {:?}",
        blank_closes[0].summary,
        blank_ops
            .iter()
            .map(|item| (
                item.operation,
                item.accepted,
                item.streaming_mode,
                item.summary.clone(),
            ))
            .collect::<Vec<_>>()
    );
    assert_no_markdown_post(session, "the empty-Final phase").await?;
    assert_canonical_final_blank(session, &bot_id, MESSAGE_BLANK_FINAL).await?;
    evidence.push(format!(
        "blank-final: preview {} bytes confirmed on card {blank_card_id}, canonical Final blank, close summary \"{NO_FINAL_SUMMARY}\", lifecycle=noFinalReply, finalContentHash cleared, status={blank_status}",
        blank_prefix.len()
    ));

    // ---- Phase F: an applied but unanswered cumulative body update ----------
    //
    // The gate holds the reply after its streamed head, so the Turn is provably
    // still open and one cumulative body is already confirmed when the case arms
    // the unanswered operation. The platform then applies the next body update
    // and never answers it: the reply must stop as a real unknown outcome, keep
    // the last confirmed body, and never retry the operation.
    session
        .control()?
        .send_event(inbound(MESSAGE_UNKNOWN_UPDATE, PROMPT_UNKNOWN_UPDATE))
        .await?;
    wait_gate(update_stage(), "unknown-update stage").await?;
    let update_preview = wait_preview_observation(session, UPDATE_HEAD_MARKER).await?;
    let update_card_id = update_preview.card_id.clone();
    let update_preview_content = update_preview.content.clone().unwrap_or_default();
    ensure!(
        update_preview_content.contains(UPDATE_HEAD_MARKER),
        "the confirmed preview must carry the streamed head"
    );
    ensure!(
        !update_stage().is_released(),
        "the unknown-update reply must still be held when the preview is armed"
    );
    session
        .control()?
        .set_card_script(vec![
            CardDisposition::AcceptThenDrop,
            CardDisposition::Succeed,
            CardDisposition::Succeed,
        ])
        .await;
    update_stage().release();
    let update_dropped =
        wait_dropped_operation(session, &update_card_id, CardOperation::Update).await?;
    let update_status = wait_inbound_terminal(session, &bot_id, MESSAGE_UNKNOWN_UPDATE).await?;
    ensure!(
        update_status != "completed",
        "an unanswered body update must not be reported as completed (status={update_status})"
    );
    let update_stream =
        super::card_stream::card_stream(&session.home, &bot_id, MESSAGE_UNKNOWN_UPDATE).await?;
    ensure!(
        update_stream.state.lifecycle == Lifecycle::NeedsAttention,
        "an unanswered body update must end as needsAttention, got {:?}",
        update_stream.state.lifecycle
    );
    ensure!(
        update_stream.state.card_id.as_deref() == Some(update_card_id.as_str()),
        "the unknown update must keep its original card {}",
        update_card_id
    );
    let update_op = update_stream
        .state
        .last_operation
        .as_ref()
        .context("the unknown update must keep its last card operation")?;
    ensure!(
        update_op.action.kind == ActionKind::Content,
        "the unknown outcome belongs to a body update, got {:?}",
        update_op.action.kind
    );
    ensure!(
        matches!(
            update_op.status,
            OperationStatus::Unknown | OperationStatus::Intent
        ),
        "an unanswered body update must stay unknown or intent, got {:?}",
        update_op.status
    );
    ensure!(
        update_dropped.uuid.as_deref() == Some(update_op.uuid.as_str()),
        "the durable intent must keep the exact uuid the platform applied ({:?} vs {:?})",
        update_dropped.uuid,
        update_op.uuid
    );
    ensure!(
        update_dropped.sequence == Some(i64::from(update_op.sequence)),
        "the durable intent must keep the exact sequence the platform applied ({:?} vs {})",
        update_dropped.sequence,
        update_op.sequence
    );
    ensure!(
        update_stream.state.confirmed_text == update_preview_content,
        "an unknown update must not overwrite the last confirmed body"
    );
    let update_entity = session
        .control()?
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == update_card_id)
        .context("the unknown-update card entity vanished")?;
    ensure!(
        update_entity
            .content
            .starts_with(&update_stream.state.confirmed_text)
            && update_entity.content.len() > update_stream.state.confirmed_text.len(),
        "the platform must hold the applied-but-unconfirmed extension on top of the confirmed body"
    );
    ensure!(
        update_dropped.content.as_deref() == Some(update_entity.content.as_str()),
        "the unanswered request must be the body the platform actually applied"
    );
    let update_retries = session
        .control()?
        .card_observations()
        .await
        .into_iter()
        .filter(|item| {
            item.card_id == update_card_id
                && item.operation == CardOperation::Update
                && item.ordinal > update_dropped.ordinal
        })
        .count();
    ensure!(
        update_retries == 0,
        "an unknown body update must not be retried or followed by a new sequence, got {update_retries}"
    );
    evidence.push(format!(
        "unknown-update: card={update_card_id} seq={:?} uuid={:?} answered=false, last confirmed body kept ({} bytes), applied extension {} bytes on the platform, no retry, status={update_status}",
        update_dropped.sequence,
        update_dropped.uuid,
        update_stream.state.confirmed_text.len(),
        update_entity.content.len()
    ));

    // ---- Phase G: an applied but unanswered stream close --------------------
    //
    // Every body is confirmed before the case arms the close, so a lost close
    // answer must stay an explicit unknown instead of becoming a completion.
    session
        .control()?
        .send_event(inbound(MESSAGE_UNKNOWN_CLOSE, PROMPT_UNKNOWN_CLOSE))
        .await?;
    let close_attempts_before = session.model_attempts();
    wait_gate(close_stage(), "unknown-close stage").await?;
    let close_preview = wait_preview_observation(session, CLOSE_MARKER).await?;
    let close_card_id = close_preview.card_id.clone();
    let close_final = format!("{CLOSE_HEAD}{CLOSE_TAIL}");
    ensure!(
        close_preview.content.as_deref() == Some(close_final.as_str()),
        "the complete body must be confirmed before the stream close is armed"
    );
    ensure!(
        !close_stage().is_released(),
        "the unknown-close reply must still be held before its terminal frames"
    );
    ensure!(
        inbound_status(session, &bot_id, MESSAGE_UNKNOWN_CLOSE).await? != "completed",
        "the Turn must still be open while the complete body is confirmed"
    );
    // A completed Turn first confirms one final-content update and only then
    // closes the stream, so the unanswered operation must be armed on the close:
    // the final content is allowed, the settings close is applied without an
    // answer.
    session
        .control()?
        .set_card_script(vec![
            CardDisposition::Succeed,
            CardDisposition::AcceptThenDrop,
            CardDisposition::Succeed,
        ])
        .await;
    close_stage().release();
    let close_dropped =
        wait_dropped_operation(session, &close_card_id, CardOperation::Close).await?;
    let close_status = wait_inbound_terminal(session, &bot_id, MESSAGE_UNKNOWN_CLOSE).await?;
    ensure!(
        close_status != "completed",
        "an unanswered stream close must not be reported as completed (status={close_status})"
    );
    let close_stream =
        super::card_stream::card_stream(&session.home, &bot_id, MESSAGE_UNKNOWN_CLOSE).await?;
    ensure!(
        close_stream.state.lifecycle == Lifecycle::NeedsAttention,
        "an unanswered close must end as needsAttention, got {:?}",
        close_stream.state.lifecycle
    );
    ensure!(
        close_stream.state.card_id.as_deref() == Some(close_card_id.as_str()),
        "the unknown close must keep its original card {}",
        close_card_id
    );
    ensure!(
        close_stream.state.confirmed_text == close_final,
        "the lost close must keep the complete Final as confirmed text"
    );
    let close_op = close_stream
        .state
        .last_operation
        .as_ref()
        .context("the unknown close must keep its last card operation")?;
    ensure!(
        close_op.action.kind == ActionKind::Settings && close_op.action.streaming == Some(false),
        "the unknown outcome belongs to the stream close, got {:?}/{:?}",
        close_op.action.kind,
        close_op.action.streaming
    );
    ensure!(
        matches!(
            close_op.status,
            OperationStatus::Unknown | OperationStatus::Intent
        ),
        "an unanswered close must stay unknown or intent, got {:?}",
        close_op.status
    );
    ensure!(
        close_dropped.uuid.as_deref() == Some(close_op.uuid.as_str()),
        "the durable close intent must keep the exact uuid the platform applied"
    );
    ensure!(
        close_dropped.sequence == Some(i64::from(close_op.sequence)),
        "the durable close intent must keep the exact sequence the platform applied"
    );
    let close_entity = session
        .control()?
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == close_card_id)
        .context("the unknown-close card entity vanished")?;
    ensure!(
        close_entity.streaming_closed && close_entity.content == close_final,
        "the platform really applied the close, so a completed reply would be a false success"
    );
    let close_retries = session
        .control()?
        .card_observations()
        .await
        .into_iter()
        .filter(|item| item.card_id == close_card_id && item.ordinal > close_dropped.ordinal)
        .count();
    ensure!(
        close_retries == 0,
        "an unknown close must not be retried or followed by a new sequence, got {close_retries}"
    );
    ensure!(
        session.model_attempts() == close_attempts_before + 1,
        "an unknown close must not run the model Turn again ({} -> {})",
        close_attempts_before,
        session.model_attempts()
    );
    evidence.push(format!(
        "unknown-close: card={close_card_id} seq={:?} uuid={:?} answered=false while the platform applied the close, complete Final kept ({} bytes), no retry, status={close_status}",
        close_dropped.sequence,
        close_dropped.uuid,
        close_stream.state.confirmed_text.len()
    ));

    // ---- One restart over both unknown outcomes ----------------------------
    let before_restart = Baseline::capture(session).await?;
    let attempts_before_restart = session.model_attempts();
    let update_state_before = update_stream.state.clone();
    let close_state_before = close_stream.state.clone();
    let restart = session.restart_studio_server().await?;
    evidence.push(restart.to_string());
    session.wait_connected(&bot_id).await?;
    http::hold_for(RESTART_QUIET).await;
    let after_restart = Baseline::capture(session).await?;
    ensure!(
        after_restart.model == before_restart.model,
        "a restart must not re-execute the unknown Turns ({} -> {})",
        before_restart.model,
        after_restart.model
    );
    ensure!(
        session.model_attempts() == attempts_before_restart,
        "a restart must not attempt the model again for an unknown reply ({} -> {})",
        attempts_before_restart,
        session.model_attempts()
    );
    ensure!(
        after_restart.card_operations == before_restart.card_operations,
        "a restart must not add or replay any card operation ({} -> {})",
        before_restart.card_operations,
        after_restart.card_operations
    );
    ensure!(
        after_restart.sends == before_restart.sends,
        "a restart must not send any unknown reply again ({} -> {})",
        before_restart.sends,
        after_restart.sends
    );
    ensure!(
        after_restart.entities == before_restart.entities,
        "a restart must not create a replacement card entity"
    );
    let update_state_after =
        super::card_stream::card_stream(&session.home, &bot_id, MESSAGE_UNKNOWN_UPDATE).await?;
    ensure!(
        update_state_after.state == update_state_before,
        "the restart rewrote the unknown body update: {:?} -> {:?}",
        update_state_before,
        update_state_after.state
    );
    let close_state_after =
        super::card_stream::card_stream(&session.home, &bot_id, MESSAGE_UNKNOWN_CLOSE).await?;
    ensure!(
        close_state_after.state == close_state_before,
        "the restart rewrote the unknown close: {:?} -> {:?}",
        close_state_before,
        close_state_after.state
    );
    ensure!(
        inbound_status(session, &bot_id, MESSAGE_UNKNOWN_UPDATE).await? == update_status
            && inbound_status(session, &bot_id, MESSAGE_UNKNOWN_CLOSE).await? == close_status,
        "the restart must not change the unknown reply outcomes"
    );
    ensure!(
        canonical_total_bytes(session, &bot_id, MESSAGE_UNKNOWN_CLOSE).await?
            == close_final.len() as u64,
        "both unknown outcomes must keep their complete local Final history"
    );
    let restart_evidence = format!(
        "unknown restart: model={} ops={} sends={} entities={} unchanged, both durable states unchanged",
        after_restart.model,
        after_restart.card_operations,
        after_restart.sends,
        after_restart.entities
    );
    evidence.push(restart_evidence);

    // Oracle self-check: a visible payload outside the selected markdown element
    // (a card header and a second element) must make the hidden-marker audit
    // fail. Without this the audit could silently pass while a real leak stayed
    // in a field nobody looked at.
    assert_non_selected_payload_is_audited(session, evidence).await?;

    let mut result = report::passed(
        CASE,
        "one JSON 2.0 card entity was created once, sent once, updated cumulatively while the Turn was open and closed with the exact canonical Final while the commentary channel stayed local; over-limit, missing scope, unknown creation, preview growth, a blank canonical Final (same card, noFinalReply, exact summary, hash cleared), an unanswered body update and an unanswered stream close stayed explicit outcomes with their original identities across a same-home restart, without plain-message fallback, replay, new sequence or truncation",
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

struct Baseline {
    entities: usize,
    card_operations: usize,
    sends: usize,
    model: usize,
}

impl Baseline {
    async fn capture(session: &Session) -> Result<Self> {
        let report = session.control()?.snapshot_report().await;
        Ok(Self {
            entities: report.card_entities.len(),
            card_operations: report.cards.len(),
            sends: {
                // Distinct platform messages: an idempotent retry is not a send.
                let ids: std::collections::BTreeSet<&str> = report
                    .calls
                    .iter()
                    .filter(|call| {
                        call.kind == Some(CallKind::MessageSend)
                            && call.accepted
                            && !call.deduplicated
                    })
                    .filter_map(|call| call.assigned_message_id.as_deref())
                    .filter(|message_id| !message_id.is_empty())
                    .collect();
                ids.len()
            },
            model: session.model_executions(),
        })
    }
}

/// Bounded predicate polling with the shared observe cadence.
async fn poll_until<T, F, Fut>(mut probe: F, what: &str) -> Result<T>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<Option<T>>>,
{
    let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
    loop {
        if let Some(value) = probe().await? {
            return Ok(value);
        }
        if Instant::now() >= deadline {
            bail!("{what} did not happen within the observe predicate budget");
        }
        tokio::time::sleep(http::POLL).await;
    }
}

/// Waits until one ordered gate is actually reached by the fixture.
async fn wait_gate(stage: &'static ReplyStage, what: &str) -> Result<()> {
    tokio::time::timeout(http::PREDICATE_TIMEOUT, stage.wait_reached())
        .await
        .with_context(|| format!("the {what} was never reached by the fixture"))?;
    Ok(())
}

async fn wait_stage_reached() -> Result<()> {
    tokio::time::timeout(http::PREDICATE_TIMEOUT, stage().wait_reached())
        .await
        .context("the model fixture never streamed the first Markdown stage")?;
    Ok(())
}

/// Waits for one accepted cumulative card body update carrying `marker`.
async fn wait_preview_observation(session: &Session, marker: &str) -> Result<CardObservation> {
    poll_until(
        || async {
            let observations = session.control()?.card_observations().await;
            Ok(observations.into_iter().find(|item| {
                item.operation == CardOperation::Update
                    && item.accepted
                    && item
                        .content
                        .as_deref()
                        .is_some_and(|content| content.contains(marker))
            }))
        },
        "a card body update while the Turn is open",
    )
    .await
}

/// State of the target Turn as the public snapshot reports it.
async fn active_turn_state(
    session: &Session,
    bot_id: &str,
) -> Result<Option<pl_protocol::TurnState>> {
    let thread_id = wait_thread_binding(&session.home, bot_id, DIRECT_CHAT_ID).await?;
    let snapshot = session.http()?.read_thread(&thread_id).await?;
    Ok(snapshot.active_turn.map(|turn| turn.state))
}

/// Waits bounded until an accepted cumulative body equals `expected`.
///
/// Returns `None` when the product legitimately never pushes the complete body
/// before the terminal; the caller then relies on the explicit withheld-terminal
/// facts instead of inventing a second verdict.
async fn wait_full_body_update(
    session: &Session,
    expected: &str,
) -> Result<Option<CardObservation>> {
    // Bounded probe: this is an "either" oracle, not a required state.
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        let observations = session.control()?.card_observations().await;
        if let Some(found) = observations.into_iter().find(|item| {
            item.operation == CardOperation::Update
                && item.accepted
                && item.content.as_deref() == Some(expected)
        }) {
            return Ok(Some(found));
        }
        if Instant::now() >= deadline {
            return Ok(None);
        }
        tokio::time::sleep(http::POLL).await;
    }
}

async fn wait_card_completed(
    session: &Session,
    card_id: &str,
    expected: &str,
) -> Result<CardEntityReport> {
    poll_until(
        || async {
            let entities = session.control()?.card_entities().await;
            Ok(entities.into_iter().find(|entity| {
                entity.card_id == card_id && entity.streaming_closed && entity.content == expected
            }))
        },
        "the closed card entity holding the exact Final",
    )
    .await
}

async fn inbound_status(session: &Session, bot_id: &str, message_id: &str) -> Result<String> {
    let inbound = crate::sqlite::inbound(&session.home, bot_id).await?;
    Ok(inbound
        .iter()
        .find(|row| row.message_id == message_id)
        .map_or_else(|| "absent".to_owned(), |row| row.status.clone()))
}

async fn inbound_diagnostic(session: &Session, bot_id: &str, message_id: &str) -> Result<String> {
    let inbound = crate::sqlite::inbound(&session.home, bot_id).await?;
    Ok(inbound
        .iter()
        .find(|row| row.message_id == message_id)
        .map_or_else(String::new, |row| row.diagnostic.clone()))
}

async fn wait_inbound_terminal(
    session: &Session,
    bot_id: &str,
    message_id: &str,
) -> Result<String> {
    poll_until(
        || async {
            let inbound = crate::sqlite::inbound(&session.home, bot_id).await?;
            for row in inbound.iter().filter(|row| row.message_id == message_id) {
                if super::inbound_is_terminal(&row.status)? {
                    return Ok(Some(row.status.clone()));
                }
            }
            Ok(None)
        },
        "a terminal inbound status",
    )
    .await
}

async fn wait_unknown_creation(session: &Session) -> Result<CardObservation> {
    poll_until(
        || async {
            let observations = session.control()?.card_observations().await;
            Ok(observations
                .into_iter()
                .find(|item| item.operation == CardOperation::Create && item.response_dropped))
        },
        "the unconfirmed card creation",
    )
    .await
}

/// Waits for one applied card operation whose HTTP answer was never written.
async fn wait_dropped_operation(
    session: &Session,
    card_id: &str,
    operation: CardOperation,
) -> Result<CardObservation> {
    poll_until(
        || async {
            let observations = session.control()?.card_observations().await;
            Ok(observations.into_iter().find(|item| {
                item.card_id == card_id && item.operation == operation && item.response_dropped
            }))
        },
        "an applied card operation whose answer was never written",
    )
    .await
}

async fn peer_sends(
    session: &Session,
    predicate: impl Fn(&RecordedCall) -> bool,
) -> Result<Vec<RecordedCall>> {
    let report = session.control()?.snapshot_report().await;
    Ok(report
        .calls
        .into_iter()
        .filter(|call| {
            call.kind == Some(CallKind::MessageSend)
                && call.accepted
                && !call.deduplicated
                && call
                    .assigned_message_id
                    .as_deref()
                    .is_some_and(|message_id| !message_id.is_empty())
        })
        .filter(|call| predicate(call))
        .collect())
}

async fn assert_no_markdown_post(session: &Session, phase: &str) -> Result<()> {
    let report = session.control()?.snapshot_report().await;
    let posts = report
        .calls
        .iter()
        .filter(|call| call.kind == Some(CallKind::MessageSend) && call.accepted)
        .filter(|call| call.msg_type.as_deref() == Some("post"))
        .count();
    ensure!(
        posts == 0,
        "{phase} must not send an ordinary post message; automatic replies use one card entity"
    );
    Ok(())
}

/// Proves the audit actually covers card headers and non-selected elements.
async fn assert_non_selected_payload_is_audited(
    session: &Session,
    evidence: &mut Vec<String>,
) -> Result<()> {
    const PROBE_MARKER: &str = "PROBE_HEADER_ONLY_MARKER";
    let peer = session
        .peer
        .as_ref()
        .context("the Feishu peer is not running")?;
    let origin = peer.origin().to_owned();
    let client = reqwest::Client::builder()
        .no_proxy()
        .timeout(Duration::from_secs(10))
        .build()
        .context("probe client")?;
    let entity = serde_json::json!({
        "schema": "2.0",
        "config": { "streaming_mode": true, "update_multi": true },
        "header": { "title": { "tag": "plain_text", "content": PROBE_MARKER } },
        "body": { "elements": [
            { "tag": "markdown", "element_id": "selected", "content": "clean body" },
            { "tag": "markdown", "element_id": "second", "content": format!("{PROBE_MARKER} 第二个元素") }
        ]}
    })
    .to_string();
    let answer: serde_json::Value = client
        .post(format!("{origin}/open-apis/cardkit/v1/cards"))
        .bearer_auth(pl_provider_fixture::feishu::TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "type": "card_json", "data": entity }))
        .send()
        .await
        .context("probe create request")?
        .json()
        .await
        .context("probe create answer")?;
    ensure!(
        answer["code"] == 0,
        "the probe card must be created so the audit has a real payload"
    );
    let audit = assert_no_hidden_markers(session, "the probe card", &[PROBE_MARKER]).await;
    ensure!(
        audit.is_err(),
        "the hidden-marker audit must fail when a header or a non-selected element carries the marker"
    );
    evidence.push(
        "oracle self-check: marker in a card header and in a second element made the audit fail"
            .into(),
    );
    Ok(())
}

/// Resolve an inbound to its durable card-bound Turn, not the thread's newest Turn.
async fn target_timeline(
    session: &Session,
    bot_id: &str,
    message_id: &str,
) -> Result<(TimelinePage, String)> {
    let thread_id = wait_thread_binding(&session.home, bot_id, DIRECT_CHAT_ID).await?;
    let stream = super::card_stream::card_stream(&session.home, bot_id, message_id).await?;
    ensure!(
        stream.thread_id == thread_id
            && stream.state.binding.thread_id == thread_id
            && stream.state.binding.chat_id == DIRECT_CHAT_ID
            && stream.state.binding.message_id == message_id,
        "card stream for {message_id} does not match the inbound thread binding"
    );
    let turn_id = stream
        .turn_id
        .context("card stream has no consumed Turn identity")?;
    ensure!(
        stream.state.turn_id.as_deref() == Some(turn_id.as_str()),
        "card stream Turn identity disagrees with its durable state"
    );
    let page = session.http()?.read_timeline(&thread_id, 100).await?;
    Ok((page, turn_id))
}

/// The over-limit case can fail before a card stream exists, so resolve its
/// original inbound input directly, without falling back from a stream lookup.
async fn inbound_target_timeline(
    session: &Session,
    bot_id: &str,
    message_id: &str,
) -> Result<(TimelinePage, String)> {
    let thread_id = wait_thread_binding(&session.home, bot_id, DIRECT_CHAT_ID).await?;
    let page = session.http()?.read_timeline(&thread_id, 100).await?;
    ensure!(
        !page.has_older,
        "cannot uniquely resolve inbound {message_id} on a truncated timeline page"
    );
    let input_id = format!("bot:{bot_id}:{DIRECT_CHAT_ID}:{message_id}");
    let mut turns = page.items.iter().filter(|item| {
        matches!(&item.descriptor,
        TimelineDescriptor::Turn(turn) if turn.input_id() == Some(input_id.as_str()))
    });
    let turn = turns
        .next()
        .context("inbound input has no Turn in the timeline")?;
    ensure!(
        turns.next().is_none(),
        "inbound input has multiple Turns in the timeline"
    );
    ensure!(
        turn.header.thread_id == thread_id && !turn.header.turn_id.is_empty(),
        "inbound Turn has an invalid thread or empty Turn identity"
    );
    let turn_id = turn.header.turn_id.clone();
    Ok((page, turn_id))
}

fn text_field(item: &TimelineItem) -> Result<&pl_protocol::TimelineFieldPreview> {
    item.fields
        .iter()
        .find(|field| field.field == ThreadContentField::Text)
        .context("the text item must expose a text content field")
}

/// Reads the newest canonical Final for the inbound Turn (complete preview required).
async fn canonical_final(session: &Session, bot_id: &str, message_id: &str) -> Result<String> {
    let (page, turn_id) = target_timeline(session, bot_id, message_id).await?;
    let item = final_item(&page, &turn_id)?;
    let field = text_field(item)?;
    ensure!(
        field.preview_bytes() == field.total_bytes,
        "the small canonical Final must be a complete preview, preview={} total={}",
        field.preview_bytes(),
        field.total_bytes
    );
    Ok(field.text.clone())
}

/// Every canonical Final of the target Turn is empty or whitespace only.
///
/// Both shapes are legal for "the Turn produced no answer": the timeline may
/// keep a Final item whose text is blank, or may hold no Final item at all. The
/// check fails when any non-blank Final text survived, which is what a leaked
/// preview or a truncated finalization would leave behind.
async fn assert_canonical_final_blank(
    session: &Session,
    bot_id: &str,
    message_id: &str,
) -> Result<()> {
    let (page, turn_id) = target_timeline(session, bot_id, message_id).await?;
    ensure!(
        !page.has_older,
        "cannot prove blank Final on a truncated timeline page for Turn {turn_id}"
    );
    for item in page
        .items
        .iter()
        .filter(|item| is_channel(item, &turn_id, ThreadTextChannel::Final))
    {
        let field = text_field(item)?;
        ensure!(
            field.preview_bytes() == field.total_bytes,
            "blank Final preview is incomplete for Turn {turn_id}"
        );
        ensure!(
            field.text.trim().is_empty(),
            "the canonical Final must be blank, got {} bytes of visible text",
            field.text.len()
        );
    }
    Ok(())
}

/// The real commentary-phase text exists in the thread, in its own channel.
async fn assert_commentary_channel_local(
    session: &Session,
    bot_id: &str,
    message_id: &str,
) -> Result<()> {
    let (page, turn_id) = target_timeline(session, bot_id, message_id).await?;
    let item = unique_channel_item(&page, &turn_id, ThreadTextChannel::Commentary)?;
    let field = text_field(item)?;
    ensure!(
        field.preview_bytes() == field.total_bytes,
        "commentary preview is incomplete for Turn {turn_id}"
    );
    ensure!(
        field.text == COMMENTARY_TEXT,
        "the model really produced a commentary-phase message, so the absence of its marker on the \
         peer proves channel filtering"
    );
    Ok(())
}

/// Reads the exact UTF-8 size of the newest Final content field.
async fn canonical_total_bytes(session: &Session, bot_id: &str, message_id: &str) -> Result<u64> {
    let (page, turn_id) = target_timeline(session, bot_id, message_id).await?;
    final_total_bytes(&page, &turn_id)
}

fn final_total_bytes(page: &TimelinePage, turn_id: &str) -> Result<u64> {
    let item = final_item(page, turn_id)?;
    let detail = item
        .details()
        .find(|detail| detail.field == ThreadContentField::Text)
        .context("the Final item must expose a text content field")?;
    Ok(detail.total_bytes)
}

fn is_channel(item: &TimelineItem, turn_id: &str, channel: ThreadTextChannel) -> bool {
    item.header.turn_id == turn_id
        && matches!(&item.descriptor, TimelineDescriptor::Text(text) if text.channel == channel)
}

fn final_item<'a>(page: &'a TimelinePage, turn_id: &str) -> Result<&'a TimelineItem> {
    unique_channel_item(page, turn_id, ThreadTextChannel::Final)
}

fn unique_channel_item<'a>(
    page: &'a TimelinePage,
    turn_id: &str,
    channel: ThreadTextChannel,
) -> Result<&'a TimelineItem> {
    ensure!(
        !page.has_older,
        "cannot prove unique {channel:?} for Turn {turn_id} on a truncated timeline page"
    );
    let mut items = page
        .items
        .iter()
        .filter(|item| is_channel(item, turn_id, channel));
    let item = items
        .next()
        .with_context(|| format!("target Turn {turn_id} has no {channel:?} text item"))?;
    ensure!(
        items.next().is_none(),
        "target Turn {turn_id} has multiple {channel:?} text items"
    );
    Ok(item)
}
