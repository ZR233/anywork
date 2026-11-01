//! Thread-tool owned read qualifications. Only resources and bounded scan progress are retained.
use super::{StudioRuntime, output};
use crate::studio::ConversationReader;
#[cfg(test)]
mod tests;
use anyhow::{Context, Result, ensure};
use base64::Engine;
use pl_protocol::{ChatBatch, ChatScope, ContentRange, ContentRef, ReadDemand};
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
const WINDOW: u32 = 32 * 1024;
#[cfg(test)]
#[derive(Clone, Copy, PartialEq, Eq)]
enum TestBoundary {
    FirstSet,
    SearchRead,
    SearchCommit,
}
#[cfg(test)]
struct TestGate {
    boundary: TestBoundary,
    skip: usize,
    entered: tokio::sync::oneshot::Sender<String>,
    release: tokio::sync::oneshot::Receiver<()>,
}
pub(super) struct ReadOwners {
    readers: Mutex<BTreeMap<String, Arc<ReadResource>>>,
    permits: Arc<Semaphore>,
    stopping: CancellationToken,
    opens: RwLock<()>,
    #[cfg(test)]
    gate: Mutex<Option<TestGate>>,
}
struct ReadResource {
    reader: ConversationReader,
    feed: Mutex<crate::studio::ConversationFeed>,
    cancel: CancellationToken,
    closing: AtomicBool,
    _permit: OwnedSemaphorePermit,
    fingerprint: Option<String>,
    #[cfg(test)]
    close_fault: AtomicBool,
}
impl ReadResource {
    fn request_close(&self) {
        self.closing.store(true, Ordering::Release);
        self.cancel.cancel();
        self.reader.request_close();
    }
    async fn close(&self) -> Result<()> {
        self.request_close();
        #[cfg(test)]
        if self.close_fault.swap(false, Ordering::AcqRel) {
            anyhow::bail!("injected read-resource join failure");
        }
        let (feed, reader) = tokio::join!(
            async { self.feed.lock().await.close().await },
            self.reader.close()
        );
        feed?;
        reader?;
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
            #[cfg(test)]
            gate: Mutex::new(None),
        }
    }
}
fn stale_scope() -> anyhow::Error {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::StaleRevision,
        "Tool read scope is unknown or retired",
        false,
    )
    .with_reason(
        pl_protocol::studio::StudioErrorReason::StaleReadScope,
        serde_json::Value::Null,
    )
    .into()
}
fn search_cancelled() -> anyhow::Error {
    anyhow::anyhow!("search cancelled")
}

