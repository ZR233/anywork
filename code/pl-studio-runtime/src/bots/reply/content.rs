//! Explicit first-coverage and terminal recovery, always through the feed's reader.

use super::projection::{ReplyProjection, gap};
use crate::studio::{StudioRuntime, TimelineContentReader};
use pl_protocol::{
    ThreadContentField, ThreadTextChannel, TimelineDescriptor, TimelineDetailCursor,
    TimelineDetailQuery, TimelineItem, TimelineLifecycle, TimelinePageCursor, TimelinePageQuery,
    TimelineTailBaseline,
};
use std::collections::{BTreeMap, BTreeSet};

pub(super) const MAX_TURN_CONTENT_ITEMS: usize = 16_384;
pub(super) const MAX_TURN_BODY_BYTES: usize = 800_000;

pub(super) enum FinalError {
    Retryable(String),
    Attention(String),
}

pub(super) enum FinalText {
    CompleteNoText,
    CompleteText(String),
}

/// The latest 32 are not a Turn boundary. Recover only the missing older prefix,
/// once for this target/connection, without promoting omitted previews to full text.
pub(super) fn begin_projection(
    thread_id: &str,
    turn_id: &str,
    baseline: TimelineTailBaseline,
) -> Result<(ReplyProjection, Option<PrefixRecovery>), FinalError> {
    let mut projection = ReplyProjection::new(thread_id, turn_id);
    let mut coverage = Coverage::new(thread_id);
    coverage.page(&baseline.items)?;
    projection.add_page(baseline.items)?;
    if projection.has_start() || !baseline.has_older {
        projection.mark_covered();
        return Ok((projection, None));
    }
    Ok((
        projection,
        Some(PrefixRecovery {
            coverage,
            before: baseline.before,
            has_older: true,
        }),
    ))
}

pub(super) struct PrefixRecovery {
    coverage: Coverage,
    before: Option<String>,
    has_older: bool,
}

pub(super) async fn recover_prefix(
    reader: &TimelineContentReader,
    projection: &mut ReplyProjection,
    recovery: &mut PrefixRecovery,
) -> Result<(), FinalError> {
    while !projection.has_start() && recovery.has_older {
        let token = recovery.coverage.cursor(recovery.before.clone())?;
        let page = reader
            .page(&TimelinePageQuery {
                before: Some(token),
                limit: Some(100),
            })
            .await
            .map_err(|error| read_failure("reply prefix recovery page failed", error))?;
        if page.thread_id != reader.thread_id() {
            return Err(gap("reply prefix page belongs to another Thread"));
        }
        recovery.coverage.page(&page.items)?;
        projection.add_page(page.items)?;
        recovery.before = page.before;
        recovery.has_older = page.has_older;
    }
    projection.mark_covered();
    Ok(())
}

/// Observe reliable save coverage first, then check the complete Final on this
/// exact Session. No terminal flag is inferred from the live preview's length.
pub(super) async fn collect_complete_turn_text(
    runtime: &StudioRuntime,
    reader: &TimelineContentReader,
    turn_id: &str,
) -> Result<FinalText, FinalError> {
    runtime
        .synchronize_thread_observation(reader.thread_id())
        .await
        .map_err(|error| read_failure("thread observation barrier failed", error))?;
    let mut collected = BTreeMap::new();
    let mut body_bytes = 0usize;
    let mut before = None;
    let mut coverage = Coverage::new(reader.thread_id());
    let mut saw_target = false;
    loop {
        let page = reader
            .page(&TimelinePageQuery {
                before: before.clone(),
                limit: Some(100),
            })
            .await
            .map_err(|error| read_failure("canonical final timeline page failed", error))?;
        if page.thread_id != reader.thread_id() {
            return Err(gap("canonical final page belongs to another Thread"));
        }
        coverage.page(&page.items)?;
        let mut found_start = false;
        for item in page.items {
            if item.header.turn_id != turn_id {
                continue;
            }
            saw_target = true;
            if !item.saved {
                return Err(gap(
                    "canonical target has not reached reliable save coverage",
                ));
            }
            found_start |= matches!(item.descriptor, TimelineDescriptor::Turn(_));
            let TimelineDescriptor::Text(descriptor) = &item.descriptor else {
                continue;
            };
            if descriptor.channel != ThreadTextChannel::Final {
                continue;
            }
            if item.lifecycle != TimelineLifecycle::Terminal || !descriptor.lifecycle.is_terminal()
            {
                return Err(gap("canonical Final has not reached Terminal"));
            }
            let fields: Vec<_> = item
                .fields
                .iter()
                .filter(|field| field.field == ThreadContentField::Text)
                .collect();
            if fields.len() > 1 {
                return Err(gap("canonical Final has duplicate text fields"));
            }
            let Some(field) = fields.first() else {
                continue;
            };
            if field.text.len() as u64 > field.total_bytes {
                return Err(gap("canonical Final preview exceeds total bytes"));
            }
            let body = if field.text.len() as u64 != field.total_bytes {
                read_complete_text(
                    reader,
                    &item,
                    field.total_bytes,
                    &field.text,
                    &mut body_bytes,
                )
                .await?
            } else {
                account_body_bytes(&field.text, &mut body_bytes)?;
                field.text.clone()
            };
            collected.insert((item.header.ordinal, item.header.id), body);
        }
        if found_start || !page.has_older {
            break;
        }
        before = Some(coverage.cursor(page.before)?);
    }
    if !saw_target {
        return Err(gap("canonical terminal target content is not yet covered"));
    }
    // Blocks are original content fragments, not paragraphs we may normalize.
    let text = collected.into_values().collect::<String>();
    if text.trim().is_empty() {
        Ok(FinalText::CompleteNoText)
    } else {
        Ok(FinalText::CompleteText(text))
    }
}

