use crate::studio::StudioRuntime;
use pl_protocol::{
    ThreadContentField, ThreadItemState, ThreadTextChannel, TimelineDetailQuery, TimelineItem,
    TimelineLifecycle, TimelinePageQuery,
};
use std::collections::BTreeMap;

pub(super) const MAX_TURN_CONTENT_ITEMS: usize = 16_384;
const MAX_TURN_BODY_BYTES: usize = 800_000;

pub(super) enum FinalError {
    Retryable(String),
    Attention(String),
}

pub(super) enum FinalText {
    CompleteNoText,
    CompleteText(String),
}

/// A throttled canonical read of the active target Turn, not a second tail reducer.
/// Stop at its Turn marker, so token updates do not rescan unrelated old history.
/// A missing marker or an expired detail revision yields no preview, never a
/// truncated snapshot masquerading as the whole current answer.
pub(super) async fn collect_preview(
    runtime: &StudioRuntime,
    thread_id: &str,
    turn_id: &str,
) -> Result<Option<String>, FinalError> {
    let reader = runtime
        .timeline_reader(thread_id)
        .await
        .map_err(|_| FinalError::Retryable("canonical preview reader is not ready".to_string()))?;
    let mut before = None;
    let mut inspected = 0usize;
    let mut body_bytes = 0usize;
    let mut collected = BTreeMap::new();
    loop {
        let page = reader
            .page(&TimelinePageQuery {
                before: before.clone(),
                limit: Some(100),
            })
            .await
            .map_err(|_| {
                FinalError::Retryable("canonical preview page is not ready".to_string())
            })?;
        if page.thread_id != thread_id {
            return Err(FinalError::Attention(
                "canonical preview Thread conflict".to_string(),
            ));
        }
        inspected = inspected.saturating_add(page.items.len());
        if inspected > MAX_TURN_CONTENT_ITEMS {
            return Err(FinalError::Attention(
                "canonical turn coverage exceeded 16384 content items".to_string(),
            ));
        }
        let mut found_start = false;
        let mut saw_target = false;
        for item in page.items {
            if item.preview.thread_id != thread_id {
                return Err(FinalError::Attention(
                    "canonical preview item identity conflict".to_string(),
                ));
            }
            if item.preview.turn_id != turn_id {
                continue;
            }
            saw_target = true;
            found_start |= matches!(item.preview.state(), ThreadItemState::Turn(_));
            let Some(text) = item
                .preview
                .text()
                .filter(|text| text.channel() == ThreadTextChannel::Final)
            else {
                continue;
            };
            let body = if item.omitted_bytes > 0 {
                match read_complete_text(runtime, thread_id, &item, &mut body_bytes).await {
                    Ok(body) => body,
                    Err(FinalError::Retryable(_)) => return Ok(None),
                    Err(error) => return Err(error),
                }
            } else {
                account_body_bytes(text.text(), &mut body_bytes)?;
                text.text().to_string()
            };
            collected.insert(item.preview.ordinal, body);
        }
        if found_start || !page.has_older {
            let text = collected
                .into_values()
                .filter(|text| !text.trim().is_empty())
                .collect::<Vec<_>>()
                .join("\n\n");
            return Ok((!text.trim().is_empty()).then_some(text));
        }
        // The active target is no longer in the latest window. Do not scan the
        // Thread for an unrelated Turn merely to produce an optional live preview.
        if !saw_target && collected.is_empty() {
            return Ok(None);
        }
        let next = page.before.filter(|next| !next.is_empty()).ok_or_else(|| {
            FinalError::Attention("canonical preview page lacks its older cursor".to_string())
        })?;
        if before.as_ref() == Some(&next) {
            return Err(FinalError::Attention(
                "canonical preview cursor did not advance".to_string(),
            ));
        }
        before = Some(next);
    }
}

