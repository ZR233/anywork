use std::convert::Infallible;
use std::time::Duration;

use axum::extract::{Path, State};
use axum::http::HeaderMap;
use axum::response::sse::{Event, KeepAlive, Sse};
use futures::Stream;
use pl_protocol::{
    ThreadNotification, ThreadSubscriptionRequest, ThreadSubscriptionUpdate, TimelineTailUpdate,
};
use pl_studio_runtime::StudioProductFrame;
use serde::Serialize;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tokio_util::sync::CancellationToken;

use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiQuery, ProductTopicQuery, StudioApiErrors, parse_product_topic};

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
        ("projectId" = Option<String>, Query, description = "Skills topic 的项目作用域"),
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
                    if !send_json(&sender, "baseline", Some(&event_id), &*baseline).await {
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
        StudioProductTopic::Skills { project_id } => {
            query.append_pair("topic", "skills");
            query.append_pair("projectId", project_id);
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
        StudioProductTopic::ModelPerformance => "modelPerformance",
        StudioProductTopic::SessionCosts { .. } => "sessionCosts",
        StudioProductTopic::Updater => "updater",
        StudioProductTopic::Persistence => "persistence",
        StudioProductTopic::PersistenceQueue => "persistenceQueue",
        StudioProductTopic::AgentProfiles => "agentProfiles",
    }
}

/// 状态订阅：只转发当前执行、活动、交互与运行时状态。
///
/// 内容**不**经本流传送，也不再让客户端据此去重读历史页：内容有自己的通道
/// `/api/v1/threads/{id}/timeline/events`（基线 + 连续补丁／显式重同步）与
/// `/api/v1/threads/{id}/timeline`（无状态页），与 FRB 的 `BridgeTimeline` 用同一份共享会话事实。
/// 旧 `itemStarted`/`itemDelta`/`itemCompleted` 事件已删除——内容只有这一条推送源。
#[utoipa::path(
    get,
    path = "/api/v1/threads/{thread_id}/events",
    operation_id = "thread.subscribe",
    params(("thread_id" = String, Path, description = "Thread ID")),
    responses(StudioApiErrors, (status = 200, description = "Authoritative Thread stream", body = String, content_type = "text/event-stream"))
)]
pub(crate) async fn thread_events(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let mut events = state
        .runtime
        .subscribe_thread(ThreadSubscriptionRequest {
            thread_id: thread_id.clone(),
        })
        .await
        .map_err(ApiError::from)?;
    let residency_pin = state.runtime.pin_thread(&thread_id);
    let shutdown = state.shutdown.clone();
    let has_cursor = headers.contains_key("last-event-id");
    let (sender, receiver) = mpsc::channel(128);
    tokio::spawn(async move {
        let _permit = permit;
        let _residency_pin = residency_pin;
        if has_cursor
            && !send_json(
                &sender,
                "stale",
                None,
                &StaleEvent {
                    reason: "replayUnsupported",
                    dropped: None,
                    resync: "resubscribe".to_string(),
                },
            )
            .await
        {
            return;
        }
        loop {
            tokio::select! {
                _ = shutdown.cancelled() => break,
                _ = sender.closed() => break,
                update = events.recv() => {
                    let update = match update {
                        Ok(Some(update)) => update,
                        Ok(None) => break,
                        Err(error) => {
                            send_json(
                                &sender,
                                "error",
                                None,
                                &serde_json::json!({"message": error.to_string()}),
                            )
                            .await;
                            break;
                        }
                    };
                    let (event_name, event_id) = match &update {
                        ThreadSubscriptionUpdate::Snapshot { snapshot } => (
                            "snapshot",
                            Some(format!("thread:{}", snapshot.revision)),
                        ),
                        ThreadSubscriptionUpdate::Notification { notification } => {
                            let name = if matches!(notification.notification, ThreadNotification::Lagged { .. }) {
                                "lagged"
                            } else {
                                "notification"
                            };
                            // 事件 id 携带 stream epoch 与 revision；客户端据此判断缺口，
                            // 重连时 SSE 仍然只发 `stale`，由数据库窗口重同步。
                            (
                                name,
                                Some(format!(
                                    "thread:{}:{}",
                                    notification.epoch, notification.revision
                                )),
                            )
                        }
                    };
                    if !send_json(&sender, event_name, event_id.as_deref(), &update).await {
                        return;
                    }
                }
            }
        }
        let _ = sender.try_send(Ok(Event::default().event("closed").data("{}")));
    });
    Ok(Sse::new(ReceiverStream::new(receiver))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("")))
}

/// Timeline 内容订阅：每条连接持有自己的有界尾部观察与订阅身份。
///
/// 首帧是 `baseline`（最新小页 + 该连接的 `subscriptionId`），之后只交付该连接的连续 `patch`。无法连续
/// 表达时交付一次 `resync`（同订阅身份 + 新基线），客户端按身份重新对账。没有 durable replay：带
/// `Last-Event-ID` 重连必须建立新基线，不能当作可续读的事件日志。
///
/// 待发送正文最多保留一个批次：核心已经把普通正文合帧，并且只在消费者落后超出可证连续范围时给出
/// `resync`，因此这里不在 transport 侧堆积多份大正文。读取失败会先交付可见 `error` 再关闭，不静默
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
    let baseline = stream.initial().map_err(ApiError::from)?;
    let shutdown = state.shutdown.clone();
    // 一个批次容量：核心已经合帧，慢消费者由核心判定连续性或重同步，而不是在 transport 堆积。
    let (sender, receiver) = mpsc::channel(1);
    tokio::spawn(async move {
        let _permit = permit;
        if !send_json(&sender, "baseline", None, &baseline).await {
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
                    let (event_name, event_id) = match &update {
                        TimelineTailUpdate::Patch { to, .. } => {
                            ("patch", Some(format!("timeline:{to}")))
                        }
                        TimelineTailUpdate::Resync { baseline, .. } => {
                            ("resync", Some(format!("timeline:{}", baseline.version)))
                        }
                    };
                    if !send_json(&sender, event_name, event_id.as_deref(), &update).await {
                        return;
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
                    let _ = send_json(&sender, "error", None, &mapped).await;
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
    event_name: &'static str,
    event_id: Option<&str>,
    value: &impl Serialize,
) -> bool {
    let Ok(event) = encode_event(event_name, event_id, value) else {
        return false;
    };
    sender.send(Ok(event)).await.is_ok()
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
