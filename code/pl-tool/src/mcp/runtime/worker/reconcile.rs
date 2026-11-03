use std::collections::{BTreeMap, VecDeque};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use futures::future::BoxFuture;
use futures::stream::{FuturesUnordered, StreamExt};
use pl_protocol::{PureError, Result};
use tokio_util::sync::CancellationToken;

use super::super::{McpGeneration, McpResetScope};
use super::redaction::McpErrorRedactor;
use super::server::{
    RuntimeGeneration, RuntimeServer, assign_tool_descriptors, server_descriptor,
    server_fingerprint,
};
use super::tools::{configured_startup_timeout, configured_tool_timeout, filter_tool_definitions};
use crate::mcp::config::EffectiveMcpServerConfig;
use crate::mcp::config::McpServerStatusKind;
use crate::mcp::health::McpAvailabilityKind;
use crate::mcp::{McpConnectRequest, McpConnector};

pub(super) struct PendingReconcile {
    pub(super) servers: BTreeMap<String, EffectiveMcpServerConfig>,
    pub(super) reset_scope: Option<McpResetScope>,
    pub(super) reply: tokio::sync::oneshot::Sender<Result<()>>,
}

pub(super) struct ActivePreparation {
    pub(super) future: BoxFuture<'static, RuntimeGeneration>,
    pub(super) cancel: CancellationToken,
    pub(super) reply: tokio::sync::oneshot::Sender<Result<()>>,
    pub(super) reset_scope: Option<McpResetScope>,
}

pub(super) async fn await_preparation(
    preparation: &mut Option<ActivePreparation>,
) -> RuntimeGeneration {
    preparation
        .as_mut()
        .expect("guarded MCP preparation must exist")
        .future
        .as_mut()
        .await
}

pub(super) async fn cancel_and_collect_reconciles(
    preparation: Option<ActivePreparation>,
    pending: &mut VecDeque<PendingReconcile>,
) -> Option<RuntimeGeneration> {
    for request in pending.drain(..) {
        let _ = request.reply.send(Err(runtime_stopping_error()));
    }
    let active = preparation?;
    let _ = active.reply.send(Err(runtime_stopping_error()));
    active.cancel.cancel();
    Some(active.future.await)
}

fn runtime_stopping_error() -> PureError {
    PureError::ToolExecutionFailed {
        tool: "mcp".to_string(),
        error: "MCP runtime stopped while preparing a generation".to_string(),
    }
}

pub(super) async fn prepare_generation(
    connector: McpConnector,
    generation_id: McpGeneration,
    servers: BTreeMap<String, EffectiveMcpServerConfig>,
    mut reusable: BTreeMap<String, RuntimeServer>,
    cancel: CancellationToken,
) -> RuntimeGeneration {
    let mut next = RuntimeGeneration::empty(generation_id);
    let mut connecting = FuturesUnordered::new();
    for (server_id, config) in servers {
        let fingerprint = server_fingerprint(&config);
        let server = match config.status_kind {
            McpServerStatusKind::Disabled => Some(RuntimeServer::terminal(
                &config,
                fingerprint,
                McpAvailabilityKind::Disabled,
                Some("MCP server is disabled in configuration".to_string()),
            )),
            McpServerStatusKind::MissingCredential => Some(RuntimeServer::terminal(
                &config,
                fingerprint,
                McpAvailabilityKind::MissingCredential,
                config.status_message.clone(),
            )),
            McpServerStatusKind::Enabled => reusable.remove(&server_id).filter(|server| {
                server.fingerprint == fingerprint
                    && server.availability == McpAvailabilityKind::Available
            }),
        };
        if let Some(server) = server {
            next.servers.insert(server.descriptor.id.clone(), server);
            continue;
        }
        let connector = connector.clone();
        let server_cancel = cancel.child_token();
        connecting.push(async move {
            let server =
                connect_server(&connector, server_id, config, fingerprint, server_cancel).await;
            (server.descriptor.id.clone(), server)
        });
    }
    while let Some((server_id, server)) = connecting.next().await {
        next.servers.insert(server_id, server);
    }
    assign_tool_descriptors(&mut next.servers);
    next
}