/// 从统一内容源完整收集目标 Turn 的用户可见终态正文；只统计 Final 且 Terminal。
pub(super) async fn collect_complete_turn_text(
    runtime: &StudioRuntime,
    thread_id: &str,
    turn_id: &str,
) -> Result<FinalText, FinalError> {
    runtime
        .synchronize_thread_observation(thread_id)
        .await
        .map_err(|error| {
            FinalError::Retryable(format!("thread observation barrier failed: {error:#}"))
        })?;
    let mut collected = BTreeMap::new();
    let mut inspected = 0usize;
    let mut body_bytes = 0usize;
    let mut before = None;
    let mut previous_before = None;
    loop {
        let page = runtime
            .timeline_page(
                thread_id,
                &TimelinePageQuery {
                    before: before.clone(),
                    limit: Some(100),
                },
            )
            .await
            .map_err(|error| {
                FinalError::Retryable(format!("canonical timeline page failed: {error:#}"))
            })?;
        if page.thread_id != thread_id {
            return Err(FinalError::Attention(
                "canonical timeline page belongs to another Thread".to_string(),
            ));
        }
        inspected = inspected.saturating_add(page.items.len());
        if inspected > MAX_TURN_CONTENT_ITEMS {
            return Err(FinalError::Attention(
                "canonical turn coverage exceeded 16384 content items".to_string(),
            ));
        }
        for item in page.items {
            if item.preview.turn_id != turn_id {
                continue;
            }
            let Some(text) = item.preview.text() else {
                continue;
            };
            if text.channel() != ThreadTextChannel::Final {
                continue;
            }
            if item.lifecycle != TimelineLifecycle::Terminal || !text.lifecycle().is_terminal() {
                return Err(FinalError::Retryable(
                    "canonical Final has not reached Terminal".to_string(),
                ));
            }
            if item.preview.thread_id != thread_id {
                return Err(FinalError::Attention(
                    "canonical Final Thread conflict".to_string(),
                ));
            }
            let body = if item.omitted_bytes > 0 {
                read_complete_text(runtime, thread_id, &item, &mut body_bytes).await?
            } else {
                account_body_bytes(text.text(), &mut body_bytes)?;
                text.text().to_string()
            };
            collected.insert(item.preview.ordinal, (item.preview.id.clone(), body));
        }
        if !page.has_older {
            break;
        }
        let Some(next) = page.before.filter(|token| !token.is_empty()) else {
            return Err(FinalError::Attention(
                "canonical timeline reported older content without a before cursor".to_string(),
            ));
        };
        if before.as_ref() == Some(&next) || previous_before.as_ref() == Some(&next) {
            return Err(FinalError::Attention(
                "canonical timeline before cursor did not advance".to_string(),
            ));
        }
        previous_before = before.clone();
        before = Some(next);
    }
    if collected.is_empty() {
        return Ok(FinalText::CompleteNoText);
    }
    let mut parts = Vec::new();
    let mut last_id = None;
    for (_ordinal, (id, body)) in collected {
        if last_id.as_ref() == Some(&id) {
            continue;
        }
        last_id = Some(id);
        if !body.trim().is_empty() {
            parts.push(body);
        }
    }
    let joined = parts.join("\n\n");
    if joined.trim().is_empty() {
        return Ok(FinalText::CompleteNoText);
    }
    Ok(FinalText::CompleteText(joined))
}

async fn read_complete_text(
    runtime: &StudioRuntime,
    thread_id: &str,
    item: &TimelineItem,
    body_bytes: &mut usize,
) -> Result<String, FinalError> {
    let mut continuation = None;
    let mut body = String::new();
    let mut previous = None;
    loop {
        let chunk = runtime
            .read_timeline_detail(
                thread_id,
                &item.preview.id,
                &TimelineDetailQuery {
                    field: ThreadContentField::Text,
                    revision: item.preview.revision,
                    continuation,
                    max_bytes: None,
                },
            )
            .await
            .map_err(|error| {
                FinalError::Retryable(format!("canonical timeline detail failed: {error:#}"))
            })?;
        if chunk.thread_id != thread_id
            || chunk.item_id != item.preview.id
            || chunk.field != ThreadContentField::Text
        {
            return Err(FinalError::Attention(
                "canonical timeline detail identity conflict".to_string(),
            ));
        }
        if chunk.revision != item.preview.revision {
            return Err(FinalError::Retryable(
                "canonical timeline detail revision conflict".to_string(),
            ));
        }
        if chunk.total_bytes > MAX_TURN_BODY_BYTES as u64 {
            return Err(FinalError::Attention(
                "canonical turn text exceeded 800000 UTF-8 bytes".to_string(),
            ));
        }
        account_body_bytes(&chunk.text, body_bytes)?;
        body.push_str(&chunk.text);
        match chunk.continuation {
            Some(token) if previous.as_ref() == Some(&token) => {
                return Err(FinalError::Attention(
                    "canonical timeline detail continuation did not advance".to_string(),
                ));
            }
            Some(token) => {
                previous = Some(token.clone());
                continuation = Some(token);
            }
            None => {
                if body.len() as u64 != chunk.total_bytes {
                    return Err(FinalError::Retryable(
                        "canonical timeline detail is incomplete".to_string(),
                    ));
                }
                break;
            }
        }
    }
    Ok(body)
}

fn account_body_bytes(text: &str, body_bytes: &mut usize) -> Result<(), FinalError> {
    *body_bytes = body_bytes.saturating_add(text.len());
    if *body_bytes > MAX_TURN_BODY_BYTES {
        return Err(FinalError::Attention(
            "canonical turn text exceeded 800000 UTF-8 bytes".to_string(),
        ));
    }
    Ok(())
}
