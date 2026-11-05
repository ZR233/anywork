//! Remote stdio MCP connector backed by `RemoteCommandBackend::spawn_protocol`.

use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use pl_protocol::Result;
use rmcp::model::ProtocolVersion;
use rmcp::service::ClientServiceExt;
use rmcp::transport::async_rw::AsyncRwTransport;

use tokio_util::sync::CancellationToken;

use crate::command::ManagedCommand;
use crate::remote::{RemoteCommandBackend, RemoteProtocolSpawnRequest};

use super::stderr_capture::StderrCapture;
use super::{
    ConnectedMcp, McpConnectRequest, ToolListChangedSink, client_handler, connection_config_error,
    connection_error, discovery_lifecycle,
};

static NEXT_REMOTE_MCP_PROCESS_ID: AtomicU64 = AtomicU64::new(1);

pub(super) async fn connect_remote_stdio(
    request: McpConnectRequest,
    commands: RemoteCommandBackend,
    tool_list_changed: Option<ToolListChangedSink>,
    close_timeout: Duration,
    cancel: CancellationToken,
) -> Result<ConnectedMcp> {
    if cancel.is_cancelled() {
        return Err(connection_error(
            &request.server_id,
            "MCP connection cancelled before remote stdio start",
        ));
    }
    let config = &request.server.config;
    let command_name = config
        .command
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| connection_config_error(&request.server_id, "stdio command is required"))?
        .to_string();

    let cwd = commands
        .resolve_protocol_cwd(config.cwd.as_deref().map(Path::new))
        .map_err(|error| connection_error(&request.server_id, error))?;

    let sequence = NEXT_REMOTE_MCP_PROCESS_ID.fetch_add(1, Ordering::Relaxed);
    let process_id = format!("mcp-stdio-{}-{sequence}", request.server_id);

    let start_control = crate::command::CommandStartControl::new(
        tokio::time::Instant::now() + Duration::from_secs(3600),
        cancel.clone(),
        CancellationToken::new(),
    );
    let mut process = commands
        .spawn_protocol(RemoteProtocolSpawnRequest {
            process_id,
            program: command_name.clone(),
            arguments: config.args.clone(),
            cwd,
            environment: config.env.clone(),
            remove_environment: vec!["BASH_ENV".into(), "ENV".into()],
            start_control: Some(start_control),
        })
        .await
        .map_err(|error| {
            connection_error(
                &request.server_id,
                format!("failed to start remote stdio command {command_name}: {error}"),
            )
        })?;

    let stdin = process.take_stdin();
    let stdout = process.take_stdout();
    let stderr = process.take_stderr();
    let (Some(stdin), Some(stdout)) = (stdin, stdout) else {
        cancel_and_wait_remote_process(process, close_timeout).await;
        return Err(connection_error(
            &request.server_id,
            format!("remote stdio command {command_name} did not expose piped stdio"),
        ));
    };

    let stderr = stderr.map(|stderr| StderrCapture::spawn(stderr, &config.env));
    let transport = AsyncRwTransport::new_client(stdout, stdin);
    let handshake = client_handler(
        &request.server_id,
        ProtocolVersion::V_2026_07_28,
        tool_list_changed,
    )
    .serve_with_lifecycle(transport, discovery_lifecycle());
    let service = tokio::select! {
        biased;
        () = cancel.cancelled() => {
            cancel_and_wait_remote_process(process, close_timeout).await;
            return Err(connection_error(
                &request.server_id,
                "MCP connection cancelled during remote stdio handshake",
            ));
        }
        result = handshake => match result {
            Ok(service) => service,
            Err(error) => {
                tokio::task::yield_now().await;
                let rendered = stderr.as_ref().and_then(StderrCapture::render).map_or_else(
                    || error.to_string(),
                    |stderr| format!("{error}; stderr: {stderr}"),
                );
                cancel_and_wait_remote_process(process, close_timeout).await;
                return Err(connection_error(&request.server_id, rendered));
            }
        }
    };

    Ok(ConnectedMcp::from_running_with_stdio_command(service, process, close_timeout).await)
}

async fn cancel_and_wait_remote_process(mut process: ManagedCommand, close_timeout: Duration) {
    process.cancellation().cancel();
    let _ = tokio::time::timeout(close_timeout, process.wait()).await;
}
