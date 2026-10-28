//! `conversation-frontend-budget`: the documented display budget on a real
//! public frontend.
//!
//! One first inbound produces two public items whose canonical text exceeds both
//! documented limits. The platform must receive a presentable card per item, in
//! item order, with a separate host truncation notice; the canonical history,
//! the model output and the desktop text stay complete, and the Final item is
//! never suppressed by the preceding truncated item. No transcript file, no
//! automatic re-split and no alternative message shape may replace that.
//!
//! The observer computes both budgets itself (scalars over the received element
//! body, and the peer's own recorded request bytes); no product truncation helper
//! is imported.

use super::super::Session;
use super::super::replies::optional_title_step;
use super::{
    entity_texts, first_inbound, platform_counts, prepare_bot, scalars, wait_accepted_items,
    wait_authorized, wait_card_message_sent, wait_idle, wait_public_items,
};
use anyhow::{Context, Result, ensure};
use pl_protocol::studio::{BotAudienceCanonicalItem, BotPublicTextChannel, BotTextIntegrity};
use pl_provider_fixture::feishu::{CardObservation, CardOperation, DIRECT_CHAT_ID};
use pl_provider_fixture::{Protocol, Reply, Step, responses_public_items_segments};

/// The documented display bounds, restated here as the observer's own oracle.
const DISPLAY_SCALARS: usize = 4_000;
const REQUEST_BYTES: usize = 30_000;

/// The product's documented truncation notice. Copied as an independent text
/// oracle so a silently reworded notice cannot satisfy this case.
const TRUNCATION_HINT: &str =
    "内容已截断，以下不是完整答复或代码；全文保留在 Studio，可要求导出 Markdown 文件";

const PROMPT: &str = "Conversation frontend fixture: over-budget public answer";
const MESSAGE: &str = "om_frontend_budget_inbound";

const COMMENTARY_MARKER: &str = "FRONTEND_BUDGET_COMMENTARY";
const FINAL_MARKER: &str = "FRONTEND_BUDGET_FINAL";

/// A dense-newline sample: every line ends with a real newline, so an available
/// line break always exists right before any display cut.
///
/// Chinese text, an emoji, quotes, a backslash and a fence are included, and the
/// complete text exceeds both documented budgets.
fn dense_lines(marker: &str, count: usize) -> String {
    let mut text = format!("# {marker} 长文样例\n");
    for index in 0..count {
        text.push_str(&format!(
            "第 {index:03} 行：合成中文正文包含「书名号」、\"双引号\"、反斜杠 \\、`inline code` 与表情 🚀🧪，并带有 ```rust let value = {index}; ``` 的围栏片段\n"
        ));
    }
    text.push_str(&format!("{marker}_TAIL\n"));
    text
}

/// A single-line sample: no newline exists anywhere, so only the UTF-8 boundary
/// and the two budgets can be asserted.
fn single_line(marker: &str, chunks: usize) -> String {
    let mut text = format!("{marker} ");
    for index in 0..chunks {
        text.push_str(&format!(
            "合成单行长文{index:03}中文与\"引号\"、反斜杠\\、`code`、🚀🧪以及围栏```rust```片段；"
        ));
    }
    text.push_str("FRONTEND_BUDGET_SINGLE_TAIL");
    text
}

fn commentary_text() -> String {
    // 240 lines: 22,516 Unicode scalars and 41,724 raw UTF-8 bytes, so the
    // stimulus itself is over both documented bounds, not only one of them.
    dense_lines(COMMENTARY_MARKER, 240)
}

fn final_text() -> String {
    // 420 chunks: 20,209 Unicode scalars and 42,889 raw UTF-8 bytes.
    single_line(FINAL_MARKER, 420)
}

pub(super) fn budget_model_steps() -> Vec<Step> {
    let segments = responses_public_items_segments(
        &["FRONTEND_BUDGET_THINKING internal line"],
        &[("frontend-budget-commentary", &commentary_text())],
        &final_text(),
        "",
        &[],
        "frontend-budget",
        "fixture-model",
    );
    vec![
        optional_title_step(0, PROMPT),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT,
            1,
            Reply::Sse(segments.concat()),
        ),
    ]
}

