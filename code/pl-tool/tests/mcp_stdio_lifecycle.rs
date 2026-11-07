//! Local MCP stdio handshake, framing and cancellation through real child pipes.
#[cfg(target_os = "linux")]
#[path = "support/helper.rs"]
mod helper;
#[path = "support/mcp_stdio.rs"]
mod stdio;

use pl_tool::mcp::config::McpExecutionContext;
use pl_tool::mcp::{McpConnectRequest, McpConnector};
use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use stdio::{STDIO_MCP_SCRIPT, stdio_effective_config, write_python_mcp_server};

/// T06: `ConnectedMcp::close` does not block waiting for an in-flight `call_tool` / `read_resource`
/// before taking `owner` and cancelling the service.
#[tokio::test]
async fn t06_close_does_not_block_on_inflight_call_tool() -> anyhow::Result<()> {
    let temp = tempfile::tempdir()?;
    let script = write_python_mcp_server(temp.path(), "server.py", STDIO_MCP_SCRIPT);
    let mut env = BTreeMap::new();
    env.insert("MCP_HANG_CALL_MS".to_owned(), "10000".to_owned());

    let connector = McpConnector::default();
    #[cfg(target_os = "linux")]
    let connector = connector.with_stdio_worker(helper::remote_helper_executable().to_path_buf());
    let config = stdio_effective_config(
        "slow-call",
        &script,
        Vec::new(),
        env,
        Some(temp.path().to_string_lossy().into_owned()),
        McpExecutionContext::Host,
    );
    let session = Arc::new(
        connector
            .connect(McpConnectRequest {
                server_id: "slow-call".to_owned(),
                server: config,
            })
            .await?,
    );

    let call_session = session.clone();
    let call_task = tokio::spawn(async move {
        call_session
            .call_tool("inspect_env".to_owned(), serde_json::json!({}))
            .await
    });

    tokio::time::sleep(Duration::from_millis(100)).await;
    let close_start = Instant::now();
    session.close().await?;
    assert!(
        close_start.elapsed() < Duration::from_secs(3),
        "close() blocked on in-flight call_tool instead of cancelling immediately"
    );
    let call_result = tokio::time::timeout(Duration::from_secs(2), call_task).await??;
    assert!(
        call_result.is_err(),
        "in-flight call_tool should fail after close()"
    );
    Ok(())
}
