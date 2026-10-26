//! Existing hot/cold queries provide the rows and clocks. A loaded window ends at a key, not N rows.
use std::sync::Arc;

use anyhow::Result;
use pl_protocol::ObservedResource;
use pl_protocol::studio::ThreadDirectoryQuery;
use tokio_util::sync::CancellationToken;

use super::super::StudioRuntime;
use super::ThreadDirectoryScope;
use super::source::{DirectoryBinding, DirectoryRows, DirectorySnapshot};
use crate::studio::store::directory::ThreadDirectoryCursor;

#[derive(Clone, PartialEq)]
pub(super) struct CapturedDirectory {
    pub(super) metadata: ObservedResource<()>,
    pub(super) rows: DirectoryRows,
    pub(super) directory_revision: Option<u64>,
    pub(super) search_project_revision: Option<u64>,
    pub(super) pinned_ids: Vec<String>,
    pub(super) frontier: Option<String>,
}

pub(super) async fn capture(
    runtime: &StudioRuntime,
    binding: &DirectoryBinding,
    previous: Option<&Arc<DirectorySnapshot>>,
    cancel: &CancellationToken,
) -> Result<CapturedDirectory> {
    check(runtime, cancel)?;
    let events = &runtime.agent_facility.product_events;
    match binding {
        DirectoryBinding::Projects => {
            let state = events.read_project_directory().await?.state;
            Ok(CapturedDirectory {
                rows: DirectoryRows::Projects(
                    state
                        .value()
                        .map(|value| value.projects.clone())
                        .unwrap_or_default(),
                ),
                metadata: state.map(|_| ()),
                directory_revision: None,
                search_project_revision: None,
                pinned_ids: Vec::new(),
                frontier: None,
            })
        }
        DirectoryBinding::Agents => {
            let state = events.read_agent_directory().await.state;
            Ok(CapturedDirectory {
                rows: DirectoryRows::Agents(
                    state
                        .value()
                        .map(|value| value.agents.clone())
                        .unwrap_or_default(),
                ),
                metadata: state.map(|_| ()),
                directory_revision: None,
                search_project_revision: None,
                pinned_ids: Vec::new(),
                frontier: None,
            })
        }
        DirectoryBinding::Threads(ThreadDirectoryScope::Thread { thread_id }) => {
            let before = events.read_thread_directory().await?.state;
            if before.value().is_none() {
                return Ok(unknown_threads(before.map(|_| ())));
            }
            let thread = runtime.read_thread(thread_id).await?;
            let after = events.read_thread_directory().await?.state;
            if before != after {
                return Err(super::stale().into());
            }
            Ok(CapturedDirectory {
                directory_revision: Some(before.revision()),
                metadata: before.map(|_| ()),
                rows: DirectoryRows::Threads(vec![thread]),
                search_project_revision: None,
                pinned_ids: Vec::new(),
                frontier: None,
            })
        }
        DirectoryBinding::Threads(ThreadDirectoryScope::Query {
            query,
            include_pinned,
        }) => capture_window(runtime, query, *include_pinned, previous, cancel).await,
    }
}

async fn capture_window(
    runtime: &StudioRuntime,
    query: &ThreadDirectoryQuery,
    include_pinned: bool,
    previous: Option<&Arc<DirectorySnapshot>>,
    cancel: &CancellationToken,
) -> Result<CapturedDirectory> {
    let include_pinned = include_pinned && !query.archived;
    let source = runtime
        .agent_facility
        .product_events
        .read_thread_directory()
        .await?
        .state;
    if source.value().is_none() {
        return Ok(unknown_threads(source.map(|_| ())));
    }
    let captured_project_revision = project_revision(runtime, query).await?;
    let captured_pins = pinned_ids(runtime, include_pinned)?;
    // Keep the original native frontier across head insertions/removals. If the prior window
    // reached the end, refresh through the end; never substitute a local offset or row count.
    let boundary = previous
        .and_then(|previous| previous.capture.frontier.as_deref())
        .map(decode)
        .transpose()?;
    let mut cursor = None;
    let mut rows = Vec::new();
    let mut metadata: Option<ObservedResource<()>> = None;
    loop {
        check(runtime, cancel)?;
        let page = query_page(runtime, query, include_pinned, cursor.as_deref(), 32).await?;
        let state = page.state;
        if let Some(original) = &metadata
            && original != &state.clone().map(|_| ())
        {
            return Err(super::stale().into());
        }
        metadata = Some(state.clone().map(|_| ()));
        let value = state.value().ok_or_else(|| {
            pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Unavailable,
                "Thread directory has no readable source value",
                true,
            )
        })?;
        append_unique(&mut rows, value.threads.clone());
        let next = value.next_cursor.clone();
        let reached = match (&boundary, next.as_deref()) {
            (Some(boundary), Some(next)) => key(&decode(next)?) <= key(boundary),
            _ => false,
        };
        let stop = next.is_none() || previous.is_none() || reached;
        if stop {
            if project_revision(runtime, query).await? != captured_project_revision
                || pinned_ids(runtime, include_pinned)? != captured_pins
            {
                return Err(super::stale().into());
            }
            let frontier = if let Some(boundary) = &boundary {
                let older = rows.iter().any(|row| {
                    !captured_pins.contains(&row.id)
                        && (row.directory_sort_time(), row.id.as_str()) < key(boundary)
                });
                rows.retain(|row| {
                    captured_pins.contains(&row.id)
                        || (row.directory_sort_time(), row.id.as_str()) >= key(boundary)
                });
                if older || next.is_some() {
                    previous.and_then(|previous| previous.capture.frontier.clone())
                } else {
                    None
                }
            } else {
                next
            };
            let metadata = metadata.ok_or_else(super::cancelled)?;
            return Ok(CapturedDirectory {
                directory_revision: Some(metadata.revision()),
                metadata,
                rows: DirectoryRows::Threads(rows),
                search_project_revision: captured_project_revision,
                pinned_ids: captured_pins,
                frontier,
            });
        }
        if next == cursor {
            return Err(super::wrong_field().into());
        }
        cursor = next;
    }
}

