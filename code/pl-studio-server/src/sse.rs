use std::convert::Infallible;
use std::time::Duration;

use axum::extract::State;
use axum::http::HeaderMap;
use axum::response::sse::{Event, KeepAlive, Sse};
use futures::Stream;
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
                pl_studio_runtime::McpScope::Host => {
                    query.append_pair("scope", "host");
                }
                pl_studio_runtime::McpScope::Ssh { ssh_alias } => {
                    query.append_pair("scope", "ssh");
                    query.append_pair("sshAlias", ssh_alias);
                }
            }
        }
        StudioProductTopic::ThreadMcp { thread_id } => {
            query.append_pair("topic", "threadMcp");
            query.append_pair("threadId", thread_id);
        }
        StudioProductTopic::ThreadLsp { thread_id } => {
            query.append_pair("topic", "threadLsp");
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
        StudioProductTopic::ThreadLsp { .. } => "threadLsp",
        StudioProductTopic::Lsp => "lsp",
        StudioProductTopic::Skills { .. } => "skills",
        StudioProductTopic::ThreadModeCatalog => "threadModeCatalog",
        StudioProductTopic::AcpAuth => "acpAuth",
        StudioProductTopic::AcpInstall => "acpInstall",
        StudioProductTopic::AcpLocalDetection => "acpLocalDetection",
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

/// Lossless send for baseline and non-coalescable frames.
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

/// Best-effort send for coalescable product updates. A full buffer is reported so the
/// caller can deliver one `stale` marker instead of silently treating the update as sent.
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

/// Wait for room and deliver a `stale` marker without dropping the resynchronization signal.
async fn flush_stale(
    sender: &mpsc::Sender<Result<Event, Infallible>>,
    shutdown: &CancellationToken,
    stale: StaleEvent,
) -> bool {
    let permit = tokio::select! {
        biased;
        () = shutdown.cancelled() => return false,
        permit = sender.reserve() => match permit {
            Ok(permit) => permit,
            Err(_) => return false,
        },
    };
    let Ok(event) = encode_event("stale", None, &stale) else {
        return false;
    };
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

#[cfg(test)]
mod tests {
    use anyhow::{Context, Result};
    use axum::{extract::FromRequestParts, http::Request};
    use pl_studio_runtime::StudioErrorCode;

    use super::*;

    async fn product_topic(uri: &str) -> Result<pl_studio_runtime::StudioProductTopic, ApiError> {
        let (mut parts, _) = Request::builder().uri(uri).body(()).unwrap().into_parts();
        let ApiQuery(query) =
            ApiQuery::<ProductTopicQuery>::from_request_parts(&mut parts, &()).await?;
        parse_product_topic(&query)
    }

    #[tokio::test]
    async fn product_resync_preserves_topic_and_encoded_scope() {
        use pl_studio_runtime::StudioProductTopic;

        let identity = " 宿主 /?&=+#% ";
        for topic in [
            StudioProductTopic::ProjectDirectory,
            StudioProductTopic::AcpLocalDetection,
            StudioProductTopic::Skills {
                workspace_id: identity.into(),
            },
            StudioProductTopic::SessionCosts {
                root_thread_id: identity.into(),
            },
            StudioProductTopic::ChildInteractions {
                host_thread_id: identity.into(),
            },
            StudioProductTopic::McpCatalog {
                scope: pl_studio_runtime::McpScope::Host,
            },
            StudioProductTopic::McpCatalog {
                scope: pl_studio_runtime::McpScope::Ssh {
                    ssh_alias: identity.into(),
                },
            },
            StudioProductTopic::ThreadMcp {
                thread_id: identity.into(),
            },
        ] {
            let resync = topic_resync_path(&topic);
            let uri: axum::http::Uri = resync.parse().unwrap();
            assert_eq!(uri.path(), "/api/v1/state/product");
            let parsed = product_topic(&resync)
                .await
                .unwrap_or_else(|error| panic!("invalid resync URI {resync}: {}", error.0));
            assert_eq!(parsed, topic);
        }
    }

    #[tokio::test]
    async fn child_interactions_query_requires_exactly_its_host_scope() {
        use pl_studio_runtime::StudioProductTopic;

        let valid = "/?topic=childInteractions&hostThreadId=host-a";
        assert!(matches!(
            product_topic(valid).await,
            Ok(StudioProductTopic::ChildInteractions { host_thread_id }) if host_thread_id == "host-a"
        ));
        for uri in [
            "/?topic=childInteractions",
            "/?topic=childInteractions&hostThreadId=",
            "/?topic=childInteractions&hostThreadId=%20%09",
            "/?topic=childInteractions&workspaceId=host-a",
            "/?topic=childInteractions&rootThreadId=host-a",
            "/?topic=childInteractions&hostThreadId=host-a&workspaceId=workspace-a",
            "/?topic=childInteractions&hostThreadId=host-a&rootThreadId=root-a",
            "/?topic=childInteractions&hostThreadId=host-a&hostThreadId=host-b",
            "/?topic=childInteractions&host_thread_id=host-a",
            "/?topic=projectDirectory&hostThreadId=host-a",
            "/?topic=skills&workspaceId=workspace-a&hostThreadId=host-a",
            "/?topic=sessionCosts&rootThreadId=root-a&hostThreadId=host-a",
        ] {
            let Err(error) = product_topic(uri).await else {
                panic!("invalid topic scope was admitted: {uri}");
            };
            assert_eq!(error.0.code, StudioErrorCode::InvalidArgument, "{uri}");
        }
    }

    #[test]
    fn openapi_has_history_and_unified_feed_ports_without_legacy_current() -> Result<()> {
        let document = serde_json::to_value(crate::openapi_document())?;
        let paths = document["paths"].as_object().context("missing paths")?;
        for path in [
            "/api/v1/threads/{thread_id}/history/open",
            "/api/v1/threads/{thread_id}/history/timeline",
            "/api/v1/threads/{thread_id}/history/turns",
            "/api/v1/threads/{thread_id}/history/event",
            "/api/v1/threads/{thread_id}/history/body",
            "/api/v1/threads/{thread_id}/history/changed",
            "/api/v1/threads/{thread_id}/history/close",
            "/api/v1/threads/{thread_id}/feed/open",
            "/api/v1/threads/{thread_id}/feed/{feed_id}/older",
            "/api/v1/threads/{thread_id}/feed/{feed_id}/work-group",
            "/api/v1/threads/{thread_id}/feed/{feed_id}/body",
            "/api/v1/threads/{thread_id}/feed/{feed_id}/detail",
            "/api/v1/threads/{thread_id}/feed/{feed_id}/reset",
            "/api/v1/threads/{thread_id}/feed/{feed_id}/close",
        ] {
            assert!(paths[path]["post"].is_object(), "{path}");
        }
        for path in [
            "/api/v1/threads/{thread_id}/feed/{feed_id}/events",
            "/api/v1/threads/{thread_id}/feed/{feed_id}/meta",
        ] {
            assert!(paths[path]["get"].is_object(), "{path}");
        }
        assert!(
            paths.keys().all(|path| !path.contains("/current/")),
            "legacy CurrentReader routes remain in OpenAPI"
        );
        assert!(
            paths.keys().all(|path| !path.contains("/timeline/")),
            "legacy timeline pipeline remains in OpenAPI"
        );
        assert!(
            paths.keys().all(|path| !path.ends_with("/state/events")),
            "legacy State feed remains in OpenAPI"
        );
        let schemas = &document["components"]["schemas"];
        for removed in ["ViewUpdate", "TailUpdate", "TailSnapshot", "HistoryDelta"] {
            assert!(
                schemas.get(removed).is_none(),
                "{removed} remains in OpenAPI"
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn full_sse_send_ends_on_shutdown_or_receiver_close() {
        use std::task::Poll;

        for disconnect in [false, true] {
            let shutdown = CancellationToken::new();
            let (sender, receiver) = mpsc::channel(1);
            assert!(send_json(&sender, &shutdown, "baseline", None, &"held").await);
            let send = send_json(&sender, &shutdown, "batch", None, &"blocked");
            tokio::pin!(send);
            assert!(matches!(futures::poll!(send.as_mut()), Poll::Pending));
            if disconnect {
                drop(receiver);
            } else {
                shutdown.cancel();
            }
            assert!(matches!(futures::poll!(send.as_mut()), Poll::Ready(false)));
        }
    }
}
