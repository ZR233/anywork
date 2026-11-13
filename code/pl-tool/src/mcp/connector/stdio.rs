//! Shared MCP stdio framing over a concrete executor Child.
use super::{
    ConnectedMcp, McpConnectRequest, ToolListChangedSink, client_handler, connection_config_error,
    connection_error, startup_lifecycle, stderr_capture::StderrCapture,
};
use crate::mcp::config::McpExecutionContext;
use pl_protocol::Result;
use rmcp::transport::async_rw::AsyncRwTransport;
use std::time::Duration;
use tokio_util::sync::CancellationToken;
pub(super) async fn connect(
    request: McpConnectRequest,
    executor: pl_remote_helper::Executor,
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

    let (program, arguments, cwd) = match &request.server.execution_context {
        McpExecutionContext::Host => {
            let (_, resolved) = super::resolve_stdio_program(&request)?;
            let program = resolved
                .executable
                .into_os_string()
                .into_string()
                .map_err(|_| connection_error(&request.server_id, "stdio program is not UTF-8"))?;
            let mut args = resolved
                .prefix_args
                .into_iter()
                .map(|arg| {
                    arg.into_string().map_err(|_| {
                        connection_error(&request.server_id, "stdio argument is not UTF-8")
                    })
                })
                .collect::<Result<Vec<_>>>()?;
            args.extend(config.args.clone());
            (program, args, config.cwd.clone())
        }
        McpExecutionContext::Remote { commands } => {
            let cwd =
                commands.resolve_protocol_cwd(config.cwd.as_deref().map(std::path::Path::new))?;
            commands.validate_cwd(&cwd).await?;
            (command_name.clone(), config.args.clone(), Some(cwd))
        }
    };
    let mut command = executor.command(program);
    command
        .args(arguments)
        .envs(config.env.clone())
        .env_remove("BASH_ENV")
        .env_remove("ENV")
        .stdin(pl_remote_helper::Stdio::Piped)
        .stdout(pl_remote_helper::Stdio::Piped)
        .stderr(pl_remote_helper::Stdio::Piped);
    if let Some(cwd) = cwd {
        command.current_dir(cwd);
    }
    let child = tokio::select! {
        biased;
        _=cancel.cancelled()=>return Err(connection_error(&request.server_id,"MCP stdio start cancelled")),
        result=command.spawn()=>result.map_err(|error|connection_error(&request.server_id,error))?,
    };
    let mut process = crate::command::managed_child(child, None);

    let stdin = process.take_stdin();
    let stdout = process.take_stdout();
    let stderr = process.take_stderr();
    let (Some(stdin), Some(stdout)) = (stdin, stdout) else {
        super::close_stdio_command(Some(process))
            .await
            .map_err(|error| connection_error(&request.server_id, error))?;
        return Err(connection_error(
            &request.server_id,
            format!("remote stdio command {command_name} did not expose piped stdio"),
        ));
    };

    let stderr = stderr.map(|stderr| StderrCapture::spawn(stderr, &config.env));
    let transport = AsyncRwTransport::new_client(stdout, stdin);
    let (protocol_version, lifecycle) = startup_lifecycle(config.startup_mode);
    let handshake = client_handler(&request.server_id, protocol_version, tool_list_changed)
        .serve_observed(transport, lifecycle);
    let service = tokio::select! {
        biased;
        () = cancel.cancelled() => {
            super::close_stdio_command(Some(process)).await.map_err(|error|connection_error(&request.server_id,error))?;
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
                super::close_stdio_command(Some(process)).await.map_err(|error|connection_error(&request.server_id,error))?;
                return Err(connection_error(&request.server_id, rendered));
            }
        }
    };

    Ok(ConnectedMcp::from_running_with_stdio_command(service, process, close_timeout).await)
}
