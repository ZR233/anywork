//! Explicit public-client regression for directory response failure isolation.
use anyhow::{Context, ensure};
use pl_protocol::remote::{
    REMOTE_PROTOCOL_VERSION, RemotePathRequest, RemoteRequest, RemoteResponse,
};
use pl_tool::remote::RemoteClient;
use std::process::Stdio;
use tokio::io::AsyncReadExt;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .with_writer(std::io::stderr)
        .init();
    let executable = std::env::args()
        .nth(1)
        .context("usage: remote_directory_validation HELPER [ENTRIES]")?;
    let count = std::env::args()
        .nth(2)
        .map(|value| value.parse::<usize>())
        .transpose()?
        .unwrap_or(1000);
    let root = tempfile::tempdir()?;
    for index in 0..count {
        std::fs::write(
            root.path()
                .join(format!("entry-{index:04}-{}", "x".repeat(180))),
            b"fixture",
        )?;
    }
    let mut child = tokio::process::Command::new(executable)
        .arg("--serve")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()?;
    let client =
        RemoteClient::from_streams(child.stdout.take().unwrap(), child.stdin.take().unwrap())
            .await?;
    let stderr = child.stderr.take().unwrap();
    let diagnostic = tokio::spawn(async move {
        let mut bytes = Vec::new();
        let mut stderr = stderr.take(16 * 1024);
        let mut buffer = [0; 1024];
        loop {
            let count = stderr.read(&mut buffer).await?;
            if count == 0 {
                break;
            }
            eprint!("{}", String::from_utf8_lossy(&buffer[..count]));
            bytes.extend_from_slice(&buffer[..count]);
        }
        anyhow::Ok(String::from_utf8_lossy(&bytes).into_owned())
    });
    let outcome = async {
        eprintln!("phase=hello");
        client.request(RemoteRequest::Hello { protocol_version: REMOTE_PROTOCOL_VERSION }, &[]).await?;
        eprintln!("phase=workspace");
        let opened = client.request(RemoteRequest::OpenWorkspace { path: root.path().to_string_lossy().into_owned() }, &[]).await?;
        let RemoteResponse::WorkspaceOpened(workspace) = opened.response else { anyhow::bail!("unexpected workspace response") };
        let target = RemotePathRequest { workspace_id: workspace.workspace_id, path: ".".into() };
        eprintln!("phase=directory");
        let listing = client.request(RemoteRequest::ListDirectory(target.clone()), &[]).await;
        let heartbeat = client.request(RemoteRequest::Heartbeat, &[]).await;
        let stat = client.request(RemoteRequest::Stat(target), &[]).await;
        println!("{}", serde_json::json!({"scenario":"large-directory-isolation", "entries":count, "listingOk":listing.is_ok(), "heartbeatOk":heartbeat.is_ok(), "statOk":stat.is_ok(), "disconnected":client.is_disconnected()}));
        ensure!(heartbeat.is_ok() && stat.is_ok(), "directory response killed shared transport: {listing:?}");
        let RemoteResponse::Directory(mut page) = listing?.response else { anyhow::bail!("directory did not return a page"); };
        let mut seen = page.entries.len();
        let mut pages = 1;
        while let Some(cursor) = page.next_cursor {
            eprintln!("phase=next-page page={pages}");
            let reply = client.request(RemoteRequest::ContinueDirectory { cursor }, &[]).await?;
            let RemoteResponse::Directory(next) = reply.response else { anyhow::bail!("expected continuation page"); };
            page = next;
            seen += page.entries.len();
            pages += 1;
        }
        ensure!(seen == count, "directory pagination dropped or duplicated entries");
        client.request(RemoteRequest::Heartbeat, &[]).await?;
        println!("{}", serde_json::json!({"scenario":"complete-directory", "entries":seen, "pages":pages}));
        anyhow::Ok(())
    }.await;
    eprintln!("phase=close");
    let close = client.close().await;
    let status = child.wait().await?;
    let diagnostic = diagnostic.await??;
    eprintln!("helper_status={status}; diagnostic={diagnostic}");
    outcome?;
    close?;
    println!("REMOTE_DIRECTORY_ISOLATION=PASS");
    Ok(())
}
