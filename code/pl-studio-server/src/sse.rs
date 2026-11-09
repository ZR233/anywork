use std::convert::Infallible;
use std::sync::Arc;
use std::time::Duration;

use axum::extract::{Path, State};
use axum::http::HeaderMap;
use axum::response::IntoResponse;
use axum::response::sse::{Event, KeepAlive, Sse};
use futures::Stream;
use pl_protocol::{ThreadNotification, ThreadSubscriptionUpdate};
use pl_studio_runtime::{ConversationEvent, StudioProductFrame};
use serde::Serialize;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tokio_util::sync::CancellationToken;

use crate::AppState;
use crate::conversation::{
    CONVERSATION_HEADER, ContentRequest, EventSender, NativeFeed, ReadOwner,
};
use crate::error::ApiError;
use crate::routes::{ApiJson, ApiQuery, ProductTopicQuery, StudioApiErrors, parse_product_topic};

#[cfg(test)]
mod tests;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct StaleEvent {
    reason: &'static str,
    dropped: Option<u64>,
    resync: String,
}

/// Product 事件是可合并的目录/状态更新：缓冲满时丢弃该条并经一次 `stale` 让客户端
/// 从 `/api/v1/state` 重同步。`stale` 等待容量后送达，因此慢消费者不会因为缓冲满被
/// 静默断开；连接本身的终态由流的关闭表达。
enum Delivery {
    Sent,
    /// 缓冲已满：该条更新被合并，需要先送达一次 `stale` 标记。
    Stalled,
    /// 该帧无法送达：接收端已关闭，或事件无法编码。调用方应结束该流，让客户端重连重同步，
    /// 不把未送达的观测当成已送达。
    Closed,
}

/// typed 产品 topic 订阅：先登记接收者，再由 runtime 读取该领域基线。
///
/// 首帧是 `baseline` 事件（含 topic 与领域 revision），其后只交付该 topic 的领域
/// 事件；缓冲合并后以一次 `stale` 通知客户端仅重读该 topic 的基线。SSE 没有 durable
/// replay：带 `Last-Event-ID` 重连同样先收到 `stale`。
#[utoipa::path(
    get,
    path = "/api/v1/events/product",
    operation_id = "studio.subscribeProduct",
    params(
        ("topic" = String, Query, description = "typed 产品 topic（camelCase 标签）"),
        ("workspaceId" = Option<String>, Query, description = "Skills topic 的项目作用域"),
        ("rootThreadId" = Option<String>, Query, description = "SessionCosts topic 的根会话作用域"),
        ("hostThreadId" = Option<String>, Query, description = "ChildInteractions topic 的宿主会话作用域")
    ),
    responses(StudioApiErrors, (status = 200, description = "Product topic event stream", body = String, content_type = "text/event-stream"))
)]
pub(crate) async fn product_events(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<ProductTopicQuery>,
    headers: HeaderMap,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    let topic = parse_product_topic(&query)?;
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let mut events = state
        .runtime
        .subscribe_product_topic(topic)
        .await
        .map_err(ApiError::from)?;
    let shutdown = state.shutdown.clone();
    let has_cursor = headers.contains_key("last-event-id");
    let resync = topic_resync_path(events.topic());
    let (sender, receiver) = mpsc::channel(64);
    tokio::spawn(async move {
        let _permit = permit;
        if has_cursor
            && !flush_stale(
                &sender,
                &shutdown,
                StaleEvent {
                    reason: "replayUnsupported",
                    dropped: None,
                    resync: resync.clone(),
                },
            )
            .await
        {
            return;
        }
        loop {
            let frame = tokio::select! {
                _ = shutdown.cancelled() => break,
                frame = events.recv() => match frame {
                    Ok(Some(frame)) => frame,
                    Ok(None) | Err(_) => break,
                },
            };
            match frame {
                StudioProductFrame::Baseline(baseline) => {
                    let event_id = format!("topic:{}", baseline.revision);
                    if !send_json(&sender, &shutdown, "baseline", Some(&event_id), &*baseline).await
                    {
                        return;
                    }
                }
                StudioProductFrame::Event(event) => {
                    match try_send_json(&sender, "event", Some(&event.event_id), &event) {
                        Delivery::Sent => {}
                        Delivery::Stalled => {
                            if !flush_stale(
                                &sender,
                                &shutdown,
                                StaleEvent {
                                    reason: "slowConsumer",
                                    dropped: None,
                                    resync: resync.clone(),
                                },
                            )
                            .await
                            {
                                return;
                            }
                        }
                        Delivery::Closed => return,
                    }
                }
                StudioProductFrame::Lagged { dropped, .. } => {
                    if !flush_stale(
                        &sender,
                        &shutdown,
                        StaleEvent {
                            reason: "lagged",
                            dropped: Some(dropped),
                            resync: resync.clone(),
                        },
                    )
                    .await
                    {
                        return;
                    }
                }
            }
        }
        // 终态标记是尽力而为：shutdown 必须立即结束连接，不能用等待容量阻塞优雅关闭。
        let _ = sender.try_send(Ok(Event::default().event("closed").data("{}")));
    });
    Ok(Sse::new(ReceiverStream::new(receiver))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("")))
}

