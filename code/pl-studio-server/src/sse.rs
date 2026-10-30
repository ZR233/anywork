use std::convert::Infallible;
use std::time::Duration;

use axum::extract::{Path, State};
use axum::http::HeaderMap;
use axum::response::sse::{Event, KeepAlive, Sse};
use futures::Stream;
use pl_protocol::{
    ActivityContentFrame, ThreadNotification, ThreadSubscriptionUpdate, TimelineCompletionCursor,
    TimelineTailUpdate,
};
use pl_studio_runtime::{ConversationEvent, StudioProductFrame};
use serde::Serialize;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tokio_util::sync::CancellationToken;

use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiQuery, ProductTopicQuery, StudioApiErrors, parse_product_topic};

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
        ("rootThreadId" = Option<String>, Query, description = "SessionCosts topic 的根会话作用域")
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
    let mut query = url::form_urlencoded::Serializer::new(String::from("/api/v1/state/product"));
    match topic {
        StudioProductTopic::Skills { workspace_id } => {
            query.append_pair("topic", "skills");
            query.append_pair("workspaceId", workspace_id);
        }
        StudioProductTopic::SessionCosts { root_thread_id } => {
            query.append_pair("topic", "sessionCosts");
            query.append_pair("rootThreadId", root_thread_id);
        }
        other => {
            query.append_pair("topic", topic_token(other));
        }
    }
    query.finish()
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
        StudioProductTopic::Mcp => "mcp",
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
    }
}

#[derive(Default, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct ConversationQuery {
    timeline_epoch: Option<String>,
    append_seq: Option<u64>,
}

impl ConversationQuery {
    fn resume_after(self) -> Result<Option<TimelineCompletionCursor>, ApiError> {
        match (self.timeline_epoch, self.append_seq) {
            (None, None) => Ok(None),
            (Some(timeline_epoch), Some(append_seq))
                if !timeline_epoch.is_empty() && append_seq <= i64::MAX as u64 =>
            {
                Ok(Some(TimelineCompletionCursor {
                    timeline_epoch,
                    append_seq,
                }))
            }
            _ => Err(pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::InvalidArgument,
                "timelineEpoch and appendSeq must name one accepted completion prefix",
                false,
            )
            .into()),
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ActivityDelivery<'a> {
    frame: &'a ActivityContentFrame,
    completed: Option<&'a TimelineTailUpdate>,
}

/// Mechanical SSE mapping of the same feed used by FRB. Activity Commit keeps
/// its completion batch in one event; HTTP never reduces or queries live text.
#[utoipa::path(
    get,
    path = "/api/v1/threads/{thread_id}/events",
    operation_id = "thread.subscribe",
    params(
        ("thread_id" = String, Path, description = "Thread ID"),
        ("timelineEpoch" = Option<String>, Query, description = "Accepted completion epoch; requires appendSeq"),
        ("appendSeq" = Option<u64>, Query, description = "Exclusive accepted completion prefix; requires timelineEpoch")
    ),
    responses(StudioApiErrors, (status = 200, description = "Authoritative Thread stream", body = String, content_type = "text/event-stream"))
)]
pub(crate) async fn thread_events(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiQuery(query): ApiQuery<ConversationQuery>,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    let resume_after = query.resume_after()?;
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let mut events = state
        .runtime
        .open_conversation_feed(&thread_id, resume_after)
        .await
        .map_err(ApiError::from)?;
    let shutdown = state.shutdown.clone();
    let (sender, receiver) = mpsc::channel(1);
    tokio::spawn(async move {
        let _permit = permit;
        loop {
            let received = tokio::select! {
                biased;
                () = shutdown.cancelled() => break,
                () = sender.closed() => break,
                received = events.recv() => received,
            };
            let event = match received {
                Ok(Some(event)) => event,
                Ok(None) => break,
                Err(error) => {
                    let mapped = pl_studio_runtime::studio_error_from_anyhow(error);
                    let _ = send_json(&sender, &shutdown, "error", None, &mapped).await;
                    break;
                }
            };
            let sent = send_conversation_event(&sender, &shutdown, &event).await;
            if !sent {
                break;
            }
        }
        events.request_close();
        if let Err(error) = events.close().await {
            let mapped = pl_studio_runtime::studio_error_from_anyhow(error);
            tracing::warn!(
                thread_id,
                code = mapped.code.label(),
                "conversation SSE close failed"
            );
        }
        let _ = sender.try_send(Ok(Event::default().event("closed").data("{}")));
    });
    Ok(Sse::new(ReceiverStream::new(receiver))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("")))
}

