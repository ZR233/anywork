//! Bounded visible-message reads and resumable substring search over canonical Session content.
use anyhow::{Context, Result, ensure};
use base64::Engine;
use pl_protocol::{ThreadContentField, TimelineDescriptor, TimelineDetailQuery, TimelinePageQuery};
use serde::{Deserialize, Serialize};

use super::{StudioRuntime, output};

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ReadInput {
    session_id: String,
    before: Option<String>,
    #[serde(default = "super::default_limit")]
    limit: u32,
    item_id: Option<String>,
    revision: Option<u64>,
    continuation: Option<String>,
}

pub(super) async fn read(
    runtime: &StudioRuntime,
    args: ReadInput,
) -> Result<pl_core::tool::ToolOutput> {
    let reader = runtime.timeline_reader(&args.session_id).await?;
    if let Some(item_id) = args.item_id {
        return output(
            &reader
                .read_detail(
                    &item_id,
                    &TimelineDetailQuery {
                        field: ThreadContentField::Text,
                        revision: args.revision.context("revision is required with itemId")?,
                        continuation: args.continuation,
                        max_bytes: Some(32 * 1024),
                    },
                )
                .await?,
        );
    }
    ensure!(
        (1..=100).contains(&args.limit),
        "limit must be between 1 and 100"
    );
    let page = reader
        .page(&TimelinePageQuery {
            before: args.before,
            limit: Some(args.limit),
        })
        .await?;
    output(&page)
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct SearchInput {
    query: String,
    project_id: Option<String>,
    session_id: Option<String>,
    #[serde(default)]
    archived: bool,
    cursor: Option<String>,
}

#[derive(Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Cursor {
    fingerprint: String,
    directory_cursor: Option<String>,
    directory_done: bool,
    session_id: Option<String>,
    before: Option<String>,
    pending: Option<PendingText>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct PendingText {
    item_id: String,
    revision: u64,
    continuation: Option<String>,
    overlap: String,
    next_before: Option<String>,
    end_of_session: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Match {
    session_id: String,
    item_id: String,
    revision: u64,
    snippet: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SearchPage {
    matches: Vec<Match>,
    cursor: Option<String>,
    complete: bool,
}

pub(super) async fn search(
    runtime: &StudioRuntime,
    args: SearchInput,
    cancel: &tokio_util::sync::CancellationToken,
) -> Result<pl_core::tool::ToolOutput> {
    ensure!(
        !args.query.trim().is_empty() && args.query.chars().count() <= 200,
        "query must contain 1 to 200 characters"
    );
    let fingerprint = crate::canonical_content_hash(&serde_json::to_vec(&(
        &args.query,
        &args.project_id,
        &args.session_id,
        args.archived,
    ))?);
    let mut cursor = match args.cursor {
        Some(token) => {
            ensure!(token.len() <= 16 * 1024, "search cursor too large");
            let value: Cursor = serde_json::from_slice(
                &base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(token)?,
            )?;
            ensure!(
                value.fingerprint == fingerprint,
                "search cursor belongs to another query"
            );
            value
        }
        None => Cursor {
            fingerprint,
            directory_done: args.session_id.is_some(),
            session_id: args.session_id,
            ..Default::default()
        },
    };
    let needle = args.query.to_lowercase();
    let overlap_chars = needle.chars().count().saturating_add(120);
    let mut matches = Vec::new();
    // Both tiny entries and large fields consume a step. Each field chunk is <=32 KiB.
    for _ in 0..32 {
        ensure!(!cancel.is_cancelled(), "search cancelled");
        if cursor.session_id.is_none() {
            if cursor.directory_done {
                break;
            }
            let page = runtime
                .agent_facility
                .product_events
                .query_threads(
                    &pl_protocol::studio::ThreadDirectoryQuery {
                        project_id: args.project_id.clone(),
                        archived: args.archived,
                        ..Default::default()
                    },
                    cursor.directory_cursor.as_deref(),
                    1,
                )
                .await?;
            let data = page
                .state
                .value()
                .context("session directory is unavailable")?;
            cursor.directory_cursor = data.next_cursor.clone();
            cursor.directory_done = data.next_cursor.is_none();
            cursor.session_id = data.threads.first().map(|thread| thread.id.clone());
            if cursor.session_id.is_none() {
                continue;
            }
        }
        let session_id = cursor
            .session_id
            .clone()
            .context("search session missing")?;
        let reader = runtime.timeline_reader(&session_id).await?;
        if cursor.pending.is_none() {
            let page = reader
                .page(&TimelinePageQuery {
                    before: cursor.before.clone(),
                    limit: Some(1),
                })
                .await?;
            let Some(item) = page.items.first() else {
                cursor.session_id = None;
                cursor.before = None;
                continue;
            };
            if !matches!(&item.descriptor, TimelineDescriptor::Text(_)) {
                advance(&mut cursor, page.before, !page.has_older);
                continue;
            }
            let Some(text) = item
                .fields
                .iter()
                .find(|field| field.field == ThreadContentField::Text)
            else {
                advance(&mut cursor, page.before, !page.has_older);
                continue;
            };
            let pending = PendingText {
                item_id: item.header.id.clone(),
                revision: item.revision,
                continuation: None,
                overlap: String::new(),
                next_before: page.before,
                end_of_session: !page.has_older,
            };
            if text.preview_bytes() < text.total_bytes {
                cursor.pending = Some(pending);
            } else {
                if let Some(snippet) = matched_snippet(&text.text, &needle) {
                    matches.push(Match {
                        session_id,
                        item_id: pending.item_id,
                        revision: pending.revision,
                        snippet,
                    });
                }
                advance(&mut cursor, pending.next_before, pending.end_of_session);
                if matches.len() >= 10 {
                    break;
                }
                continue;
            }
        }
        let mut pending = cursor.pending.take().context("search text missing")?;
        let chunk = reader
            .read_detail(
                &pending.item_id,
                &TimelineDetailQuery {
                    field: ThreadContentField::Text,
                    revision: pending.revision,
                    continuation: pending.continuation.take(),
                    max_bytes: Some(32 * 1024),
                },
            )
            .await?;
        let text = pending.overlap + &chunk.text;
        if let Some(snippet) = matched_snippet(&text, &needle) {
            matches.push(Match {
                session_id,
                item_id: pending.item_id,
                revision: pending.revision,
                snippet,
            });
            advance(&mut cursor, pending.next_before, pending.end_of_session);
        } else if let Some(continuation) = chunk.continuation {
            pending.continuation = Some(continuation);
            pending.overlap = text
                .chars()
                .rev()
                .take(overlap_chars)
                .collect::<Vec<_>>()
                .into_iter()
                .rev()
                .collect();
            cursor.pending = Some(pending);
        } else {
            advance(&mut cursor, pending.next_before, pending.end_of_session);
        }
        if matches.len() >= 10 {
            break;
        }
    }
    let complete = cursor.directory_done && cursor.session_id.is_none();
    let token = (!complete)
        .then(|| {
            serde_json::to_vec(&cursor)
                .map(|bytes| base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes))
        })
        .transpose()?;
    output(&SearchPage {
        matches,
        cursor: token,
        complete,
    })
}

fn advance(cursor: &mut Cursor, before: Option<String>, end: bool) {
    cursor.before = before;
    cursor.pending = None;
    if end {
        cursor.session_id = None;
    }
}

fn matched_snippet(text: &str, needle: &str) -> Option<String> {
    let folded = text.to_lowercase();
    let offset = folded.find(needle)?;
    // Lowercasing can change UTF-8 width; calculate context in the folded string.
    let before = folded[..offset]
        .chars()
        .rev()
        .take(80)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect::<String>();
    let after: String = folded[offset..].chars().take(240).collect();
    Some(format!("{before}{after}"))
}