/// 该 topic 基线端点的查询串；`stale` 的 resync 指令指向它。
///
/// 作用域值经 form-urlencoded 百分号编码：身份不假设为 UUID 等安全字符集。
fn topic_resync_path(topic: &pl_studio_runtime::StudioProductTopic) -> String {
    use pl_studio_runtime::StudioProductTopic;
    let mut query = url::form_urlencoded::Serializer::new(String::new());
    match topic {
        StudioProductTopic::Skills { workspace_id } => {
            query.append_pair("topic", "skills");
            query.append_pair("workspaceId", workspace_id);
        }
        StudioProductTopic::SessionCosts { root_thread_id } => {
            query.append_pair("topic", "sessionCosts");
            query.append_pair("rootThreadId", root_thread_id);
        }
        StudioProductTopic::ChildInteractions { host_thread_id } => {
            query.append_pair("topic", "childInteractions");
            query.append_pair("hostThreadId", host_thread_id);
        }
        StudioProductTopic::McpCatalog { scope } => {
            query.append_pair("topic", "mcpCatalog");
            match scope {
                pl_protocol::McpScope::Host => {
                    query.append_pair("scope", "host");
                }
                pl_protocol::McpScope::Ssh { ssh_alias } => {
                    query.append_pair("scope", "ssh");
                    query.append_pair("sshAlias", ssh_alias);
                }
            }
        }
        StudioProductTopic::ThreadMcp { thread_id } => {
            query.append_pair("topic", "threadMcp");
            query.append_pair("threadId", thread_id);
        }
        other => {
            query.append_pair("topic", topic_token(other));
        }
    }
    format!("/api/v1/state/product?{}", query.finish())
}

/// topic 的查询标签；与 `parse_product_topic` 接受的标签一一对应。
fn topic_token(topic: &pl_studio_runtime::StudioProductTopic) -> &'static str {
    use pl_studio_runtime::StudioProductTopic;
    match topic {
        StudioProductTopic::ProjectDirectory => "projectDirectory",
        StudioProductTopic::ThreadDirectory => "threadDirectory",
        StudioProductTopic::AgentDirectory => "agentDirectory",
        StudioProductTopic::SettingsConfig => "settingsConfig",
        StudioProductTopic::ModelCatalog => "modelCatalog",
        StudioProductTopic::Recovery => "recovery",
        StudioProductTopic::McpCatalog { .. } => "mcpCatalog",
        StudioProductTopic::ThreadMcp { .. } => "threadMcp",
        StudioProductTopic::Lsp => "lsp",
        StudioProductTopic::Skills { .. } => "skills",
        StudioProductTopic::ThreadModeCatalog => "threadModeCatalog",
        StudioProductTopic::AccountUsage => "accountUsage",
        StudioProductTopic::AcpAuth => "acpAuth",
        StudioProductTopic::AcpInstall => "acpInstall",
        StudioProductTopic::ModelPerformance => "modelPerformance",
        StudioProductTopic::SessionCosts { .. } => "sessionCosts",
        StudioProductTopic::Updater => "updater",
        StudioProductTopic::Persistence => "persistence",
        StudioProductTopic::PersistenceQueue => "persistenceQueue",
        StudioProductTopic::AgentProfiles => "agentProfiles",
        StudioProductTopic::Bots => "bots",
        StudioProductTopic::ChildInteractions { .. } => "childInteractions",
    }
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct ConversationQuery {
    max_items: u32,
    max_bytes: u32,
    parent_id: Option<String>,
    run_database_id: Option<String>,
    run_index_version: Option<u32>,
    run_start_seq: Option<u64>,
}