async fn send_conversation_event(
    sender: &mpsc::Sender<Result<Event, Infallible>>,
    shutdown: &CancellationToken,
    event: &ConversationEvent,
) -> bool {
    match event {
        ConversationEvent::State { update } => {
            let (name, id) = match &**update {
                ThreadSubscriptionUpdate::Snapshot { snapshot } => {
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
            send_json(sender, shutdown, name, Some(&id), update).await
        }
        ConversationEvent::ContentBaseline { baseline } => {
            let id = format!(
                "timeline:{}:{}",
                baseline.timeline_epoch, baseline.completed_cursor.append_seq
            );
            send_json(sender, shutdown, "contentBaseline", Some(&id), baseline).await
        }
        ConversationEvent::ContentUpdate { update } => {
            let id = completion_event_id(update);
            send_json(sender, shutdown, "contentUpdate", Some(&id), update).await
        }
        ConversationEvent::ActivityContent { frame, completed } => {
            send_json(
                sender,
                shutdown,
                "activityContent",
                None,
                &ActivityDelivery {
                    frame,
                    completed: completed.as_deref(),
                },
            )
            .await
        }
    }
}

fn completion_event_id(update: &TimelineTailUpdate) -> String {
    let (epoch, through) = match update {
        TimelineTailUpdate::Batch {
            timeline_epoch,
            through_seq,
            ..
        } => (timeline_epoch, *through_seq),
        TimelineTailUpdate::Reset { baseline } => (
            &baseline.timeline_epoch,
            baseline.completed_cursor.append_seq,
        ),
    };
    format!("timeline:{epoch}:{through}")
}

/// Timeline 内容订阅：每条连接持有自己的有界尾部观察与订阅身份。
///
/// 首帧是 `baseline`（最新小页 + 该连接的 `subscriptionId`），之后只交付该连接的连续 `batch`。只有 epoch
/// 变化才交付 `reset`（新基线），客户端按身份重新对账。没有 durable replay：带
/// `Last-Event-ID` 重连必须建立新基线，不能当作可续读的事件日志。
///
/// 待发送正文最多保留一个批次：核心按连续完成位置补发，不在 transport 侧堆积多份大正文。
/// 读取失败会先交付可见 `error` 再关闭，不静默
/// 循环失败伪装成 EOF。
#[utoipa::path(
    get,
    path = "/api/v1/threads/{thread_id}/timeline/events",
    operation_id = "thread.subscribeTimeline",
    params(("thread_id" = String, Path, description = "Thread ID")),
    responses(StudioApiErrors, (status = 200, description = "Bounded timeline tail", body = String, content_type = "text/event-stream"))
)]
pub(crate) async fn thread_timeline_events(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let mut stream = state
        .runtime
        .open_timeline_tail(&thread_id)
        .await
        .map_err(ApiError::from)?;
    let baseline = stream.initial().await.map_err(ApiError::from)?;
    let shutdown = state.shutdown.clone();
    // 一个批次容量：核心已经合帧，慢消费者由核心判定连续性或重同步，而不是在 transport 堆积。
    let (sender, receiver) = mpsc::channel(1);
    tokio::spawn(async move {
        let _permit = permit;
        if !send_json(&sender, &shutdown, "baseline", None, &baseline).await {
            stream.close();
            return;
        }
        loop {
            let step = tokio::select! {
                _ = shutdown.cancelled() => Step::End,
                _ = sender.closed() => Step::End,
                update = stream.next() => match update {
                    Ok(Some(update)) => Step::Update(update),
                    Ok(None) => Step::End,
                    Err(error) => Step::Failed(error),
                },
            };
            match step {
                Step::Update(update) => {
                    let event_name = match &update {
                        TimelineTailUpdate::Batch { .. } => "batch",
                        TimelineTailUpdate::Reset { .. } => "reset",
                    };
                    let event_id = completion_event_id(&update);
                    if !send_json(&sender, &shutdown, event_name, Some(&event_id), &update).await {
                        break;
                    }
                }
                Step::End => break,
                Step::Failed(error) => {
                    // 错误必须可见，且与 HTTP/FRB 使用同一份类型化分类：只发送映射后的 StudioError，
                    // 不发送原始诊断文本，因此不会泄漏 SQLite/IO 等内部细节，也保留 code、可重试性与
                    // 脱敏 details。随后结束这条流，由客户端重连建立新基线。
                    let mapped = pl_studio_runtime::studio_error_from_anyhow(error);
                    tracing::debug!(
                        thread_id,
                        code = mapped.code.label(),
                        "timeline tail stream ended with a typed error"
                    );
                    let _ = send_json(&sender, &shutdown, "error", None, &mapped).await;
                    break;
                }
            }
        }
        stream.close();
        let _ = sender.try_send(Ok(Event::default().event("closed").data("{}")));
    });
    Ok(Sse::new(ReceiverStream::new(receiver))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("")))
}

/// 一次循环里要处理的结果，避免在 `select!` 表达式中借用 `stream`。
enum Step {
    Update(TimelineTailUpdate),
    Failed(anyhow::Error),
    End,
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
