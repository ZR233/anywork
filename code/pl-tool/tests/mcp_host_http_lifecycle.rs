//! Host HTTP bootstrap cancellation and the protocol paths sharing its backend.

use std::{convert::Infallible, sync::Arc, time::Duration};

use axum::{
    Json, Router,
    body::{Body, Bytes},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    routing::{any, get, post},
};
use pl_tool::mcp::{
    McpConnectRequest, McpConnector,
    config::{
        EffectiveMcpServerConfig, McpExecutionContext, McpServerMutationPolicy,
        McpServerSourceKind, McpServerStatusKind,
    },
};
use rmcp::model::{DiscoverResult, ProtocolVersion, ServerCapabilities, ToolsCapability};
use tokio_util::sync::CancellationToken;

fn request(url: String) -> McpConnectRequest {
    McpConnectRequest {
        server_id: "host-http".into(),
        server: EffectiveMcpServerConfig {
            id: "host-http".into(),
            source_kind: McpServerSourceKind::User,
            source_label: "test".into(),
            source_detail: None,
            status_kind: McpServerStatusKind::Enabled,
            status_message: None,
            mutation_policy: McpServerMutationPolicy::UserEditable,
            bearer_token: Some("fixture-token".into()),
            tool_effect: None,
            execution_context: McpExecutionContext::Host,
            config: serde_json::from_value(serde_json::json!({
                "transport": "streamableHttp",
                "url": url,
                "headers": { "x-fixture": "fixture-header" }
            }))
            .expect("fixture config"),
        },
    }
}

async fn serve(
    app: Router,
) -> anyhow::Result<(
    String,
    CancellationToken,
    tokio::task::JoinHandle<std::io::Result<()>>,
)> {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
    let url = format!("http://{}", listener.local_addr()?);
    let stop = CancellationToken::new();
    let task = tokio::spawn(
        axum::serve(listener, app)
            .with_graceful_shutdown(stop.clone().cancelled_owned())
            .into_future(),
    );
    Ok((url, stop, task))
}

#[tokio::test]
async fn cancelled_host_http_bootstrap_releases_json_and_sse_bodies() -> anyhow::Result<()> {
    for content_type in ["application/json", "text/event-stream"] {
        let streaming = CancellationToken::new();
        let dropped = CancellationToken::new();
        let app = Router::new().route(
            "/mcp",
            post({
                let streaming = streaming.clone();
                let dropped = dropped.clone();
                move || {
                    let streaming = streaming.clone();
                    let guard = dropped.clone().drop_guard();
                    async move {
                        let body = futures::stream::once(async move {
                            let _guard = guard;
                            streaming.cancel();
                            std::future::pending::<Result<Bytes, Infallible>>().await
                        });
                        (
                            [(axum::http::header::CONTENT_TYPE, content_type)],
                            Body::from_stream(body),
                        )
                    }
                }
            }),
        );
        let (url, stop, server) = serve(app).await?;
        let connector = McpConnector::default();
        let mut connecting = Box::pin(connector.connect(request(format!("{url}/mcp"))));
        tokio::select! {
            result = &mut connecting => panic!("bootstrap unexpectedly completed: {result:?}"),
            () = streaming.cancelled() => {}
            () = tokio::time::sleep(Duration::from_secs(2)) => panic!("fixture was not reached"),
        }
        drop(connecting);
        // The server owns the body until the client physically disconnects.
        // Do not stop the server first: that would hide an abandoned worker.
        let released = tokio::time::timeout(Duration::from_secs(2), dropped.cancelled()).await;
        stop.cancel();
        tokio::time::timeout(Duration::from_secs(2), server).await???;
        released.unwrap_or_else(|_| panic!("{content_type} bootstrap body was not released"));
    }
    Ok(())
}