impl ConversationQuery {
    fn scope_demand(self) -> Result<(pl_protocol::ChatScope, pl_protocol::ReadDemand), ApiError> {
        let scope = match (
            self.parent_id,
            self.run_database_id,
            self.run_index_version,
            self.run_start_seq,
        ) {
            (None, None, None, None) => pl_protocol::ChatScope::Main,
            (Some(parent_id), None, None, None) => pl_protocol::ChatScope::Children { parent_id },
            (None, Some(database_id), Some(index_version), Some(start_seq)) => {
                if index_version != pl_protocol::COMPLETED_READ_INDEX_VERSION {
                    return Err(ApiError(
                        pl_protocol::studio::StudioError::new(
                            pl_protocol::studio::StudioErrorCode::Protocol,
                            "Unsupported completion run index version",
                            false,
                        )
                        .with_reason(
                            pl_protocol::studio::StudioErrorReason::ProtocolVersionMismatch,
                            serde_json::json!({
                                "expected": pl_protocol::COMPLETED_READ_INDEX_VERSION,
                                "actual": index_version,
                            }),
                        ),
                    ));
                }
                if database_id.is_empty() || start_seq == 0 || start_seq > i64::MAX as u64 {
                    return Err(ApiError(
                        pl_protocol::studio::StudioError::invalid_argument(
                            "A completion run reference requires a database ID and positive start sequence",
                        ),
                    ));
                }
                pl_protocol::ChatScope::Run {
                    reference: pl_protocol::CompletionRunRef {
                        database_id,
                        index_version,
                        start_seq,
                    },
                }
            }
            _ => {
                return Err(ApiError(pl_protocol::studio::StudioError::new(
                    pl_protocol::studio::StudioErrorCode::InvalidArgument,
                    "Use Main, a real parentId, or a complete completion run reference, never mixed scopes",
                    false,
                )));
            }
        };
        let demand = pl_protocol::ReadDemand {
            max_items: self.max_items,
            max_bytes: self.max_bytes,
        };
        Ok((scope, demand))
    }
}

/// The original runtime feed owns both chat delivery and independent reads.
#[utoipa::path(
    get,
    path = "/api/v1/threads/{thread_id}/events",
    operation_id = "thread.subscribe",
    params(
        ("thread_id" = String, Path, description = "Thread ID"),
        ("maxItems" = u32, Query, description = "Requested bounded item count"),
        ("maxBytes" = u32, Query, description = "Requested encoded byte budget"),
        ("parentId" = Option<String>, Query, description = "Real business Children parent; cannot be combined with run fields"),
        ("runDatabaseId" = Option<String>, Query, description = "Completion run databaseId; all run fields are required together"),
        ("runIndexVersion" = Option<u32>, Query, description = "Completion run indexVersion (currently 1)"),
        ("runStartSeq" = Option<u64>, Query, description = "Completion run startSeq")
    ),
    responses(StudioApiErrors, (status = 200, description = "Authoritative Thread stream", body = String, content_type = "text/event-stream",
        headers(("X-Anywork-Conversation" = String, description = "Original feed read capability"))))
)]
pub(crate) async fn thread_events(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiQuery(query): ApiQuery<ConversationQuery>,
) -> Result<impl IntoResponse, ApiError> {
    let (scope, demand) = query.scope_demand()?;
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let events = state
        .runtime
        .open_conversation_feed(&thread_id, scope, demand)
        .await
        .map_err(ApiError::from)?;
    let (sender, receiver) = mpsc::channel(1);
    let id = register_conversation(
        &state,
        thread_id,
        NativeFeed::Conversation(Box::new(events)),
        permit,
        Some(sender),
    )
    .await?;
    Ok((
        [(CONVERSATION_HEADER, id)],
        Sse::new(ReceiverStream::new(receiver))
            .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("")),
    ))
}