async fn connect_server(
    connector: &McpConnector,
    server_id: String,
    config: EffectiveMcpServerConfig,
    fingerprint: u64,
    cancel: CancellationToken,
) -> RuntimeServer {
    let descriptor = server_descriptor(&config);
    let server_config = config.config.clone();
    let redactor = McpErrorRedactor::new(&config);
    if cancel.is_cancelled() {
        return RuntimeServer::unavailable(
            descriptor,
            fingerprint,
            "MCP generation preparation was cancelled".to_string(),
            server_config,
            redactor,
        );
    }
    let startup_timeout = configured_startup_timeout(config.config.startup_timeout_secs);
    let request_timeout = configured_tool_timeout(config.config.tool_timeout_secs);
    let connect_cancel = cancel.child_token();
    let timed_out = Arc::new(AtomicBool::new(false));
    let timeout_flag = timed_out.clone();
    let timeout_token = connect_cancel.clone();
    let timer = tokio::spawn(async move {
        tokio::time::sleep(startup_timeout).await;
        timeout_flag.store(true, Ordering::Release);
        timeout_token.cancel();
    });
    let connected = connector
        .connect_cancellable(
            McpConnectRequest {
                server_id,
                server: config.clone(),
            },
            connect_cancel,
        )
        .await;
    timer.abort();
    let session = match connected {
        Ok(session) => Arc::new(session),
        Err(error) => {
            if timed_out.load(Ordering::Acquire) && !cancel.is_cancelled() {
                return RuntimeServer::unavailable(
                    descriptor,
                    fingerprint,
                    format!(
                        "MCP health check timed out after {} seconds",
                        startup_timeout.as_secs()
                    ),
                    server_config,
                    redactor,
                );
            }
            return RuntimeServer::unavailable(
                descriptor,
                fingerprint,
                redactor.redact(error.to_string()),
                server_config,
                redactor,
            );
        }
    };
    let supports_resources = session.supports_resources();
    let discovery = tokio::select! {
        biased;
        () = cancel.cancelled() => None,
        result = tokio::time::timeout(startup_timeout, session.list_tools()) => Some(result),
    };
    match discovery {
        None => {
            let mut unavailable = RuntimeServer::unavailable(
                descriptor,
                fingerprint,
                "MCP generation preparation was cancelled".to_string(),
                server_config,
                redactor,
            );
            unavailable.session = Some(session);
            unavailable
        }
        Some(Ok(Ok(tools))) => RuntimeServer::available(super::server::AvailableRuntimeServer {
            descriptor,
            fingerprint,
            session,
            definitions: filter_tool_definitions(tools, &config.config),
            supports_resources,
            request_timeout,
            config: server_config,
            tool_effect: config.tool_effect,
            redactor,
        }),
        Some(Ok(Err(error))) => {
            let close_failed = if let Err(close_error) = session.close().await {
                tracing::warn!(
                    %close_error,
                    "MCP session did not confirm closure after discovery failure"
                );
                true
            } else {
                false
            };
            let message = redactor.redact(error.to_string());
            let mut unavailable = RuntimeServer::unavailable(
                descriptor,
                fingerprint,
                message,
                server_config,
                redactor,
            );
            if close_failed {
                unavailable.session = Some(session);
            }
            unavailable
        }
        Some(Err(_)) => {
            let close_failed = if let Err(close_error) = session.close().await {
                tracing::warn!(
                    %close_error,
                    "MCP session did not confirm closure after discovery timeout"
                );
                true
            } else {
                false
            };
            let mut unavailable = RuntimeServer::unavailable(
                descriptor,
                fingerprint,
                format!(
                    "MCP tool discovery timed out after {} seconds",
                    startup_timeout.as_secs()
                ),
                server_config,
                redactor,
            );
            if close_failed {
                unavailable.session = Some(session);
            }
            unavailable
        }
    }
}
