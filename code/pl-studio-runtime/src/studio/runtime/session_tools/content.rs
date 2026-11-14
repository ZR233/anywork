//! Thread-tool owned read qualifications. Only resources and bounded scan progress are retained.
use super::{StudioRuntime, output};
use crate::studio::ConversationReader;

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
    BeforeOpen,
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
        self.open_scoped(
            runtime,
            session,
            ChatScope::conversation(None),
            demand,
            fingerprint,
            cancel,
        )
        .await
    }

    async fn open_scoped(
        &self,
        runtime: &StudioRuntime,
        session: &str,
        scope: ChatScope,
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
            result=async {
                #[cfg(test)]
                self.test_boundary(TestBoundary::BeforeOpen, session).await;
                runtime.open_conversation_feed(session, scope, demand).await
            }=>result?,
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
    #[schemars(with = "Option<serde_json::Value>")]
    scope: Option<ChatScope>,
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
    read_business_refs: bool,
    #[serde(default)]
    close_read_scope: bool,
}
pub(super) fn read_schema() -> serde_json::Value {
    let mut schema = pl_agent_tool::typed::input_schema_for::<ReadInput>();
    schema["properties"]["demand"] = serde_json::json!({"anyOf":[{"type":"object","required":["maxItems","maxBytes"],"additionalProperties":false,"properties":{
        "maxItems":{"type":"integer","minimum":1,"maximum":pl_protocol::CHAT_READ_MAX_ITEMS},
        "maxBytes":{"type":"integer","minimum":1,"maximum":pl_protocol::CHAT_BATCH_MAX_BYTES}}},{"type":"null"}]});
    schema["properties"]["reference"] = serde_json::json!({"anyOf":[{"type":"object","description":"Copy the canonical ContentRef from the Chat envelope or manifest unchanged."},{"type":"null"}]});
    schema["properties"]["scope"] = serde_json::json!({
        "description": "Select only when opening a scope; omit for Main. Copy a returned run reference unchanged. Children requires a real encoded business parentId, not a display run.",
        "anyOf": [
            {"type":"object","required":["kind"],"additionalProperties":false,
             "properties":{"kind":{"type":"string","enum":["main"]}}},
            {"type":"object","required":["kind","reference"],"additionalProperties":false,
             "properties":{"kind":{"type":"string","enum":["run"]},
                "reference":{"type":"object","required":["databaseId","indexVersion","startSeq"],
                    "additionalProperties":false,"properties":{
                        "databaseId":{"type":"string","minLength":1},
                        "indexVersion":{"type":"integer","enum":[pl_protocol::COMPLETED_READ_INDEX_VERSION]},
                        "startSeq":{"type":"integer","minimum":1,"maximum":i64::MAX}}}}},
            {"type":"object","required":["kind","parentId"],"additionalProperties":false,
             "properties":{"kind":{"type":"string","enum":["children"]},
                "parentId":{"type":"string","minLength":1}}},
            {"type":"null"}
        ]
    });
    schema["properties"]["collection"] = serde_json::json!({"anyOf":[{"type":"object","description":"Copy a canonical CurrentCollectionRef unchanged; demand and continuation select a bounded page."},{"type":"null"}]});
    schema["properties"]["readBusinessRefs"]["description"] = serde_json::json!(
        "Read the current Plan and interaction resource heads on this readScope; no demand or content cursor is required."
    );
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
    let result = async {
        let activity = initial_activity(&resource, batch.through_seq).await?;
        // Get is a one-shot business query, including the original small
        // runtime/activity summary. It does not refresh a GUI subscription.
        let snapshot = runtime.thread_snapshot(session).await?;
        ensure!(snapshot.thread.id == session, "Get state identity conflict");
        // A one-shot content tool reads the same domain heads that State
        // publishes. Activity and history do not confer interaction authority.
        let references = reader.read_business_refs().await?;
        let mut pending = Vec::new();
        let mut pending_more = false;
        if let Some(reference) = &references.interactions {
            let page = reader
                .page_current(
                    reference,
                    None,
                    ReadDemand {
                        max_items: 32,
                        max_bytes: 64 * 1024,
                    },
                )
                .await?;
            pending_more = page.continuation.is_some();
            for entry in page.entries {
                let interaction =
                    match entry.payload {
                        pl_protocol::PayloadData::Inline { bytes } => Some(
                            serde_json::from_slice::<pl_protocol::InteractionRequest>(&bytes)?,
                        ),
                        pl_protocol::PayloadData::Deferred { .. } => None,
                    };
                let value = if let Some(interaction) = interaction {
                    let kind = match &interaction.content {
                        pl_protocol::InteractionContent::UserInput(_) => "userInput",
                        pl_protocol::InteractionContent::ToolApproval(_) => "toolApproval",
                    };
                    serde_json::json!({"interactionId":interaction.interaction_id,"kind":kind,
                        "revision":interaction.revision,"scope":interaction.scope,
                        "summary":super::interaction_summary(&interaction.content)})
                } else {
                    serde_json::json!({"interactionId":entry.id,"detailsDeferred":true})
                };
                pending.push(value);
            }
        }
        let execution = batch
            .entries
            .into_iter()
            .rev()
            .take(4)
            .map(|entry| {
                let atom = entry.atom;
                let outcome = match &atom.lifecycle {
                    pl_protocol::ChatAtomLifecycle::Terminal { outcome, .. } => Some(*outcome),
                    pl_protocol::ChatAtomLifecycle::Active { .. } => None,
                };
                serde_json::json!({"id":entry.record_id,"kind":atom.kind,"turnId":atom.turn_id,
                "startedAt":atom.started_at,"finishedAt":atom.finished_at,"outcome":outcome,
                "mainPresentation":entry.main_presentation,"tool":atom.tool})
            })
            .collect::<Vec<_>>();
        let plan = references
            .plan
            .map(|plan| serde_json::json!({"revision":plan.revision,"phase":plan.phase}));
        output(
            &serde_json::json!({"thread":snapshot.thread,"activeTurn":snapshot.active_turn,
            "activity":snapshot.activity,"logicalStatus":snapshot.thread.status,
            "executionPresent":activity.execution_present,"plan":plan,
            "model":snapshot.model_route,"storage":snapshot.storage,
            "pending":pending,"pendingHasMore":pending_more,"recentExecution":execution}),
        )
    }
    .await;
    operation_and_cleanup(result, owners.close(reader.subscription_id()).await)
}