/// Extend only the captured query's original keyset cursor and clocks. The caller holds its
/// original capture gate and validates the original handle's exposed expected collection.
pub(super) async fn extend(
    runtime: &StudioRuntime,
    previous: &DirectorySnapshot,
    limit: u32,
    cancel: &CancellationToken,
) -> Result<CapturedDirectory> {
    if !(1..=100).contains(&limit) {
        return Err(pl_protocol::studio::StudioError::invalid_argument(
            "Directory limit must be in 1..=100",
        )
        .into());
    }
    let DirectoryBinding::Threads(ThreadDirectoryScope::Query {
        query,
        include_pinned,
    }) = &previous.binding
    else {
        return Err(pl_protocol::studio::StudioError::invalid_argument(
            "Single Thread metadata has no extensible frontier",
        )
        .into());
    };
    let include_pinned = *include_pinned && !query.archived;
    check(runtime, cancel)?;
    let Some(cursor) = previous.capture.frontier.as_deref() else {
        return Ok(previous.capture.clone());
    };
    if project_revision(runtime, query).await? != previous.capture.search_project_revision
        || pinned_ids(runtime, include_pinned)? != previous.capture.pinned_ids
    {
        return Err(super::stale().into());
    }
    let page = query_page(runtime, query, include_pinned, Some(cursor), limit as usize).await?;
    if page.state.clone().map(|_| ()) != previous.capture.metadata {
        return Err(super::stale().into());
    }
    let value = page.state.value().ok_or_else(super::stale)?;
    let mut capture = previous.capture.clone();
    let DirectoryRows::Threads(rows) = &mut capture.rows else {
        return Err(super::wrong_field().into());
    };
    append_unique(rows, value.threads.clone());
    capture.frontier = value.next_cursor.clone();
    if capture.frontier.as_deref() == Some(cursor) {
        return Err(super::wrong_field().into());
    }
    if project_revision(runtime, query).await? != capture.search_project_revision
        || pinned_ids(runtime, include_pinned)? != capture.pinned_ids
    {
        return Err(super::stale().into());
    }
    check(runtime, cancel)?;
    Ok(capture)
}

async fn query_page(
    runtime: &StudioRuntime,
    query: &ThreadDirectoryQuery,
    include_pinned: bool,
    cursor: Option<&str>,
    limit: usize,
) -> Result<crate::StudioThreadDirectoryPage> {
    if include_pinned {
        runtime.query_threads(query, cursor, limit).await
    } else {
        runtime
            .agent_facility
            .product_events
            .query_threads(query, cursor, limit)
            .await
    }
}
async fn project_revision(
    runtime: &StudioRuntime,
    query: &ThreadDirectoryQuery,
) -> Result<Option<u64>> {
    if query.search.is_none() {
        return Ok(None);
    }
    Ok(Some(
        runtime
            .agent_facility
            .product_events
            .read_project_directory()
            .await?
            .state
            .revision(),
    ))
}
fn pinned_ids(runtime: &StudioRuntime, include_pinned: bool) -> Result<Vec<String>> {
    if include_pinned {
        Ok(runtime
            .config_runtime
            .read()?
            .config
            .ui
            .pinned_thread_ids
            .clone())
    } else {
        Ok(Vec::new())
    }
}
fn append_unique(rows: &mut Vec<pl_protocol::Thread>, page: Vec<pl_protocol::Thread>) {
    for row in page {
        if !rows.iter().any(|existing| existing.id == row.id) {
            rows.push(row);
        }
    }
}
fn decode(cursor: &str) -> Result<ThreadDirectoryCursor> {
    ThreadDirectoryCursor::decode(cursor).ok_or_else(|| super::wrong_field().into())
}
fn key(cursor: &ThreadDirectoryCursor) -> (i64, &str) {
    (cursor.sort_time, &cursor.id)
}
fn check(runtime: &StudioRuntime, cancel: &CancellationToken) -> Result<()> {
    if cancel.is_cancelled() || runtime.shutdown_committed() {
        return Err(super::cancelled().into());
    }
    runtime.workspace_source.ensure_open()?;
    Ok(())
}
fn unknown_threads(metadata: ObservedResource<()>) -> CapturedDirectory {
    CapturedDirectory {
        metadata,
        rows: DirectoryRows::Threads(Vec::new()),
        directory_revision: None,
        search_project_revision: None,
        pinned_ids: Vec::new(),
        frontier: None,
    }
}