/// A missing sender is the timeline open-before-events phase, not a second session.
pub(crate) async fn register_conversation(
    state: &AppState,
    thread_id: String,
    feed: NativeFeed,
    permit: tokio::sync::OwnedSemaphorePermit,
    sender: Option<EventSender>,
) -> Result<String, ApiError> {
    let id = feed.subscription_id().to_owned();
    let owner = Arc::new(ReadOwner::with_feed(thread_id, feed));
    let (start, started) = tokio::sync::oneshot::channel();
    if sender.is_none() {
        *owner.events.lock().expect("conversation start poisoned") = Some(start);
    }
    let mut pending = Some((permit, started, sender));
    {
        // Register and start under the same lock used by shutdown and query
        // admission. No capability can outlive an untracked owner task.
        let mut owners = state
            .conversations
            .0
            .lock()
            .expect("conversation owners poisoned");
        if !owners.closed && !state.shutdown.is_cancelled() {
            while let Some(result) = owners.tasks.try_join_next() {
                if let Err(error) = result {
                    tracing::warn!(%error, "conversation HTTP owner task failed");
                }
            }
            owners.readers.insert(id.clone(), owner.clone());
            let (permit, started, sender) = pending.take().expect("unstarted conversation");
            let state = state.clone();
            let id = id.clone();
            let owner = owner.clone();
            owners.tasks.spawn(async move {
                let _permit = permit;
                let _completion = ConversationCompletion {
                    owner: Arc::clone(&owner),
                };
                let sender = match sender {
                    Some(sender) => Some(sender),
                    None => tokio::select! {
                        biased;
                        () = state.shutdown.cancelled() => None,
                        () = owner.cancel.cancelled() => None,
                        sender = started => sender.ok(),
                    },
                };
                run_conversation(&state, &id, owner, sender).await;
            });
        }
    }
    if let Some((_permit, _started, _sender)) = pending {
        // Even a shutdown race retains the original slot if its close fails.
        state
            .conversations
            .0
            .lock()
            .expect("conversation owners poisoned")
            .readers
            .insert(id.clone(), Arc::clone(&owner));
        let result = close_conversation(&owner).await;
        owner.completed.send_replace(Some(result.clone()));
        if result.is_ok() {
            state.conversations.forget(&id);
        }
        result.map_err(ApiError)?;
        return Err(crate::conversation::stale_scope());
    }
    Ok(id)
}

struct ConversationCompletion {
    owner: Arc<ReadOwner>,
}

impl Drop for ConversationCompletion {
    fn drop(&mut self) {
        if self.owner.completed.borrow().is_none() {
            self.owner.request_close();
            self.owner
                .completed
                .send_replace(Some(Err(pl_protocol::studio::StudioError::new(
                    pl_protocol::studio::StudioErrorCode::Internal,
                    "conversation HTTP owner task did not finish cleanup",
                    false,
                ))));
        }
    }
}

