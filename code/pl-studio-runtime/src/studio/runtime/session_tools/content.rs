//! Thread-tool reads over unified ConversationFeed and immutable History ports.

use super::{StudioRuntime, output};
use crate::timeline::{BodyRef, ConversationFeed};
use crate::{ChatScope, ContentRange, ReadDemand};
use anyhow::{Context, Result, ensure};
use base64::Engine;
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};
use tokio::sync::{Mutex, OwnedSemaphorePermit, RwLock, Semaphore};
use tokio_util::sync::CancellationToken;

const MAX_READ_SCOPES: usize = 16;

pub(super) struct ReadOwners {
    readers: Mutex<BTreeMap<String, Arc<ReadResource>>>,
    permits: Arc<Semaphore>,
    stopping: CancellationToken,
    opens: RwLock<()>,
}

struct ReadResource {
    feed: ConversationFeed,
    history: crate::history::HistoryReader,
    cancel: CancellationToken,
    closing: AtomicBool,
    _permit: OwnedSemaphorePermit,
}

impl ReadResource {
    fn request_close(&self) {
        self.closing.store(true, Ordering::Release);
        self.cancel.cancel();
        self.feed.request_close();
        self.history.request_close();
    }

    async fn close(&self) -> Result<()> {
        self.request_close();
        tokio::join!(self.feed.close(), self.history.close());
        Ok(())
    }
}

impl Default for ReadOwners {
    fn default() -> Self {
        Self {
            readers: Mutex::new(BTreeMap::new()),
            permits: Arc::new(Semaphore::new(MAX_READ_SCOPES)),
            stopping: CancellationToken::new(),
            opens: RwLock::new(()),
        }
    }
}

fn stale_scope() -> anyhow::Error {
    crate::StudioError::new(
        crate::StudioErrorCode::StaleRevision,
        "Tool read scope is unknown or retired",
        false,
    )
    .with_reason(
        crate::StudioErrorReason::StaleReadScope,
        serde_json::Value::Null,
    )
    .into()
}

fn search_cancelled() -> anyhow::Error {
    anyhow::anyhow!("search cancelled")
}

fn operation_and_cleanup<T>(operation: Result<T>, cleanup: Result<()>) -> Result<T> {
    match (operation, cleanup) {
        (Err(error), Err(cleanup)) => Err(error.context(format!(
            "read scope cleanup failed; original owner retains retry responsibility: {cleanup:#}"
        ))),
        (Err(error), Ok(())) => Err(error),
        (Ok(_), Err(error)) => Err(error),
        (Ok(value), Ok(())) => Ok(value),
    }
}

async fn search_read<T, E: Into<anyhow::Error>>(
    cancel: &CancellationToken,
    read: impl std::future::Future<Output = std::result::Result<T, E>>,
) -> Result<T> {
    tokio::select! { biased;
        _=cancel.cancelled()=>Err(search_cancelled()),
        result=read=>result.map_err(Into::into),
    }
}

impl ReadOwners {
    async fn open(
        &self,
        runtime: &StudioRuntime,
        session: &str,
        demand: ReadDemand,
    ) -> Result<(String, Arc<ReadResource>)> {
        let _open = tokio::select! { biased;
            _=self.stopping.cancelled()=>return Err(stale_scope()),
            open=self.opens.read()=>open
        };
        ensure!(!self.stopping.is_cancelled(), stale_scope());
        let permit = self.permits.clone().try_acquire_owned().map_err(|_| {
            pl_core::chat::ChatError::Overloaded(
                "close an existing tool read scope before opening another".into(),
            )
        })?;
        let feed = tokio::select! { biased;
            _=self.stopping.cancelled()=>return Err(stale_scope()),
            result=runtime.open_conversation_feed(session, demand.max_items)=>result?
        };
        let history_result = tokio::select! { biased;
            _=self.stopping.cancelled()=>return Err(stale_scope()),
            result=runtime.open_history_reader(session, crate::history::HISTORY_PROTOCOL_VERSION)=>result
        };
        let history = match history_result {
            Ok(history) => history,
            Err(error) => {
                feed.close().await;
                return Err(error);
            }
        };
        let resource = Arc::new(ReadResource {
            feed: feed.clone(),
            history: history.clone(),
            cancel: feed.cancellation_token(),
            closing: AtomicBool::new(false),
            _permit: permit,
        });
        let id = crate::studio::new_id("read");
        self.readers
            .lock()
            .await
            .insert(id.clone(), resource.clone());
        Ok((id, resource))
    }