#[tokio::test]
async fn host_http_discovery_and_legacy_initialize_keep_roundtrip_and_cleanup() -> anyhow::Result<()>
{
    for legacy in [false, true] {
        let methods = Arc::new(std::sync::Mutex::new(Vec::new()));
        let deleted = CancellationToken::new();
        let app = Router::new()
            .route(
                "/entry",
                any(|| async { (StatusCode::TEMPORARY_REDIRECT, [("location", "/mcp")]) }),
            )
            .route(
                "/mcp",
                post({
                    let methods = methods.clone();
                    move |headers: HeaderMap, Json(message): Json<serde_json::Value>| {
                        let methods = methods.clone();
                        async move {
                            assert_eq!(headers["authorization"], "Bearer fixture-token");
                            assert_eq!(headers["x-fixture"], "fixture-header");
                            let method = message["method"].as_str().unwrap().to_owned();
                            methods.lock().unwrap().push(method.clone());
                            let result = match method.as_str() {
                                "server/discover" if legacy => {
                                    return Json(serde_json::json!({
                                        "jsonrpc": "2.0", "id": message["id"],
                                        "error": { "code": -32601, "message": "method not found" }
                                    })).into_response();
                                }
                                "server/discover" => {
                                    let mut capabilities = ServerCapabilities::default();
                                    capabilities.tools = Some(ToolsCapability::default());
                                    serde_json::to_value(DiscoverResult::new(
                                        vec![ProtocolVersion::V_2026_07_28],
                                        capabilities,
                                    )).unwrap()
                                }
                                "initialize" => serde_json::json!({
                                    "protocolVersion": "2025-11-25",
                                    "capabilities": { "tools": {} },
                                    "serverInfo": { "name": "fixture", "version": "1" }
                                }),
                                "notifications/initialized" => return StatusCode::ACCEPTED.into_response(),
                                "tools/list" => serde_json::json!({
                                    "tools": [{ "name": "echo", "inputSchema": { "type": "object" } }]
                                }),
                                "tools/call" => serde_json::json!({
                                    "content": [{ "type": "text", "text": "roundtrip" }]
                                }),
                                _ => panic!("unexpected method: {method}"),
                            };
                            let mut response = Json(serde_json::json!({
                                "jsonrpc": "2.0", "id": message["id"], "result": result
                            })).into_response();
                            if method == "initialize" {
                                response.headers_mut().insert("mcp-session-id", "fixture-session".parse().unwrap());
                            }
                            response
                        }
                    }
                })
                .get(|| async { StatusCode::METHOD_NOT_ALLOWED })
                .delete({
                    let deleted = deleted.clone();
                    move |headers: HeaderMap| {
                        let deleted = deleted.clone();
                        async move {
                            assert_eq!(headers["mcp-session-id"], "fixture-session");
                            deleted.cancel();
                            StatusCode::OK
                        }
                    }
                }),
            );
        let (url, stop, server) = serve(app).await?;
        let session = tokio::time::timeout(
            Duration::from_secs(5),
            McpConnector::default().connect(request(format!("{url}/entry"))),
        )
        .await??;
        let tools = session.list_tools().await?;
        assert_eq!(tools.len(), 1);
        assert_eq!(tools[0].name, "echo");
        let reply = session
            .call_tool("echo".into(), serde_json::json!({}))
            .await?;
        assert_eq!(reply.content[0].as_text().unwrap().text, "roundtrip");
        session.close().await?;
        session.close().await?;
        assert_eq!(
            deleted.is_cancelled(),
            legacy,
            "legacy session DELETE must complete before close"
        );
        let methods = methods.lock().unwrap().clone();
        assert_eq!(methods[0], "server/discover");
        assert_eq!(methods.contains(&"initialize".to_owned()), legacy);
        assert_eq!(
            methods.contains(&"notifications/initialized".to_owned()),
            legacy
        );
        stop.cancel();
        tokio::time::timeout(Duration::from_secs(2), server).await???;
    }
    Ok(())
}

#[tokio::test]
async fn host_http_does_not_forward_custom_credentials_across_origin() -> anyhow::Result<()> {
    let received = CancellationToken::new();
    let app = Router::new().route(
        "/mcp",
        get({
            let received = received.clone();
            move || async move {
                received.cancel();
                StatusCode::OK
            }
        })
        .post({
            let received = received.clone();
            move || async move {
                received.cancel();
                StatusCode::OK
            }
        }),
    );
    let (destination, destination_stop, destination_server) = serve(app).await?;
    let app = Router::new().route(
        "/mcp",
        post(move || {
            let destination = destination.clone();
            async move {
                (
                    StatusCode::TEMPORARY_REDIRECT,
                    [("location", format!("{destination}/mcp"))],
                )
            }
        }),
    );
    let (origin, origin_stop, origin_server) = serve(app).await?;
    let result = tokio::time::timeout(
        Duration::from_secs(2),
        McpConnector::default().connect(request(format!("{origin}/mcp"))),
    )
    .await?;
    assert!(
        result.is_err(),
        "cross-origin redirects must remain rejected"
    );
    assert!(
        !received.is_cancelled(),
        "no request may reach the other origin"
    );
    origin_stop.cancel();
    destination_stop.cancel();
    tokio::time::timeout(Duration::from_secs(2), origin_server).await???;
    tokio::time::timeout(Duration::from_secs(2), destination_server).await???;
    Ok(())
}