async fn run_conversation(
    state: &AppState,
    id: &str,
    owner: Arc<ReadOwner>,
    sender: Option<EventSender>,
) {
    if let Some(sender) = &sender {
        let mut native = owner.native.lock().await;
        if let Some(events) = native.as_mut() {
            loop {
                // Reserve before polling the feed: at most one queued frame, with no
                // second encoded body held while waiting for the slow HTTP consumer.
                let capacity = tokio::select! {
                    biased;
                    () = state.shutdown.cancelled() => break,
                    () = owner.cancel.cancelled() => break,
                    capacity = sender.reserve() => match capacity {
                        Ok(capacity) => capacity,
                        Err(_) => break,
                    },
                };
                let received = tokio::select! {
                    biased;
                    () = state.shutdown.cancelled() => break,
                    () = owner.cancel.cancelled() => break,
                    () = sender.closed() => break,
                    received = events.recv() => received,
                };
                match received {
                    Ok(Some(event)) => {
                        if let ConversationEvent::Timeline { batch } = &event
                            && let Err(error) = batch.validate()
                        {
                            if let Ok(event) = encode_event("error", None, &error) {
                                capacity.send(Ok(event));
                            }
                            break;
                        }
                        match encode_conversation_event(&event) {
                            Ok(event) => {
                                capacity.send(Ok(event));
                            }
                            Err(_) => break,
                        }
                    }
                    Ok(None) => break,
                    Err(error) => {
                        let error = pl_studio_runtime::studio_error_from_anyhow(error);
                        // This capacity was reserved before receive, so a domain failure is
                        // delivered without either dropping it or blocking cancellation.
                        if let Ok(event) = encode_event("error", None, &error) {
                            capacity.send(Ok(event));
                        }
                        break;
                    }
                }
            }
        }
    }
    // Seal admission before any potentially backpressured terminal delivery.
    state.conversations.remove(id);
    let result = close_conversation(&owner).await;
    if result.is_ok() {
        state.conversations.forget(id);
    }
    if let Some(sender) = sender {
        if let Err(error) = &result
            && let Ok(event) = encode_event("error", None, &error)
        {
            let _ = sender.try_send(Ok(event));
        }
        let _ = sender.try_send(Ok(Event::default().event("closed").data("{}")));
    }
    owner.completed.send_replace(Some(result));
}

pub(crate) async fn close_conversation(
    owner: &ReadOwner,
) -> Result<(), pl_protocol::studio::StudioError> {
    owner.request_close();
    let _close = owner.close_gate.lock().await;
    // These are independent owners: one failure must never skip the other join.
    let feed_close = async {
        let mut native = owner.native.lock().await;
        if let Some(feed) = native.as_mut() {
            feed.request_close();
            feed.close().await?;
            native.take();
        }
        Ok(())
    };
    let (feed_result, reader_result) = tokio::join!(feed_close, owner.reader.close());
    let mut failure = None;
    for (side, result) in [("feed", feed_result), ("reader", reader_result)] {
        if let Err(error) = result {
            let mapped = pl_studio_runtime::studio_error_from_anyhow(error);
            tracing::warn!(
                side,
                code = mapped.code.label(),
                "conversation SSE close failed"
            );
            failure.get_or_insert(mapped);
        }
    }
    owner.drain().await;
    let members = owner
        .members
        .lock()
        .expect("conversation members poisoned")
        .clone();
    for member in members {
        let mut native = member.lock().await;
        if let Some(source) = native.as_mut() {
            source.request_close();
            match source.close().await {
                Ok(()) => {
                    native.take();
                }
                Err(error) => {
                    failure
                        .get_or_insert_with(|| pl_studio_runtime::studio_error_from_anyhow(error));
                }
            }
        }
        if native.is_none() {
            owner
                .members
                .lock()
                .expect("conversation members poisoned")
                .retain(|entry| !Arc::ptr_eq(entry, &member));
        }
    }
    failure.map_or(Ok(()), Err)
}

fn encode_conversation_event(event: &ConversationEvent) -> Result<Event, axum::Error> {
    match event {
        ConversationEvent::State { update } => {
            let (name, id) = match &**update {
                ThreadSubscriptionUpdate::Snapshot { snapshot, .. } => {
                    ("snapshot", format!("thread:{}", snapshot.revision))
                }
                ThreadSubscriptionUpdate::Notification { notification } => (
                    if matches!(notification.notification, ThreadNotification::Lagged { .. }) {
                        "lagged"
                    } else {
                        "notification"
                    },
                    format!("thread:{}:{}", notification.epoch, notification.revision),
                ),
            };
            encode_event(name, Some(&id), update)
        }
        ConversationEvent::Chat { batch } => encode_event("chat", None, batch),
        ConversationEvent::Activity { snapshot } => encode_event("activity", None, snapshot),
        ConversationEvent::Timeline { batch } => encode_event("timeline", None, batch),
    }
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/contents/watch",
    operation_id = "thread.watchContent",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = ContentRequest,
    responses(StudioApiErrors, (status = 200, description = "Bounded ContentWindow events", body = String, content_type = "text/event-stream")))]
