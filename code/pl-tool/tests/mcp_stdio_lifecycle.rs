//! Local MCP stdio handshake, framing and cancellation through real child pipes.
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
    #[cfg(target_os = "linux")]
    let source = format!(
        "import subprocess\nchild = subprocess.Popen(['/bin/sh', '-c', 'trap \"\" TERM; exec sleep 100000'], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\nopen({:?}, 'w').write(str(child.pid))\n{}",
        temp.path().join("descendant.pid").to_string_lossy(),
        STDIO_MCP_SCRIPT
    );
    #[cfg(not(target_os = "linux"))]
    let source = STDIO_MCP_SCRIPT.to_owned();
    let script = write_python_mcp_server(temp.path(), "server.py", &source);
    let mut env = BTreeMap::new();
    env.insert("MCP_HANG_CALL_MS".to_owned(), "10000".to_owned());

    let connector = McpConnector::default();
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
    #[cfg(target_os = "linux")]
    {
        let pid: u32 = std::fs::read_to_string(temp.path().join("descendant.pid"))?.parse()?;
        // A killed adopted descendant may await the harness/init reaper; it must
        // no longer execute. Failure cleanup is explicit and never hides the assertion.
        let deadline = Instant::now() + Duration::from_secs(2);
        let live = loop {
            let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok();
            let live = stat
                .as_deref()
                .and_then(|s| s.rsplit_once(") "))
                .is_some_and(|(_, tail)| !tail.starts_with('Z'));
            if !live || Instant::now() >= deadline {
                break live;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        };
        if live {
            std::process::Command::new("kill")
                .args(["-KILL", &pid.to_string()])
                .status()?;
        }
        assert!(
            !live,
            "stdio EOF raced process-group termination and leaked an in-group descendant"
        );
    }
    let call_result = tokio::time::timeout(Duration::from_secs(2), call_task).await??;
    assert!(
        call_result.is_err(),
        "in-flight call_tool should fail after close()"
    );
    Ok(())
}