async fn cancelled(cancel: Option<&CancellationToken>) {
    match cancel {
        Some(cancel) => cancel.cancelled().await,
        None => std::future::pending().await,
    }
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

async fn search_read<T>(
    cancel: &CancellationToken,
    read: impl std::future::Future<Output = Result<T>>,
) -> Result<T> {
    tokio::select! { biased;
        _=cancel.cancelled()=>Err(search_cancelled()),
        result=read=>result,
    }
}

impl ReadOwners {
    #[cfg(test)]
    async fn arm_test_boundary(
        &self,
        boundary: TestBoundary,
        skip: usize,
    ) -> (
        tokio::sync::oneshot::Receiver<String>,
        tokio::sync::oneshot::Sender<()>,
    ) {
        let (entered, receiver) = tokio::sync::oneshot::channel();
        let (release, released) = tokio::sync::oneshot::channel();
        *self.gate.lock().await = Some(TestGate {
            boundary,
            skip,
            entered,
            release: released,
        });
        (receiver, release)
    }

    #[cfg(test)]
    async fn test_boundary(&self, boundary: TestBoundary, id: &str) {
        let gate = {
            let mut slot = self.gate.lock().await;
            if let Some(gate) = slot.as_mut() {
                if gate.boundary != boundary {
                    return;
                }
                if gate.skip > 0 {
                    gate.skip -= 1;
                    return;
                }
            }
            slot.take()
        };
        if let Some(gate) = gate {
            let _ = gate.entered.send(id.to_owned());
            let _ = gate.release.await;
        }
    }

    async fn open(
        &self,
        runtime: &StudioRuntime,
        session: &str,
        demand: ReadDemand,
        fingerprint: Option<&str>,
        cancel: Option<&CancellationToken>,
    ) -> Result<(ConversationReader, ChatBatch)> {
        let _open = tokio::select! { biased; _=self.stopping.cancelled()=>return Err(stale_scope()),open=self.opens.read()=>open };
        if self.stopping.is_cancelled() {
            return Err(stale_scope());
        }
        let permit = self.permits.clone().try_acquire_owned().map_err(|_| {
            pl_core::chat::ChatError::Overloaded(
                "close an existing tool read scope before opening another".into(),
            )
        })?;
        let feed = tokio::select! { biased;
            _=self.stopping.cancelled()=>return Err(stale_scope()),
            _=cancelled(cancel)=>return Err(search_cancelled()),
            result=runtime.open_conversation_feed(session, ChatScope::Main, demand)=>result?,
        };
        let reader = feed.reader().clone();
        let resource = Arc::new(ReadResource {
            cancel: feed.cancellation_token(),
            reader: reader.clone(),
            feed: Mutex::new(feed),
            closing: AtomicBool::new(false),
            _permit: permit,
            fingerprint: fingerprint.map(str::to_owned),
            #[cfg(test)]
            close_fault: AtomicBool::new(false),
        });
        self.readers
            .lock()
            .await
            .insert(reader.subscription_id().into(), resource.clone());
        let first = tokio::select! { biased;
            _=self.stopping.cancelled()=>Err(stale_scope()),
            _=cancelled(cancel)=>Err(search_cancelled()),
            result=async {
                #[cfg(test)]
                self.test_boundary(TestBoundary::FirstSet, reader.subscription_id()).await;
                let mut feed = resource.feed.lock().await;
                match feed.recv().await? {
                    Some(crate::studio::ConversationEvent::Chat { batch }) => Ok(*batch),
                    _ => anyhow::bail!("conversation did not open with Set"),
                }
            }=>result,
        };
        let first = first.and_then(|batch| {
            if self.stopping.is_cancelled() {
                Err(stale_scope())
            } else if cancel.is_some_and(CancellationToken::is_cancelled) {
                Err(search_cancelled())
            } else {
                Ok(batch)
            }
        });
        match first {
            Ok(first) => Ok((reader, first)),
            Err(error) => {
                operation_and_cleanup(Err(error), self.close(reader.subscription_id()).await)
            }
        }
    }
    async fn get(
        &self,
        id: &str,
        session: &str,
        fingerprint: Option<&str>,
    ) -> Result<ConversationReader> {
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
            !resource.closing.load(Ordering::Acquire)
                && resource.reader.thread_id() == session
                && resource.fingerprint.as_deref() == fingerprint,
            stale_scope()
        );
        Ok(resource.reader.clone())
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
        let resource = self
            .readers
            .lock()
            .await
            .get(id)
            .cloned()
            .ok_or_else(stale_scope)?;
        ensure!(resource.reader.thread_id() == session, stale_scope());
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
    read_scope: Option<String>,
    before: Option<String>,
    #[schemars(with = "Option<serde_json::Value>")]
    demand: Option<ReadDemand>,
    item_id: Option<String>,
    continuation: Option<String>,
    #[schemars(with = "Option<serde_json::Value>")]
    reference: Option<ContentRef>,
    #[schemars(with = "Option<serde_json::Value>")]
    collection: Option<pl_protocol::CurrentCollectionRef>,
    #[schemars(with = "Option<serde_json::Value>")]
    range: Option<ContentRange>,
    #[serde(default)]
    close_read_scope: bool,
}
pub(super) fn read_schema() -> serde_json::Value {
    let mut schema = schemars::schema_for!(ReadInput).to_value();
    schema["properties"]["demand"] = serde_json::json!({"anyOf":[{"type":"object","required":["maxItems","maxBytes"],"additionalProperties":false,"properties":{
        "maxItems":{"type":"integer","minimum":1,"maximum":pl_protocol::CHAT_READ_MAX_ITEMS},
        "maxBytes":{"type":"integer","minimum":1,"maximum":pl_protocol::CHAT_BATCH_MAX_BYTES}}},{"type":"null"}]});
    schema["properties"]["reference"] = serde_json::json!({"anyOf":[{"type":"object","description":"Copy the canonical ContentRef from the Chat envelope or manifest unchanged."},{"type":"null"}]});
    schema["properties"]["collection"] = serde_json::json!({"anyOf":[{"type":"object","description":"Copy a CurrentCollectionRef from this readScope's Chat.current unchanged; demand and continuation select a bounded page."},{"type":"null"}]});
    schema["properties"]["range"] = serde_json::json!({"anyOf":[{"type":"object","required":["offset","maxBytes"],"additionalProperties":false,"properties":{
        "offset":{"type":"integer","minimum":0},"maxBytes":{"type":"integer","minimum":1,"maximum":pl_protocol::CONTENT_WINDOW_MAX_BYTES}}},{"type":"null"}]});
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
    let (reader, batch) = owners
        .open(runtime, session, demand(16)?, None, None)
        .await?;
    let resource = owners
        .readers
        .lock()
        .await
        .get(reader.subscription_id())
        .cloned()
        .ok_or_else(stale_scope)?;
    let result=async {
        let current=batch.current.context("Main Set has no current")?;
        let snapshot=match resource.feed.lock().await.recv().await? {
            Some(crate::studio::ConversationEvent::State { update })=>match *update {
                pl_protocol::ThreadSubscriptionUpdate::Snapshot { snapshot }=>snapshot,
                _=>anyhow::bail!("Get did not receive the registered State baseline"),
            },
            _=>anyhow::bail!("Get did not receive the registered State baseline"),
        };
        let mut pending=Vec::new();let mut pending_more=false;
        if let Some(reference)=current.interactions.as_ref() {
            let page=reader.page_current(reference,None,ReadDemand { max_items:32,max_bytes:64*1024 }).await?;
            pending_more=page.continuation.is_some();
            for entry in page.entries {
                let interaction=match entry.payload {
                    pl_protocol::PayloadData::Inline { bytes }=>serde_json::from_slice::<pl_protocol::InteractionRequest>(&bytes).ok(),
                    pl_protocol::PayloadData::Deferred { .. }=>None,
                };
                let value=if let Some(interaction)=interaction {
                    let kind=match &interaction.content { pl_protocol::InteractionContent::UserInput(_)=>"userInput",pl_protocol::InteractionContent::ToolApproval(_)=>"toolApproval" };
                    serde_json::json!({"interactionId":interaction.interaction_id,"kind":kind,"revision":interaction.revision,
                        "scope":interaction.scope,"summary":super::interaction_summary(&interaction.content)})
                } else { serde_json::json!({"interactionId":entry.id,"detailsDeferred":true}) };
                pending.push(value);
            }
        }
        let execution=batch.messages.into_iter().rev().filter_map(|message| {
            match message.payload {
                pl_protocol::PayloadData::Deferred { .. }=>Some(serde_json::json!({"id":message.id,"kind":"deferred"})),
                pl_protocol::PayloadData::Inline { bytes }=>match serde_json::from_slice::<serde_json::Value>(&bytes) {
                    Ok(value) if matches!(value["type"].as_str(),Some("turn"|"inference"))=>Some(serde_json::json!({"id":message.id,"kind":value["type"],
                        "turnId":value.get("turnId"),"sourceEffectSeq":value.get("sourceEffectSeq"),"sealedAt":value.get("sealedAt")})),
                    Err(_)=>Some(serde_json::json!({"id":message.id,"kind":"malformed"})),
                    _=>None,
                },
            }
        }).take(4).collect::<Vec<_>>();
        // No ContentRef/collection continuation escapes this short-lived Get qualification.
        output(&serde_json::json!({"thread":snapshot.thread,"activeTurn":current.active_turn,"activity":current.active,
            "logicalStatus":current.logical_status,"executionPresent":current.execution_present,
            "plan":current.plan.map(|plan|serde_json::json!({"revision":plan.revision,"phase":plan.phase})),
            "model":snapshot.model_route,"storage":snapshot.storage,
            "pending":pending,"pendingHasMore":pending_more,"recentExecution":execution}))
    }.await;
    owners.close(reader.subscription_id()).await?;
    result
}

async fn text_reference(reader: &ConversationReader, item: &str) -> Result<Option<ContentRef>> {
    let page = reader
        .list_contents(
            item,
            None,
            ReadDemand {
                max_items: 1,
                max_bytes: 16 * 1024,
            },
        )
        .await?;
    Ok(page
        .entries
        .into_iter()
        .find(|entry| entry.key == "body")
        .map(|entry| entry.reference))
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
    if args.reference.is_some() {
        ensure!(
            args.range.is_some()
                && args.before.is_none()
                && args.continuation.is_none()
                && args.item_id.is_none()
                && args.collection.is_none(),
            "ContentRef reads require only range and the original readScope"
        );
    } else {
        ensure!(args.range.is_none(), "range requires a ContentRef");
        args.demand
            .context("demand is required for a chat, manifest or current page")?
            .validate(1)?;
        ensure!(
            args.item_id.is_none() || args.collection.is_none(),
            "choose one manifest or current collection"
        );
        ensure!(
            args.before.is_none() || (args.item_id.is_none() && args.collection.is_none()),
            "before belongs only to a Chat page"
        );
    }
    let page_demand = args.demand.unwrap_or(ReadDemand {
        max_items: 1,
        max_bytes: 64 * 1024,
    });
    let (reader, initial) = if let Some(id) = args.read_scope.as_deref() {
        (owners.get(id, &args.session_id, None).await?, None)
    } else {
        if args.before.is_some() || args.continuation.is_some() {
            return Err(stale_scope());
        }
        let (reader, page) = owners
            .open(runtime, &args.session_id, page_demand, None, None)
            .await?;
        (reader, Some(page))
    };
    let id = reader.subscription_id();
    let created = initial.is_some();
    let result = async {
        if let Some(reference) = args.reference {
            ensure!(
                args.before.is_none() && args.continuation.is_none() && args.item_id.is_none(),
                "range reads do not accept page or manifest cursors"
            );
            let range = args.range.context("range is required with reference")?;
            let window = reader.read_content(&reference, range).await?;
            return output(&serde_json::json!({"readScope":id,"window":window}));
        }
        ensure!(args.range.is_none(), "range requires a ContentRef");
        if let Some(reference) = args.collection {
            let page = reader
                .page_current(
                    &reference,
                    args.continuation.as_deref(),
                    args.demand
                        .context("demand is required for a current page")?,
                )
                .await
                .map_err(scope_cursor_error)?;
            return output(&serde_json::json!({"readScope":id,"currentPage":page}));
        }
        if let Some(item) = args.item_id {
            ensure!(args.before.is_none(), "before cannot be used with itemId");
            let page = reader
                .list_contents(
                    &item,
                    args.continuation.as_deref(),
                    args.demand
                        .context("demand is required for a manifest page")?,
                )
                .await
                .map_err(scope_cursor_error)?;
            return output(&serde_json::json!({"readScope":id,"itemId":item,"manifest":page}));
        }
        ensure!(
            args.continuation.is_none(),
            "manifest continuation requires itemId"
        );
        let demand = args.demand.context("demand is required for a chat page")?;
        let batch = if let Some(before) = args.before {
            reader
                .load_older(&before, demand)
                .await
                .map_err(scope_cursor_error)?
        } else {
            initial.context("an existing read scope requires before, itemId or reference")?
        };
        output(&serde_json::json!({"readScope":id,"chat":batch}))
    }
    .await;
    if result.is_err() && created {
        return operation_and_cleanup(result, owners.close(id).await);
    }
    result
}

fn scope_cursor_error(error: anyhow::Error) -> anyhow::Error {
    if matches!(
        error.downcast_ref::<pl_core::chat::ChatError>(),
        Some(pl_core::chat::ChatError::InvalidArgument(_))
    ) {
        stale_scope().context(error)
    } else {
        error
    }
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
    read_scope_id: Option<String>,
    before: Option<String>,
    pending: Option<PendingText>,
}
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct PendingText {
    item_id: String,
    reference: ContentRef,
    offset: u64,
    generation: Option<String>,
    overlap: String,
    utf8_tail: Vec<u8>,
    next_before: Option<String>,
    end_of_session: bool,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Match {
    session_id: String,
    item_id: String,
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
    cancel: &tokio_util::sync::CancellationToken,
) -> Result<pl_core::tool::ToolOutput> {
    ensure!(
        !args.query.trim().is_empty() && args.query.chars().count() <= 200,
        "query must contain 1 to 200 characters"
    );
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
    let borrowed = cursor.read_scope_id.clone();
    let mut opened = Vec::new();
    let operation = async {
        let needle = args.query.to_lowercase();
        let overlap_chars = needle.chars().count();
        let mut matches = Vec::new();
        // One scan step is one message or one actual bounded content window, never a full payload read.
        for _ in 0..32 {
            ensure!(!cancel.is_cancelled(), "search cancelled");
            if cursor.session_id.is_none() {
                if cursor.directory_done {
                    break;
                }
                let page = search_read(
                    cancel,
                    runtime.agent_facility.product_events.query_threads(
                        &pl_protocol::studio::ThreadDirectoryQuery {
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
                cursor.session_id = directory.threads.first().map(|thread| thread.id.clone());
                if cursor.session_id.is_none() {
                    continue;
                }
            }
            let session_id = cursor
                .session_id
                .clone()
                .context("search session missing")?;
            let (reader, initial) = match cursor.read_scope_id.as_deref() {
                Some(id) => (
                    owners
                        .get(id, &session_id, Some(&cursor.fingerprint))
                        .await?,
                    None,
                ),
                None => {
                    let (reader, page) = owners
                        .open(
                            runtime,
                            &session_id,
                            demand(1)?,
                            Some(&cursor.fingerprint),
                            Some(cancel),
                        )
                        .await?;
                    let id = reader.subscription_id().to_owned();
                    opened.push(id.clone());
                    cursor.read_scope_id = Some(id);
                    (reader, Some(page))
                }
            };
            #[cfg(test)]
            search_read(cancel, async {
                owners
                    .test_boundary(TestBoundary::SearchRead, reader.subscription_id())
                    .await;
                Ok(())
            })
            .await?;
            if cursor.pending.is_none() {
                let page = if let Some(page) = initial {
                    page
                } else if let Some(before) = cursor.before.as_deref() {
                    search_read(cancel, reader.load_older(before, demand(1)?)).await?
                } else {
                    anyhow::bail!("search lost its original exclusive boundary");
                };
                let end = page.before.is_none();
                let Some(item) = page.messages.first() else {
                    advance(&mut cursor, page.before, end);
                    continue;
                };
                let Some(reference) =
                    search_read(cancel, text_reference(&reader, &item.id)).await?
                else {
                    advance(&mut cursor, page.before, end);
                    continue;
                };
                cursor.pending = Some(PendingText {
                    item_id: item.id.clone(),
                    reference,
                    offset: 0,
                    generation: None,
                    overlap: String::new(),
                    utf8_tail: Vec::new(),
                    next_before: page.before,
                    end_of_session: end,
                });
            }
            let mut pending = cursor.pending.take().context("search text missing")?;
            let window = search_read(
                cancel,
                reader.read_content(
                    &pending.reference,
                    ContentRange {
                        offset: pending.offset,
                        max_bytes: WINDOW,
                    },
                ),
            )
            .await?;
            ensure!(
                pending
                    .generation
                    .as_ref()
                    .is_none_or(|generation| generation == &window.generation),
                pl_core::chat::ChatError::StaleContent
            );
            pending.generation = Some(window.generation);
            pending.offset += window.bytes.len() as u64;
            let mut bytes = pending.utf8_tail;
            bytes.extend_from_slice(&window.bytes);
            let (valid, tail) = match std::str::from_utf8(&bytes) {
                Ok(text) => (text, Vec::new()),
                Err(error) if error.error_len().is_none() => {
                    let at = error.valid_up_to();
                    (std::str::from_utf8(&bytes[..at])?, bytes[at..].to_vec())
                }
                Err(error) => return Err(error.into()),
            };
            let text = pending.overlap + valid;
            if let Some(snippet) = matched_snippet(&text, &needle) {
                matches.push(Match {
                    session_id,
                    item_id: pending.item_id,
                    snippet,
                });
                advance(&mut cursor, pending.next_before, pending.end_of_session);
            } else if pending.offset < window.available_through {
                ensure!(!window.bytes.is_empty(), "content window did not advance");
                pending.utf8_tail = tail;
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
                ensure!(tail.is_empty(), "sealed text ends with incomplete UTF-8");
                advance(&mut cursor, pending.next_before, pending.end_of_session);
            }
            if matches.len() >= 10 {
                break;
            }
        }
        let complete = cursor.directory_done && cursor.session_id.is_none();
        let token = (!complete).then(|| encode(&cursor)).transpose()?;
        let result = output(&SearchPage {
            matches,
            cursor: token,
            complete,
        })?;
        #[cfg(test)]
        search_read(cancel, async {
            owners
                .test_boundary(
                    TestBoundary::SearchCommit,
                    cursor
                        .read_scope_id
                        .as_deref()
                        .or(borrowed.as_deref())
                        .unwrap_or(""),
                )
                .await;
            Ok(())
        })
        .await?;
        ensure!(!cancel.is_cancelled(), "search cancelled");
        Ok(result)
    }
    .await;

    let result = match operation {
        Ok(result) => result,
        Err(error) => {
            return operation_and_cleanup(Err(error), close_scopes(owners, &opened).await);
        }
    };
    // Result encoding has succeeded. Commit retirement without cancelling joins. An input cursor
    // is borrowed until this boundary; new scopes belong to this call until its output is returned.
    let keep = cursor.read_scope_id.as_deref();
    let retired = opened
        .iter()
        .filter(|id| Some(id.as_str()) != keep)
        .cloned()
        .collect::<Vec<_>>();
    let transferred = opened
        .iter()
        .filter(|id| Some(id.as_str()) == keep)
        .cloned()
        .collect::<Vec<_>>();
    if let Err(error) = close_scopes(owners, &retired).await {
        return operation_and_cleanup(Err(error), close_scopes(owners, &transferred).await);
    }
    if let Some(id) = borrowed.as_deref().filter(|id| Some(*id) != keep)
        && let Err(error) = owners.close(id).await
    {
        return operation_and_cleanup(Err(error), close_scopes(owners, &transferred).await);
    }
    Ok(result)
}

async fn close_scopes(owners: &ReadOwners, ids: &[String]) -> Result<()> {
    let mut failure: Option<anyhow::Error> = None;
    for id in ids {
        if let Err(error) = owners.close(id).await {
            failure = Some(match failure {
                Some(previous) => {
                    previous.context(format!("another read scope cleanup failed: {error:#}"))
                }
                None => error,
            });
        }
    }
    match failure {
        Some(error) => Err(error),
        None => Ok(()),
    }
}

fn advance(cursor: &mut Cursor, before: Option<String>, end: bool) {
    cursor.before = before;
    cursor.pending = None;
    if end {
        cursor.session_id = None;
        cursor.read_scope_id = None;
    }
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