pub(crate) async fn watch_content(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<ContentRequest>,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    let mut source = lease
        .owner
        .reader
        .watch_content(&request.reference, request.range)
        .await?;
    let (sender, receiver) = mpsc::channel(1);
    tokio::spawn(async move {
        let _permit = permit;
        let mut failure = None;
        loop {
            let capacity = tokio::select! {
                biased;
                () = state.shutdown.cancelled() => break,
                () = lease.owner.cancel.cancelled() => break,
                capacity = sender.reserve() => match capacity {
                    Ok(capacity) => capacity,
                    Err(_) => break,
                },
            };
            let received = tokio::select! {
                biased;
                () = state.shutdown.cancelled() => break,
                () = lease.owner.cancel.cancelled() => break,
                () = sender.closed() => break,
                received = source.recv() => received,
            };
            match received {
                Ok(Some(window)) => match encode_event("content", None, &window) {
                    Ok(event) => {
                        capacity.send(Ok(event));
                    }
                    Err(_) => break,
                },
                Ok(None) => break,
                Err(error) => {
                    failure = Some(pl_studio_runtime::studio_error_from_anyhow(error));
                    break;
                }
            }
        }
        // A watch has its own cancellation token. Never close the shared reader
        // here: other queries and the original conversation must remain valid.
        source.request_close();
        if let Err(error) = source.close().await {
            tracing::warn!(%error, "content SSE watch close failed");
        }
        if let Some(error) = failure {
            let _ = send_json(&sender, &lease.owner.cancel, "error", None, &error).await;
        }
        let _ = sender.try_send(Ok(Event::default().event("closed").data("{}")));
        drop(lease);
    });
    Ok(Sse::new(ReceiverStream::new(receiver))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("")))
}

/// Lossless send: awaits channel capacity so transcript/turn terminal frames are never dropped.
async fn send_json(
    sender: &mpsc::Sender<Result<Event, Infallible>>,
    shutdown: &CancellationToken,
    event_name: &'static str,
    event_id: Option<&str>,
    value: &impl Serialize,
) -> bool {
    let Ok(event) = encode_event(event_name, event_id, value) else {
        return false;
    };
    tokio::select! {
        biased;
        () = shutdown.cancelled() => false,
        sent = sender.send(Ok(event)) => sent.is_ok(),
    }
}

/// Best-effort send for coalescable product updates: reports a full buffer instead of dropping
/// silently, so the caller can deliver one `stale` marker and keep the stream alive.
fn try_send_json(
    sender: &mpsc::Sender<Result<Event, Infallible>>,
    event_name: &'static str,
    event_id: Option<&str>,
    value: &impl Serialize,
) -> Delivery {
    let Ok(event) = encode_event(event_name, event_id, value) else {
        return Delivery::Closed;
    };
    match sender.try_send(Ok(event)) {
        Ok(()) => Delivery::Sent,
        Err(mpsc::error::TrySendError::Full(_)) => Delivery::Stalled,
        Err(mpsc::error::TrySendError::Closed(_)) => Delivery::Closed,
    }
}

/// 无损送达一次 `stale`：等待缓冲容量，因此慢消费者一定收到重同步指令而不是被静默断开。
///
/// 返回 `false` 表示接收端已关闭或事件编码失败，调用方应结束该流。
async fn flush_stale(
    sender: &mpsc::Sender<Result<Event, Infallible>>,
    shutdown: &CancellationToken,
    stale: StaleEvent,
) -> bool {
    let permit = tokio::select! {
        _ = shutdown.cancelled() => return false,
        permit = sender.reserve() => match permit {
            Ok(permit) => permit,
            Err(_) => return false,
        },
    };
    let Ok(event) = encode_event("stale", None, &stale) else {
        return false;
    };
    // 已持有保留容量：`reserve()` 成功即保证这次 `send` 不会失败（接收端关闭会在上面的
    // `reserve()` 分支就已经返回 false），因此这里返回 true 是真实送达，而不是乐观假设。
    permit.send(Ok(event));
    true
}

fn encode_event(
    event_name: &'static str,
    event_id: Option<&str>,
    value: &impl Serialize,
) -> Result<Event, axum::Error> {
    let mut event = Event::default().event(event_name);
    if let Some(event_id) = event_id {
        event = event.id(event_id);
    }
    event.json_data(value)
}