async fn initial_activity(
    resource: &ReadResource,
    through_seq: u64,
) -> Result<Arc<pl_protocol::ActivitySnapshot>> {
    let mut feed = resource.feed.lock().await;
    match feed.recv().await? {
        Some(crate::studio::ConversationEvent::Activity { snapshot }) => {
            ensure!(
                snapshot.completed_through == through_seq,
                "initial Activity completion prefix conflict"
            );
            Ok(snapshot)
        }
        _ => anyhow::bail!("missing initial Activity snapshot"),
    }
}

async fn opened_facts(
    runtime: &StudioRuntime,
    session: &str,
    resource: &ReadResource,
    through_seq: u64,
) -> Result<(
    pl_protocol::ThreadSnapshot,
    Arc<pl_protocol::ActivitySnapshot>,
)> {
    let activity = initial_activity(resource, through_seq).await?;
    // One-shot tool output reads the point-in-time helper. It does not open a second assembler.
    let state = runtime.thread_snapshot(session).await?;
    Ok((state, activity))
}

#[cfg(test)]
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
    ensure!(
        args.read_scope.is_none() || args.scope.is_none(),
        "scope is only accepted when opening a read scope"
    );
    if args.close_read_scope {
        let id = args
            .read_scope
            .context("readScope is required with closeReadScope")?;
        owners.close_target(&id, &args.session_id).await?;
        return output(&serde_json::json!({"readScope":id,"closed":true}));
    }
    if args.read_business_refs {
        ensure!(
            args.reference.is_none()
                && args.range.is_none()
                && args.before.is_none()
                && args.continuation.is_none()
                && args.item_id.is_none()
                && args.collection.is_none(),
            "business head reads do not accept content or page selectors"
        );
    } else if args.reference.is_some() {
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
            .open_scoped(
                runtime,
                &args.session_id,
                args.scope.unwrap_or(ChatScope::conversation(None)),
                page_demand,
                None,
                None,
            )
            .await?;
        (reader, Some(page))
    };
    let id = reader.subscription_id();
    let created = initial.is_some();
    let result = async {
        if args.read_business_refs {
            let references = reader.read_business_refs().await?;
            if let Some(batch) = initial {
                let resource = owners
                    .readers
                    .lock()
                    .await
                    .get(id)
                    .cloned()
                    .ok_or_else(stale_scope)?;
                let (state, activity) =
                    opened_facts(runtime, &args.session_id, &resource, batch.through_seq).await?;
                return output(&serde_json::json!({"readScope":id,"chat":batch,
                    "state":state,"activity":activity,"businessRefs":references}));
            }
            return output(&serde_json::json!({"readScope":id,"businessRefs":references}));
        }
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
        if created {
            let resource = owners
                .readers
                .lock()
                .await
                .get(id)
                .cloned()
                .ok_or_else(stale_scope)?;
            let (state, activity) =
                opened_facts(runtime, &args.session_id, &resource, batch.through_seq).await?;
            output(
                &serde_json::json!({"readScope":id,"chat":batch,"state":state,"activity":activity}),
            )
        } else {
            output(&serde_json::json!({"readScope":id,"chat":batch}))
        }
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
    #[serde(default)]
    run: Option<RunCursor>,
}
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RunCursor {
    read_scope_id: String,
    before: Option<String>,
    next_main_before: Option<String>,
    end_of_session: bool,
    through_seq: u64,
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
    manifest_continuation: Option<String>,
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
    let borrowed = cursor
        .read_scope_id
        .iter()
        .chain(cursor.run.iter().map(|run| &run.read_scope_id))
        .cloned()
        .collect::<Vec<_>>();
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
                cursor.session_id = directory.rows.first().map(|row| row.thread_id.clone());
                if cursor.session_id.is_none() {
                    continue;
                }
            }
            let session_id = cursor
                .session_id
                .clone()
                .context("search session missing")?;
            let (mut reader, initial) = match cursor.read_scope_id.as_deref() {
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
                    let resource = owners
                        .readers
                        .lock()
                        .await
                        .get(reader.subscription_id())
                        .cloned()
                        .ok_or_else(stale_scope)?;
                    search_read(cancel, initial_activity(&resource, page.through_seq)).await?;
                    (reader, Some(page))
                }
            };
            let initial = if let Some(run) = &cursor.run {
                reader = owners
                    .get(&run.read_scope_id, &session_id, Some(&cursor.fingerprint))
                    .await?;
                None
            } else {
                initial
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
                let before = cursor
                    .run
                    .as_ref()
                    .and_then(|run| run.before.as_deref())
                    .or(cursor.before.as_deref());
                let mut page = if let Some(page) = initial {
                    page
                } else if let Some(before) = before {
                    search_read(cancel, reader.load_older(before, demand(1)?)).await?
                } else {
                    anyhow::bail!("search lost its original exclusive boundary");
                };
                if cursor.run.is_none()
                    && let Some(entry) = page.entries.first()
                    && matches!(
                        entry.main_presentation,
                        pl_protocol::MainPresentation::ForegroundWork
                            | pl_protocol::MainPresentation::BackgroundResults
                    )
                {
                    let Some(pl_protocol::PayloadData::Deferred { reference, .. }) =
                        &entry.atom.payload
                    else {
                        anyhow::bail!("work representative has no canonical database reference");
                    };
                    let run = entry.run.context("work representative has no run index")?;
                    let (run_reader, first) = owners
                        .open_scoped(
                            runtime,
                            &session_id,
                            ChatScope::Run {
                                reference: pl_protocol::CompletionRunRef {
                                    database_id: reference.database_id.clone(),
                                    index_version: pl_protocol::COMPLETED_READ_INDEX_VERSION,
                                    start_seq: run.start_seq,
                                },
                            },
                            demand(1)?,
                            Some(&cursor.fingerprint),
                            Some(cancel),
                        )
                        .await?;
                    let id = run_reader.subscription_id().to_owned();
                    opened.push(id.clone());
                    let resource = owners
                        .readers
                        .lock()
                        .await
                        .get(&id)
                        .cloned()
                        .ok_or_else(stale_scope)?;
                    search_read(cancel, initial_activity(&resource, first.through_seq)).await?;
                    cursor.run = Some(RunCursor {
                        read_scope_id: id,
                        before: None,
                        next_main_before: page.before.clone(),
                        end_of_session: page.before.is_none(),
                        through_seq: page.through_seq,
                    });
                    reader = run_reader;
                    page = first;
                }
                let end = page.before.is_none();
                let Some(item) = page.entries.first().filter(|entry| {
                    cursor
                        .run
                        .as_ref()
                        .is_none_or(|run| entry.completion_seq <= run.through_seq)
                }) else {
                    advance(&mut cursor, page.before, end);
                    continue;
                };
                let manifest = search_read(
                    cancel,
                    reader.list_contents(&item.record_id, None, demand(1)?),
                )
                .await?;
                let Some(content) = manifest.entries.into_iter().next() else {
                    ensure!(
                        manifest.continuation.is_none(),
                        "empty manifest did not advance"
                    );
                    advance(&mut cursor, page.before, end);
                    continue;
                };
                cursor.pending = Some(PendingText {
                    item_id: item.record_id.clone(),
                    reference: content.reference,
                    offset: 0,
                    generation: None,
                    overlap: String::new(),
                    utf8_tail: Vec::new(),
                    next_before: page.before,
                    end_of_session: end,
                    manifest_continuation: manifest.continuation,
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
            let mut bytes = std::mem::take(&mut pending.utf8_tail);
            bytes.extend_from_slice(&window.bytes);
            let (valid, tail) = match std::str::from_utf8(&bytes) {
                Ok(text) => (text, Vec::new()),
                Err(error) if error.error_len().is_none() => {
                    let at = error.valid_up_to();
                    (std::str::from_utf8(&bytes[..at])?, bytes[at..].to_vec())
                }
                Err(error) => return Err(error.into()),
            };
            let text = std::mem::take(&mut pending.overlap) + valid;
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
                if let Some(continuation) = pending.manifest_continuation.take() {
                    let manifest = search_read(
                        cancel,
                        reader.list_contents(&pending.item_id, Some(&continuation), demand(1)?),
                    )
                    .await?;
                    ensure!(
                        manifest.continuation.as_deref() != Some(continuation.as_str()),
                        "manifest cursor did not advance"
                    );
                    if let Some(content) = manifest.entries.into_iter().next() {
                        pending.reference = content.reference;
                        pending.offset = 0;
                        pending.generation = None;
                        pending.manifest_continuation = manifest.continuation;
                        cursor.pending = Some(pending);
                    } else {
                        ensure!(
                            manifest.continuation.is_none(),
                            "empty manifest did not advance"
                        );
                        advance(&mut cursor, pending.next_before, pending.end_of_session);
                    }
                } else {
                    advance(&mut cursor, pending.next_before, pending.end_of_session);
                }
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
                        .or(borrowed.first().map(String::as_str))
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
    let keep = cursor
        .read_scope_id
        .iter()
        .chain(cursor.run.iter().map(|run| &run.read_scope_id))
        .collect::<Vec<_>>();
    let retired = opened
        .iter()
        .filter(|id| !keep.contains(id))
        .cloned()
        .collect::<Vec<_>>();
    let transferred = opened
        .iter()
        .filter(|id| keep.contains(id))
        .cloned()
        .collect::<Vec<_>>();
    if let Err(error) = close_scopes(owners, &retired).await {
        return operation_and_cleanup(Err(error), close_scopes(owners, &transferred).await);
    }
    for id in borrowed.iter().filter(|id| !keep.contains(id)) {
        if let Err(error) = owners.close(id).await {
            return operation_and_cleanup(Err(error), close_scopes(owners, &transferred).await);
        }
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
    cursor.pending = None;
    if let Some(run) = &mut cursor.run {
        run.before = before;
        if !end {
            return;
        }
        let run = cursor.run.take().expect("owned run cursor");
        advance(cursor, run.next_main_before, run.end_of_session);
        return;
    }
    cursor.before = before;
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

#[cfg(test)]
mod tests {
    use super::*;

    use crate::runtime_test_support as support;

    /// Build the required fields of the advertised scope branch, then let the
    /// production argument decoder and real reader prove that it is callable.
    fn advertised_scope(kind: &str, values: serde_json::Value) -> Result<serde_json::Value> {
        let schema = read_schema();
        let branch = schema["properties"]["scope"]["anyOf"]
            .as_array()
            .context("scope alternatives")?
            .iter()
            .find(|branch| {
                branch["properties"]["kind"]["enum"]
                    .as_array()
                    .is_some_and(|variants| variants.iter().any(|value| value == kind))
            })
            .context("advertised scope kind")?;
        let mut scope = serde_json::json!({"kind":kind});
        for key in branch["required"]
            .as_array()
            .context("scope required fields")?
        {
            let key = key.as_str().context("required field name")?;
            if key != "kind" {
                scope[key] = values
                    .get(key)
                    .with_context(|| format!("missing advertised field {key}"))?
                    .clone();
            }
        }
        Ok(scope)
    }

    #[tokio::test]
    async fn run_read_and_search_cover_nonrepresentative_members_and_release_scopes() -> Result<()>
    {
        use pl_provider_fixture::Reply;
        use serde_json::json;
        let mut events = vec![
            json!({"type":"response.created","response":{"id":"search-run","model":support::MODEL}}),
        ];
        for index in 0..40 {
            let id = format!("search-reason-{index}");
            let text = if index == 20 {
                "only-inside-member"
            } else {
                "ordinary reasoning"
            };
            events.extend([
            json!({"type":"response.output_item.added","output_index":index,
                "item":{"id":id,"type":"reasoning","summary":[],"content":[]}}),
            json!({"type":"response.reasoning_summary_text.delta","output_index":index,
                "item_id":id,"summary_index":0,"delta":text}),
            json!({"type":"response.output_item.done","output_index":index,
                "item":{"id":id,"type":"reasoning","summary":[{"type":"summary_text","text":text}]}}),
        ]);
        }
        for mut event in
            pl_provider_fixture::responses_text("final answer", "search-run", support::MODEL)
                .into_iter()
                .skip(1)
        {
            if let Some(index) = event
                .get("output_index")
                .and_then(serde_json::Value::as_u64)
            {
                event["output_index"] = (index + 40).into();
            }
            events.push(event);
        }
        let env = support::Environment::new(
            vec![support::prompt_step(
                "search-run-members",
                0,
                Reply::Sse(events),
            )],
            vec![],
        )
        .await?;
        let result = async {
        let thread = env
            .start(
                pl_protocol::ThreadWorkspaceMode::Local,
                "search-run-members",
            )
            .await?;
        let session = &thread.thread.id;
        let completed = support::completed_prompt(&env.runtime, session, "search-run-members").await?;
        env.runtime.synchronize_thread_observation(session).await?;
        let owners = ReadOwners::default();
        let main = read(&env.runtime, &owners, pl_agent_tool::typed::decode_json(&json!({
            "sessionId":session,"scope":advertised_scope("main", json!({}))?,
            "demand":{"maxItems":16,"maxBytes":131072}
        }).to_string())?).await?;
        let main: serde_json::Value = serde_json::from_str(main.payload().content())?;
        let main_id = main["readScope"].as_str().context("Main read scope")?;
        let page: ChatBatch = serde_json::from_value(main["chat"].clone())?;
        let representative = page
            .entries
            .iter()
            .find(|entry| entry.main_presentation == pl_protocol::MainPresentation::ForegroundWork)
            .context("reasoning run representative")?;
        let Some(pl_protocol::PayloadData::Deferred { reference, .. }) =
            &representative.atom.payload
        else {
            anyhow::bail!("work representative eagerly included its payload");
        };
        let scope = advertised_scope("run", json!({
            "reference": pl_protocol::CompletionRunRef {
                database_id: reference.database_id.clone(),
                index_version: pl_protocol::COMPLETED_READ_INDEX_VERSION,
                start_seq: representative.run.context("run position")?.start_seq,
            },
        }))?;
        let opened = read(
            &env.runtime,
            &owners,
            pl_agent_tool::typed::decode_json(&json!({
                "sessionId":session,"scope":scope,"demand":{"maxItems":1,"maxBytes":131072}
            }).to_string())?,
        )
        .await?;
        let opened: serde_json::Value = serde_json::from_str(opened.payload().content())?;
        assert!(opened["activity"].is_object());
        let run_id = opened["readScope"].as_str().context("run read scope")?;
        let run_reader = owners.get(run_id, session, None).await?;
        let mut page: ChatBatch = serde_json::from_value(opened["chat"].clone())?;
        let mut members = std::collections::BTreeSet::new();
        loop {
            for entry in page.entries {
                assert_eq!(entry.atom.kind, pl_protocol::ChatAtomKind::Reasoning);
                assert!(members.insert(entry.record_id));
            }
            let Some(before) = page.before else { break };
            page = run_reader.load_older(&before, demand(1)?).await?;
        }
        assert_eq!(members.len(), 40);
        owners.close(run_id).await?;
        owners.close(main_id).await?;
        let parent = pl_core::chat::ChatKey::new("turn", &completed.id)?;
        let children = read(&env.runtime, &owners, pl_agent_tool::typed::decode_json(&json!({
            "sessionId":session,"scope":advertised_scope("children", json!({"parentId":parent.as_str()}))?,
            "demand":{"maxItems":100,"maxBytes":131072}
        }).to_string())?).await?;
        let children: serde_json::Value = serde_json::from_str(children.payload().content())?;
        let child_id = children["readScope"].as_str().context("Children read scope")?;
        let child_reader = owners.get(child_id, session, None).await?;
        let mut page: ChatBatch = serde_json::from_value(children["chat"].clone())?;
        let mut child_members = std::collections::BTreeSet::new();
        let mut terminal_receipt = false;
        for _ in 0..64 {
            for entry in &page.entries {
                if entry.atom.kind == pl_protocol::ChatAtomKind::Reasoning {
                    assert!(child_members.insert(entry.record_id.clone()));
                }
                terminal_receipt |= entry.atom.kind == pl_protocol::ChatAtomKind::TurnReceipt;
            }
            let Some(before) = page.before.as_deref() else { break };
            page = child_reader.load_older(before, demand(100)?).await?;
        }
        assert!(page.before.is_none(), "Children pagination did not terminate");
        assert_eq!(child_members, members);
        assert!(terminal_receipt, "Children omitted the real hidden Turn receipt");
        owners.close(child_id).await?;
        let cancel = CancellationToken::new();
        let mut token: Option<String> = None;
        let mut found = Vec::new();
        let mut complete = false;
        for _ in 0..8 {
            let result = search(
                &env.runtime,
                &owners,
                serde_json::from_value(json!({
                    "sessionId":session,"query":"only-inside-member","cursor":token
                }))?,
                &cancel,
            )
            .await?;
            let result: serde_json::Value = serde_json::from_str(result.payload().content())?;
            found.extend(
                result["matches"]
                    .as_array()
                    .context("search matches")?
                    .iter()
                    .cloned(),
            );
            complete = result["complete"] == true;
            token = result["cursor"].as_str().map(str::to_owned);
            if complete {
                break;
            }
            assert!(token.is_some());
            assert!(owners.readers.lock().await.len() <= MAX_READ_SCOPES);
        }
        assert!(complete, "bounded search never completed its run");
        assert_eq!(found.len(), 1);
        assert!(
            members.contains(
                found[0]["itemId"]
                    .as_str()
                    .context("member match identity")?
            )
        );
        assert!(
            found[0]["snippet"]
                .as_str()
                .unwrap()
                .contains("only-inside-member")
        );
        assert!(owners.readers.lock().await.is_empty());
        assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);
        owners.close_all().await?;
        Ok(())
    }
    .await;
        env.finish(result).await
    }

    fn reason(error: &anyhow::Error) -> Option<&str> {
        error
            .downcast_ref::<pl_protocol::studio::StudioError>()
            .and_then(|error| error.reason())
    }

    #[tokio::test]
    async fn session_tools_read_plan_and_interaction_refs_then_keep_hidden_continuation_out_of_history()
    -> Result<()> {
        use pl_protocol::studio::{CreateThreadRequest, NewThreadModelRoute, StudioPromptInput};
        use pl_protocol::{
            AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, InteractionResolution, InteractionStatus,
            ThreadNotification, ThreadSubscriptionUpdate, UserInputAnswer, UserInputResolution,
        };
        use serde_json::json;
        use std::time::Duration;
        const PROMPT: &str = "session-business-plan";
        const PLAN: &str =
            "# Business reference plan\n\nRead the actual saved plan and approve once.";
        let env = support::Environment::new(
            vec![
                support::prompt_step(
                    PROMPT,
                    0,
                    support::tool_reply(
                        "plan_submit",
                        "business-plan-call",
                        json!({"expectedRevision":0,"plan":PLAN}),
                    ),
                ),
                support::prompt_step(
                    PLAN,
                    1,
                    support::text_reply("approved once", "business-plan-final"),
                ),
            ],
            vec![],
        )
        .await?;
        let result = async {
            let started = Box::pin(env.runtime.create_thread_command(
                env.project.id.clone(),
                CreateThreadRequest {
                    title: Some("Business reference tool consumer".into()),
                    input: StudioPromptInput {
                        input_id: "business-plan-input".into(),
                        text: PROMPT.into(),
                        attachment_draft_ids: Vec::new(),
                    },
                    mode: pl_protocol::ThreadModeId::task().to_string(),
                    route: NewThreadModelRoute {
                        account_id: "root-fixture".into(),
                        model_id: support::MODEL.into(),
                        effort: None,
                    },
                    delegation_mode: None,
                    delegation_preference: None,
                    workspace_mode: pl_protocol::ThreadWorkspaceMode::Local,
                },
                None,
            ))
            .await?;
            let id = &started.thread.id;
            let mut subscription = env.runtime.open_conversation_state_feed(id).await?;
            let pending = tokio::time::timeout(Duration::from_secs(20), async {
                while let Some(update) = subscription.recv().await? {
                    let interaction = match update {
                        ThreadSubscriptionUpdate::Snapshot { snapshot, .. } => snapshot
                            .interactions
                            .into_iter()
                            .find(|interaction| interaction.status() == InteractionStatus::Pending),
                        ThreadSubscriptionUpdate::Notification { notification } => {
                            match notification.notification {
                                ThreadNotification::InteractionChanged { interaction }
                                    if interaction.status() == InteractionStatus::Pending =>
                                {
                                    Some(*interaction)
                                }
                                _ => None,
                            }
                        }
                    };
                    if let Some(interaction) = interaction {
                        return Ok::<_, anyhow::Error>(interaction);
                    }
                }
                anyhow::bail!("plan never reached pending confirmation");
            })
            .await??;
            env.runtime.synchronize_thread_observation(id).await?;
            let source = env
                .runtime
                .create_thread(&env.project.id, "Business tool caller")
                .await?;
            let actionable = env
                .runtime
                .pending_interaction_from_bot(&source.id, id, &pending.interaction_id)
                .await?;
            assert_eq!(actionable, pending);
            let owners = ReadOwners::default();
            let got = get(&env.runtime, &owners, id).await?;
            let got: serde_json::Value = serde_json::from_str(got.payload().content())?;
            assert!(
                got["plan"].is_object(),
                "get_session erased the existing Plan head"
            );
            assert_eq!(got["pending"][0]["interactionId"], pending.interaction_id);
            assert!(
                owners.readers.lock().await.is_empty(),
                "Get leaked its one-shot qualification"
            );
            let opened = read(
                &env.runtime,
                &owners,
                serde_json::from_value(json!({
                    "sessionId":id,"demand":{"maxItems":16,"maxBytes":131072}
                }))?,
            )
            .await?;
            let opened: serde_json::Value = serde_json::from_str(opened.payload().content())?;
            assert_eq!(
                opened["state"]["schemaVersion"],
                pl_protocol::THREAD_SCHEMA_VERSION
            );
            let state_refs: pl_protocol::ThreadBusinessRefs =
                serde_json::from_value(opened["state"]["businessRefs"].clone())?;
            let scope = opened["readScope"].as_str().context("read scope")?;
            let reader = owners.get(scope, id, None).await?;
            let heads = read(
                &env.runtime,
                &owners,
                serde_json::from_value(json!({
                    "sessionId":id,"readScope":scope,"readBusinessRefs":true
                }))?,
            )
            .await?;
            let heads: serde_json::Value = serde_json::from_str(heads.payload().content())?;
            assert_eq!(
                serde_json::from_value::<pl_protocol::ThreadBusinessRefs>(
                    heads["businessRefs"].clone()
                )?,
                state_refs
            );
            let plan = state_refs.plan.as_ref().context("Plan head")?;
            assert_eq!(got["plan"]["revision"], plan.revision);
            let document = plan.document.as_ref().context("Plan document reference")?;
            let window = read(
                &env.runtime,
                &owners,
                serde_json::from_value(json!({
                    "sessionId":id,"readScope":scope,"reference":document,
                    "range":{"offset":0,"maxBytes":65536}
                }))?,
            )
            .await?;
            let window: serde_json::Value = serde_json::from_str(window.payload().content())?;
            let window: pl_protocol::ContentWindow =
                serde_json::from_value(window["window"].clone())?;
            assert!(String::from_utf8(window.bytes)?.contains("Business reference plan"));
            let collection = state_refs.interactions.context("interaction collection")?;
            let page = read(
                &env.runtime,
                &owners,
                serde_json::from_value(json!({
                    "sessionId":id,"readScope":scope,"collection":collection,
                    "demand":{"maxItems":1,"maxBytes":131072}
                }))?,
            )
            .await?;
            let page: serde_json::Value = serde_json::from_str(page.payload().content())?;
            assert_eq!(
                page["currentPage"]["entries"][0]["id"],
                pending.interaction_id
            );
            let approve = || {
                InteractionResolution::UserInput(UserInputResolution {
                    answers: [(
                        AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID.into(),
                        UserInputAnswer {
                            answers: vec!["Approve".into()],
                        },
                    )]
                    .into(),
                })
            };
            let resolved = env
                .runtime
                .resolve_interaction(
                    "tool-business-approve".into(),
                    id.clone(),
                    pending.revision,
                    pending.interaction_id.clone(),
                    approve(),
                )
                .await?;
            assert_eq!(resolved.interaction.status(), InteractionStatus::Resolved);
            tokio::time::timeout(Duration::from_secs(20), async {
                while let Some(update) = subscription.recv().await? {
                    if let ThreadSubscriptionUpdate::Notification { notification } = update
                        && let ThreadNotification::TurnCompleted { turn } =
                            notification.notification
                        && turn.input_id.as_deref() != Some("business-plan-input")
                    {
                        anyhow::ensure!(
                            matches!(turn.state, pl_protocol::TurnState::Completed(_)),
                            "approved continuation failed: {:?}",
                            turn.state
                        );
                        return Ok::<_, anyhow::Error>(());
                    }
                }
                anyhow::bail!("approved plan continuation did not complete");
            })
            .await??;
            env.runtime.synchronize_thread_observation(id).await?;
            let (before_replay_reader, before_replay) = owners
                .open(&env.runtime, id, demand(100)?, None, None)
                .await?;
            owners.close(before_replay_reader.subscription_id()).await?;
            let replayed = env
                .runtime
                .resolve_interaction(
                    "tool-business-repeat".into(),
                    id.clone(),
                    pending.revision,
                    pending.interaction_id.clone(),
                    approve(),
                )
                .await?;
            assert_eq!(
                replayed.interaction, resolved.interaction,
                "idempotent replay changed the actual resolution"
            );
            // Replaying the same decision returns its original receipt. It must not
            // make a historical question actionable or permit a different decision.
            assert!(
                env.runtime
                    .pending_interaction_from_bot(&source.id, id, &pending.interaction_id)
                    .await
                    .is_err(),
                "historical interaction returned as an actionable question"
            );
            let conflicting = InteractionResolution::UserInput(UserInputResolution {
                answers: [(
                    AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID.into(),
                    UserInputAnswer {
                        answers: vec!["Revise".into()],
                    },
                )]
                .into(),
            });
            assert!(
                env.runtime
                    .resolve_interaction(
                        "tool-business-conflict".into(),
                        id.clone(),
                        pending.revision,
                        pending.interaction_id.clone(),
                        conflicting
                    )
                    .await
                    .is_err(),
                "historical interaction authorized a conflicting decision"
            );
            env.runtime.synchronize_thread_observation(id).await?;
            let after = get(&env.runtime, &owners, id).await?;
            let after: serde_json::Value = serde_json::from_str(after.payload().content())?;
            assert_eq!(after["pending"], json!([]));
            let mut history = env
                .runtime
                .open_conversation_feed(id, ChatScope::conversation(None), demand(100)?)
                .await?;
            let Some(crate::studio::ConversationEvent::Chat { batch }) = history.recv().await?
            else {
                anyhow::bail!("missing completion history");
            };
            assert_eq!(
                batch.through_seq, before_replay.through_seq,
                "resolution replay published another completed fact"
            );
            assert!(batch.before.is_none());
            assert_eq!(
                batch
                    .entries
                    .iter()
                    .filter(|entry| entry.atom.kind == pl_protocol::ChatAtomKind::Input)
                    .count(),
                1,
                "hidden approval continuation became another user message"
            );
            let unique = batch
                .entries
                .iter()
                .map(|entry| &entry.record_id)
                .collect::<std::collections::BTreeSet<_>>();
            assert_eq!(unique.len(), batch.entries.len());
            assert_eq!(
                env.root_provider.recorded().len(),
                2,
                "approval replay executed work twice"
            );
            history.close().await?;
            history.reader().close().await?;
            owners.close(scope).await?;
            assert!(
                reader.read_business_refs().await.is_err(),
                "retired scope published business references"
            );
            owners.close_all().await?;
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn stopping_interrupts_first_open_and_first_set_and_failed_join_keeps_original_owner()
    -> Result<()> {
        use std::time::Duration;

        let env = support::Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = env
                .runtime
                .create_thread(&env.project.id, "tool open cancellation")
                .await?;
            let session = &thread.id;
            let owners = ReadOwners::default();
            let (waiting, _release_open) =
                owners.arm_test_boundary(TestBoundary::BeforeOpen, 0).await;
            let (opened, closed) = tokio::time::timeout(Duration::from_secs(3), async {
                tokio::join!(
                    owners.open(&env.runtime, session, demand(1).unwrap(), None, None),
                    async {
                        waiting.await?;
                        owners.close_all().await
                    }
                )
            })
            .await?;
            assert_eq!(reason(&opened.unwrap_err()), Some("staleReadScope"));
            closed?;
            assert!(owners.readers.lock().await.is_empty());
            assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);

            // After a real feed is acquired, cancellation must join both registered owners.
            let owners = ReadOwners::default();
            let (entered, _release) = owners.arm_test_boundary(TestBoundary::FirstSet, 0).await;
            let (opened, closed) = tokio::time::timeout(Duration::from_secs(3), async {
                tokio::join!(
                    owners.open(&env.runtime, session, demand(1).unwrap(), None, None),
                    async {
                        entered.await?;
                        owners.close_all().await
                    }
                )
            })
            .await?;
            assert_eq!(reason(&opened.unwrap_err()), Some("staleReadScope"));
            closed?;
            assert!(owners.readers.lock().await.is_empty());
            assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);

            // Fail the first receive via explicit read revocation, and fail its first join once.
            let owners = ReadOwners::default();
            let (entered, release) = owners.arm_test_boundary(TestBoundary::FirstSet, 0).await;
            let (opened, id) = tokio::time::timeout(Duration::from_secs(3), async {
                tokio::join!(
                    owners.open(&env.runtime, session, demand(1).unwrap(), None, None),
                    async {
                        let id = entered.await?;
                        owners.readers.lock().await[&id]
                            .close_fault
                            .store(true, Ordering::Release);
                        owners.readers.lock().await[&id].reader.invalidate();
                        let _ = release.send(());
                        Ok::<_, anyhow::Error>(id)
                    }
                )
            })
            .await?;
            let id = id?;
            let error = opened.unwrap_err();
            assert_eq!(reason(&error), Some("conversationResyncRequired"));
            assert!(format!("{error:#}").contains("injected read-resource join failure"));
            assert_eq!(owners.readers.lock().await.len(), 1);
            assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES - 1);
            assert_eq!(
                reason(&owners.get(&id, session, None).await.unwrap_err()),
                Some("staleReadScope")
            );
            owners.close(&id).await?;
            assert!(owners.readers.lock().await.is_empty());
            assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);
            owners.close_all().await?;
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn search_new_scope_failures_and_cancellation_release_capacity_and_retain_failed_join()
    -> Result<()> {
        use std::time::Duration;

        let env = support::Environment::new(
            vec![support::prompt_step(
                "search-new-scope",
                0,
                support::text_reply("a public text body", "search-new-response"),
            )],
            vec![],
        )
        .await?;
        let result = async {
            let thread = env
                .start(pl_protocol::ThreadWorkspaceMode::Local, "search-new-scope")
                .await?;
            let session = &thread.thread.id;
            support::completed_prompt(&env.runtime, session, "search-new-scope").await?;
            let owners = ReadOwners::default();
            let input = || {
                serde_json::from_value::<SearchInput>(
                    serde_json::json!({"sessionId":session,"query":"absent search needle"}),
                )
            };
            // More than the entire quota: both cancellation and an explicit read revocation must reclaim
            // scopes that have never been transferred in a successful ToolOutput.
            for attempt in 0..MAX_READ_SCOPES + 2 {
                let cancel = CancellationToken::new();
                let (entered, release) =
                    owners.arm_test_boundary(TestBoundary::SearchRead, 0).await;
                let (found, control) = tokio::time::timeout(Duration::from_secs(3), async {
                    tokio::join!(
                        search(&env.runtime, &owners, input().unwrap(), &cancel),
                        async {
                            let id = entered.await?;
                            assert_eq!(owners.readers.lock().await.len(), 1);
                            if attempt % 2 == 0 {
                                cancel.cancel();
                            } else {
                                owners.readers.lock().await[&id].reader.invalidate();
                            }
                            let _ = release.send(());
                            Ok::<_, anyhow::Error>(id)
                        }
                    )
                })
                .await?;
                control?;
                let error = found
                    .err()
                    .with_context(|| format!("search attempt {attempt} returned a cursor"))?;
                if attempt % 2 == 0 {
                    assert!(format!("{error:#}").contains("search cancelled"));
                } else {
                    assert_eq!(reason(&error), Some("conversationResyncRequired"));
                }
                assert!(owners.readers.lock().await.is_empty());
                assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);
            }
            // The original typed read error wins over cleanup failure. Its original resource and permit
            // stay in the same owner table, closing and retryable, rather than being silently dropped.
            let cancel = CancellationToken::new();
            let (entered, release) = owners.arm_test_boundary(TestBoundary::SearchRead, 0).await;
            let (found, control) = tokio::time::timeout(Duration::from_secs(3), async {
                tokio::join!(
                    search(&env.runtime, &owners, input().unwrap(), &cancel),
                    async {
                        let id = entered.await?;
                        owners.readers.lock().await[&id]
                            .close_fault
                            .store(true, Ordering::Release);
                        owners.readers.lock().await[&id].reader.invalidate();
                        let _ = release.send(());
                        Ok::<_, anyhow::Error>(id)
                    }
                )
            })
            .await?;
            let id = control?;
            let error = found
                .err()
                .context("failed read returned a search result")?;
            assert_eq!(reason(&error), Some("conversationResyncRequired"));
            assert!(format!("{error:#}").contains("injected read-resource join failure"));
            assert_eq!(owners.readers.lock().await.len(), 1);
            assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES - 1);
            owners.close(&id).await?;
            assert!(owners.readers.lock().await.is_empty());
            assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);
            owners.close_all().await?;
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn search_borrows_input_until_cross_session_result_commit_and_retries_original_cleanup()
    -> Result<()> {
        use std::time::Duration;

        // A real successful first search stops inside the text window budget, not at a forged cursor.
        let body = format!("{}search-final-needle", "x".repeat(WINDOW as usize * 36));
        let env = support::Environment::new(
            vec![support::prompt_step(
                "search-borrowed-scope",
                0,
                support::text_reply(&body, "search-borrowed-response"),
            )],
            vec![],
        )
        .await?;
        let result = async {
        let older = env.runtime.create_thread(&env.project.id, "older empty search session").await?;
        let thread = env.start(pl_protocol::ThreadWorkspaceMode::Local, "search-borrowed-scope").await?;
        let session = &thread.thread.id;
        support::completed_prompt(&env.runtime, session, "search-borrowed-scope").await?;
        // Validate the actual directory order used by the production cross-session scan.
        let directory = env.runtime.agent_facility.product_events.query_threads(
            &pl_protocol::studio::ThreadDirectoryQuery {
                workspace_id: Some(env.project.id.clone()), ..Default::default()
            }, None, 1,
        ).await?;
        let directory = directory.state.value().context("directory unavailable")?;
        assert_eq!(directory.rows[0].thread_id, *session);
        assert!(directory.next_cursor.is_some());
        let input = |cursor: Option<&str>| serde_json::from_value::<SearchInput>(
            serde_json::json!({"workspaceId":env.project.id,"query":"search-final-needle","cursor":cursor})
        );
        let owners = ReadOwners::default();
        let first = search(&env.runtime, &owners, input(None)?, &CancellationToken::new()).await?;
        let page: serde_json::Value = serde_json::from_str(first.payload().content())?;
        assert_eq!(page["complete"], false);
        let token = page["cursor"].as_str().context("successful search continuation")?;
        let cursor: Cursor = decode(token)?;
        assert_eq!(cursor.session_id.as_deref(), Some(session.as_str()));
        assert!(!cursor.directory_done);
        let id = cursor.read_scope_id.as_deref().context("transferred scope")?;
        let pending = cursor.pending.as_ref().context("real pending body window")?;
        let reader = owners.get(id, session, Some(&cursor.fingerprint)).await?;
        // Cancelling a borrowed read must not revoke the successful input cursor.
        let cancel = CancellationToken::new();
        let (entered, _release) = owners.arm_test_boundary(TestBoundary::SearchRead, 0).await;
        let (found, control) = tokio::time::timeout(Duration::from_secs(3), async {
            tokio::join!(
                search(&env.runtime, &owners, input(Some(token)).unwrap(), &cancel),
                async { assert_eq!(entered.await?, id); cancel.cancel(); Ok::<_, anyhow::Error>(()) }
            )
        }).await?;
        control?;
        assert!(format!("{:#}", found.err().context("cancelled search succeeded")?).contains("search cancelled"));
        owners.get(id, session, Some(&cursor.fingerprint)).await?;
        reader.read_content(&pending.reference, ContentRange { offset: pending.offset, max_bytes: 16 }).await?;

        // Crossing to another session cannot open a 17th scope or evict the input qualification.
        let mut occupied = Vec::new();
        for _ in 1..MAX_READ_SCOPES {
            let (reader, _) = owners.open(&env.runtime, session, demand(1)?, None, None).await?;
            occupied.push(reader.subscription_id().to_owned());
        }
        let error = search(&env.runtime, &owners, input(Some(token))?, &CancellationToken::new())
            .await.err().context("cross-session scan exceeded the quota")?;
        assert!(matches!(error.downcast_ref::<pl_core::chat::ChatError>(), Some(pl_core::chat::ChatError::Overloaded(_))));
        assert_eq!(owners.readers.lock().await.len(), MAX_READ_SCOPES);
        assert_eq!(owners.permits.available_permits(), 0);
        owners.get(id, session, Some(&cursor.fingerprint)).await?;
        owners.get(&occupied[0], session, None).await?;
        close_scopes(&owners, &occupied).await?;

        // Both cancellation and an actual first-Set read failure in the next session leave the
        // input scope unretired and release only this call's untransferred new scope.
        for fail_read in [false, true] {
            let cancel = CancellationToken::new();
            let (entered, release) = owners.arm_test_boundary(TestBoundary::FirstSet, 0).await;
            let (found, control) = tokio::time::timeout(Duration::from_secs(3), async {
                tokio::join!(
                    search(&env.runtime, &owners, input(Some(token)).unwrap(), &cancel),
                    async {
                        let new_id = entered.await?;
                        assert_ne!(new_id, id);
                        assert_eq!(owners.readers.lock().await.len(), 2);
                        assert_eq!(owners.readers.lock().await[&new_id].reader.thread_id(), older.id);
                        if fail_read {
                            owners.readers.lock().await[&new_id].reader.invalidate();
                        } else {
                            cancel.cancel();
                        }
                        let _ = release.send(());
                        Ok::<_, anyhow::Error>(())
                    }
                )
            }).await?;
            control?;
            let error = found.err().context("cross-session failure returned an output")?;
            if fail_read {
                assert_eq!(reason(&error), Some("conversationResyncRequired"));
            } else {
                assert!(format!("{error:#}").contains("search cancelled"));
            }
            assert_eq!(owners.readers.lock().await.len(), 1);
            assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES - 1);
            owners.get(id, session, Some(&cursor.fingerprint)).await?;
            reader.read_content(&pending.reference, ContentRange { offset: pending.offset, max_bytes: 16 }).await?;
        }

        // Once a complete output is encoded, a failed irreversible retirement keeps the original
        // owner closing for retry; it must not pretend the old cursor remains usable.
        let cancel = CancellationToken::new();
        let (entered, release) = owners.arm_test_boundary(TestBoundary::SearchCommit, 0).await;
        let (found, control) = tokio::time::timeout(Duration::from_secs(3), async {
            tokio::join!(
                search(&env.runtime, &owners, input(Some(token)).unwrap(), &cancel),
                async {
                    assert_eq!(entered.await?, id);
                    owners.readers.lock().await[id].close_fault.store(true, Ordering::Release);
                    let _ = release.send(());
                    Ok::<_, anyhow::Error>(())
                }
            )
        }).await?;
        control?;
        let error = found.err().context("failed result commit returned an output")?;
        assert!(format!("{error:#}").contains("injected read-resource join failure"));
        assert_eq!(owners.readers.lock().await.len(), 1);
        assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES - 1);
        assert_eq!(reason(&owners.get(id, session, Some(&cursor.fingerprint)).await.unwrap_err()), Some("staleReadScope"));
        owners.close(id).await?;
        assert!(owners.readers.lock().await.is_empty());
        assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);
        drop(reader);
        // The ordinary successful continuation path finally retires all snippet-only resources.
        let first = search(&env.runtime, &owners, input(None)?, &CancellationToken::new()).await?;
        let page: serde_json::Value = serde_json::from_str(first.payload().content())?;
        let next = page["cursor"].as_str().context("second first-page cursor")?;
        let last = search(&env.runtime, &owners, input(Some(next))?, &CancellationToken::new()).await?;
        let page: serde_json::Value = serde_json::from_str(last.payload().content())?;
        assert_eq!(page["complete"], true);
        assert!(page["matches"].as_array().context("matches")?.iter().any(|entry| entry["sessionId"] == *session));
        assert!(owners.readers.lock().await.is_empty());
        assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);
        owners.close_all().await?;
        Ok(())
    }.await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn tool_read_eof_keeps_qualification_until_explicit_or_tool_close_and_never_rebinds()
    -> Result<()> {
        let body = format!("{}汉界关键字工具正文跨调用保留", "x".repeat(32767));
        let env = support::Environment::new(
            vec![support::prompt_step(
                "tool-read-scopes",
                0,
                support::text_reply(&body, "tool-read-response"),
            )],
            vec![],
        )
        .await?;
        let result = async {
        let thread = env
            .start(pl_protocol::ThreadWorkspaceMode::Local, "tool-read-scopes")
            .await?;
        let session = &thread.thread.id;
        support::completed_prompt(&env.runtime, session, "tool-read-scopes").await?;
        let owners = ReadOwners::default();
        let other = ReadOwners::default();
        let input =
            serde_json::json!({"sessionId":session,"demand":{"maxItems":100,"maxBytes":131072}});
        let output = read(&env.runtime, &owners, serde_json::from_value(input)?).await?;
        let page: serde_json::Value = serde_json::from_str(output.payload().content())?;
        assert!(
            page["chat"]["before"].is_null(),
            "fixture is not at the real history EOF"
        );
        let scope = page["readScope"].as_str().context("read scope")?;
        let reader = owners.get(scope, session, None).await?;
        assert_eq!(
            reason(&other.get(scope, session, None).await.unwrap_err()),
            Some("staleReadScope")
        );
        assert_eq!(
            reason(&owners.get(scope, "another-thread", None).await.unwrap_err()),
            Some("staleReadScope")
        );
        let batch: ChatBatch = serde_json::from_value(page["chat"].clone())?;
        let item = batch
            .entries
            .iter()
            .find_map(|entry| {
                (entry.atom.kind == pl_protocol::ChatAtomKind::Text)
                    .then(|| entry.record_id.clone())
            })
            .context("public text item")?;
        let reference = text_reference(&reader, &item)
            .await?
            .context("public body")?;
        let output = read(
            &env.runtime,
            &owners,
            serde_json::from_value(serde_json::json!({"sessionId":session,"readScope":scope,
            "reference":reference,"range":{"offset":0,"maxBytes":128}}))?,
        )
        .await?;
        let window: serde_json::Value = serde_json::from_str(output.payload().content())?;
        assert!(
            !window["window"]["bytes"]
                .as_array()
                .context("body bytes")?
                .is_empty()
        );
        assert!(
            owners.get(scope, session, None).await.is_ok(),
            "history EOF revoked body reads"
        );
        read(
            &env.runtime,
            &owners,
            serde_json::from_value(
                serde_json::json!({"sessionId":session,"readScope":scope,"closeReadScope":true}),
            )?,
        )
        .await?;
        assert_eq!(
            reason(&owners.get(scope, session, None).await.unwrap_err()),
            Some("staleReadScope")
        );
        let search_owners = ReadOwners::default();
        let output = search(
            &env.runtime,
            &search_owners,
            serde_json::from_value(serde_json::json!({"sessionId":session,"query":"汉界关键字"}))?,
            &CancellationToken::new(),
        )
        .await?;
        let search: serde_json::Value = serde_json::from_str(output.payload().content())?;
        assert!(
            search["matches"]
                .as_array()
                .context("search matches")?
                .iter()
                .any(|entry| entry["snippet"]
                    .as_str()
                    .is_some_and(|snippet| snippet.contains("汉界关键字")))
        );
        assert_eq!(search["complete"], true);
        assert!(
            search_owners.readers.lock().await.is_empty(),
            "snippet-only search EOF leaked its read qualification"
        );
        search_owners.close_all().await?;
        let mut ids = Vec::new();
        for _ in 0..MAX_READ_SCOPES {
            let (reader, _) = owners
                .open(&env.runtime, session, demand(1)?, None, None)
                .await?;
            ids.push(reader.subscription_id().to_owned());
        }
        let error = owners
            .open(&env.runtime, session, demand(1)?, None, None)
            .await
            .err()
            .context("17th scope was admitted")?;
        assert!(matches!(
            error.downcast_ref::<pl_core::chat::ChatError>(),
            Some(pl_core::chat::ChatError::Overloaded(_))
        ));
        assert!(
            owners.get(&ids[0], session, None).await.is_ok(),
            "capacity pressure evicted an original scope"
        );
        owners.close_all().await?;
        assert!(owners.readers.lock().await.is_empty());
        assert_eq!(
            reason(&owners.get(&ids[0], session, None).await.unwrap_err()),
            Some("staleReadScope")
        );
        assert!(
            owners
                .open(&env.runtime, session, demand(1)?, None, None)
                .await
                .is_err(),
            "closed tool reopened an execution-qualified read"
        );
        other.close_all().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
        env.finish(result).await
    }
}