    async fn get(&self, id: &str, session: &str) -> Result<Arc<ReadResource>> {
        if self.stopping.is_cancelled() {
            return Err(stale_scope());
        }
        let resource = self
            .readers
            .lock()
            .await
            .get(id)
            .cloned()
            .ok_or_else(stale_scope)?;
        ensure!(
            !resource.closing.load(Ordering::Acquire) && resource.feed.thread_id() == session,
            stale_scope()
        );
        Ok(resource)
    }

    async fn close(&self, id: &str) -> Result<()> {
        let resource = self
            .readers
            .lock()
            .await
            .get(id)
            .cloned()
            .ok_or_else(stale_scope)?;
        resource.close().await?;
        let mut readers = self.readers.lock().await;
        if readers
            .get(id)
            .is_some_and(|current| Arc::ptr_eq(current, &resource))
        {
            readers.remove(id);
        }
        Ok(())
    }

    async fn close_target(&self, id: &str, session: &str) -> Result<()> {
        let resource = self.get(id, session).await?;
        ensure!(resource.feed.thread_id() == session, stale_scope());
        self.close(id).await
    }

    pub(super) async fn close_all(&self) -> Result<()> {
        self.stopping.cancel();
        let _opens = self.opens.write().await;
        let resources = self
            .readers
            .lock()
            .await
            .iter()
            .map(|(id, resource)| (id.clone(), resource.clone()))
            .collect::<Vec<_>>();
        for (_, resource) in &resources {
            resource.request_close();
        }
        let mut failure = None;
        for (id, _) in resources {
            if let Err(error) = self.close(&id).await
                && failure.is_none()
            {
                failure = Some(error);
            }
        }
        match failure {
            Some(error) => Err(error),
            None => Ok(()),
        }
    }
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ReadInput {
    session_id: String,
    scope: Option<ChatScope>,
    read_scope: Option<String>,
    before: Option<String>,
    #[schemars(with = "Option<serde_json::Value>")]
    demand: Option<ReadDemand>,
    item_id: Option<String>,
    continuation: Option<String>,
    #[schemars(with = "Option<serde_json::Value>")]
    body_ref: Option<BodyRef>,
    #[schemars(with = "Option<serde_json::Value>")]
    range: Option<ContentRange>,
    #[serde(default)]
    read_business_refs: bool,
    #[serde(default)]
    close_read_scope: bool,
}

pub(super) fn read_schema() -> serde_json::Value {
    let mut schema = pl_agent_tool::typed::input_schema_for::<ReadInput>();
    schema["properties"]["demand"] = serde_json::json!({"anyOf":[{"type":"object","required":["maxItems","maxBytes"],"additionalProperties":false,"properties":{
        "maxItems":{"type":"integer","minimum":1,"maximum":crate::CHAT_READ_MAX_ITEMS},
        "maxBytes":{"type":"integer","minimum":1,"maximum":crate::CHAT_BATCH_MAX_BYTES}}},{"type":"null"}]});
    schema["properties"]["bodyRef"] = serde_json::json!({"anyOf":[{"type":"object","description":"Copy a BodyRef unchanged."},{"type":"null"}]});
    schema["properties"]["scope"]["description"] = serde_json::json!(
        "History original scope for a new read. Existing readScope continues the same immutable cut."
    );
    schema["properties"]["readBusinessRefs"]["description"] = serde_json::json!(
        "Read the current Plan and interaction snapshots; no history or demand is required."
    );
    schema
}

fn encode(value: &impl Serialize) -> Result<String> {
    Ok(base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(serde_json::to_vec(value)?))
}

fn decode<T: serde::de::DeserializeOwned>(token: &str) -> Result<T> {
    ensure!(token.len() <= 16 * 1024, "tool continuation is too large");
    Ok(serde_json::from_slice(
        &base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(token)?,
    )?)
}

fn demand(limit: u32) -> Result<ReadDemand> {
    ensure!(
        (1..=100).contains(&limit),
        "limit must be between 1 and 100"
    );
    Ok(ReadDemand {
        max_items: limit,
        max_bytes: 128 * 1024,
    })
}

pub(super) async fn get(
    runtime: &StudioRuntime,
    owners: &ReadOwners,
    session: &str,
) -> Result<pl_core::tool::ToolOutput> {
    let (id, resource) = owners.open(runtime, session, demand(16)?).await?;
    let result = async {
        let meta = resource.feed.session_meta_snapshot();
        output(&serde_json::json!({
            "readScope": id,
            "current": meta,
            "pending": meta.interactions,
            "pendingHasMore": false,
        }))
    }
    .await;
    operation_and_cleanup(result, owners.close(&id).await)
}

pub(super) async fn read(
    runtime: &StudioRuntime,
    owners: &ReadOwners,
    args: ReadInput,
) -> Result<pl_core::tool::ToolOutput> {
    if args.close_read_scope {
        let id = args
            .read_scope
            .context("readScope is required with closeReadScope")?;
        owners.close_target(&id, &args.session_id).await?;
        return output(&serde_json::json!({"readScope":id,"closed":true}));
    }
    let page_demand = args.demand.unwrap_or(ReadDemand {
        max_items: 1,
        max_bytes: 64 * 1024,
    });
    page_demand.validate(1)?;
    let (id, resource, created) = if let Some(id) = args.read_scope.clone() {
        (id.clone(), owners.get(&id, &args.session_id).await?, false)
    } else {
        ensure!(
            args.scope.is_some()
                || args.read_business_refs
                || args.body_ref.is_some()
                || args.item_id.is_some(),
            "scope is required when opening a history read"
        );
        let (id, resource) = owners.open(runtime, &args.session_id, page_demand).await?;
        (id, resource, true)
    };
    let result = async {
        if args.read_business_refs {
            let meta = resource.feed.session_meta_snapshot();
            return output(&serde_json::json!({
                "readScope": id,
                "businessRefs": { "plan": meta.plan, "interactions": meta.interactions },
                "currentRevision": meta.revision,
            }));
        }
        if let Some(body_ref) = args.body_ref {
            let range = args.range.context("range is required for a bodyRef read")?;
            let window = resource
                .feed
                .read_body_window(&body_ref, range.offset, range.max_bytes)
                .await?;
            return output(&serde_json::json!({"readScope": id, "window": window}));
        }
        if let Some(item_id) = args.item_id {
            let page = resource
                .history
                .list_bodies(item_id.clone(), args.continuation, crate::history::HistoryDemand {
                    max_rows: page_demand.max_items,
                    max_bytes: page_demand.max_bytes,
                })
                .await?;
            return output(&serde_json::json!({"readScope":id,"itemId":item_id,"manifest":page}));
        }
        let scope = args
            .scope
            .unwrap_or(ChatScope::conversation(None));
        let page = resource
            .history
            .events_page(
                crate::history::HistoryEventsQuery::Originals { scope },
                None,
                args.before,
                crate::history::HistoryDemand {
                    max_rows: page_demand.max_items,
                    max_bytes: page_demand.max_bytes,
                },
            )
            .await?;
        output(&serde_json::json!({"readScope":id,"historyPage":page}))
    }
    .await;
    if result.is_err() && created {
        return operation_and_cleanup(result, owners.close(&id).await);
    }
    result
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct SearchInput {
    query: String,
    workspace_id: Option<String>,
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
    history_cursor: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Match {
    session_id: String,
    event_id: String,
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
    owners: &ReadOwners,
    args: SearchInput,
    cancel: &CancellationToken,
) -> Result<pl_core::tool::ToolOutput> {
    ensure!(
        !args.query.trim().is_empty() && args.query.chars().count() <= 200,
        "query must contain 1 to 200 characters"
    );
    let _ = owners;
    let fingerprint = crate::canonical_content_hash(&serde_json::to_vec(&(
        &args.query,
        &args.workspace_id,
        &args.session_id,
        args.archived,
    ))?);
    let mut cursor = match args.cursor {
        Some(token) => {
            let cursor: Cursor = decode(&token)?;
            ensure!(
                cursor.fingerprint == fingerprint,
                "search cursor belongs to another query"
            );
            cursor
        }
        None => Cursor {
            fingerprint,
            directory_done: args.session_id.is_some(),
            session_id: args.session_id,
            ..Default::default()
        },
    };
    let needle = args.query.to_lowercase();
    let mut matches = Vec::new();
    for _ in 0..32 {
        ensure!(!cancel.is_cancelled(), "search cancelled");
        if cursor.session_id.is_none() {
            if cursor.directory_done {
                break;
            }
            let page = search_read(
                cancel,
                runtime.agent_facility.product_events.query_threads(
                    &crate::ThreadDirectoryQuery {
                        workspace_id: args.workspace_id.clone(),
                        archived: args.archived,
                        ..Default::default()
                    },
                    cursor.directory_cursor.as_deref(),
                    1,
                ),
            )
            .await?;
            let directory = page
                .state
                .value()
                .context("session directory is unavailable")?;
            cursor.directory_cursor = directory.next_cursor.clone();
            cursor.directory_done = directory.next_cursor.is_none();
            cursor.session_id = directory.rows.first().map(|row| row.thread_id.clone());
            if cursor.session_id.is_none() {
                continue;
            }
        }
        let session = cursor
            .session_id
            .clone()
            .context("search session missing")?;
        let reader = search_read(
            cancel,
            runtime.open_history_reader(&session, crate::history::HISTORY_PROTOCOL_VERSION),
        )
        .await?;
        let page = search_read(
            cancel,
            reader.events_page(
                crate::history::HistoryEventsQuery::TextOriginals,
                None,
                cursor.history_cursor.clone(),
                crate::history::HistoryDemand {
                    max_rows: 1,
                    max_bytes: 1024 * 1024,
                },
            ),
        )
        .await?;
        for detail in page.entries {
            if let Some(text) = search_text(&reader, &detail).await?
                && let Some(snippet) = matched_snippet(&text, &needle)
            {
                matches.push(Match {
                    session_id: session.clone(),
                    event_id: detail.event_id.clone(),
                    snippet,
                });
            }
            if matches.len() >= 10 {
                break;
            }
        }
        reader.close().await;
        if matches.len() >= 10 {
            cursor.history_cursor = page.next;
            break;
        }
        if let Some(next) = page.next {
            cursor.history_cursor = Some(next);
        } else {
            cursor.session_id = None;
            cursor.history_cursor = None;
        }
    }
    let complete = cursor.directory_done && cursor.session_id.is_none();
    let token = (!complete).then(|| encode(&cursor)).transpose()?;
    output(&SearchPage {
        matches,
        cursor: token,
        complete,
    })
}

async fn search_text(
    reader: &crate::history::HistoryReader,
    detail: &crate::history::HistoryEventRecord,
) -> Result<Option<String>> {
    if detail.payload_schema != "anywork.event/1" {
        return Ok(None);
    }
    let Ok(envelope) = crate::history::decode_event_envelope(detail) else {
        return Ok(None);
    };
    if envelope.item_type != "text" {
        return Ok(None);
    }
    let Some(bytes) =
        crate::history::read_event_body_bytes(reader, detail, "body", Some(800_000)).await?
    else {
        return Ok(None);
    };
    Ok(Some(String::from_utf8(bytes)?))
}

fn matched_snippet(text: &str, needle: &str) -> Option<String> {
    let folded = text.to_lowercase();
    let offset = folded.find(needle)?;
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_schema_uses_body_references() {
        let schema = read_schema();
        assert!(schema["properties"]["bodyRef"].is_object());
        assert!(schema["properties"]["readBusinessRefs"].is_object());
    }

    #[test]
    fn cursor_token_round_trips_without_accepting_foreign_payloads() {
        let cursor = Cursor {
            fingerprint: "f".into(),
            directory_cursor: None,
            directory_done: false,
            session_id: Some("s".into()),
            history_cursor: Some("h".into()),
        };
        let token = encode(&cursor).unwrap();
        let decoded: Cursor = decode(&token).unwrap();
        assert_eq!(decoded.session_id.as_deref(), Some("s"));
        assert_eq!(decoded.history_cursor.as_deref(), Some("h"));
        let foreign = encode(&Match {
            session_id: "other".into(),
            event_id: "e".into(),
            snippet: "not a cursor".into(),
        })
        .unwrap();
        assert!(decode::<Cursor>(&foreign).is_err());
        assert!(decode::<Cursor>("not-a-token").is_err());
    }
}