pub(super) async fn budget(session: &mut Session, evidence: &mut Vec<String>) -> Result<String> {
    let (bot_id, _) = prepare_bot(session).await?;
    let before = platform_counts(session).await?;
    let thread_id = first_inbound(session, &bot_id, MESSAGE, PROMPT).await?;
    let authorized = wait_authorized(session, &thread_id).await?;
    let items = wait_public_items(session, &thread_id, 2).await?;
    wait_idle(session, &thread_id).await?;
    ensure!(
        items.len() == 2
            && items[0].channel == BotPublicTextChannel::Commentary
            && items[1].channel == BotPublicTextChannel::Final,
        "the over-budget Turn must publish one commentary and one final item, got {:?}",
        items.iter().map(|item| item.channel).collect::<Vec<_>>()
    );
    let commentary = commentary_text();
    let final_text = final_text();
    // `prefer_newline` marks the sample whose text always has a real line break
    // available before any cut. The single-line sample must not be held to that
    // rule.
    let expected = [(&commentary, true), (&final_text, false)];
    for (item, (full, _)) in items.iter().zip(expected) {
        ensure!(
            item.text == *full,
            "the canonical item text must stay complete (item {} bytes, expected {})",
            item.text.len(),
            full.len()
        );
        ensure!(
            item.total_bytes == full.len() as u64 && item.omitted_bytes == 0,
            "local history must keep the complete text ({} != {} bytes)",
            item.total_bytes,
            full.len()
        );
        ensure!(
            scalars(full) > DISPLAY_SCALARS && full.len() > REQUEST_BYTES,
            "the scenario text must exceed both documented bounds, got {} scalars / {} bytes",
            scalars(full),
            full.len()
        );
    }
    let accepted = wait_accepted_items(
        session,
        &thread_id,
        &authorized,
        &items,
        BotTextIntegrity::Truncated,
    )
    .await?;
    ensure!(
        accepted.iter().all(|status| matches!(
            &status.canonical,
            BotAudienceCanonicalItem::Present {
                saved: true,
                eligibility: pl_protocol::studio::BotItemEligibility::Text { .. },
                ..
            }
        )),
        "both over-budget items must stay saved and eligible text items"
    );

    // ---- Independent platform budget checks --------------------------------
    let observations = session.control()?.card_observations().await;
    let entities = session.control()?.card_entities().await;
    let entities = entities
        .into_iter()
        .skip(before.entities)
        .collect::<Vec<_>>();
    ensure!(
        entities.len() == 2,
        "one card per public item: expected 2 entities, got {}",
        entities.len()
    );
    for (index, (entity, (full, prefer_newline))) in entities.iter().zip(expected).enumerate() {
        // The card must really be one accepted interactive message of the bound
        // direct chat; message type and byte counts alone do not prove delivery.
        let send = wait_card_message_sent(session, &entity.card_id).await?;
        ensure!(
            send.chat_id == DIRECT_CHAT_ID,
            "card entity {index} must be sent to the bound direct chat, got {}",
            send.chat_id
        );
        ensure!(
            entity.entity_json.len() <= REQUEST_BYTES,
            "card entity {index} serialized to {} bytes, above the {REQUEST_BYTES}-byte budget",
            entity.entity_json.len()
        );
        let (texts, _) = entity_texts(&entity.entity_json)?;
        let body = texts
            .iter()
            .filter(|text| !text.is_empty() && full.starts_with(text.as_str()))
            .max_by_key(|text| text.len())
            .with_context(|| {
                format!(
                    "card entity {index} carries no body that is a prefix of its canonical text"
                )
            })?;
        ensure!(
            scalars(body) <= DISPLAY_SCALARS,
            "card entity {index} body holds {} scalars, above {DISPLAY_SCALARS}",
            scalars(body)
        );
        ensure!(
            body.len() < full.len(),
            "the presented body of card entity {index} must be a real truncation"
        );
        // The display cut is a prefix of the canonical text at a real UTF-8
        // boundary. No Markdown repair is required of the product here: a code
        // fence may legitimately be cut open by the display budget, and the
        // notice is a separate host element rather than a body suffix.
        ensure!(
            full.is_char_boundary(body.len()) && full.starts_with(body.as_str()),
            "the presented body of card entity {index} must be a UTF-8-safe prefix of the canonical text"
        );
        // The dense sample always has an available line break before the cut, so
        // the presented body must end on one. This asserts the documented
        // preference without encoding any private search radius of the product.
        if prefer_newline {
            ensure!(
                body.ends_with('\n'),
                "truncation must prefer the available line break instead of cutting mid-line"
            );
        }
        ensure!(
            !body.contains(TRUNCATION_HINT),
            "the host truncation notice must be a separate element, not concatenated into the body"
        );
        let notice = texts
            .iter()
            .filter(|text| text.contains(TRUNCATION_HINT))
            .count();
        ensure!(
            notice == 1,
            "card entity {index} needs exactly one separate host truncation notice, got {notice}"
        );
        ensure!(
            entity
                .sent_message_id
                .as_deref()
                .is_some_and(|id| !id.is_empty()),
            "card entity {index} was never sent as a platform message"
        );
    }
    for observation in &observations {
        ensure!(
            observation.request_bytes <= REQUEST_BYTES,
            "card operation #{ordinal} sent {bytes} bytes, above the {REQUEST_BYTES}-byte request budget",
            ordinal = observation.ordinal,
            bytes = observation.request_bytes
        );
    }
    // ---- Whole-card update: body plus the separate host notice, same entity --
    //
    // The documented shape for "body and the independent host notice change
    // together" is one whole-card update of the same entity, not a static resend
    // after an error. Its document size and its real request bytes are separate
    // facts and both stay inside the budget.
    let whole_ops: Vec<&CardObservation> = observations
        .iter()
        .filter(|op| op.operation == CardOperation::WholeCard && op.accepted && !op.idempotent)
        .collect();
    for (index, (entity, (full, _))) in entities.iter().zip(expected).enumerate() {
        let op = whole_ops
            .iter()
            .find(|op| op.card_id == entity.card_id)
            .with_context(|| {
                format!("card entity {index} has no applied whole-card update for its host notice")
            })?;
        ensure!(
            op.sequence.is_some_and(|sequence| sequence > 0)
                && op.uuid.as_deref().is_some_and(|uuid| !uuid.is_empty()),
            "the whole-card update of card entity {index} needs a positive sequence and a stable uuid"
        );
        ensure!(
            op.card_bytes == Some(entity.entity_bytes),
            "the recorded whole-card document size must equal the stored entity ({} vs {})",
            op.card_bytes.unwrap_or(0),
            entity.entity_bytes
        );
        ensure!(
            op.card_bytes.is_some_and(|bytes| bytes <= REQUEST_BYTES)
                && op.request_bytes <= REQUEST_BYTES,
            "the whole-card update of card entity {index} exceeds the {REQUEST_BYTES}-byte budget ({} entity / {} request)",
            op.card_bytes.unwrap_or(0),
            op.request_bytes
        );
        ensure!(
            entity.whole_card_updates >= 1,
            "card entity {index} must count its accepted whole-card update in the entity report (got {})",
            entity.whole_card_updates
        );
        // The entity counter is the platform-side fact; the operation log is the
        // request-side fact. Only an applied (accepted, non-idempotent) whole-card
        // operation may be counted, so the two sides must agree exactly: a broken
        // counter cannot hide behind the operation records, and uuid replays must
        // inflate neither side.
        let applied_whole = whole_ops
            .iter()
            .filter(|op| op.card_id == entity.card_id)
            .count();
        ensure!(
            entity.whole_card_updates == applied_whole,
            "the whole-card write count of card entity {index} is {}, but {} applied WholeCard operations were recorded",
            entity.whole_card_updates,
            applied_whole
        );
        let (texts, primary) = entity_texts(&entity.entity_json)?;
        let primary =
            primary.with_context(|| format!("card entity {index} has no markdown body element"))?;
        ensure!(
            full.starts_with(&primary) && primary == entity.content,
            "card entity {index} must store the real truncated body, not a fabricated snapshot"
        );
        ensure!(
            texts
                .iter()
                .filter(|text| text.contains(TRUNCATION_HINT))
                .count()
                == 1,
            "card entity {index} must keep exactly one separate host notice after the whole-card update"
        );
    }
    for (index, entity) in entities.iter().enumerate() {
        let mut sequences: Vec<(usize, i64)> = observations
            .iter()
            .filter(|op| op.card_id == entity.card_id && op.accepted)
            .filter_map(|op| op.sequence.map(|sequence| (op.ordinal, sequence)))
            .collect();
        sequences.sort();
        ensure!(
            sequences.windows(2).all(|pair| pair[0].1 < pair[1].1),
            "card entity {index} must share one strictly increasing sequence counter across element content, whole card and settings"
        );
    }
    let counts = platform_counts(session).await?;
    ensure!(
        counts.sends == before.sends + 2,
        "two public items must be two platform messages, got {}",
        counts.sends.saturating_sub(before.sends)
    );
    ensure!(
        counts.uploads == before.uploads,
        "an over-budget text must never be re-sent as a file"
    );
    let sends = super::accepted_sends(session).await?;
    ensure!(
        sends.iter().all(|call| {
            call.msg_type.as_deref() == Some("interactive") && call.request_bytes <= REQUEST_BYTES
        }),
        "every public message must be one interactive card within the request budget"
    );
    evidence.push(format!(
        "budget: commentary {} scalars / {} bytes and final {} scalars / {} bytes stayed complete locally; both cards {}-byte-limited with a separate notice; {} accepted sends, {} uploads",
        scalars(&commentary),
        commentary.len(),
        scalars(&final_text),
        final_text.len(),
        REQUEST_BYTES,
        counts.sends.saturating_sub(before.sends),
        counts.uploads.saturating_sub(before.uploads)
    ));
    Ok(format!(
        "Thread {thread_id}: one over-budget commentary and one over-budget final item stayed complete in canonical history ({} / {} bytes) while each platform card presented at most {DISPLAY_SCALARS} scalars inside {REQUEST_BYTES} request bytes with one separate truncation notice; the final item was delivered after the truncated commentary, with no transcript file, re-split or alternative message shape",
        commentary.len(),
        final_text.len()
    ))
}
