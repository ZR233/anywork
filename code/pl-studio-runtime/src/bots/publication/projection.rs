//! Bounded exact-revision reads and serializer-proven display limits, never a Turn transcript.

use super::{attention, unavailable};
use crate::bots::protocol::cardkit;
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::card::CardLifecycle;
use crate::bots::storage::publication::{DELIVERY_TEXT_CHARS, DeliveryText};
use crate::studio::{TimelineContentReader, TimelineFieldLength, TimelineItemMetadata};
use pl_protocol::studio::{BotPublicTextChannel, BotTextIntegrity};
use pl_protocol::{ThreadContentField, TimelineDetailQuery};

pub(super) const TRUNCATED: &str =
    "内容已截断，以下不是完整答复或代码；全文保留在 Studio，可要求导出 Markdown 文件";
const EMPTY_BODY: &str = "此项当前没有正文。";
const PREFIX_BYTES: usize = (DELIVERY_TEXT_CHARS + 1) * 4;

pub(super) struct Projection {
    pub body: String,
    pub integrity: BotTextIntegrity,
    pub request_bytes: u64,
}

pub(super) async fn read(
    reader: &TimelineContentReader,
    metadata: &TimelineItemMetadata,
) -> Result<Projection, FeishuError> {
    let total = text_length(&metadata.fields)
        .ok_or_else(|| unavailable("canonical public text length is not ready"))?;
    let mut body = String::new();
    let mut continuation = None;
    while (body.len() as u64) < total && body.chars().count() <= DELIVERY_TEXT_CHARS {
        let remaining = PREFIX_BYTES.saturating_sub(body.len());
        if remaining < 4 {
            break;
        }
        let chunk = reader
            .read_detail(
                &metadata.shell.id,
                &TimelineDetailQuery {
                    field: ThreadContentField::Text,
                    revision: metadata.shell.revision,
                    continuation: continuation.clone(),
                    max_bytes: Some(remaining.min(4096) as u32),
                },
            )
            .await
            .map_err(|e| super::content_error("read public text revision prefix", e))?;
        if chunk.thread_id != metadata.shell.thread_id
            || chunk.item_id != metadata.shell.id
            || chunk.revision != metadata.shell.revision
            || chunk.field != ThreadContentField::Text
            || chunk.total_bytes != total
            || chunk.text.is_empty()
            || chunk.text.len() > remaining
            || chunk
                .continuation
                .as_ref()
                .is_some_and(|next| Some(next) == continuation.as_ref())
        {
            return Err(unavailable(
                "public text revision changed or detail coverage is incomplete",
            ));
        }
        let remaining_chars = (DELIVERY_TEXT_CHARS + 1).saturating_sub(body.chars().count());
        body.extend(chunk.text.chars().take(remaining_chars));
        if body.chars().count() == DELIVERY_TEXT_CHARS + 1 {
            // The reliable total length plus this exact-revision prefix is enough. Do not retain
            // an oversized ASCII chunk merely because the detail endpoint is byte-addressed.
            break;
        }
        continuation = chunk.continuation;
        if continuation.is_none() && body.len() as u64 != total {
            return Err(unavailable(
                "public text detail ended without complete length evidence",
            ));
        }
    }
    let complete = body.len() as u64 == total;
    fit(&body, complete)
}

/// All legal prefix boundaries are considered. Newline preference spans the entire fitting
/// prefix, not an arbitrary byte-radius, and no Markdown/code-fence repair is attempted.
pub(super) fn fit(text: &str, complete: bool) -> Result<Projection, FeishuError> {
    let mut boundaries = vec![0];
    boundaries.extend(
        text.char_indices()
            .take(DELIVERY_TEXT_CHARS)
            .map(|(i, ch)| i + ch.len_utf8()),
    );
    let character_end = *boundaries
        .last()
        .ok_or_else(|| attention("missing public prefix boundary"))?;
    let initially_full = complete && character_end == text.len();
    if initially_full && let Ok(request_bytes) = budget(text, false) {
        // Full has no truncation notice: test it before searching truncated prefixes, whose
        // extra host text otherwise makes the final boundary non-monotonic near the byte limit.
        return Ok(Projection {
            body: text.to_owned(),
            integrity: BotTextIntegrity::Full,
            request_bytes: if text.is_empty() { 0 } else { request_bytes },
        });
    }
    let mut low = 0;
    let mut high = boundaries.len();
    while low + 1 < high {
        let middle = (low + high) / 2;
        let end = boundaries[middle];
        let truncated = !initially_full || end != text.len();
        if budget(&text[..end], truncated).is_ok() {
            low = middle;
        } else {
            high = middle;
        }
    }
    let mut end = boundaries[low];
    let truncated = !initially_full || end != text.len();
    if truncated
        && let Some(newline) = text[..end].rfind('\n')
        && newline > 0
    {
        end = newline;
    }
    let body = text[..end].to_owned();
    Ok(Projection {
        // An empty item has no request until the caller proves a real safe status or an existing
        // card that must reflect a canonical clearing. That caller reserves the host-only request.
        request_bytes: if body.is_empty() {
            0
        } else {
            budget(&body, truncated)?
        },
        body,
        integrity: if truncated {
            BotTextIntegrity::Truncated
        } else {
            BotTextIntegrity::Full
        },
    })
}