async fn read_complete_text(
    reader: &TimelineContentReader,
    item: &TimelineItem,
    total_bytes: u64,
    preview: &str,
    body_bytes: &mut usize,
) -> Result<String, FinalError> {
    if total_bytes > MAX_TURN_BODY_BYTES as u64 {
        return Err(FinalError::Attention(
            "canonical turn text exceeded 800000 UTF-8 bytes".to_string(),
        ));
    }
    let mut continuation = None;
    let mut body = String::new();
    loop {
        let chunk = reader
            .read_detail(
                &item.header.id,
                &TimelineDetailQuery {
                    field: ThreadContentField::Text,
                    revision: item.revision,
                    continuation,
                    max_bytes: None,
                },
            )
            .await
            .map_err(|error| read_failure("canonical Final detail failed", error))?;
        if chunk.thread_id != reader.thread_id()
            || chunk.item_id != item.header.id
            || chunk.field != ThreadContentField::Text
            || chunk.revision != item.revision
            || chunk.total_bytes != total_bytes
        {
            return Err(gap("canonical Final detail identity or revision conflict"));
        }
        account_body_bytes(&chunk.text, body_bytes)?;
        body.push_str(&chunk.text);
        if body.len() as u64 > total_bytes {
            return Err(gap("canonical Final detail exceeds declared length"));
        }
        match chunk.continuation {
            Some(token) => {
                let cursor = TimelineDetailCursor::decode(&token)
                    .ok_or_else(|| gap("invalid Final detail continuation"))?;
                if cursor.thread_id != reader.thread_id()
                    || cursor.item_id != item.header.id
                    || cursor.field != ThreadContentField::Text.token_label()
                    || cursor.revision != item.revision
                    || cursor.offset != body.len() as u64
                    || chunk.text.is_empty()
                {
                    return Err(gap("canonical Final detail continuation did not advance"));
                }
                continuation = Some(token);
            }
            None => {
                if body.len() as u64 != total_bytes || !body.starts_with(preview) {
                    return Err(gap("canonical Final detail does not cover its preview"));
                }
                return Ok(body);
            }
        }
    }
}

pub(super) struct Coverage {
    thread_id: String,
    inspected: usize,
    oldest: Option<(u64, String)>,
    cursors: BTreeSet<String>,
}

impl Coverage {
    pub(super) fn new(thread_id: &str) -> Self {
        Self {
            thread_id: thread_id.to_string(),
            inspected: 0,
            oldest: None,
            cursors: BTreeSet::new(),
        }
    }

    pub(super) fn page(&mut self, items: &[TimelineItem]) -> Result<(), FinalError> {
        self.inspected = self.inspected.saturating_add(items.len());
        if self.inspected > MAX_TURN_CONTENT_ITEMS {
            return Err(FinalError::Attention(
                "canonical turn coverage exceeded 16384 content items".to_string(),
            ));
        }
        let mut previous = None;
        for item in items {
            let order = (item.header.ordinal, item.header.id.as_str());
            if item.header.thread_id != self.thread_id
                || item.header.id.is_empty()
                || previous.is_some_and(|previous| previous >= order)
                || self
                    .oldest
                    .as_ref()
                    .is_some_and(|oldest| order >= (oldest.0, oldest.1.as_str()))
            {
                return Err(gap(
                    "canonical reply page identity or stable order conflict",
                ));
            }
            previous = Some(order);
        }
        if let Some(first) = items.first() {
            self.oldest = Some((first.header.ordinal, first.header.id.clone()));
        }
        Ok(())
    }

    pub(super) fn cursor(&mut self, token: Option<String>) -> Result<String, FinalError> {
        let token = token
            .filter(|token| !token.is_empty())
            .ok_or_else(|| gap("canonical reply page lacks older cursor"))?;
        let cursor = TimelinePageCursor::decode(&token)
            .ok_or_else(|| gap("canonical reply page cursor is invalid"))?;
        if cursor.thread_id != self.thread_id
            || self.oldest.as_ref() != Some(&(cursor.order, cursor.item_id))
        {
            return Err(gap(
                "canonical reply cursor is not the page's older boundary",
            ));
        }
        if !self.cursors.insert(token.clone()) {
            return Err(gap("canonical reply page cursor did not advance"));
        }
        Ok(token)
    }
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

pub(super) fn read_failure(context: &str, error: anyhow::Error) -> FinalError {
    let error = crate::studio_error_from_anyhow(error);
    let diagnostic = format!(
        "{context}: {} (correlation id: {})",
        error.code.label(),
        error.correlation_id
    );
    if error.retryable {
        FinalError::Retryable(diagnostic)
    } else {
        FinalError::Attention(diagnostic)
    }
}