fn budget(text: &str, truncated: bool) -> Result<u64, FeishuError> {
    // Reserve the longest lifecycle summary and host-state text, max positive int32 sequence,
    // and UUID before an Intent exists. The transaction callback validates actual bytes again.
    let states = [
        CardLifecycle::Paused,
        CardLifecycle::Cancelled,
        CardLifecycle::Failed,
        CardLifecycle::BudgetLimited,
        CardLifecycle::InteractionEnded,
        CardLifecycle::NoFinalReply,
    ];
    let longest = states
        .into_iter()
        .map(|lifecycle| host_region(BotTextIntegrity::Full, lifecycle))
        .max_by_key(String::len)
        .unwrap_or_default();
    let mut host = if truncated {
        format!("{TRUNCATED}\n\n{longest}")
    } else {
        longest
    };
    if text.trim().is_empty() {
        host = format!("{EMPTY_BODY}\n\n{host}");
    }
    let card =
        cardkit::publication_card_json(text, &host, false, CardLifecycle::NoFinalReply.summary())?;
    let create = cardkit::publication_create(card.clone())?;
    let whole = cardkit::publication_whole(card, i32::MAX, &"u".repeat(32))?;
    let content = cardkit::publication_content(text, i32::MAX, &"u".repeat(32))?;
    Ok(create.len().max(whole.len()).max(content.len()) as u64)
}

/// Use the same worst-state serializer proof for every revision/lifecycle so a Turn transition
/// cannot make an unchanged canonical revision conflict only because its budget metadata changed.
pub(super) fn reserve_host_request(text: &mut DeliveryText) -> Result<(), FeishuError> {
    text.request_bytes = budget(&text.body, text.integrity == BotTextIntegrity::Truncated)?;
    Ok(())
}

pub(super) fn render_host(
    body: &str,
    integrity: BotTextIntegrity,
    lifecycle: CardLifecycle,
) -> String {
    let state = host_region(integrity, lifecycle);
    if body.trim().is_empty() {
        if state.is_empty() {
            EMPTY_BODY.to_owned()
        } else {
            format!("{EMPTY_BODY}\n\n{state}")
        }
    } else {
        state
    }
}

fn text_length(fields: &[TimelineFieldLength]) -> Option<u64> {
    fields
        .iter()
        .find(|field| field.field == ThreadContentField::Text)
        .map(|field| field.total_bytes)
}

pub(super) fn host_region(integrity: BotTextIntegrity, lifecycle: CardLifecycle) -> String {
    let state = match lifecycle {
        CardLifecycle::Paused => "等待本机确认；请在 Studio 中处理交互。",
        CardLifecycle::Cancelled => "此轮已取消；所示内容不代表完整答复。",
        CardLifecycle::Failed => "此轮执行失败；所示内容不代表完整答复。",
        CardLifecycle::BudgetLimited => "此轮已达到预算限制；全文和状态保留在 Studio。",
        CardLifecycle::InteractionEnded => "本机交互已结束。",
        CardLifecycle::NoFinalReply => CardLifecycle::NoFinalReply.summary(),
        CardLifecycle::Empty
        | CardLifecycle::Created
        | CardLifecycle::Streaming
        | CardLifecycle::Completed
        | CardLifecycle::NeedsAttention => "",
    };
    match (integrity == BotTextIntegrity::Truncated, state.is_empty()) {
        (true, false) => format!("{TRUNCATED}\n\n{state}"),
        (true, true) => TRUNCATED.to_owned(),
        (false, _) => state.to_owned(),
    }
}

pub(super) fn text_from_projection(
    projection: Projection,
    channel: BotPublicTextChannel,
    revision: u64,
    saved: bool,
) -> DeliveryText {
    DeliveryText {
        channel,
        revision,
        integrity: projection.integrity,
        saved,
        body_chars: projection.body.chars().count() as u64,
        body: projection.body,
        request_bytes: projection.request_bytes,
    }
}
